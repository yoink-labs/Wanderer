import CryptoKit
import Foundation

/// Offline reading for signed-in trips.
///
/// Wraps the network session: every successful GET is written to Caches,
/// keyed by the signed-in account and the request URL. When the network is
/// unreachable, the same GET is answered from that copy instead of failing,
/// so trips, days, places, bookings and costs stay readable on a plane.
/// Writes still need a connection. The copy is scoped per account and
/// cleared on sign-out and account deletion.
final class OfflineReadCache: URLSessioning, @unchecked Sendable {
    static let shared = OfflineReadCache(base: URLSession.shared, directory: OfflineReadCache.defaultDirectory)
    static let offlineHeader = "x-wanderer-offline"

    static var defaultDirectory: URL {
        (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("offline-api", isDirectory: true)
    }

    private let base: URLSessioning
    private let directory: URL
    private let lock = NSLock()
    private var scopeValue: String?

    init(base: URLSessioning, directory: URL) {
        self.base = base
        self.directory = directory
    }

    /// The signed-in account's id. Nothing is cached or served without one,
    /// so one person never reads another's copy on a shared device.
    var scope: String? {
        get { lock.lock(); defer { lock.unlock() }; return scopeValue }
        set { lock.lock(); scopeValue = newValue; lock.unlock() }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let isRead = (request.httpMethod ?? "GET") == "GET"
        let key = isRead ? cacheKey(for: request) : nil
        do {
            let (data, response) = try await base.data(for: request)
            if let key, let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                store(data, key: key)
            }
            return (data, response)
        } catch let error as URLError where Self.isOffline(error) {
            guard let key, let cached = load(key: key), let url = request.url else { throw error }
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["content-type": "application/json", Self.offlineHeader: "1"]
            )!
            return (cached, response)
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: directory)
    }

    static func isOffline(_ error: URLError) -> Bool {
        [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost, .cannotFindHost, .dataNotAllowed]
            .contains(error.code)
    }

    private func cacheKey(for request: URLRequest) -> String? {
        guard let scope, let url = request.url?.absoluteString else { return nil }
        let digest = SHA256.hash(data: Data("\(scope)|\(url)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func store(_ data: Data, key: String) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent(key), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            // A missed write only means this screen isn't available offline.
        }
    }

    private func load(key: String) -> Data? {
        try? Data(contentsOf: directory.appendingPathComponent(key))
    }
}
