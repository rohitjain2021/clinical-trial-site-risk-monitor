# FastAPI Container: Local Build and Test

The image is defined in `services/risk_service/Dockerfile`. It uses the official Python 3.13 slim Linux image, installs only the runtime requirements, and runs Uvicorn as user/group `10001:10001`. It does not include the test client, tests, credentials, or Terraform configuration.

The build context is the service directory, not the repository root. Its `.dockerignore` allows only the two application files, runtime requirements, Dockerfile, and ignore file. Do not pass credentials as build arguments or mount private deployment settings into the container.

**Validation status:** built and tested locally on October 25, 2026 using Docker Desktop's Linux engine. `GET /health` returned `200`; the synthetic assessment returned `200`, `High` risk, five reasons, and `Cache-Control: no-store`; an invalid assessment returned `400`. Runtime checks confirmed user `10001:10001`, a read-only root filesystem, a loopback-only published port, and only the runtime input files under `/app`. The temporary test container was stopped and removed. AWS deployment remains pending.

## Windows Prerequisites

Docker Desktop must be running with its Linux container engine available. Docker Desktop uses WSL 2 on this machine; installing/enabling WSL may require an administrator prompt and Windows restart. A separate Ubuntu distribution is not required solely for Docker Desktop.

Open a new PowerShell terminal after installation and check:

```powershell
wsl --version
docker version
```

`docker version` must show both Client and Server information. A client-only response is not enough to build or run an image. See [Docker's Windows installation guide](https://docs.docker.com/desktop/setup/install/windows-install/).

## Build the Image

From the repository root:

```powershell
docker build --pull -t clinical-trial-risk-service:local services/risk_service
```

Only the FastAPI service is packaged. Lambda continues using its separate ZIP deployment. The base tag follows the Python 3.13 release line; `--pull` refreshes its current patch/security updates.

## Start Locally

```powershell
docker run --detach --name clinical-trial-risk-local --publish 127.0.0.1:8000:8000 --read-only --tmpfs /tmp --cap-drop ALL --security-opt no-new-privileges:true clinical-trial-risk-service:local
```

Uvicorn listens on the container's port 8000. The published host port is restricted to `127.0.0.1`; this unauthenticated development service is not a public API. The command uses a read-only container filesystem with writable temporary storage and drops additional Linux capabilities.

## Verify Requests

```powershell
Invoke-RestMethod -Uri http://127.0.0.1:8000/health

$siteBody = Get-Content docs/examples/site-assessment.json -Raw
Invoke-RestMethod -Uri http://127.0.0.1:8000/site-assessments -Method Post -ContentType application/json -Body $siteBody
```

Expect health status `ok`, followed by `risk_level: High`, `rules_version: prototype-v1`, and five reasons for the synthetic example. These are prototype operational rules, not validated clinical judgments. Confirm an invalid record returns `400` and that no submitted data is stored.

Inspect runtime information if needed:

```powershell
docker logs clinical-trial-risk-local
docker inspect --format '{{.Config.User}}' clinical-trial-risk-local
```

The configured user should be `10001:10001`. Access logging is disabled in Uvicorn; startup and error messages remain available.

## Automated Checks

GitHub Actions has a separate `container` job on pull requests, pushes to `main`, and manual workflow runs. It builds the image and runs the same standard-library check used locally:

```powershell
python scripts/check_container.py
```

Build the image first. The script starts its own uniquely named container on a random loopback port, waits for readiness, and verifies health (`200`), a synthetic assessment (`200`, High, five reasons, `no-store`), invalid input (`400`), and the configured non-root user and read-only filesystem. It prints container logs and removes only its test container on success or failure. A failed assertion exits with an error and fails the CI job. No Python test packages or AWS credentials are required on the host.

Check the `container` job in the pull request's checks or the repository's Actions tab for the GitHub result. The AWS job waits for both the existing checks and container checks to pass. This job tests the image without publishing it to a registry or deploying it.

## Stop the Local Test

```powershell
docker stop clinical-trial-risk-local
docker rm clinical-trial-risk-local
```

These commands stop and remove only the named development container. Do not run broad Docker cleanup commands against unrelated containers or images.

No ECR push, EKS provisioning, AWS infrastructure change, or Lambda integration is part of this step.
