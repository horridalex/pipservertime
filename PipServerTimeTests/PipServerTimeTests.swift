import XCTest
@testable import PipServerTime

final class URLNormalizerTests: XCTestCase {
    func testAddsHTTPSAndPath() {
        XCTAssertEqual(URLNormalizer.normalize("naver.com")?.absoluteString, "https://naver.com/")
        XCTAssertEqual(URLNormalizer.normalize("  ticket.yes24.com  ")?.absoluteString, "https://ticket.yes24.com/")
    }

    func testKeepsSchemeAndPath() {
        XCTAssertEqual(URLNormalizer.normalize("http://example.com/a")?.absoluteString, "http://example.com/a")
    }

    func testRejectsInvalid() {
        XCTAssertNil(URLNormalizer.normalize(""))
        XCTAssertNil(URLNormalizer.normalize("   "))
        XCTAssertNil(URLNormalizer.normalize("abc"))
    }
}

final class ConsensusTests: XCTestCase {
    typealias Bound = DirectServerTimeSource.Bound

    /// 실제 오프셋 theta 인 서버에 rtt 로 요청한 샘플들을 흉내 냄 (요청 시점을 1초 안에 고르게 분산)
    private func bounds(theta: Double, count: Int, rtt: Double, start: Double = 1_000) -> [Bound] {
        (0..<count).map { i in
            let t0 = start + Double(i) * 0.037
            let t1 = t0 + rtt
            let serverSecond = floor(t0 + rtt / 2 + theta)
            return Bound(lower: serverSecond - t1, upper: serverSecond + 1 - t0, rtt: rtt)
        }
    }

    func testFindsTrueOffset() throws {
        for theta in [-0.882, -0.21, 0, 0.015, 0.4] {
            let c = try XCTUnwrap(DirectServerTimeSource.Consensus(bounds(theta: theta, count: 60, rtt: 0.04)))
            XCTAssertLessThanOrEqual(c.lower, theta, "theta \(theta)")
            XCTAssertGreaterThan(c.upper, theta, "theta \(theta)")
            XCTAssertLessThan(c.width, 0.09, "theta \(theta)")
            XCTAssertEqual(c.agreed, 60)
        }
    }

    func testIgnoresOutliersFromAnotherServer() throws {
        let good = bounds(theta: 0.1, count: 50, rtt: 0.04)
        let bad = bounds(theta: 0.6, count: 8, rtt: 0.04, start: 2_000)
        let c = try XCTUnwrap(DirectServerTimeSource.Consensus(good + bad))
        XCTAssertLessThanOrEqual(c.lower, 0.1)
        XCTAssertGreaterThan(c.upper, 0.1)
        XCTAssertGreaterThanOrEqual(c.agreed, 50)
    }

    func testEmpty() {
        XCTAssertNil(DirectServerTimeSource.Consensus([]))
    }

    func testMedian() {
        XCTAssertEqual(DirectServerTimeSource.median([3, 1, 2]), 2)
        XCTAssertEqual(DirectServerTimeSource.median([4, 1, 2, 3]), 2.5)
        XCTAssertEqual(DirectServerTimeSource.median([]), 0)
    }
}

final class ClockFormatTests: XCTestCase {
    func testFractionDigits() {
        let d = Date(timeIntervalSince1970: 1_794_396_026.987)
        XCTAssertTrue(ClockFormat.time(d, digits: 3).hasSuffix(".987"), ClockFormat.time(d, digits: 3))
        XCTAssertTrue(ClockFormat.time(d, digits: 2).hasSuffix(".98"))
        XCTAssertTrue(ClockFormat.time(d, digits: 1).hasSuffix(".9"))
        XCTAssertFalse(ClockFormat.time(d, digits: 0).contains("."))
    }

    func testCountdown() {
        XCTAssertEqual(ClockFormat.countdown(0), "지금")
        XCTAssertEqual(ClockFormat.countdown(7), "7.0초")
        XCTAssertEqual(ClockFormat.countdown(125), "2:05")
        XCTAssertEqual(ClockFormat.countdown(3_725), "1:02:05")
        XCTAssertEqual(ClockFormat.countdown(90_000), "D-1 01:00:00")
    }
}

final class NavyismParseTests: XCTestCase {
    func testParsesPageValuesAndOffset() throws {
        let html = """
        <script>
        var mgap = 743;
        var thisTime2\t= 1794396026;
        var mgval = new Date().getTime() - (thisTime2 * 1000 + mgap);
        function startShow() { show(1794396026 - time() + 0); }
        mgval = mgval + 900;
        </script>
        """
        let v = try NavyismTimeSource.parse(html)
        XCTAssertEqual(v, .init(mgap: 743, thisTime2: 1794396026, targetSeconds: 1794396026, targetAdjust: 0, mgvalAdjust: 900))
        let offset = v.offset(scriptExecutedAt: Date(timeIntervalSince1970: 1_794_396_027))
        XCTAssertEqual(offset, -1.157, accuracy: 0.0001)
    }

    func testDetectsMissingTime() {
        XCTAssertThrowsError(try NavyismTimeSource.parse("<script>show('e');</script>"))
    }
}

final class MiscTests: XCTestCase {
    func testBeepWavHeader() {
        let data = BeepPlayer.wav(frequency: 880, duration: 0.01)
        XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertEqual(data.count, 44 + Int(0.01 * 44_100) * 2)
    }

    func testProjectedAccuracyGrowsWithDrift() {
        let t = Date(timeIntervalSince1970: 1_000_000)
        let r = SyncResult(offset: 0.1, accuracy: 0.05, source: .direct, host: "x", siteName: "x", syncedAt: t)
        XCTAssertEqual(r.projectedAccuracy(at: t) ?? 0, 0.05, accuracy: 1e-9)
        XCTAssertEqual(r.projectedAccuracy(at: t.addingTimeInterval(600)) ?? 0, 0.056, accuracy: 1e-9)
    }

    func testFriendlyErrors() {
        let offline = ClockStore.friendlyMessage(for: URLError(.notConnectedToInternet), host: "a.com")
        XCTAssertTrue(offline.contains("인터넷"))
        let noDate = ClockStore.friendlyMessage(for: DirectServerTimeSource.DirectError.noDateHeader, host: "a.com")
        XCTAssertTrue(noDate.contains("a.com"))
    }
}
