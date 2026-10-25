# WATTSON

**WATTSON is an evidence-based, self-driving AI cloud optimizer.** It runs one closed loop:

```
MEASURE -> ANALYZE -> SIMULATE -> APPROVE -> EXECUTE -> VERIFY
```

It measures an AI workload baseline, generates a bounded optimization plan, simulates every
eligible candidate, **stops for a recorded human approval**, executes once through an idempotent
provider adapter, and verifies the result against the baseline. Regressions are reported honestly;
missing data is never turned into zero.

The default configuration is a **simulator**: no cloud credentials are needed, no paid API is
called, and every workload/result metric is labelled `simulated`. Temporal, the API, approvals,
the audit ledger, reports, and the dashboard are real software paths.

---

## Quick demo

### Prerequisites

- Python **3.12** and [`uv`](https://docs.astral.sh/uv/)
- [Temporal CLI](https://docs.temporal.io/cli) with `temporal` on `PATH`
- Node.js **20+** and npm (for the dashboard)
- Windows: PowerShell; macOS/Linux: Bash

### One command (Windows)

```powershell
cd C:\Users\ADMIN\wattson
powershell -ExecutionPolicy Bypass -File scripts/demo.ps1
```

### One command (macOS/Linux)

```bash
cd wattson
bash scripts/demo.sh
```

The script starts Temporal if port 7233 is free, starts a worker and the API on the first free
port from 8000/8010/8020, seeds a fresh `.data/demo.db`, and runs the complete loop. It stops only
the processes it started.

### What the demo proves

The demo exits non-zero unless both scenarios behave as expected:

| Scenario | Expected result | Why |
| --- | --- | --- |
| `Demo - Vision fine-tune` | **improved** | Nominal execution; cost, energy, latency, and throughput all improve. |
| `Demo - Speech fine-tune (throttled I/O)` | **regressed** | A documented throttled-I/O profile wipes out the savings; WATTSON reports the regression. |

Actual output from the final verification run (2026-10-25):

```text
Scenario A: IMPROVED  overall +58.49%   analysis=gemma (ollama)
  cost_usd             1.6504 -> 0.4922 USD   +70.17% [simulated->simulated]
  energy_kwh           0.2131 -> 0.0785 kWh   +63.17% [simulated->simulated]
  latency_ms           1.2195 -> 0.7667 ms    +37.13% [simulated->simulated]
  throughput_samples_s 820.0232 -> 1304.2243  +59.05% [simulated->simulated]
  provider launches=1, retries=1, cleanup events=1

Scenario B: REGRESSED  overall -83.20%   analysis=deterministic_fallback
  cost_usd             1.6317 -> 1.2777 USD   +21.69% [simulated->simulated]
  energy_kwh           0.2106 -> 0.2037 kWh    +3.30% [simulated->simulated]
  latency_ms           1.2052 -> 5.3241 ms   -341.76% [simulated->simulated]
  throughput_samples_s 829.7426 -> 488.3444  -41.15% [simulated->simulated]
  provider launches=1, retries=0, cleanup events=1
```

Exact percentages vary slightly between runs because each demo creates new workflow IDs, which
seed deterministic simulator jitter. The direction is asserted by the demo. **No real cloud
workload ran.** The demo itself spends no cloud money; the separate Gemma verification used a
temporary JarvisLabs L4, destroyed afterward.

Logs: `.data/logs/demo-api.*.log`, `demo-worker.*.log`, `demo-temporal.*.log`.

---

## Architecture

```text
Browser
  |
  |  no API token in the browser
  v
Next.js dashboard (server components + server actions)
  |
  |  Bearer WATTSON_API_TOKEN (server side only)
  v
FastAPI  -------- SQLAlchemy -------- SQLite or PostgreSQL
  |                                   workloads, proposals, approvals,
  |                                   runs, measurements, reports, audit
  |
  |  start / signal / query / cancel
  v
Temporal  <---- Worker (OptimizationWorkflow + activities)
                    |
                    +-- deterministic optimizer + simulator
                    +-- JarvisLabs adapter (optional, paid, not live-tested)
                    +-- Kepler Prometheus reader (optional, not wired into collection)
                    +-- Gemma via Ollama or hosted API (optional, untrusted, fallback)
```

### The loop

| Stage | Implementation | Evidence produced |
| --- | --- | --- |
| **MEASURE** | Workload records and baseline measurements; demo seeds simulated baselines. | Value, unit, timestamp, source, and provenance per metric. |
| **ANALYZE** | Deterministic optimizer generates 24 candidates (GPU type/count, batch size, precision, checkpointing), applies hard constraints, and ranks eligible candidates. Gemma is optional. | Candidate estimates (`predicted`), constraint failures, normalized scores. |
| **SIMULATE** | Eligible candidates are simulated; it is not presented as a benchmark. | Selected plan and simulated candidate estimates. |
| **APPROVE** | Temporal workflow waits indefinitely up to `WATTSON_APPROVAL_TIMEOUT_SECONDS` for a recorded decision. | Persisted approval/rejection with actor, reason, and timestamp. |
| **EXECUTE** | Execution guard re-queries approval, budget, runtime, kill switch, and provider capability; launches once with a workflow-derived idempotency key. | Provider launch, retries, cleanup, audit events. |
| **VERIFY** | Result is compared with the baseline; percentages and weighted overall change are computed deterministically. | Report with per-metric provenance, completeness, uncertainty, and verdict. |

### Main code paths

- `backend/wattson/optimizer.py` — hard constraints, min-max normalization, weighted scoring.
- `backend/wattson/simulator_math.py` — deterministic cost/energy/latency/throughput estimates.
- `backend/wattson/workflows.py` — deterministic Temporal workflow, signals, approval gate.
- `backend/wattson/workflow_activities.py` — DB, provider, AI, report, cleanup, finalize activities.
- `backend/wattson/providers/` — simulator, JarvisLabs, Kepler adapters.
- `backend/wattson/ai/` — strict schemas, Ollama/hosted Gemma, deterministic fallback, comparison CLI.
- `backend/wattson/api/` — authenticated FastAPI routes and error envelope.
- `backend/wattson/services/reports.py` — honest verdicts and provenance-aware comparison.
- `frontend/app/` — six dashboard pages: Overview, Workloads, Optimizations, Workflows, Reports, Settings.

### Repository layout

```text
wattson/
├── backend/wattson/          FastAPI, Temporal workflow/activities, optimizer, adapters, AI
├── frontend/                 Next.js 15 App Router dashboard
├── tests/                    unit, API, report, and Temporal time-skipping tests
├── alembic/                  database migration
├── scripts/demo.ps1          one-command Windows demo
├── scripts/demo.sh           one-command POSIX demo
├── simulator_assumptions.yaml illustrative GPU profiles and assumptions
├── Dockerfile                backend/worker image
├── docker-compose.yml        Temporal + backend + worker + dashboard (SQLite volume)
├── docker-compose.postgres.yml optional PostgreSQL override
├── Makefile                  common local commands
└── README.md
```

---

## Local development

### 1. Configure

```powershell
Copy-Item .env.example .env
# Edit .env and set a long random WATTSON_API_TOKEN.
python -c "import secrets; print(secrets.token_urlsafe(36))"
```

The API and worker read `.env` from the repository root. The frontend reads its own
`frontend/.env.local`; it must **never** use a `NEXT_PUBLIC_*` token.

```dotenv
# frontend/.env.local
WATTSON_API_URL=http://localhost:8000
WATTSON_API_TOKEN=<same token as the API>
```

### 2. Install

```powershell
uv sync --extra dev
cd frontend
npm ci
cd ..
```

Optional live adapters:

```powershell
uv sync --extra jarvis   # only if you intend to use JarvisLabs
```

### 3. Start Temporal

```powershell
temporal server start-dev --db-filename .data/temporal.db
```

Keep this terminal open. The Temporal UI is normally at `http://localhost:8233`.

### 4. Migrate and run the services

In separate terminals:

```powershell
uv run alembic upgrade head
uv run uvicorn wattson.api.app:app --port 8000
uv run python -m wattson.worker
```

The API's OpenAPI document is at `http://localhost:8000/docs` (the schema is public; API calls
still require the token).

### 5. Run the dashboard

```powershell
cd frontend
npm run dev
```

Open `http://localhost:3000`. The dashboard proxies every API call server-side, so the Bearer
token never reaches the browser.

### 6. Run the demo against an existing stack

```powershell
uv run wattson-demo --api-url http://127.0.0.1:8000 --token <token>
```

The demo seeds its own workloads and baselines, so it is safe to run against a fresh development
database. Do not point it at a production database: it creates demo records.

### Useful commands

```powershell
uv run pytest -q                  # full backend test suite
uv run ruff check backend tests   # lint
uv run mypy backend/wattson       # types
cd frontend
npm run typecheck
npm run lint
npm run build
```

`make check` runs lint, typecheck, and tests on systems with `make`.

---

## Dashboard

Six pages, with provenance badges on metrics and "Unavailable" for missing values:

1. **Overview** — loop status, health checks with provenance, counts, latest verdict, recent workflows, audit.
2. **Workloads** — current config, constraints, dataset size, baseline logs, provenance; create a proposal.
3. **Optimizations** — selected plan, all 24 candidates with rejection reasons, optional Gemma analysis, approval/rejection controls, start workflow.
4. **Workflows** — persisted stages, live Temporal stage, retry count, errors, cancellation, links to reports.
5. **Reports** — baseline vs result per metric, provenance and source for both sides, change chart, uncertainty, completeness, measurement window.
6. **Settings** — kill switch, runtime configuration, live integration status, safety contract, audit ledger.

Server actions perform mutations (`createProposal`, `startWorkflow`, `approve`, `reject`, `cancel`,
`toggleKillSwitch`). The API remains the authority; the dashboard does not bypass the approval
gate.

---

## API

All `/api` routes except `/api/health` require:

```http
Authorization: Bearer <WATTSON_API_TOKEN>
```

Errors use one envelope:

```json
{"error": {"code": "not_found", "message": "Workload not found.", "details": null}}
```

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/api/health` | Public health and provenance-labelled integration checks. |
| `GET` | `/api/integrations` | Database, Temporal, provider, Gemma, Kepler status. |
| `GET` | `/api/workloads` | Paginated workloads. |
| `POST` | `/api/workloads` | Register a workload with config and constraints. |
| `GET` | `/api/workloads/{id}` | Workload plus runs and measurements. |
| `GET` | `/api/workloads/{id}/runs` | Paginated runs. |
| `GET` | `/api/optimizations` | Paginated proposals. |
| `POST` | `/api/optimizations` | Create a deterministic proposal from a workload. |
| `GET` | `/api/optimizations/{id}` | Proposal, candidates, analysis, approval. |
| `POST` | `/api/optimizations/{id}/approve` | Persist approval, then signal the workflow. |
| `POST` | `/api/optimizations/{id}/reject` | Persist rejection, then signal the workflow. |
| `POST` | `/api/workflows` | Start the Temporal workflow for a proposal. |
| `GET` | `/api/workflows` | Paginated workflow refs. |
| `GET` | `/api/workflows/{id}` | Live stage plus persisted state. |
| `POST` | `/api/workflows/{id}/cancel` | Request cancellation. |
| `GET` | `/api/reports` | Paginated evidence reports. |
| `GET` | `/api/reports/{id}` | Full report. |
| `GET` | `/api/audit` | Paginated append-only audit events. |
| `GET` | `/api/settings` | Runtime configuration without secrets. |
| `PATCH` | `/api/settings` | Enable or disable the kill switch. |

Pagination uses `limit`, `offset`, and returns `{items, total, limit, offset}`.

---

## Configuration

Copy `.env.example` to `.env`. Secrets are read only from the environment.

| Variable | Default | Notes |
| --- | --- | --- |
| `WATTSON_API_TOKEN` | empty | **Required.** Static Bearer token for every protected route. |
| `WATTSON_DATABASE_URL` | `sqlite:///./.data/wattson.db` | PostgreSQL: `postgresql+psycopg://...`. |
| `WATTSON_KILL_SWITCH` | `false` | When true, blocks every **new** provider launch. Environment wins over the dashboard. |
| `WATTSON_PROVIDER` | `simulator` | `simulator` or `jarvislabs`. |
| `WATTSON_TEMPORAL_HOST` | `localhost:7233` | Temporal frontend address. |
| `WATTSON_TEMPORAL_NAMESPACE` | `default` | Temporal namespace. |
| `WATTSON_TEMPORAL_TASK_QUEUE` | `wattson` | Worker and workflow must use the same queue. |
| `WATTSON_APPROVAL_TIMEOUT_SECONDS` | `900` | After timeout the workflow ends as `needs_intervention`. |
| `WATTSON_API_URL` | `http://localhost:8000` | Read by the **dashboard server**, not the browser. |
| `WATTSON_CORS_ORIGINS` | `http://localhost:3000` | Comma-separated browser origins if the API is called directly. |
| `WATTSON_AI_PROVIDER` | `none` | `none`, `ollama`, or `hosted`. |
| `GEMMA_MODEL` | empty | Required when the AI provider is not `none`. |
| `OLLAMA_BASE_URL` | `http://localhost:11434` | Local Ollama endpoint. |
| `HOSTED_GEMMA_BASE_URL` | Google Generative Language API | Hosted Gemma endpoint. |
| `HOSTED_GEMMA_API_KEY` | empty | Required for `hosted`. |
| `JL_API_KEY` | empty | JarvisLabs credential; adapter is disconnected without it. |
| `WATTSON_KEPLER_PROMETHEUS_URL` | empty | Prometheus-compatible Kepler endpoint. |
| `WATTSON_KEPLER_POD_LABEL` | empty | Pod label used in the Kepler query. |
| `WATTSON_ASSUMPTIONS_PATH` | `./simulator_assumptions.yaml` | Simulator assumptions. |
| `WATTSON_REPORT_DIR` | `./.data/reports` | Reserved evidence directory; this build serves reports from the database. |

Never commit `.env` or `frontend/.env.local`.

---

## Safety model

WATTSON is built around safeguards, not model trust:

- **No paid execution without recorded approval.** The approval row is committed before the
  Temporal signal is sent. The execution guard queries that row again immediately before launch.
- **Revalidation at execution time.** The guard checks approval, budget, runtime, kill switch,
  selected candidate eligibility, and provider capability. A plan that was safe earlier cannot
  bypass changed conditions.
- **Kill switch.** Stored as an audited setting; `WATTSON_KILL_SWITCH=true` always wins and cannot
  be overridden from the UI. It blocks new launches; it does not retroactively stop a provider job
  already running.
- **Idempotent launches.** The launch key is derived from the Temporal workflow ID. The simulator
  reconciles by key, JarvisLabs uses a deterministic `wattson-` instance name, and duplicate
  activity retries do not create a second instance.
- **Cleanup scope.** Only resources tagged `wattson:managed=true` and named with the `wattson-`
  prefix are cleaned up. Foreign resources are refused.
- **Untrusted model output.** Logs are redacted before being sent to a model. Model JSON must pass
  a strict schema; proposed tweaks pass a policy validator. Model text cannot change constraints,
  the selected candidate, budget, or the verdict.
- **Honest metrics.** Every measurement carries value, unit, timestamp, source, and provenance.
  Missing values are `unavailable`, never `0`. A regression produces a `regressed` verdict.
- **Single observation.** The demo produces one observation per metric and therefore makes no
  statistical-confidence claim.

### Provenance values

`measured`, `calculated`, `estimated`, `predicted`, `simulated`, `unavailable`.

In the default demo, baselines and results are `simulated`; optimizer estimates are `predicted`;
infrastructure/health checks are `measured`; deterministic analysis is `calculated`.

---

## Optional Gemma analysis

Gemma is optional and never authoritative. Without a configured model, WATTSON uses deterministic
analysis and labels it `deterministic_fallback`.

### Ollama

```powershell
ollama pull gemma4:e2b
$env:WATTSON_AI_PROVIDER="ollama"
$env:GEMMA_MODEL="gemma4:e2b"
```

### Hosted

```powershell
$env:WATTSON_AI_PROVIDER="hosted"
$env:GEMMA_MODEL="gemma-4-26b-a4b-it"
$env:HOSTED_GEMMA_API_KEY="<key>"
```

Restart the API and worker after changing these values.

### Side-by-side comparison

```powershell
$env:WATTSON_DATABASE_URL="sqlite:///./.data/demo.db"
uv run wattson-gemma-compare
```

This prints the deterministic analysis and, when available, the schema-validated Gemma analysis.
It never invents model output:

- No provider configured -> `gemma.status = "unavailable"`, `payload = null`.
- Provider unreachable -> `gemma.status = "error"`, `payload = null`, safe reason only.
- Provider available -> `gemma.status = "available"` plus its payload.

**Verified run (2026-10-25):** real Gemma inference was verified against a JarvisLabs L4
instance (1x L4, 24 GB, `IN2`) running Ollama 0.40.11 and `gemma4:e2b` over an SSH tunnel.
`/api/health` reported `gemma connected` with provenance `measured`, and
`uv run wattson-gemma-compare` returned `gemma.status = "available"` with a schema-validated
payload. The end-to-end demo used `gemma:ollama:gemma4:e2b` for Scenario A's analysis and for
both report narratives. Scenario B's analysis safely fell back to deterministic output because
the model emitted a malformed `proposed_tweak`; schema validation and the policy fallback worked
as designed. The GPU instance was destroyed after verification to stop billing. Gemma remains
optional and untrusted; the deterministic optimizer and policy validator stay authoritative.

> Ollama note: the provider sends `think: false` and reserves 1800 output tokens. Without that,
> Gemma 4 can spend the whole budget on hidden reasoning and return a truncated JSON stub.

---

## Adapters

### Simulator (default)

- Deterministic estimates from `simulator_assumptions.yaml`.
- Records simulated instances and simulates one transient launch/collect failure on request.
- Never contacts a cloud and never spends money.
- Cleanup is idempotent.

### JarvisLabs (optional, paid; adapter not live-verified)

Implemented against the documented `jarvislabs` Python SDK 0.2.x:

- configure `JL_API_KEY` and install with `uv sync --extra jarvis`;
- set `WATTSON_PROVIDER=jarvislabs`;
- supports documented GPU types (`A30`, `L4`, `A100`, `A100-80GB`, `H100`, `H200`, `RTX-PRO6000`);
- provision reconciles by deterministic `wattson-` name;
- cleanup destroys only `wattson-` instances.

**Important limitation:** the documented SDK exposes instance lifecycle but no verified arbitrary
job-run + per-job metrics API. WATTSON therefore implements provision and cleanup but deliberately
raises on `collect` rather than fabricating measurements. A fully live paid run is not claimed to
work end to end. Contract tests are mocked. The live JarvisLabs verification on 2026-10-25 used the
API only to host Ollama/Gemma; it did not exercise this adapter's provision/collect path.

### Kepler (optional)

- Reads documented Prometheus counters such as `kepler_pod_gpu_joules_total` and converts joules
  to kWh.
- Disconnected by default; energy remains labelled `simulated`.
- Contract-tested against a mocked Prometheus response. The reader is **not wired into the
  execution result path** in this build; it is available for integration and status reporting.
  No live Kepler installation was tested.

---

## Verification results

Verified on **2026-10-25** in this repository.

### Backend

```text
$ uv run pytest -q
57 passed, 1 warning in 9.23s

$ uv run ruff check backend tests
All checks passed!

$ uv run mypy backend/wattson
Success: no issues found in 37 source files
```

Test breakdown:

| Area | Tests |
| --- | --- |
| Deterministic optimizer and simulator math | 9 |
| AI schemas, injection defense, fallback, summaries | 12 |
| Gemma comparison availability/error handling | 3 |
| Adapter contracts (simulator/JarvisLabs/Kepler, mocked) | 10 |
| Reports and provenance | 6 |
| API auth, errors, pagination, approvals, kill switch | 10 |
| Workflow stage-status regression | 1 |
| Temporal time-skipping workflows | 6 |

The workflow suite uses Temporal's time-skipping test environment and covers: approved completion
with one idempotent launch, throttled execution reported as regressed, missing approval blocks
execution, rejection, cancellation before approval, and approval timeout.

### Frontend

```text
npm run typecheck   -> success
npm run lint        -> no ESLint warnings or errors
npm run build       -> compiled successfully; all six pages dynamic
```

The production build generated the six dashboard routes plus `/_not-found`. (`next lint` prints a
deprecation notice because Next.js 16 removes it; the current Next.js 15 lint run is clean.)

### Demo

The final demo run on 2026-10-25 produced:

- Scenario A: **improved**, overall **+58.49%**, 4/4 metrics available, one provider launch, one
  activity retry, one cleanup. Analysis source: `gemma` (`ollama`, `gemma4:e2b`).
- Scenario B: **regressed**, overall **-83.20%**, 4/4 metrics available, one provider launch, zero
  retries, one cleanup. Analysis source: `deterministic_fallback` because the model emitted a
  malformed `proposed_tweak`; the report narrative was still Gemma-authored.
- All metric provenance: `simulated`.
- No real cloud workload ran. The only paid resource was the temporary JarvisLabs L4 used to host
  Gemma; it was destroyed after verification.

### Gemma on JarvisLabs

- Instance: 1x L4 (24 GB), `IN2`, Ollama 0.40.11, `gemma4:e2b`; the backend reached Ollama through
  an SSH tunnel.
- Health: `gemma connected`, provenance `measured`.
- `uv run wattson-gemma-compare`: `status=available` with a schema-validated payload.
- Demo: Scenario A analysis and both report narratives came from
  `gemma:ollama:gemma4:e2b`. Scenario B's malformed model tweak was rejected; deterministic
  fallback kept the plan safe.
- No WATTSON JarvisLabs execution/collect path was exercised. The instance was destroyed after
  verification.

### Dashboard actions

Manually verified against a disposable SQLite database:

1. Create a proposal from the workloads page.
2. Start its Temporal workflow and observe `awaiting_approval`.
3. Record approval through the dashboard form.
4. Observe completion and open the resulting report.
5. Enable and disable the kill switch and confirm the audit events.

This was a manual smoke test, not an automated browser test.

### Docker

The Compose files pass `docker compose config` validation for both the default SQLite stack and the
PostgreSQL override. The backend image `wattson-backend:latest` built successfully on 2026-10-25
(453 MB). The full Compose stack, frontend image, and container runtime were not verified in this
environment; treat the container path as partly unverified until you run it locally.

### Not verified

- WATTSON's live JarvisLabs execution/collect path and paid workload runs (JarvisLabs was used only
  to host Ollama/Gemma for the verification above).
- Hosted Gemma endpoint (only Ollama-hosted Gemma was verified).
- Live Kepler/Prometheus scraping.
- Production PostgreSQL deployment (migration and driver are present).
- Full Docker Compose runtime and frontend image (the backend image builds successfully).

---

## Docker Compose

The default stack uses a shared SQLite volume and the simulator:

```powershell
$env:WATTSON_API_TOKEN="replace-with-a-long-random-token"
docker compose up --build
```

- Dashboard: `http://localhost:3000`
- API: `http://localhost:8000`
- Temporal UI: `http://localhost:8233`

Optional PostgreSQL:

```powershell
docker compose -f docker-compose.yml -f docker-compose.postgres.yml up --build
```

The Compose token defaults to `wattson-demo-token` for local convenience. Change it before exposing
anything beyond your machine.

To expose a local Ollama instance to the backend container, use `OLLAMA_BASE_URL` (default in
Compose is `http://host.docker.internal:11434`). On Linux add an appropriate
`host.docker.internal` mapping or run Ollama in a container.

The Compose health checks wait for Temporal, migrations, and the API. The backend container runs
`alembic upgrade head` before starting Uvicorn. For a custom JarvisLabs image, build the backend
with `--build-arg INSTALL_JARVIS=true`.

---

## Limitations and non-goals

WATTSON is a demonstration-grade control plane, not a production cloud broker:

- The dashboard itself has no user login. It protects the API token by proxying server-side, but
  anyone who can reach the dashboard can use its actions. Put it behind authentication before
  exposing it.
- SQLite is suitable for the demo and single-host development. Use PostgreSQL for shared or
  production data; the Compose override is provided but not runtime-tested here.
- The simulator is illustrative, not a vendor benchmark. Its assumptions are in
  `simulator_assumptions.yaml`; accuracy, model quality, network variance, and spot interruptions
  are not modelled.
- Reports contain one observation per metric and no confidence interval.
- Gemma output is optional and untrusted; without a model, deterministic fallback is used.
- JarvisLabs collection is intentionally unimplemented because the documented SDK does not expose
  a verified job-run + metrics API. Provision/cleanup are implemented; live paid execution is not
  claimed.
- Kepler has a reader and status integration but is not connected to the result pipeline.
- The kill switch blocks new launches, not already-running provider jobs.
- No multi-cluster scheduling, Kubernetes operator, voice interface, carbon-aware scheduling, user
  management, or learning history. Those were intentionally out of scope.

If a metric is unavailable, the UI and reports say **Unavailable**; they never show zero as a
substitute.

---

## Troubleshooting

| Symptom | Check |
| --- | --- |
| `401` from the API | `Authorization: Bearer <WATTSON_API_TOKEN>` matches the server token. |
| Workflow stays at `created` | Worker is running and is polling the same `WATTSON_TEMPORAL_TASK_QUEUE`. |
| `temporal_unavailable` | Temporal is listening on `WATTSON_TEMPORAL_HOST`. |
| Workflow ends `needs_intervention` | Approval timed out, kill switch active, budget/runtime changed, or provider capability missing. Read the workflow error. |
| Dashboard cannot load | `frontend/.env.local` has the correct `WATTSON_API_URL` and token; API is running. |
| Demo port conflict | Let the script choose another port, or pass `-ApiPort 8030` on Windows. |
| Kill switch will not turn off | `WATTSON_KILL_SWITCH=true` is set in the environment; remove it and restart. |
| Simulated percentages differ from this README | Expected; new workflow IDs seed deterministic jitter. The expected verdict direction must still hold. |

Logs from the demo: `.data/logs/`.

---

## License

Apache-2.0. See [LICENSE](LICENSE).

## Status

Built and verified locally on 2026-10-25: 57 backend tests passing, Ruff and mypy clean, frontend
typecheck/lint/build clean, and the simulator demo completing both improved and regressed
scenarios. Not production-ready; the limitations above are part of the contract.
