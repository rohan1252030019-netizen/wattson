<#
.SYNOPSIS
    Stops all local WATTSON background processes (Temporal, API, Worker, Next.js).
#>

[CmdletBinding()]
param()

Write-Host "Stopping WATTSON services..." -ForegroundColor Yellow

$Ports = 7233, 8000, 3000

foreach ($Port in $Ports) {
    try {
        $lines = netstat -ano | Select-String ":$Port\s.*LISTENING"
        foreach ($line in $lines) {
            $parts = ($line.ToString().Trim() -split '\s+')
            $pidToKill = $parts[-1]
            if ($pidToKill -and $pidToKill -match '^\d+$' -and $pidToKill -ne "0") {
                Write-Host "Killing process on port $Port (PID: $pidToKill)..." -ForegroundColor DarkGray
                Stop-Process -Id ([int]$pidToKill) -Force -ErrorAction SilentlyContinue
            }
        }
    } catch {
        # ignore errors on shutdown
    }
}

# Also kill lingering python worker / uvicorn / temporal dev servers if any
Get-Process -Name "temporal" -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "Stopping Temporal process (PID: $($_.Id))..." -ForegroundColor DarkGray
    Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
}

Write-Host "All WATTSON services have been stopped." -ForegroundColor Green
