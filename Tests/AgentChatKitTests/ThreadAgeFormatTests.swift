import AgentChatCore
import Foundation
import Testing

struct ThreadAgeFormatTests {
    private let format = ThreadTimeFormat(timeZone: TimeZone(identifier: "Asia/Bangkok")!, locale: Locale(identifier: "en_US_POSIX@hours=h23"))
    private let now = Date(timeIntervalSince1970: 1_793_072_470)

    private func ago(_ seconds: TimeInterval) -> Date {
        now.addingTimeInterval(-seconds)
    }

    @Test func ageIsCompactUpToAWeekThenTheDate() {
        let cases: [(TimeInterval, String)] = [
            (-120, "now"), (0, "now"), (59, "now"), (60, "1m"), (12 * 60, "12m"), (3_599, "59m"), (3_600, "1h"),
            (3 * 3_600, "3h"), (86_399, "23h"), (86_400, "1d"), (2 * 86_400, "2d"), (7 * 86_400, "7d"),
            (8 * 86_400 - 1, "7d"), (8 * 86_400, "19 Oct"),
        ]
        for (seconds, expected) in cases {
            #expect(format.age(ago(seconds), now: now) == expected, "\(seconds) s ago")
        }
    }

    @Test func agoReadsTheAgeOut() {
        let cases: [(TimeInterval, String)] = [
            (-120, "just now"), (59, "just now"), (60, "1m ago"), (3 * 3_600, "3h ago"), (8 * 86_400 - 1, "7d ago"),
            (8 * 86_400, "on 19 Oct"),
        ]
        for (seconds, expected) in cases {
            #expect(format.ago(ago(seconds), now: now) == expected, "\(seconds) s ago")
        }
    }

    @Test func rowTimeIsTheAgeWithTheClockTodayAndTheDayBefore() {
        #expect(format.rowTime(ago(30), now: now) == "now · 10:40")
        #expect(format.rowTime(ago(12 * 60), now: now) == "12m · 10:29")
        #expect(format.rowTime(ago(3 * 3_600), now: now) == "3h · 07:41")
        // 2026-10-26T16:59:00Z is 23:59 yesterday in Bangkok: hours ago, but another day.
        #expect(format.rowTime(Date(timeIntervalSince1970: 1_793_033_940), now: now) == "10h · 26 Oct")
        #expect(format.rowTime(ago(2 * 86_400), now: now) == "2d · 25 Oct")
        #expect(format.rowTime(ago(8 * 86_400), now: now) == "19 Oct")
    }

    @Test func detailTimeAlwaysCarriesTheDate() {
        #expect(format.dateAndTime(Date(timeIntervalSince1970: 1_793_072_400)) == "27 Oct 10:40")
        #expect(format.dateAndTime(ago(2 * 86_400)) == "25 Oct 10:41")
    }
}
