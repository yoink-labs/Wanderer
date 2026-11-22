#if DEBUG
import Foundation

/// Debug-only tip client that serves the products in `Wanderer.storekit`
/// without StoreKit, for screenshots and UI checks launched outside Xcode
/// (where the scheme's StoreKit configuration isn't applied). Prices still
/// come from the configuration file, never from code.
///
///     -uiTipJar config                     use this client
///     -uiTipJar empty                      this client, but no products load
///     -uiTipOutcome thanks|pending|failed|cancel   what a tap does (default thanks)
///     -uiStorefront USA|GBR|BRA|none       storefront country (default: the
///                                          file's `_storefront`)
///
/// Release builds don't contain this type.
struct TipJarConfigClient: TipStoreClient {
    enum Outcome: String {
        case thanks, pending, failed, cancel
    }

    var configURL: URL = TipJarConfigClient.defaultConfigURL
    var outcome: Outcome = .thanks
    var returnsNoProducts = false
    /// nil reads the file's `_storefront`; "none" means unknown.
    var storefrontOverride: String?

    /// The simulator can read the source tree, so point at the checked-in
    /// file rather than shipping it in the app bundle.
    static var defaultConfigURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Services
            .deletingLastPathComponent() // Core
            .deletingLastPathComponent() // Wanderer
            .appendingPathComponent("Resources/Wanderer.storekit")
    }

    static func fromLaunchArguments() -> TipJarConfigClient? {
        let mode = DebugLaunch.value("uiTipJar")
        guard mode == "config" || mode == "empty" else { return nil }
        let outcome = DebugLaunch.value("uiTipOutcome").flatMap(Outcome.init(rawValue:)) ?? .thanks
        return TipJarConfigClient(
            outcome: outcome,
            returnsNoProducts: mode == "empty",
            storefrontOverride: DebugLaunch.value("uiStorefront")
        )
    }

    func canMakePayments() async -> Bool { true }

    func storefrontCountryCode() async -> String? {
        if let storefrontOverride {
            return storefrontOverride == "none" ? nil : storefrontOverride
        }
        guard let data = try? Data(contentsOf: configURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let settings = json["settings"] as? [String: Any] else { return nil }
        return settings["_storefront"] as? String
    }

    func products(for ids: [String]) async throws -> [TipProduct] {
        if returnsNoProducts { return [] }
        let data: Data
        do {
            data = try Data(contentsOf: configURL)
        } catch {
            throw TipJarError.other("Couldn't read Wanderer.storekit.")
        }
        return try Self.products(fromConfig: data).filter { ids.contains($0.id) }
    }

    func purchase(productID: String) async throws -> TipPurchaseResult {
        try? await Task.sleep(for: .milliseconds(700))
        switch outcome {
        case .thanks: return .success(productID: productID)
        case .pending: return .pending
        case .cancel: return .cancelled
        case .failed: throw TipJarError.network
        }
    }

    func completedTips() -> AsyncStream<String> {
        AsyncStream { _ in }
    }

    /// Reads the products a StoreKit configuration file declares. The file
    /// stores a bare amount; StoreKit shows it in the configured
    /// storefront's currency, and so does this.
    static func products(fromConfig data: Data) throws -> [TipProduct] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let products = json["products"] as? [[String: Any]] else {
            throw TipJarError.other("Wanderer.storekit has no products.")
        }
        let settings = json["settings"] as? [String: Any]
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: (settings?["_locale"] as? String) ?? "en_US")

        return products.compactMap { product in
            guard let id = product["productID"] as? String,
                  let tier = TipTier(productID: id),
                  let amount = (product["displayPrice"] as? String).flatMap({ Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) })
            else { return nil }
            let localization = (product["localizations"] as? [[String: Any]])?.first
            return TipProduct(
                id: id,
                tier: tier,
                displayName: localization?["displayName"] as? String ?? "",
                description: localization?["description"] as? String ?? "",
                displayPrice: formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)",
                price: amount
            )
        }
    }
}
#endif
