"""Health checks and validation-only site submissions for the initial HTTP API."""

import base64
import binascii
import json
import re

MAX_BODY_BYTES = 64 * 1024
COUNT_FIELDS = (
    "enrollment_target", "actual_enrollment", "days_behind_schedule",
    "patient_dropout_count", "protocol_deviation_count", "unresolved_issue_count",
)


def _response(status_code, body):
    """Serialize JSON responses consistently; no-store prevents submission caching."""
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json", "Cache-Control": "no-store"},
        "body": json.dumps(body),
    }


def _validate_site(record):
    """Check aggregate fields before future risk analysis; reject unknown fields.

    Return field errors without echoing values so error responses do not repeat
    potentially sensitive input. Patient-level fields are outside this contract.
    """
    if not isinstance(record, dict):
        return ["The body must be one JSON object."]
    required = {"site_id", "site_name", *COUNT_FIELDS}
    errors = []
    if set(record) != required:
        errors.append("Provide exactly the documented site fields.")
    site_id = record.get("site_id")
    if not isinstance(site_id, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", site_id):
        errors.append("site_id must contain 1-64 letters, digits, underscores, or hyphens.")
    site_name = record.get("site_name")
    if not isinstance(site_name, str) or not 1 <= len(site_name.strip()) <= 200:
        errors.append("site_name must contain 1-200 nonblank characters.")
    for field in COUNT_FIELDS:
        value = record.get(field)
        if type(value) is not int or value < 0:
            errors.append(f"{field} must be a nonnegative integer.")
    if type(record.get("enrollment_target")) is int and record["enrollment_target"] == 0:
        errors.append("enrollment_target must be greater than zero.")
    if (type(record.get("patient_dropout_count")) is int
            and type(record.get("actual_enrollment")) is int
            and record["patient_dropout_count"] > record["actual_enrollment"]):
        errors.append("patient_dropout_count cannot exceed actual_enrollment.")
    return errors


def lambda_handler(event, context):
    """Route HTTP API v2 events to health checks or synchronous site validation.

    Empty direct invocations remain health probes for the existing pipeline.
    POST does not save data, queue work, or calculate risk. Context is unused
    because neither operation needs AWS invocation metadata.
    """
    route = event.get("routeKey")
    if event == {} or route == "GET /health":
        return _response(200, {"status": "ok", "service": "clinical-trial-site-risk-monitor"})
    if route != "POST /site-assessments":
        return _response(404, {"error": "Route not found."})
    headers = {key.lower(): value for key, value in (event.get("headers") or {}).items()}
    if headers.get("content-type", "").split(";", 1)[0].strip().lower() != "application/json":
        return _response(415, {"error": "Content-Type must be application/json."})
    body = event.get("body") or ""
    if not isinstance(body, str):
        return _response(400, {"error": "Invalid request body."})
    if len(body) > MAX_BODY_BYTES * 2:
        return _response(413, {"error": "Body exceeds the 64 KiB limit."})
    try:
        raw = base64.b64decode(body, validate=True) if event.get("isBase64Encoded") else body.encode("utf-8")
        if len(raw) > MAX_BODY_BYTES:
            return _response(413, {"error": "Body exceeds the 64 KiB limit."})
        record = json.loads(raw.decode("utf-8"))
    except (ValueError, UnicodeError, binascii.Error):
        return _response(400, {"error": "Body must contain valid UTF-8 JSON."})
    errors = _validate_site(record)
    if errors:
        return _response(400, {"error": "Invalid site data.", "details": errors})
    return _response(200, {
        "status": "validated", "site_id": record["site_id"],
        "message": "Site data is valid. Storage and risk analysis are not implemented yet.",
    })
