import pathlib
import plistlib
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).parents[2]


class ReleaseConfigurationTests(unittest.TestCase):
    def test_ios_bundle_declares_only_exempt_encryption(self):
        with (REPOSITORY_ROOT / "BhargavaFamilyApp" / "Info.plist").open("rb") as plist_file:
            info = plistlib.load(plist_file)

        self.assertIs(info.get("ITSAppUsesNonExemptEncryption"), False)


if __name__ == "__main__":
    unittest.main()
