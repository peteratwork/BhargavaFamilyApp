import XCTest
@testable import BhargavaCore

final class AppConfigurationTests: XCTestCase {
    func testAcceptsValidHTTPSConfiguration() throws {
        let configuration = try AppConfiguration(values: [
            "SUPABASE_URL": "https://family.supabase.co",
            "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_valid_test_key"
        ])

        XCTAssertEqual(configuration.supabaseURL, URL(string: "https://family.supabase.co"))
        XCTAssertEqual(configuration.supabasePublishableKey, "sb_publishable_valid_test_key")
    }

    func testRejectsMissingURL() {
        XCTAssertThrowsError(try AppConfiguration(values: [
            "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_valid_test_key"
        ])) { error in
            XCTAssertEqual(error as? AppConfiguration.ConfigurationError, .missing("SUPABASE_URL"))
        }
    }

    func testRejectsNonHTTPSURL() {
        XCTAssertThrowsError(try AppConfiguration(values: [
            "SUPABASE_URL": "http://family.supabase.co",
            "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_valid_test_key"
        ])) { error in
            XCTAssertEqual(error as? AppConfiguration.ConfigurationError, .invalid("SUPABASE_URL"))
        }
    }

    func testRejectsPlaceholderPublishableKey() {
        XCTAssertThrowsError(try AppConfiguration(values: [
            "SUPABASE_URL": "https://family.supabase.co",
            "SUPABASE_PUBLISHABLE_KEY": "replace-me"
        ])) { error in
            XCTAssertEqual(
                error as? AppConfiguration.ConfigurationError,
                .invalid("SUPABASE_PUBLISHABLE_KEY")
            )
        }
    }

    func testRejectsUnexpandedBuildSettingKey() {
        XCTAssertThrowsError(try AppConfiguration(values: [
            "SUPABASE_URL": "https://family.supabase.co",
            "SUPABASE_PUBLISHABLE_KEY": "$(SUPABASE_PUBLISHABLE_KEY)"
        ])) { error in
            XCTAssertEqual(
                error as? AppConfiguration.ConfigurationError,
                .invalid("SUPABASE_PUBLISHABLE_KEY")
            )
        }
    }

    func testRejectsSecretKey() {
        XCTAssertThrowsError(try AppConfiguration(values: [
            "SUPABASE_URL": "https://family.supabase.co",
            "SUPABASE_PUBLISHABLE_KEY": "sb_secret_must_never_ship"
        ])) { error in
            XCTAssertEqual(
                error as? AppConfiguration.ConfigurationError,
                .invalid("SUPABASE_PUBLISHABLE_KEY")
            )
        }
    }

    func testRejectsLegacyServiceRoleJWT() {
        let serviceRoleJWT = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.not-a-signature"

        XCTAssertThrowsError(try AppConfiguration(values: [
            "SUPABASE_URL": "https://family.supabase.co",
            "SUPABASE_PUBLISHABLE_KEY": serviceRoleJWT
        ])) { error in
            XCTAssertEqual(
                error as? AppConfiguration.ConfigurationError,
                .invalid("SUPABASE_PUBLISHABLE_KEY")
            )
        }
    }
}
