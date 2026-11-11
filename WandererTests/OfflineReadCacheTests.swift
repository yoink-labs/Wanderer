import XCTest
@testable import Wanderer

private final class ScriptedSession: URLSessioning, @unchecked Sendable {
    var offline = false
    var body = Data("[]".utf8)
    var calls = 0

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        calls += 1
        if offline { throw URLError(.notConnectedToInternet) }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (body, response)
    }
}

final class OfflineReadCacheTests: XCTestCase {
    private var directory: URL!
    private let url = URL(string: "https://api.example/v1/trips")!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    func testServesTheLastGoodReadWhenOffline() async throws {
        let base = ScriptedSession()
        base.body = Data(#"[{"id":1}]"#.utf8)
        let cache = OfflineReadCache(base: base, directory: directory)
        cache.scope = "user_a"
        _ = try await cache.data(for: URLRequest(url: url))

        base.offline = true
        let (data, response) = try await cache.data(for: URLRequest(url: url))
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"[{"id":1}]"#)
        XCTAssertEqual((response as? HTTPURLResponse)?.value(forHTTPHeaderField: OfflineReadCache.offlineHeader), "1")
    }

    func testAnotherAccountNeverSeesTheCopy() async throws {
        let base = ScriptedSession()
        let cache = OfflineReadCache(base: base, directory: directory)
        cache.scope = "user_a"
        _ = try await cache.data(for: URLRequest(url: url))

        cache.scope = "user_b"
        base.offline = true
        do {
            _ = try await cache.data(for: URLRequest(url: url))
            XCTFail("user_b must not read user_a's cached trips")
        } catch is URLError {}
    }

    func testWritesAreNeverAnsweredFromCache() async throws {
        let base = ScriptedSession()
        let cache = OfflineReadCache(base: base, directory: directory)
        cache.scope = "user_a"
        var post = URLRequest(url: url)
        post.httpMethod = "POST"
        _ = try await cache.data(for: post)
        base.offline = true
        do {
            _ = try await cache.data(for: post)
            XCTFail("Offline writes must fail, not pretend to succeed")
        } catch is URLError {}
    }

    func testClearRemovesEverything() async throws {
        let base = ScriptedSession()
        let cache = OfflineReadCache(base: base, directory: directory)
        cache.scope = "user_a"
        _ = try await cache.data(for: URLRequest(url: url))
        cache.clear()
        base.offline = true
        do {
            _ = try await cache.data(for: URLRequest(url: url))
            XCTFail("Cleared cache must not answer")
        } catch is URLError {}
    }
}
