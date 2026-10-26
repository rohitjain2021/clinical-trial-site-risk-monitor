"""Paste one synthetic site record and call local FastAPI or the signed AWS API."""

import json
from pathlib import Path
import re
from http.client import HTTPException
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

import streamlit as st
import boto3
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest
from botocore.exceptions import BotoCoreError

API_URL = "http://127.0.0.1:8000/site-assessments"
SAMPLE_PATH = Path(__file__).resolve().parents[2] / "docs/examples/site-assessment.json"


def assess_site(text, config=None):
    """Send one JSON record, signing cloud calls on the server to keep AWS keys private.

    Parse JSON for a friendly syntax error, bound the request size, and use a
    timeout so an unavailable service cannot leave the page waiting indefinitely.
    The backend remains responsible for field validation and classification.
    """
    try:
        payload = json.dumps(json.loads(text)).encode("utf-8")
    except ValueError:
        raise ValueError("Enter valid JSON. You can copy the sample below.") from None
    if len(payload) > 64 * 1024:
        raise ValueError("Site data must be no larger than 64 KiB.")
    config = config or {}
    url = API_URL
    headers = {"Content-Type": "application/json"}
    base_url = config.get("risk_api", {}).get("base_url")
    if base_url:
        if not re.fullmatch(r"https://[a-z0-9]+\.execute-api\.us-east-1\.amazonaws\.com/dev", base_url):
            raise ValueError("The cloud API configuration is invalid. Contact the app owner.")
        url = base_url + "/site-assessments"
        try:
            aws = config.get("aws", {})
            if aws and (not aws.get("access_key_id") or not aws.get("secret_access_key")):
                raise ValueError("Cloud API credentials are incomplete. Contact the app owner.")
            session = boto3.Session(
                aws_access_key_id=aws.get("access_key_id"),
                aws_secret_access_key=aws.get("secret_access_key"),
                aws_session_token=aws.get("session_token"),
                region_name="us-east-1",
            )
            credentials = session.get_credentials()
            if credentials is None:
                raise ValueError("Cloud API credentials are missing. Contact the app owner.")
            signed = AWSRequest(method="POST", url=url, data=payload, headers=headers)
            SigV4Auth(credentials.get_frozen_credentials(), "execute-api", "us-east-1").add_auth(signed)
            headers = dict(signed.headers)
        except BotoCoreError:
            raise ValueError("Cloud API credentials are unavailable. Contact the app owner.") from None
    request = Request(url, data=payload, headers=headers)
    try:
        with urlopen(request, timeout=25) as response:
            raw = response.read(65537)
            if len(raw) > 65536:
                raise ValueError
            result = json.loads(raw)
            if (not isinstance(result, dict) or result.get("risk_level") not in ("Low", "Medium", "High")
                    or not isinstance(result.get("site_id"), str)
                    or not isinstance(result.get("rules_version"), str)
                    or not isinstance(result.get("reasons"), list)
                    or not result["reasons"]
                    or not all(isinstance(reason, str) for reason in result["reasons"])):
                raise ValueError
            return result
    except HTTPError as error:
        with error:
            if error.code == 400:
                raise ValueError("Check the site fields against the sample.") from None
            if error.code in (401, 403):
                raise ValueError("Cloud API access was denied. Ask the app owner to check credentials and permissions.") from None
        raise ValueError("The risk service could not assess this record. Please try again.") from None
    except (URLError, TimeoutError, OSError):
        raise ValueError("The risk service is unavailable. Please try again later.") from None
    except (ValueError, UnicodeError, HTTPException):
        raise ValueError("The risk service returned an invalid response. Please try again.") from None


def read_config():
    """Read server-side Streamlit secrets; no file means the existing local demo mode."""
    try:
        return st.secrets.to_dict()
    except FileNotFoundError:
        return {}


def main():
    """Render a paste-and-submit page with sample data and readable risk reasons.

    Submit only on the form button, then show the backend's result. Editing the
    record clears the old result on the next submit; no uploaded data is stored.
    """
    st.set_page_config(page_title="Clinical Trial Site Risk Monitor", page_icon="🏥")
    st.title("Clinical Trial Site Risk Monitor")
    st.caption("Paste a site record to review operational risk. Use synthetic data only.")
    config = read_config()
    st.caption("Backend: AWS API" if config.get("risk_api", {}).get("base_url") else "Backend: local FastAPI")
    sample = SAMPLE_PATH.read_text(encoding="utf-8")

    with st.form("site_assessment"):
        text = st.text_area("Site data (JSON)", value=sample, height=300, max_chars=65536)
        submitted = st.form_submit_button("Assess site", type="primary")

    if submitted:
        try:
            with st.spinner("Assessing site..."):
                result = assess_site(text, config)
        except ValueError as error:
            st.error(str(error))
        else:
            st.subheader(f"Result for {result['site_id']}")
            st.metric("Risk level", result["risk_level"])
            st.write("**Reasons**")
            for reason in result["reasons"]:
                st.write("- " + reason)
            st.caption("Prototype rules: " + result["rules_version"])
            explanation = result.get("explanation")
            if isinstance(explanation, dict):
                st.subheader("AI explanation")
                if explanation.get("status") == "available" and isinstance(explanation.get("text"), str):
                    st.text(explanation["text"])
                    st.caption("AI-generated summary; the risk level is calculated by the prototype rules.")
                else:
                    st.info("AI explanation is unavailable. The risk level and reasons are still shown above.")

    with st.expander("Copy sample JSON"):
        st.code(sample, language="json")
    st.caption("Prototype operational rules; thresholds require review before use in real trials.")


if __name__ == "__main__":
    main()
