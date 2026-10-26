"""Optional Nova Micro summaries of deterministic operational risk results."""

from functools import lru_cache
import json
import os

import boto3
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError
import botocore.session

MODEL_ID = "amazon.nova-micro-v1:0"
MAX_EXPLANATION_CHARS = 2000


@lru_cache(maxsize=1)
def bedrock_client():
    """Reuse the SDK client and refreshable pod credentials with bounded AWS calls.

    Default configuration also bounds the STS web-identity exchange. One attempt
    avoids retrying model charges while the request is waiting for an explanation.
    """
    session = botocore.session.get_session()
    session.set_default_client_config(Config(connect_timeout=1, read_timeout=3,
                                             retries={"total_max_attempts": 1}))
    return boto3.Session(botocore_session=session).client("bedrock-runtime", region_name="us-east-1")


def explain_risk(result):
    """Summarize only calculated reasons; failure never changes or hides the score.

    Local tests and containers make no AWS calls unless BEDROCK_ENABLED is true.
    No site identifiers, raw submissions, credentials, or conversation history
    are sent. Model errors and incomplete output return a generic status only.
    """
    if os.environ.get("BEDROCK_ENABLED") != "true":
        return None
    explanation = {"status": "unavailable", "model_id": MODEL_ID, "text": None}
    summary = {key: result[key] for key in ("risk_level", "rules_version", "reasons")}
    try:
        response = bedrock_client().converse(
            modelId=MODEL_ID,
            system=[{"text": (
                "Explain the supplied prototype clinical-trial SITE OPERATIONAL risk result "
                "in 2 or 3 short plain-language sentences. Use only the supplied risk level "
                "and reasons. Keep that risk level unchanged. Do not invent facts, numbers, "
                "causes, predictions, recommendations, or medical advice. This is operational "
                "monitoring, not a patient safety or treatment assessment. Return plain text only."
            )}],
            messages=[{"role": "user", "content": [{"text": json.dumps(summary)}]}],
            inferenceConfig={"maxTokens": 180, "temperature": 0},
        )
        text = " ".join(block["text"] for block in response["output"]["message"]["content"] if "text" in block).strip()
        if response.get("stopReason") == "end_turn" and 0 < len(text) <= MAX_EXPLANATION_CHARS:
            explanation.update(status="available", text=text)
    except (BotoCoreError, ClientError, KeyError, TypeError, ValueError):
        pass
    return explanation
