import importlib.util
import pathlib
import unittest


SCRIPT_PATH = pathlib.Path(__file__).parents[1] / "require_backend_ci.py"
SPEC = importlib.util.spec_from_file_location("require_backend_ci", SCRIPT_PATH)
require_backend_ci = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(require_backend_ci)


class BackendCIGateTests(unittest.TestCase):
    def test_accepts_success_for_exact_commit(self):
        runs = [
            {
                "head_sha": "abc123",
                "status": "completed",
                "conclusion": "success",
                "html_url": "https://example.test/success",
            }
        ]

        self.assertEqual(
            require_backend_ci.evaluate_runs(runs, "abc123"),
            ("success", "https://example.test/success"),
        )

    def test_rejects_failed_run_for_exact_commit(self):
        runs = [
            {
                "head_sha": "abc123",
                "status": "completed",
                "conclusion": "failure",
                "html_url": "https://example.test/failure",
            }
        ]

        self.assertEqual(
            require_backend_ci.evaluate_runs(runs, "abc123"),
            ("failure", "https://example.test/failure"),
        )

    def test_ignores_success_from_a_different_commit(self):
        runs = [
            {
                "head_sha": "older",
                "status": "completed",
                "conclusion": "success",
                "html_url": "https://example.test/older",
            }
        ]

        self.assertEqual(require_backend_ci.evaluate_runs(runs, "abc123"), ("pending", None))

    def test_waits_for_queued_or_in_progress_run(self):
        for status in ("queued", "in_progress", "waiting", "requested", "pending"):
            with self.subTest(status=status):
                runs = [{"head_sha": "abc123", "status": status, "conclusion": None}]
                self.assertEqual(
                    require_backend_ci.evaluate_runs(runs, "abc123"),
                    ("pending", None),
                )


if __name__ == "__main__":
    unittest.main()
