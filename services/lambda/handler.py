"""Basic health response for the Clinical Trial Site Risk Monitor."""

import json


def lambda_handler(event, context):
    """Return HTTP 200 with a JSON health response in API Gateway proxy format.

    This initial handler verifies deployment and invocation before risk-service
    integration. It intentionally ignores event and context because the health
    response does not depend on request data or AWS invocation metadata.
    """
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(
            {"status": "ok", "service": "clinical-trial-site-risk-monitor"}
        ),
    }
