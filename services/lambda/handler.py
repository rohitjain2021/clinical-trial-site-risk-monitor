"""Validate aggregate site records and request risk assessments through the private ALB."""

import base64
import binascii
import json
from http.client import HTTPException
import os
import re
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

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
    """Check aggregate fields before forwarding to FastAPI; reject unknown fields.

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

    target = record.get("enrollment_target")
    enrolled = record.get("actual_enrollment")
    dropouts = record.get("patient_dropout_count")
    if type(target) is int and target == 0:
        errors.append("enrollment_target must be greater than zero.")
    if type(dropouts) is int and type(enrolled) is int:
        if dropouts > enrolled:
            errors.append("patient_dropout_count cannot exceed actual_enrollment.")
    return errors


def _assess_site(record):
    """Call the configured private backend without forwarding client credentials.

    Bound HTTP time and response size, verify the result belongs to this site,
    and expose only the documented risk fields. Backend failures stay generic
    so responses cannot leak internal URLs or submitted data.
    """
    base = os.environ.get("RISK_API_URL")
    if not base:
        return _response(503, {"error": "Risk service is not configured."})
    request = Request(base + "/site-assessments",
                      data=json.dumps(record, separators=(",", ":")).encode("utf-8"),
                      headers={"Content-Type": "application/json"})
    try:
        with urlopen(request, timeout=3) as response:
            raw = response.read(MAX_BODY_BYTES + 1)
            if response.status != 200 or len(raw) > MAX_BODY_BYTES:
                return _response(502, {"error": "Invalid risk service response."})
            result = json.loads(raw.decode("utf-8"))
        if not isinstance(result, dict) or result.get("site_id") != record["site_id"]:
            return _response(502, {"error": "Invalid risk service response."})
        if (result.get("risk_level") not in ("Low", "Medium", "High")
                or not isinstance(result.get("rules_version"), str) or not result["rules_version"]
                or not isinstance(result.get("reasons"), list) or not result["reasons"]
                or not all(isinstance(reason, str) and reason for reason in result["reasons"])):
            return _response(502, {"error": "Invalid risk service response."})
        return _response(200, {key: result[key] for key in ("site_id", "risk_level", "rules_version", "reasons")})
    except HTTPError as error:
        error.close()
        return _response(502, {"error": "Risk service request failed."})
    except TimeoutError:
        return _response(504, {"error": "Risk service timed out."})
    except URLError as error:
        status = 504 if isinstance(error.reason, TimeoutError) else 503
        return _response(status, {"error": "Risk service is unavailable."})
    except OSError:
        return _response(503, {"error": "Risk service is unavailable."})
    except (ValueError, UnicodeError, HTTPException):
        return _response(502, {"error": "Invalid risk service response."})


def lambda_handler(event, context):
    """Route HTTP API v2 events to liveness or validated synchronous assessment.

    Empty direct invocations remain health probes for the existing pipeline.
    FastAPI owns risk calculation; this handler validates and forwards without
    storing records. Liveness remains available when the backend is disconnected.
    """
    route = event.get("routeKey")
    if event == {} or route == "GET /health":
        return _response(200, {"status": "ok", "service": "clinical-trial-site-risk-monitor"})
    if route != "POST /site-assessments":
        return _response(404, {"error": "Route not found."})
    headers = {key.lower(): value for key, value in (event.get("headers") or {}).items()}
    content_type = headers.get("content-type", "").split(";", 1)[0].strip().lower()
    if content_type != "application/json":
        return _response(415, {"error": "Content-Type must be application/json."})
    body = event.get("body") or ""
    if not isinstance(body, str):
        return _response(400, {"error": "Invalid request body."})
    if len(body) > MAX_BODY_BYTES * 2:
        return _response(413, {"error": "Body exceeds the 64 KiB limit."})
    try:
        if event.get("isBase64Encoded"):
            raw = base64.b64decode(body, validate=True)
        else:
            raw = body.encode("utf-8")
        if len(raw) > MAX_BODY_BYTES:
            return _response(413, {"error": "Body exceeds the 64 KiB limit."})
        record = json.loads(raw.decode("utf-8"))
    except (ValueError, UnicodeError, binascii.Error):
        return _response(400, {"error": "Body must contain valid UTF-8 JSON."})
    errors = _validate_site(record)
    if errors:
        return _response(400, {"error": "Invalid site data.", "details": errors})
    return _assess_site(record)
