# Prototype Operational Risk Rules

**Rule version: `prototype-v1`. Status: proposed baseline for local implementation and testing.**

These thresholds are project assumptions, not clinically validated standards or trial-approved operating limits. They identify potential operational concerns, not patient safety or treatment risk. Review them with clinical operations before using classifications to make operational decisions.

The calculation is implemented locally in `services/risk_service/risk.py`. The deployed API still validates data only; the calculator is not connected to it or deployed.

## Inputs

Use the existing [site submission contract](api.md#submission-contract). No additional fields are needed for this prototype:

- `site_id` and `site_name` identify the site; they do not affect risk.
- `enrollment_target` and `actual_enrollment` describe enrollment progress.
- `days_behind_schedule` describes the site's current operational delay.
- `patient_dropout_count` is the number of enrolled patients who dropped out.
- `protocol_deviation_count` and `unresolved_issue_count` describe operational concerns.

Assume actual enrollment includes patients who subsequently dropped out. All counts must refer to the same site and reporting snapshot. If source data uses another definition, map it explicitly before submitting.

## Classify Each Metric

| Metric | Low | Medium | High |
|---|---|---|---|
| Enrollment completion | At least 80% | At least 50%, below 80% | Below 50% |
| Days behind schedule | 0-7 days | 8-14 days | 15 or more days |
| Dropout percentage | At most 5% | Above 5%, at most 10% | Above 10% |
| Protocol deviations | 0 | 1-2 | 3 or more |
| Unresolved operational issues | 0 | 1-2 | 3 or more |

```text
enrollment completion = actual_enrollment / enrollment_target * 100
dropout percentage    = patient_dropout_count / actual_enrollment * 100
```

Enrollment target must be greater than zero. If actual enrollment is zero, dropout percentage is unavailable, not an observed zero-percent rate. Exclude that metric from classification and identify it as unavailable in any displayed metric details. Enrollment completion is still 0%, so the overall prototype classification is High.

Compare unrounded values to thresholds; round percentages to two decimal places only when displaying them. In code, compare integer ratios by cross-multiplication where practical to avoid floating-point boundary errors. Enrollment above the target is allowed and is Low for the enrollment metric.

## Choose the Overall Level

Use the highest level found among the available metrics:

1. Any High metric makes the site **High**.
2. Otherwise, any Medium metric makes the site **Medium**.
3. Otherwise, the site is **Low**.

Do not introduce weighted scores or additional scoring libraries for this first version. Several Medium metrics remain Medium; escalation based on combinations would be a separate reviewed rule change.

Low means no metric crossed these prototype thresholds. It is not proof that a site has no operational concerns.

## Explain the Result

Return a short factual reason for every Medium or High metric. Include the observed value and relevant threshold. Keep reasons in this fixed order: enrollment, schedule delay, dropouts, protocol deviations, unresolved issues.

If every metric is Low, return the summary: `No monitored metric exceeded the prototype thresholds.` Do not invent causes, clinical judgments, or intervention recommendations. Bedrock is not needed to produce these initial reasons.

For the existing [synthetic site example](examples/site-assessment.json):

| Metric | Value | Classification |
|---|---|---|
| Enrollment completion | 21 / 60 = 35% | High |
| Delay | 18 days | High |
| Dropouts | 2 / 21 = approximately 9.52% | Medium |
| Protocol deviations | 1 | Medium |
| Unresolved issues | 3 | High |

Local calculation output:

```json
{
  "site_id": "SITE-001",
  "risk_level": "High",
  "rules_version": "prototype-v1",
  "reasons": [
    "Enrollment is 35.00% of target, below the 50% threshold.",
    "The site is 18 days behind schedule, meeting the High threshold of 15 days.",
    "Dropouts are 9.52% of enrolled patients, above the 5% threshold.",
    "There is 1 protocol deviation, meeting the Medium threshold of 1.",
    "There are 3 unresolved issues, meeting the High threshold of 3."
  ]
}
```

This is the standalone prototype calculation result, not the current API response. Keep the existing validation-only API contract until the risk service integration is intentionally introduced.

## Sample Cases for Implementation

All rows are synthetic and use the same input field definitions as the API. These scenarios and the boundary cases are covered by local tests in `services/risk_service/test_risk.py`.

| Case | Target | Enrolled | Delay days | Dropouts | Deviations | Issues | Expected overall level |
|---|---:|---:|---:|---:|---:|---:|---|
| All metrics Low | 60 | 54 | 3 | 2 | 0 | 0 | Low |
| Medium concerns | 60 | 42 | 10 | 3 | 1 | 2 | Medium |
| Existing project example | 60 | 21 | 18 | 2 | 1 | 3 | High |
| One High metric | 60 | 60 | 15 | 0 | 0 | 0 | High |
| No enrollment yet | 60 | 0 | 0 | 0 | 0 | 0 | High; dropout percentage unavailable |
| Above enrollment target | 60 | 65 | 0 | 0 | 0 | 0 | Low |

Also test the boundaries separately: enrollment exactly 50% and 80%; delay 7, 8, 14, and 15 days; dropout percentage exactly 5% and 10%; deviations/issues 0, 1, 2, and 3. Invalid inputs must fail validation rather than receive a risk level.

## Limits of the Initial Rules

- Enrollment is compared with the total target because our current schema has no expected enrollment as of the reporting date. A newly opened site can therefore be classified High even when it is on track. Treat this as a prototype completion indicator, not a reliable enrollment-pace assessment.
- Dropout rates based on very few patients can be unstable; there is no minimum-sample rule yet.
- Deviation and issue counts do not represent severity, age, resolution history, or exposure. A single severe event can matter even when its count is classified Medium here.
- Rules are not calibrated across trial phases or protocols. Do not silently change thresholds; revise the documented version and expected tests together.

## Run Locally

From the repository root:

```powershell
python -m unittest discover -s services/risk_service -p 'test_*.py' -v
python -c "import json; from pathlib import Path; from services.risk_service.risk import calculate_risk; site = json.loads(Path('docs/examples/site-assessment.json').read_text()); print(json.dumps(calculate_risk(site), indent=2))"
```

The calculator uses only the Python standard library. It raises `ValueError` for invalid input and does not modify the submitted dictionary. Validation follows the existing API field contract, but the module has no dependency on the Lambda handler or AWS.

Next, expose the locally tested function through FastAPI. No AWS infrastructure change or API contract change was made for this calculation step.
