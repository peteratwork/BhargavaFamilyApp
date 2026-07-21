import pathlib
import plistlib
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).parents[2]
CODEMAGIC_YAML = REPOSITORY_ROOT / "codemagic.yaml"


def workflow_block(workflow_id):
    lines = CODEMAGIC_YAML.read_text(encoding="utf-8").splitlines()
    start = lines.index(f"  {workflow_id}:")
    end = next(
        (
            index
            for index in range(start + 1, len(lines))
            if lines[index].startswith("  ")
            and not lines[index].startswith("    ")
            and lines[index].endswith(":")
        ),
        len(lines),
    )
    return "\n".join(lines[start:end])


class ReleaseConfigurationTests(unittest.TestCase):
    def test_release_archive_runs_only_for_pushes_to_main(self):
        release = workflow_block("ios-release-archive")
        expected_trigger = """    triggering:
      events:
        - push
      branch_patterns:
        - pattern: main
          include: true
          source: true
      cancel_previous_builds: true"""

        self.assertIn(expected_trigger, release)

    def test_simulator_workflow_does_not_publish_automatically(self):
        simulator = workflow_block("ios-simulator-build")

        self.assertNotIn("    triggering:", simulator)
        self.assertNotIn("    publishing:", simulator)

    def test_ios_bundle_declares_only_exempt_encryption(self):
        with (REPOSITORY_ROOT / "BhargavaFamilyApp" / "Info.plist").open("rb") as plist_file:
            info = plistlib.load(plist_file)

        self.assertIs(info.get("ITSAppUsesNonExemptEncryption"), False)


if __name__ == "__main__":
    unittest.main()
