"""Sample, boundary, and invalid-input tests for the local prototype rules."""

import json
from pathlib import Path
import unittest

from risk import calculate_risk


def sample_site(**changes):
    """Return a fresh Low-risk fixture with overrides to isolate individual rules."""
    return {
        "site_id": "SITE-TEST", "site_name": "Synthetic Test Site",
        "enrollment_target": 100, "actual_enrollment": 100,
        "days_behind_schedule": 0, "patient_dropout_count": 0,
        "protocol_deviation_count": 0, "unresolved_issue_count": 0,
        **changes,
    }


class RiskTests(unittest.TestCase):
    """Verify observable rule behavior rather than HTTP or cloud infrastructure."""

    def test_documented_samples(self):
        """Check all six documented scenarios so code agrees with the rule guide."""
        cases = (
            (60, 54, 3, 2, 0, 0, "Low"),
            (60, 42, 10, 3, 1, 2, "Medium"),
            (60, 21, 18, 2, 1, 3, "High"),
            (60, 60, 15, 0, 0, 0, "High"),
            (60, 0, 0, 0, 0, 0, "High"),
            (60, 65, 0, 0, 0, 0, "Low"),
        )
        for target, enrolled, delay, dropouts, deviations, issues, expected in cases:
            with self.subTest(case=(target, enrolled, delay, dropouts, deviations, issues)):
                result = calculate_risk(sample_site(
                    enrollment_target=target, actual_enrollment=enrolled,
                    days_behind_schedule=delay, patient_dropout_count=dropouts,
                    protocol_deviation_count=deviations, unresolved_issue_count=issues,
                ))
                self.assertEqual(result["risk_level"], expected)

    def test_enrollment_boundaries(self):
        """Enrollment exactly 50% is Medium and exactly 80% is Low."""
        for enrolled, expected in ((49, "High"), (50, "Medium"), (79, "Medium"), (80, "Low")):
            with self.subTest(enrolled=enrolled):
                self.assertEqual(calculate_risk(sample_site(actual_enrollment=enrolled))["risk_level"], expected)

    def test_schedule_boundaries(self):
        """Check both sides of the 8-day and 15-day schedule cutoffs."""
        for days, expected in ((7, "Low"), (8, "Medium"), (14, "Medium"), (15, "High")):
            with self.subTest(days=days):
                self.assertEqual(calculate_risk(sample_site(days_behind_schedule=days))["risk_level"], expected)

    def test_dropout_boundaries(self):
        """Dropouts exactly 5% stay Low and exactly 10% stay Medium."""
        for dropouts, expected in ((5, "Low"), (6, "Medium"), (10, "Medium"), (11, "High")):
            with self.subTest(dropouts=dropouts):
                self.assertEqual(calculate_risk(sample_site(patient_dropout_count=dropouts))["risk_level"], expected)

    def test_classification_uses_unrounded_ratios(self):
        """A percentage displayed as a cutoff must still use its exact ratio."""
        enrollment = sample_site(enrollment_target=100000, actual_enrollment=79999)
        self.assertEqual(calculate_risk(enrollment)["risk_level"], "Medium")
        dropout = sample_site(enrollment_target=100000, actual_enrollment=100000, patient_dropout_count=10001)
        self.assertEqual(calculate_risk(dropout)["risk_level"], "High")

    def test_deviation_and_issue_boundaries(self):
        """Each count independently changes level at 1 and 3 events."""
        for field in ("protocol_deviation_count", "unresolved_issue_count"):
            for count, expected in ((0, "Low"), (1, "Medium"), (2, "Medium"), (3, "High")):
                with self.subTest(field=field, count=count):
                    self.assertEqual(calculate_risk(sample_site(**{field: count}))["risk_level"], expected)

    def test_zero_enrollment_has_no_dropout_claim(self):
        """Avoid dividing by zero or describing an unavailable rate as observed."""
        result = calculate_risk(sample_site(actual_enrollment=0))
        self.assertEqual(result["risk_level"], "High")
        self.assertEqual(len(result["reasons"]), 1)
        self.assertTrue(result["reasons"][0].startswith("Enrollment"))

    def test_example_reasons_and_input_preservation(self):
        """The repository example has ordered factual reasons and stays unchanged."""
        path = Path(__file__).resolve().parents[2] / "docs/examples/site-assessment.json"
        site = json.loads(path.read_text())
        original = site.copy()
        result = calculate_risk(site)
        self.assertEqual(result["site_id"], "SITE-001")
        self.assertEqual(result["rules_version"], "prototype-v1")
        self.assertEqual(result["risk_level"], "High")
        self.assertEqual(len(result["reasons"]), 5)
        for reason, prefix in zip(result["reasons"], ("Enrollment", "The site", "Dropouts", "There is", "There are")):
            self.assertTrue(reason.startswith(prefix))
        self.assertEqual(site, original)

    def test_low_summary(self):
        """Return an explicit prototype summary when no metric raises a concern."""
        result = calculate_risk(sample_site())
        self.assertEqual(result["reasons"], ["No monitored metric exceeded the prototype thresholds."])

    def test_invalid_records_are_not_classified(self):
        """Reject invalid contract data before producing any operational risk result."""
        invalid = [None, [], {}, {**sample_site(), "patient_name": "Unexpected"}]
        missing = sample_site()
        del missing["site_name"]
        invalid.append(missing)
        for field, value in (
            ("enrollment_target", 0), ("actual_enrollment", -1),
            ("actual_enrollment", True), ("days_behind_schedule", "8"),
            ("patient_dropout_count", 101), ("protocol_deviation_count", 1.5),
            ("unresolved_issue_count", None), ("site_id", "bad/id"),
            ("site_name", " "),
        ):
            invalid.append(sample_site(**{field: value}))
        for site in invalid:
            with self.subTest(site=site):
                with self.assertRaises(ValueError):
                    calculate_risk(site)


if __name__ == "__main__":
    unittest.main()
