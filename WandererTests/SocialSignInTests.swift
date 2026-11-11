import AuthenticationServices
import XCTest
@testable import Wanderer

final class SocialSignInTests: XCTestCase {
    func testClosingTheAppleSheetIsNotAnError() {
        XCTAssertTrue(AuthStore.isCancellation(ASAuthorizationError(.canceled)))
    }

    func testClosingTheGoogleBrowserIsNotAnError() {
        XCTAssertTrue(AuthStore.isCancellation(ASWebAuthenticationSessionError(.canceledLogin)))
    }

    func testRealFailuresAreShown() {
        XCTAssertFalse(AuthStore.isCancellation(ASAuthorizationError(.failed)))
        XCTAssertFalse(AuthStore.isCancellation(URLError(.notConnectedToInternet)))
    }

    func testIncompleteMessageNamesTheProvider() {
        XCTAssertTrue(AuthStore.incompleteSocialMessage(provider: "Apple").hasPrefix("Apple didn't finish"))
    }

    func testEntitlementRequestsSignInWithApple() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Wanderer/Resources/Wanderer.entitlements")
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any]
        XCTAssertEqual(plist?["com.apple.developer.applesignin"] as? [String], ["Default"])
    }
}
