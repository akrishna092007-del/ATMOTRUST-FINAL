# AtmoTrust

AtmoTrust is a local weather-data assurance prototype. It replays 672 hourly Open-Meteo Archive frames for five logical locations, compares each temperature, pressure and humidity reading with causal history and nearby peers, and tracks incidents through assigned maintenance. The data is **gridded weather data, not physical AWS telemetry**. The current-weather lane uses genuine Open-Meteo Current Weather values when the provider is reachable.

## Run locally

Requires Python 3.11+ and Node.js 20+. The included model artifacts are trained already; the application does not train at startup.

On Windows, from the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/start.ps1
```

On macOS/Linux, from the repository root:

```sh
sh scripts/start.sh
```

Open [http://127.0.0.1:8000/login](http://127.0.0.1:8000/login). The login page visibly lists the public demo usernames and passwords for both roles; selecting a role fills its credentials. The start script installs missing dependencies, builds the frontend when absent, and runs `scripts/seed_accounts.py`. New local databases receive those same demo accounts, and the initial employee is assigned to all five stations. Existing account passwords are left unchanged. These public accounts are for demo data only. On Windows without Python on `PATH`, the start script detects the Codex bundled Python or accepts `ATMOTRUST_PYTHON`.

The routes are `/` for the public landing page, `/login` for role selection, `/authority` for operators and `/employee` for assigned maintenance. The backend requires an HTTP-only session for portal APIs and WebSockets. The login cookie is SameSite Strict; set `ATMOTRUST_COOKIE_SECURE=true` behind HTTPS. Only one backend process should own a local demo run.

For separate development servers, from the repository root:

```sh
python -m uvicorn app.main:app --app-dir backend --reload
```

In a second terminal:

```sh
cd frontend
npm ci
npm run dev
```

The Vite server proxies `/api` to the backend. Run `python scripts/seed_accounts.py` once from the root if you launch the backend directly and need initial accounts.

## Roles and demo flow

Authority can control replay and live mode, inject six sensor faults and regional weather events, investigate Trust Scores, confirm observations, manage stations/poles and employees, assign stations, configure maintenance contacts, review/resend alerts, and view model information. Employees see only assigned stations and tasks. They can start maintenance, mark a task maintained, add notes and review their own history. Backend authorization returns `403` for authority-only actions and filters station data and tasks; employee controls in the UI show locks.

1. Sign in as authority. The Command Centre shows the station map, moving graphs and incident queue.
2. Pause in Simulation Lab. Inject a Chandigarh temperature spike and step once. Review measured evidence and the maintenance task. Reset and try freeze, drift, bias, noise or missing. A regional scenario can run with an independent fault.
3. In Stations & Employees, set a station maintenance email and assign an employee. New fault incidents create one delivery; severity increases create another. The Email Alerts page shows delivery status and message content.
4. Sign out and sign in as the assigned employee. Open Assigned Tasks, start maintenance, add a note and mark it maintained. The authority portal receives the status update over WebSocket.
5. Switch to Live to show the genuine provider timestamp. If Open-Meteo is unavailable, the UI reports unavailability without substituting replay readings. A fresh live stream requires enough genuine history for confident analysis.

## Email configuration

Copy `.env.example` to `.env` and set `ATMOTRUST_EMAIL_ENABLED=true`, `ATMOTRUST_SMTP_HOST`, `ATMOTRUST_SMTP_PORT`, `ATMOTRUST_SMTP_USERNAME`, `ATMOTRUST_SMTP_PASSWORD`, `ATMOTRUST_SMTP_SENDER` and `ATMOTRUST_FRONTEND_URL`. Station-specific recipient addresses are set in the authority portal. Delivery runs outside weather-frame processing. Without configured SMTP, alerts with a recipient are stored as `outbox` and visible in Email Alerts; they are never marked sent. Missing recipients are `suppressed`. SMTP failures are `failed` with safe error text. The database stores delivery status and deduplicates opening and severity-escalation alerts.

## Data and model

`data/prepared/demo_v1` contains the normalized historical observations, station metadata, provenance, hashes and policy. `scripts/prepare_data.py` refreshes the keyless Open-Meteo Archive package; `--allow-synthetic` is an explicitly labelled offline fallback. `backend/app/data.py` handles replay and current weather. `simulation.py` transforms copies for controlled examples. `analysis.py` uses only readings, timestamp, station identity, earlier observations and peer context. Injection labels, preserved raw values, scenario names and benchmark targets are excluded from inference.

The offline training command, from the repository root, is:

```sh
python scripts/train_model.py
```

Training first splits frames chronologically into train, validation and held-out test periods. It fits an Isolation Forest to clean training observations, generates deterministic simulated fault episodes separately inside each period, compares Random Forest and Extra Trees classifiers on validation, selects by macro-F1, fault recall, false-alarm rate and latency, and saves the chosen classifier plus the Isolation Forest with `joblib`. The model manifest records the provenance, feature order, split timestamps, sample counts, candidate and held-out metrics, hashes and limitations. Normal startup only loads these files. When artifacts are missing or incompatible, the app reports **Analysis unavailable**. Fewer than 24 earlier readings yields **Insufficient context** and an `N/A` Trust Score. The Trust Score is a model-and-evidence index, not a probability. Fault labels are simulated; no physical failure labels were available.

## Verification

From the repository root:

```sh
cd backend
python -m pytest tests -q
cd ../frontend
npm ci
npm run typecheck
npm run build
cd ..
python scripts/benchmark.py
python scripts/smoke.py
```

`scripts/benchmark.py` writes `benchmarks/results/metrics.json`, `observations.csv` and `summary.md` with clean/fault counts, binary precision/recall/F1, false-alarm rate, per-fault metrics, a multi-class confusion matrix, macro-F1, latency and artifact size. The latest nine-episode benchmark evaluated **1,620 readings** with **32 injected fault slots**: precision **0.5918**, recall **0.9062**, F1 **0.7160**, false-alarm rate **0.0126**, and mean frame analysis latency **45.33 ms** on this machine. The held-out model test in `artifacts/demo_v1/manifest.json` measured macro-F1 **0.8719**, fault recall **0.9505** and false-alarm rate **0.0312** on one chronological gridded window with simulated labels. These figures are not physical-station field accuracy. The benchmark uses further injected episodes and repeated clean contexts on that held-out window; earlier rule work also used nearby data, so external validity is limited.

SQLite operational state is created automatically in `backend/atmotrust.sqlite3` and is ignored by Git. It contains users, hashed passwords, sessions, station/pole metadata, assignments, incidents, tasks, notes, email deliveries and model metadata. Historical weather and model artifacts stay outside the operational database. A restart creates a new disposable replay run while retaining users and maintenance history. Map tiles and live provider access require network connectivity. Replay 60× is a scheduling target and may run slower on limited hardware.
