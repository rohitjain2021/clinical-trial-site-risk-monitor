"""Local prototype risk calculation; not connected to the deployed API."""

import re

RULES_VERSION = "prototype-v1"
COUNT_FIELDS = (
    "enrollment_target", "actual_enrollment", "days_behind_schedule",
    "patient_dropout_count", "protocol_deviation_count", "unresolved_issue_count",
)


def calculate_risk(site):
    """Validate one site and apply the documented prototype operational rules.

    Compare integer ratios before rounding, collect reasons in metric order,
    and choose the highest level. This pure function lets us test risk rules
    locally before adding FastAPI, storage, or any AWS integration. Invalid
    records raise ValueError; the input dictionary is never modified.
    """
    required_fields = {"site_id", "site_name", *COUNT_FIELDS}
    if not isinstance(site, dict) or set(site) != required_fields:
        raise ValueError("Provide one site object with exactly the documented fields.")

    site_id = site["site_id"]
    name = site["site_name"]
    if not isinstance(site_id, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", site_id):
        raise ValueError("site_id must contain 1-64 letters, digits, underscores, or hyphens.")
    if not isinstance(name, str) or not 1 <= len(name.strip()) <= 200:
        raise ValueError("site_name must contain 1-200 nonblank characters.")
    for field in COUNT_FIELDS:
        if type(site[field]) is not int or site[field] < 0:
            raise ValueError(f"{field} must be a nonnegative integer.")

    target = site["enrollment_target"]
    enrolled = site["actual_enrollment"]
    delay = site["days_behind_schedule"]
    dropouts = site["patient_dropout_count"]
    if target == 0:
        raise ValueError("enrollment_target must be greater than zero.")
    if dropouts > enrolled:
        raise ValueError("patient_dropout_count cannot exceed actual_enrollment.")

    levels = []
    reasons = []

    # Compare ratios using integers so values on a threshold are classified exactly.
    if enrolled * 100 < target * 50:
        levels.append("High")
        reasons.append(f"Enrollment is {enrolled / target * 100:.2f}% of target, below the 50% threshold.")
    elif enrolled * 100 < target * 80:
        levels.append("Medium")
        reasons.append(f"Enrollment is {enrolled / target * 100:.2f}% of target, below the 80% threshold.")

    if delay >= 15:
        levels.append("High")
        reasons.append(f"The site is {delay} days behind schedule, meeting the High threshold of 15 days.")
    elif delay >= 8:
        levels.append("Medium")
        reasons.append(f"The site is {delay} days behind schedule, meeting the Medium threshold of 8 days.")

    # No enrollment means no observed dropout rate, so do not evaluate that metric.
    if enrolled > 0:
        if dropouts * 100 > enrolled * 10:
            levels.append("High")
            reasons.append(f"Dropouts are {dropouts / enrolled * 100:.2f}% of enrolled patients, above the 10% threshold.")
        elif dropouts * 100 > enrolled * 5:
            levels.append("Medium")
            reasons.append(f"Dropouts are {dropouts / enrolled * 100:.2f}% of enrolled patients, above the 5% threshold.")

    for field, singular, plural in (
        ("protocol_deviation_count", "protocol deviation", "protocol deviations"),
        ("unresolved_issue_count", "unresolved issue", "unresolved issues"),
    ):
        count = site[field]
        if count >= 3:
            levels.append("High")
            reasons.append(f"There are {count} {plural}, meeting the High threshold of 3.")
        elif count >= 1:
            levels.append("Medium")
            if count == 1:
                reasons.append(f"There is 1 {singular}, meeting the Medium threshold of 1.")
            else:
                reasons.append(f"There are {count} {plural}, meeting the Medium threshold of 1.")

    if "High" in levels:
        risk_level = "High"
    elif "Medium" in levels:
        risk_level = "Medium"
    else:
        risk_level = "Low"
        reasons.append("No monitored metric exceeded the prototype thresholds.")

    return {
        "site_id": site_id,
        "risk_level": risk_level,
        "rules_version": RULES_VERSION,
        "reasons": reasons,
    }
