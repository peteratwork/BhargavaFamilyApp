import pathlib
import tomllib
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).parents[2]


class AuthConfigurationTests(unittest.TestCase):
    def test_email_otp_lifetime_is_one_hour(self):
        with (REPOSITORY_ROOT / "supabase" / "config.toml").open("rb") as config_file:
            config = tomllib.load(config_file)

        self.assertEqual(config["auth"]["email"]["otp_expiry"], 3600)

    def test_email_resend_cooldown_is_one_minute(self):
        with (REPOSITORY_ROOT / "supabase" / "config.toml").open("rb") as config_file:
            config = tomllib.load(config_file)

        self.assertEqual(config["auth"]["email"]["max_frequency"], "60s")


if __name__ == "__main__":
    unittest.main()
