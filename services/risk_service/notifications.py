"""Best-effort SNS email events for the small Bedrock assessment demo."""

from datetime import datetime, timezone
from functools import lru_cache
import logging
import os
import re

import boto3
import botocore.session
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError

logger = logging.getLogger("uvicorn.error")


@lru_cache(maxsize=1)
def notification_client():
    """Reuse refreshable pod credentials and bound SNS/STS calls without retries.

    This client runs after the HTTP response; failures cannot delay or replace
    the assessment result. No static AWS credentials are supplied by the app.
    """
    session = botocore.session.get_session()
    session.set_default_client_config(Config(connect_timeout=1, read_timeout=2,
                                             retries={"total_max_attempts": 1}))
    return boto3.Session(botocore_session=session).client("sns", region_name="us-east-1")


def notify_assessment(risk_level, ai_status):
    """Publish one minimal event after a Bedrock attempt; keep errors private.

    The optional topic enables notifications. Only status metadata is accepted,
    so site identifiers, raw records, model text, and credentials cannot enter
    the email. This in-process demo is best effort, not a durable message queue.
    """
    topic = os.environ.get("ASSESSMENT_SNS_TOPIC_ARN")
    if not topic:
        return False
    if (not re.fullmatch(r"arn:aws:sns:us-east-1:[0-9]{12}:clinical-trial-site-risk-monitor-dev-assessments", topic)
            or risk_level not in ("Low", "Medium", "High")
            or ai_status not in ("available", "unavailable")):
        logger.warning("Assessment notification configuration or status is invalid.")
        return False
    message = (
        "Clinical Trial Site Risk Monitor - development demo\n\n"
        "A site assessment attempted Amazon Bedrock.\n"
        f"Risk level: {risk_level}\n"
        f"AI explanation: {'Generated successfully' if ai_status == 'available' else 'Unavailable; risk assessment completed'}\n"
        "Model: Amazon Nova Micro\n"
        f"Processed at (UTC): {datetime.now(timezone.utc).isoformat(timespec='seconds')}\n\n"
        "This is a prototype operational assessment, not a patient safety assessment.\n"
        "No site identifiers or submitted data are included."
    )
    try:
        notification_client().publish(
            TopicArn=topic, Subject="Clinical Trial Risk Monitor - assessment processed", Message=message,
        )
    except (BotoCoreError, ClientError, OSError):
        logger.warning("Assessment notification could not be published.")
        return False
    logger.info("Assessment notification published.")
    return True
