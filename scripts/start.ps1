[CmdletBinding()]
param(
    [int]$ApiPort = 8000,
    [int]$FrontendPort = 3000,
    [switch]$NoBrowser
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

Write-Host ""
Write-Host "==========================================================" -ForegroundColor DarkGray
Write-Host "   WATTSON - Evidence-Based AI Cloud Optimizer" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor DarkGray
Write-Host ""

$uv = Get-Command uv -ErrorAction SilentlyContinue
if (-not $uv) {
    Write-Error "Error: 'uv' is not installed or not found on PATH."
    exit 1
}

$temporal = Get-Command temporal -ErrorAction SilentlyContinue
if (-not $temporal) {
    Write-Error "Error: 'temporal' CLI is not found on PATH."
    exit 1
}

$npm = Get-Command npm -ErrorAction SilentlyContinue
if (-not $npm) {
    Write-Error "Error: 'npm' is not found on PATH."
    exit 1
}

$DataDir = Join-Path $Root ".data"
$LogDir = Join-Path $DataDir "logs"
New-Item -ItemType Directory -Force -Path $DataDir, $LogDir | Out-Null

$Token = if ($env:WATTSON_API_TOKEN) { $env:WATTSON_API_TOKEN } else { "wattson-demo-token" }
$TaskQueue = "wattson-demo"
$DbPath = (Join-Path $DataDir "demo.db").Replace("\", "/")

$env:WATTSON_API_TOKEN = $Token
$env:WATTSON_TEMPORAL_HOST = "localhost:7233"
$env:WATTSON_TEMPORAL_TASK_QUEUE = $TaskQueue
$env:WATTSON_PROVIDER = "simulator"
$env:WATTSON_AI_PROVIDER = "none"
$env:WATTSON_KILL_SWITCH = "false"
$env:WATTSON_DATABASE_URL = "sqlite:///$DbPath"
$env:WATTSON_CORS_ORIGINS = "http://localhost:$FrontendPort"
$env:WATTSON_API_URL = "http://127.0.0.1:$ApiPort"

function Test-Port([int]$Port) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect("127.0.0.1", $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne(500)) { return $false }
        $client.EndConnect($async)
        return $true
    } catch {
        return $false
    } finally {
        $client.Dispose()
    }
}

function Wait-Port([int]$Port, [int]$TimeoutSeconds) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-Port $Port) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

Write-Host "[1/5] Applying database migrations..." -ForegroundColor DarkCyan
try {
    & $uv.Source run alembic upgrade head 2>$null | Out-Null
} catch {
    # If database tables already exist, stamp head
    try { & $uv.Source run alembic stamp head 2>$null | Out-Null } catch {}
}
Write-Host "      Database ready at: $DbPath" -ForegroundColor Green

if (-not (Test-Port 7233)) {
    Write-Host "[2/5] Starting Temporal dev server on localhost:7233..." -ForegroundColor DarkCyan
    $temporalProc = Start-Process -FilePath $temporal.Source `
        -ArgumentList @("server", "start-dev", "--headless", "--port", "7233", "--db-filename", (Join-Path $DataDir "temporal-demo.db")) `
        -WorkingDirectory $Root `
        -RedirectStandardOutput (Join-Path $LogDir "temporal.out.log") `
        -RedirectStandardError (Join-Path $LogDir "temporal.err.log") `
        -WindowStyle Hidden -PassThru
    
    if (-not (Wait-Port 7233 30)) {
        Write-Error "Failed to start Temporal on port 7233."
        exit 1
    }
    Write-Host "      Temporal is live (PID: $($temporalProc.Id))" -ForegroundColor Green
} else {
    Write-Host "[2/5] Temporal server already running on port 7233." -ForegroundColor Green
}

Write-Host "[3/5] Starting Wattson Worker on task queue '$TaskQueue'..." -ForegroundColor DarkCyan
$workerProc = Start-Process -FilePath $uv.Source `
    -ArgumentList @("run", "python", "-m", "wattson.worker") `
    -WorkingDirectory $Root `
    -RedirectStandardOutput (Join-Path $LogDir "worker.out.log") `
    -RedirectStandardError (Join-Path $LogDir "worker.err.log") `
    -WindowStyle Hidden -PassThru
Write-Host "      Worker is live (PID: $($workerProc.Id))" -ForegroundColor Green

if (-not (Test-Port $ApiPort)) {
    Write-Host "[4/5] Starting FastAPI backend on http://127.0.0.1:$ApiPort..." -ForegroundColor DarkCyan
    $apiProc = Start-Process -FilePath $uv.Source `
        -ArgumentList @("run", "uvicorn", "wattson.api.app:app", "--host", "127.0.0.1", "--port", "$ApiPort") `
        -WorkingDirectory $Root `
        -RedirectStandardOutput (Join-Path $LogDir "api.out.log") `
        -RedirectStandardError (Join-Path $LogDir "api.err.log") `
        -WindowStyle Hidden -PassThru

    if (-not (Wait-Port $ApiPort 30)) {
        Write-Error "Failed to start API on port $ApiPort."
        exit 1
    }
    Write-Host "      FastAPI backend is live (PID: $($apiProc.Id))" -ForegroundColor Green
} else {
    Write-Host "[4/5] API already running on port $ApiPort." -ForegroundColor Green
}

$FrontendDir = Join-Path $Root "frontend"
$EnvLocal = Join-Path $FrontendDir ".env.local"
if (-not (Test-Path $EnvLocal)) {
    $line1 = "WATTSON_API_URL=http://127.0.0.1:" + $ApiPort
    $line2 = "WATTSON_API_TOKEN=" + $Token
    Set-Content -Path $EnvLocal -Value @($line1, $line2)
}

if (-not (Test-Port $FrontendPort)) {
    Write-Host "[5/5] Starting Next.js frontend on http://localhost:$FrontendPort..." -ForegroundColor DarkCyan
    $frontendProc = Start-Process -FilePath $npm.Source `
        -ArgumentList @("run", "dev", "--", "-p", "$FrontendPort") `
        -WorkingDirectory $FrontendDir `
        -RedirectStandardOutput (Join-Path $LogDir "frontend.out.log") `
        -RedirectStandardError (Join-Path $LogDir "frontend.err.log") `
        -WindowStyle Hidden -PassThru

    if (-not (Wait-Port $FrontendPort 40)) {
        Write-Error "Frontend did not start in time."
        exit 1
    }
    Write-Host "      Frontend is live (PID: $($frontendProc.Id))" -ForegroundColor Green
} else {
    Write-Host "[5/5] Frontend already running on port $FrontendPort." -ForegroundColor Green
}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "   WATTSON is running successfully!" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  * Dashboard:   http://localhost:$FrontendPort" -ForegroundColor Cyan
Write-Host "  * API Health:  http://127.0.0.1:$ApiPort/api/health" -ForegroundColor Cyan
Write-Host "  * API Docs:    http://127.0.0.1:$ApiPort/docs" -ForegroundColor Cyan
Write-Host "  * Temporal:    localhost:7233" -ForegroundColor Cyan
Write-Host "  * Logs:        $LogDir" -ForegroundColor Gray
Write-Host ""
Write-Host "To stop all services: powershell -ExecutionPolicy Bypass -File scripts/stop.ps1" -ForegroundColor Yellow
Write-Host ""

if (-not $NoBrowser) {
    Start-Process ("http://localhost:" + $FrontendPort)
}
