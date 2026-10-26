"""Clinical operations dashboard with plain-language input and signed API requests."""

import json
from html import escape
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
SAMPLE_PATH = Path(__file__).resolve().parents[2] / "docs/examples/site-report.txt"
SITE_FIELDS = {
    "Site ID": "site_id", "Site name": "site_name",
    "Enrollment target": "enrollment_target", "Patients enrolled": "actual_enrollment",
    "Days behind schedule": "days_behind_schedule", "Patient dropouts": "patient_dropout_count",
    "Protocol deviations": "protocol_deviation_count", "Unresolved issues": "unresolved_issue_count",
}


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
                raise ValueError("Check the site details against the sample, then try again.") from None
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



def parse_report(text):
    """Convert a labelled site report into the API schema without AI or guesswork.

    Require each familiar field once, preserve names as text, and parse whole
    counts. Field validation and risk classification remain in the backend.
    """
    if len(text.encode("utf-8")) > 65536:
        raise ValueError("Keep the site report below 64 KiB.")
    labels = {label.casefold(): field for label, field in SITE_FIELDS.items()}
    record = {}
    for line in text.splitlines():
        if not line.strip():
            continue
        label, separator, value = line.partition(":")
        field = labels.get(label.strip().casefold())
        if not separator or field is None:
            raise ValueError("Use the field names in the sample, with one 'Field: value' per line.")
        if field in record:
            raise ValueError("Each field should appear only once in the report.")
        value = value.strip()
        if not value:
            raise ValueError("Fill in every field before assessing the site.")
        if field not in ("site_id", "site_name"):
            if not re.fullmatch(r"[0-9]+", value):
                raise ValueError("Use nonnegative whole numbers for all counts and days.")
            try:
                value = int(value)
            except ValueError:
                raise ValueError("A number in the report is too large. Check the counts and days.") from None
        record[field] = value
    missing = [label for label, field in SITE_FIELDS.items() if field not in record]
    if missing:
        raise ValueError("Add the missing fields: " + ", ".join(missing) + ".")
    return record


def report_text(site):
    """Format a synthetic example as readable lines users can copy without JSON syntax."""
    return "\n".join(f"{label}: {site[field]}" for label, field in SITE_FIELDS.items())


def sample_sites():
    """Provide three clearly synthetic scenarios to explore the existing risk rules."""
    delayed = parse_report(SAMPLE_PATH.read_text(encoding="utf-8"))
    return {
        "Delayed enrollment": delayed,
        "Some operational concerns": {
            **delayed, "site_id": "SITE-002", "site_name": "Harborview Study Center",
            "actual_enrollment": 45, "days_behind_schedule": 9,
            "patient_dropout_count": 1, "protocol_deviation_count": 0, "unresolved_issue_count": 1,
        },
        "Meeting operational targets": {
            **delayed, "site_id": "SITE-003", "site_name": "Lakeside Research Clinic",
            "actual_enrollment": 54, "days_behind_schedule": 0,
            "patient_dropout_count": 1, "protocol_deviation_count": 0, "unresolved_issue_count": 0,
        },
    }


def site_form(example, mode):
    """Render paste or manual input, then return the submitted record and any error.

    Keep one submit action so editing examples never triggers AWS calls. Both
    input methods produce the same single-site contract used by the existing API.
    """
    with st.form("site_assessment", border=False):
        if mode == "Paste a report":
            text = st.text_area("Site report", value=report_text(example), height=290,
                                max_chars=65536, help="One field per line. Use the example's field names.")
        else:
            site = {}
            site["site_id"] = st.text_input("Site ID", value=example["site_id"], max_chars=64,
                                          help="Use letters, numbers, hyphens, or underscores, such as SITE-001.")
            site["site_name"] = st.text_input("Site name", value=example["site_name"], max_chars=200)
            columns = st.columns(2)
            for index, (label, field) in enumerate(list(SITE_FIELDS.items())[2:]):
                with columns[index % 2]:
                    site[field] = st.number_input(label, min_value=1 if field == "enrollment_target" else 0,
                                                  value=example[field], step=1)
        submitted = st.form_submit_button("Assess site", type="primary", width="stretch")
    if not submitted:
        return None, None
    try:
        return (parse_report(text) if mode == "Paste a report" else site), None
    except ValueError as error:
        return None, str(error)


def show_result(result, site):
    """Present the submitted site's metrics, backend reasons, and optional AI summary.

    Calculate only display percentages here. The API owns the risk rating. Escape
    all dynamic HTML and keep model output as plain text so input cannot add markup.
    """
    level = result["risk_level"]
    st.html(f'<span class="risk-badge risk-{level.lower()}">{level} operational risk</span>'
            f'<div class="site-heading">{escape(site["site_name"])}</div>'
            f'<p class="site-reference">{escape(result["site_id"])} &middot; Assessed site snapshot</p>')
    enrollment = site["actual_enrollment"] / site["enrollment_target"]
    first, second = st.columns(2)
    first.metric("Risk level", level, border=True)
    second.metric("Enrollment", f"{enrollment:.0%}", border=True,
                  help=f'{site["actual_enrollment"]} of {site["enrollment_target"]} patients enrolled')
    first, second = st.columns(2)
    first.metric("Behind schedule", f'{site["days_behind_schedule"]} days', border=True)
    second.metric("Unresolved issues", str(site["unresolved_issue_count"]), border=True)
    st.progress(min(enrollment, 1.0), text=f'{site["actual_enrollment"]} of {site["enrollment_target"]} patients enrolled')
    st.caption(f'Dropouts: {site["patient_dropout_count"]}  ·  Protocol deviations: {site["protocol_deviation_count"]}')
    st.subheader("Why this rating?")
    for number, reason in enumerate(result["reasons"], start=1):
        st.html(f'<div class="reason-card"><span class="reason-number">{number}</span>'
                f'<span class="reason-text">{escape(reason)}</span></div>')
    st.caption("Rule-based assessment · " + result["rules_version"])
    explanation = result.get("explanation")
    if isinstance(explanation, dict):
        with st.container(border=True, key="explanation"):
            st.subheader("AI explanation")
            if explanation.get("status") == "available" and isinstance(explanation.get("text"), str):
                st.text(explanation["text"])
                st.caption("AI-generated summary of the result above. The rating is calculated by the rules.")
            else:
                st.info("AI explanation is unavailable. The risk level and reasons are still shown above.")


def main():
    """Render the clinical dashboard and call the existing API only on assessment.

    Example changes and input-mode switches clear the visible result. The right
    panel shows only a completed submission, never invented demo ratings or trends.
    """
    st.set_page_config(page_title="Clinical Trial Site Risk Monitor", page_icon="🏥", layout="wide")
    st.html("<style>" + Path(__file__).with_name("style.css").read_text(encoding="utf-8") + "</style>")
    config = read_config()
    with st.sidebar:
        st.html('<div class="sidebar-brand"><span class="brand-monogram">CT</span>'
                '<span class="brand-name">Clinical Trial<br>Site Risk Monitor</span></div>'
                '<div class="workspace-nav">Site assessment</div>')
        st.caption("A SIMPLE SITE REVIEW")
        st.markdown("**1. Add site details**\n\nPaste a report or fill in the fields.\n\n"
                    "**2. Run an assessment**\n\nReview the operational rating and reasons.\n\n"
                    "**3. Read the explanation**\n\nCompare the AI summary with the rule-based result.")
        st.divider()
        st.caption("Development prototype. Use synthetic site data only.")
        with st.expander("Connection details"):
            st.caption("Backend: AWS API" if config.get("risk_api", {}).get("base_url") else "Backend: local FastAPI")
    with st.container(key="workspace"):
        st.html('<div class="workspace-hero"><p class="eyebrow">Clinical operations workspace</p>'
                '<h1>Clinical Trial Site Risk Monitor</h1>'
                '<p>Turn site performance data into a clear view of operational risk.</p>'
                '<div class="hero-tags"><span>Enrollment &amp; timelines</span>'
                '<span>Rule-based ratings</span><span>AI explanations</span></div></div>')
        left, right = st.columns([1, 1.12], gap="large")
        with left, st.container(border=True, key="input_panel"):
            st.html('<p class="section-kicker">01 / Site details</p><h2 class="section-heading">Start with a site</h2>'
                    '<p class="section-description">Paste a short site report or enter the values below. No JSON needed.</p>')
            examples = sample_sites()
            selected = st.selectbox("Try a synthetic example", list(examples))
            mode = st.radio("Input method", ["Paste a report", "Fill in fields"], horizontal=True)
            site, error = site_form(examples[selected], mode)
            if error:
                st.error(error)
            with st.expander("Copy a sample report"):
                st.code(report_text(examples[selected]), language=None)
            st.caption("One site per assessment. Your submission is not saved to a database.")
        with right, st.container(border=True, key="result_panel"):
            st.html('<p class="section-kicker">02 / Assessment</p><h2 class="section-heading">Your site at a glance</h2>'
                    '<p class="section-description">The rating, contributing factors, and explanation in one place.</p>')
            if site is not None:
                try:
                    with st.spinner("Reviewing site performance..."):
                        result = assess_site(json.dumps(site), config)
                except ValueError as error:
                    st.error(str(error))
                else:
                    show_result(result, site)
            else:
                st.html('<div class="empty-state"><div class="empty-symbol">◎</div>'
                        '<h3>Your assessment will appear here</h3>'
                        '<p>Add site details on the left, then select <strong>Assess site</strong>.'
                        '<br>We will show the rating, reasons, and an AI explanation when available.</p></div>')
                first, second = st.columns(2)
                first.metric("Enrollment", "—", border=True)
                second.metric("Schedule delay", "—", border=True)
        st.caption("Prototype operational rules. Review thresholds before real-world use. "
                   "This tool does not assess patient safety or treatment risk.")


if __name__ == "__main__":
    main()
