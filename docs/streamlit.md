# Local Streamlit Interface

A simple local page lets you paste one site record as JSON, click **Assess site**, and read its risk level and reasons. The text box starts with the existing [synthetic sample](examples/site-assessment.json); **Copy sample JSON** also shows a code block with a copy button. CSV uploads are not required.

The UI sends the record to FastAPI at `http://127.0.0.1:8000/site-assessments`, which validates it and runs the existing prototype rules. The frontend does not duplicate the calculator. It does not store submissions or connect to AWS, Snowflake, or Bedrock. It has no authentication and must stay bound to localhost. Use synthetic data only.

## Install

From the repository root in PowerShell:

```powershell
python -m venv services/streamlit_ui/.venv
services/streamlit_ui/.venv/Scripts/python.exe -m pip install -r services/streamlit_ui/requirements.txt
```

Streamlit is pinned in its own requirements file and virtual environment. The installation does not change Lambda or the risk-service container dependencies.

## Run Locally

Start the existing FastAPI service in one terminal (see the [risk-service setup](risk-service.md) if its environment is not installed):

```powershell
services/risk_service/.venv/Scripts/python.exe -m uvicorn services.risk_service.app:app --host 127.0.0.1 --port 8000 --no-access-log
```

In a second terminal, start Streamlit:

```powershell
services/streamlit_ui/.venv/Scripts/python.exe -m streamlit run services/streamlit_ui/app.py --server.address 127.0.0.1 --server.port 8501 --server.headless true --browser.gatherUsageStats false
```

Open `http://127.0.0.1:8501`, leave the sample in the box, and click **Assess site**. Expect **High** risk and five reasons. Try changing the numbers or paste another record with exactly the sample's fields. Invalid JSON or invalid field values should show a readable error.

Keep both terminals running while testing; press **Ctrl+C** in each when finished. Running locally requires no EKS cluster or AWS deployment. Later, the hosted UI will call authenticated API Gateway after Lambda-to-FastAPI integration is complete.

## Validation Status

Streamlit `1.66.1` was installed in the isolated UI environment and verified locally on October 25, 2026 using Python `3.15`. Lambda and existing CI remain on Python `3.13`.

Both local HTTP health checks passed. Streamlit's AppTest exercised the real form against local FastAPI: the sample returned High with five reasons; representative Medium and Low records returned the expected levels; malformed JSON and invalid fields displayed errors without an uncaught exception; correcting the input restored the successful result. These were local checks, not cloud UI deployment or GitHub CI execution. Cloud hosting and full application integration remain planned.
