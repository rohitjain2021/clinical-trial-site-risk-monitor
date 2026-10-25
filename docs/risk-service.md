# Local FastAPI Risk Service

The local service exposes the existing [prototype risk calculator](risk-rules.md) through two HTTP routes. The app is in `services/risk_service/app.py`; it reuses `calculate_risk()` and adds no database, cloud integration, or scoring framework.

For container packaging and its current verification status, see the [local container guide](container.md).

| Route | Purpose | Successful response |
|---|---|---|
| `GET /health` | Check service connectivity and rule version | `200`, `status: ok` |
| `POST /site-assessments` | Validate one site and calculate prototype risk | `200`, risk level, rule version, and reasons |

This is separate from the deployed API Gateway endpoint, which still returns validation-only results. Lambda does not call this service yet. Snowflake, Bedrock, EKS, and the load balancer are not connected.

## Install Locally

Run from the repository root in PowerShell. Use Python 3.13 to match CI when available; the current development-machine tests also passed on Python 3.15.

```powershell
python -m venv services/risk_service/.venv
services/risk_service/.venv/Scripts/python.exe -m pip install -r services/risk_service/requirements-dev.txt
```

The `.venv` directory is ignored by Git. Runtime dependencies are pinned FastAPI and Uvicorn; the development requirements additionally install HTTPX2 for the framework's test client. Lambda remains independent of these packages.

## Start the Service

```powershell
services/risk_service/.venv/Scripts/python.exe -m uvicorn services.risk_service.app:app --host 127.0.0.1 --port 8000
```

Uvicorn runs the Python API application. This local service has no authentication and binds only to the loopback interface. It is not a public deployment; cloud networking and access control must be configured through infrastructure as code before hosting it. Stop the process with Ctrl+C.

## Send Example Requests

In a second PowerShell terminal, from the repository root:

```powershell
Invoke-RestMethod -Uri http://127.0.0.1:8000/health

$siteBody = Get-Content docs/examples/site-assessment.json -Raw
Invoke-RestMethod -Uri http://127.0.0.1:8000/site-assessments -Method Post -ContentType application/json -Body $siteBody
```

The synthetic site should return `risk_level: High`, `rules_version: prototype-v1`, and five reasons. The thresholds remain prototype assumptions requiring operational review. No submitted record is saved.

## Validation and Errors

The existing calculator validates the site fields. The API reads UTF-8 JSON without duplicating that validation schema, accepts at most 64 KiB while reading the request stream, and returns:

- `400` for malformed JSON, invalid encoding, or an invalid site record.
- `413` for a body over the size limit.
- `415` for a missing or unsupported content type.
- `404` for an unknown route.

Error responses include a safe `detail` message, not submitted values. Successful assessment responses use `Cache-Control: no-store`. The app does not log request bodies.

## Run Tests

```powershell
services/risk_service/.venv/Scripts/python.exe -m unittest discover -s services/risk_service -p 'test_*.py' -v
```

This runs 10 calculator tests and 7 HTTP service tests. Coverage includes representative Low/Medium/High records, thresholds, invalid inputs, encoding, body limits, and safe errors. CI installs the same service development requirements and runs these tests on Python 3.13. The service was also started with Uvicorn and tested over a real local HTTP connection.

References: [FastAPI testing](https://fastapi.tiangolo.com/tutorial/testing/) and [Starlette TestClient](https://starlette.dev/testclient/).
