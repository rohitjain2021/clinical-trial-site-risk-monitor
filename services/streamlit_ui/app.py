"""Simple local JSON interface for the existing FastAPI risk service."""

import json
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

import streamlit as st

API_URL = "http://127.0.0.1:8000/site-assessments"
SAMPLE_PATH = Path(__file__).resolve().parents[2] / "docs/examples/site-assessment.json"


def assess_site(text):
    """Send one JSON record to local FastAPI, keeping risk rules out of the UI.

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
    request = Request(API_URL, data=payload, headers={"Content-Type": "application/json"})
    try:
        with urlopen(request, timeout=10) as response:
            return json.load(response)
    except HTTPError as error:
        if error.code == 400:
            raise ValueError(json.load(error).get("detail", "Check the site fields against the sample.")) from None
        raise ValueError("The risk service could not assess this record. Please try again.") from None
    except (URLError, TimeoutError):
        raise ValueError("The local risk service is unavailable. Start FastAPI, then try again.") from None


def main():
    """Render a paste-and-submit page with sample data and readable risk reasons.

    Submit only on the form button, then show the backend's result. Editing the
    record clears the old result on the next submit; no uploaded data is stored.
    """
    st.set_page_config(page_title="Clinical Trial Site Risk Monitor", page_icon="🏥")
    st.title("Clinical Trial Site Risk Monitor")
    st.caption("Paste a site record to review operational risk. Use synthetic data only.")
    sample = SAMPLE_PATH.read_text(encoding="utf-8")

    with st.form("site_assessment"):
        text = st.text_area("Site data (JSON)", value=sample, height=300, max_chars=65536)
        submitted = st.form_submit_button("Assess site", type="primary")

    if submitted:
        try:
            result = assess_site(text)
        except ValueError as error:
            st.error(str(error))
        else:
            st.subheader(f"Result for {result['site_id']}")
            st.metric("Risk level", result["risk_level"])
            st.write("**Reasons**")
            for reason in result["reasons"]:
                st.write("- " + reason)
            st.caption("Prototype rules: " + result["rules_version"])

    with st.expander("Copy sample JSON"):
        st.code(sample, language="json")
    st.caption("Prototype operational rules; thresholds require review before use in real trials.")


if __name__ == "__main__":
    main()
