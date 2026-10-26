"""Local FastAPI wrapper around the tested prototype risk calculator."""

import json

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from starlette.concurrency import run_in_threadpool

from services.risk_service.risk import RULES_VERSION, calculate_risk
from services.risk_service.explanation import explain_risk

app = FastAPI(title="Clinical Trial Site Risk Service", version=RULES_VERSION)
MAX_BODY_BYTES = 64 * 1024


@app.get("/health")
def health():
    """Return service readiness and rule version for local connectivity checks."""
    return {"status": "ok", "service": "clinical-trial-risk-service", "rules_version": RULES_VERSION}


@app.post("/site-assessments")
async def assess_site(request: Request):
    """Read one JSON site and call the existing calculator without storing data.

    Reuse calculator validation rather than duplicate the field schema. Bound
    the body to 64 KiB and return safe errors without echoing submitted values.
    Run the optional blocking model call in a worker thread to keep health
    requests responsive. Classification remains entirely rule-based.
    """
    content_type = request.headers.get("content-type", "").split(";", 1)[0].strip().lower()
    if content_type != "application/json":
        raise HTTPException(status_code=415, detail="Content-Type must be application/json.")

    body = bytearray()
    async for chunk in request.stream():
        if len(body) + len(chunk) > MAX_BODY_BYTES:
            raise HTTPException(status_code=413, detail="Body exceeds the 64 KiB limit.")
        body.extend(chunk)
    try:
        site = json.loads(body.decode("utf-8"))
    except ValueError:
        raise HTTPException(status_code=400, detail="Body must contain valid UTF-8 JSON.") from None

    try:
        result = calculate_risk(site)
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from None
    explanation = await run_in_threadpool(explain_risk, result)
    if explanation is not None:
        result["explanation"] = explanation
    return JSONResponse(content=result, headers={"Cache-Control": "no-store"})
