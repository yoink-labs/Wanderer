import XCTest
@testable import Wanderer

final class LegacyBackendCleanupTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "wanderer.tests.legacy"

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testRemovesSupabaseBackendStateFromUpgradedDevice() {
        defaults.set("supabase", forKey: "wanderer.backendMode")
        defaults.set(true, forKey: "wanderer.hasSupabaseAccount")
        defaults.set("en", forKey: "wanderer.selectedLanguage")

        XCTAssertTrue(LegacyBackendCleanup.run(defaults: defaults))
        XCTAssertNil(defaults.object(forKey: "wanderer.backendMode"))
        XCTAssertNil(defaults.object(forKey: "wanderer.hasSupabaseAccount"))
        // Unrelated preferences survive.
        XCTAssertEqual(defaults.string(forKey: "wanderer.selectedLanguage"), "en")
    }

    func testIsIdempotent() {
        defaults.set("supabase", forKey: "wanderer.backendMode")
        LegacyBackendCleanup.run(defaults: defaults)
        defaults.set("supabase", forKey: "wanderer.backendMode")
        XCTAssertFalse(LegacyBackendCleanup.run(defaults: defaults))
    }

    func testFreshInstallIsANoOp() {
        XCTAssertFalse(LegacyBackendCleanup.run(defaults: defaults))
        XCTAssertTrue(defaults.bool(forKey: LegacyBackendCleanup.doneKey))
    }
}
