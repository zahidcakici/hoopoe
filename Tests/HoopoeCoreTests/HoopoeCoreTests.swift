import Foundation
import Testing
@testable import HoopoeCore

/// Mutable clock so tests control the passage of time.
final class Clock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
    func advance(_ seconds: TimeInterval) { now += seconds }
}

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.firstWeekday = 2
    return calendar
}

private func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    utc.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}

private let allTime = DateInterval(start: .distantPast, end: .distantFuture)

@MainActor
private func makeStore(at start: Date = date(16, 9)) throws -> (TrackerStore, Clock, Database) {
    let clock = Clock(start)
    let db = try Database(path: ":memory:")
    return (TrackerStore(database: db, now: { clock.now }), clock, db)
}

@MainActor
@Suite struct TimerTests {
    @Test func startStopRecordsAnEntry() throws {
        let (store, clock, _) = try makeStore()
        let task = try #require(store.addTask(name: "Writing"))

        store.start(taskID: task.id)
        #expect(store.running?.taskID == task.id)
        clock.advance(600)
        store.stop()

        #expect(store.running == nil)
        let entries = store.entries(in: allTime)
        #expect(entries.count == 1)
        #expect(entries[0].duration(now: clock.now) == 600)
    }

    @Test func startingAnotherTaskSwitches() throws {
        let (store, clock, _) = try makeStore()
        let a = try #require(store.addTask(name: "A"))
        let b = try #require(store.addTask(name: "B"))

        store.start(taskID: a.id)
        clock.advance(300)
        store.start(taskID: b.id)
        clock.advance(120)

        let entries = store.entries(in: allTime)
        #expect(entries.count == 2)
        #expect(entries[0].end == entries[1].start)
        #expect(store.running?.taskID == b.id)
        #expect(Stats.totalsByTask(entries, in: allTime, now: clock.now) == [a.id: 300, b.id: 120])
    }

    @Test func resumeContinuesLastTask() throws {
        let (store, clock, _) = try makeStore()
        let a = try #require(store.addTask(name: "A"))
        let b = try #require(store.addTask(name: "B"))

        store.start(taskID: b.id)
        clock.advance(60)
        store.stop()
        clock.advance(60)
        store.resume()

        #expect(store.running?.taskID == b.id)
        #expect(store.lastTaskID == b.id)
        _ = a
    }

    @Test func resumeWithNoHistoryStartsFirstTask() throws {
        let (store, _, _) = try makeStore()
        let a = try #require(store.addTask(name: "A"))
        store.toggle()
        #expect(store.running?.taskID == a.id)
    }

    @Test func accidentalClicksAreDiscarded() throws {
        let (store, clock, _) = try makeStore()
        let a = try #require(store.addTask(name: "A"))
        store.start(taskID: a.id)
        clock.advance(0.3)
        store.stop()
        #expect(store.entries(in: allTime).isEmpty)
    }

    @Test func lockPausesAndUnlockResumes() throws {
        let (store, clock, _) = try makeStore()
        let a = try #require(store.addTask(name: "A"))
        store.start(taskID: a.id)
        clock.advance(100)

        store.systemPause()
        store.systemPause() // lock and sleep both fire
        #expect(store.running == nil)
        clock.advance(5000)
        store.systemResume()
        store.systemResume()
        clock.advance(50)

        #expect(store.running?.taskID == a.id)
        let entries = store.entries(in: allTime)
        #expect(entries.count == 2)
        #expect(Stats.total(entries, in: allTime, now: clock.now) == 150)
    }

    @Test func unlockDoesNotResumeAManuallyStoppedTimer() throws {
        let (store, clock, _) = try makeStore()
        let a = try #require(store.addTask(name: "A"))
        store.start(taskID: a.id)
        clock.advance(100)
        store.stop()
        store.systemPause()
        store.systemResume()
        #expect(store.running == nil)
    }

    @Test func orphanedEntryIsClosedAtLastHeartbeat() throws {
        let clock = Clock(date(16, 9))
        let db = try Database(path: ":memory:")
        let crashed = TrackerStore(database: db, now: { clock.now })
        let a = try #require(crashed.addTask(name: "A"))
        crashed.start(taskID: a.id)
        clock.advance(1800)
        crashed.heartbeat()
        clock.advance(7200) // app died; machine was off for two hours

        let relaunched = TrackerStore(database: db, now: { clock.now })
        #expect(relaunched.running == nil)
        let entries = relaunched.entries(in: allTime)
        #expect(entries.count == 1)
        #expect(entries[0].duration(now: clock.now) == 1800)
        #expect(relaunched.lastTaskID == a.id)
    }
}

@MainActor
@Suite struct TaskAndEntryTests {
    @Test func taskCrud() throws {
        let (store, _, _) = try makeStore()
        #expect(store.addTask(name: "   ") == nil)
        let a = try #require(store.addTask(name: "  Reading "))
        #expect(a.name == "Reading")

        store.renameTask(id: a.id, name: "Deep reading")
        #expect(store.tasks.map(\.name) == ["Deep reading"])
        store.renameTask(id: a.id, name: "")
        #expect(store.tasks.map(\.name) == ["Deep reading"])

        store.deleteTask(id: a.id)
        #expect(store.tasks.isEmpty)
    }

    @Test func deletingATaskRemovesItsEntriesAndStopsItsTimer() throws {
        let (store, clock, _) = try makeStore()
        let a = try #require(store.addTask(name: "A"))
        let b = try #require(store.addTask(name: "B"))
        store.addEntry(taskID: b.id, start: date(15, 9), end: date(15, 10))
        store.start(taskID: a.id)
        clock.advance(60)

        store.deleteTask(id: a.id)

        #expect(store.running == nil)
        #expect(store.entries(in: allTime).map(\.taskID) == [b.id])
        #expect(store.lastTaskID == b.id)
    }

    @Test func manualEntriesCanBeAddedEditedAndDeleted() throws {
        let (store, clock, _) = try makeStore()
        let a = try #require(store.addTask(name: "A"))

        #expect(store.addEntry(taskID: a.id, start: date(15, 10), end: date(15, 9)) == false)
        #expect(store.addEntry(taskID: 999, start: date(15, 9), end: date(15, 10)) == false)
        #expect(store.addEntry(taskID: a.id, start: date(15, 9), end: date(15, 10)))

        var entry = try #require(store.entries(in: allTime).first)
        entry.end = date(15, 11, 30)
        #expect(store.updateEntry(entry))
        #expect(store.entries(in: allTime)[0].duration(now: clock.now) == 9000)

        entry.end = date(15, 8)
        #expect(store.updateEntry(entry) == false)

        store.deleteEntry(id: entry.id)
        #expect(store.entries(in: allTime).isEmpty)
    }

    @Test func editingTheRunningEntryKeepsItRunning() throws {
        let (store, clock, _) = try makeStore()
        let a = try #require(store.addTask(name: "A"))
        store.start(taskID: a.id)
        clock.advance(600)

        var entry = try #require(store.running)
        entry.start = entry.start.addingTimeInterval(-1200)
        entry.end = clock.now
        #expect(store.updateEntry(entry))

        #expect(store.running?.end == nil)
        #expect(store.running?.duration(now: clock.now) == 1800)
    }

    @Test func dataPersistsAcrossStores() throws {
        let (store, _, db) = try makeStore()
        let a = try #require(store.addTask(name: "A"))
        store.addEntry(taskID: a.id, start: date(15, 9), end: date(15, 10))

        let reopened = TrackerStore(database: db)
        #expect(reopened.tasks.map(\.name) == ["A"])
        #expect(reopened.allTimeTotals() == [a.id: 3600])
    }
}

@Suite struct StatsTests {
    private func entry(_ start: Date, _ end: Date?, task: Int64 = 1) -> TimeEntry {
        TimeEntry(id: 0, taskID: task, start: start, end: end)
    }

    @Test func overlapClipsToTheInterval() {
        let day = Period.day.interval(containing: date(16, 12), calendar: utc)
        #expect(Stats.overlap(entry(date(15, 23), date(16, 1)), day, now: date(20)) == 3600)
        #expect(Stats.overlap(entry(date(14, 9), date(14, 10)), day, now: date(20)) == 0)
        // Running entry counts up to "now".
        #expect(Stats.overlap(entry(date(16, 9), nil), day, now: date(16, 9, 30)) == 1800)
    }

    @Test func entriesAcrossMidnightAreSplitBetweenDays() {
        let week = Period.week.interval(containing: date(16), calendar: utc)
        #expect(week.start == date(16)) // Monday 16 Nov 2026
        let buckets = Stats.buckets([entry(date(16, 22), date(17, 3))], in: week, by: .day, calendar: utc, now: date(30))
        #expect(buckets.count == 7)
        #expect(buckets.map(\.duration) == [7200, 10800, 0, 0, 0, 0, 0])
    }

    @Test func dayIsBucketedByHour() {
        let day = Period.day.interval(containing: date(16), calendar: utc)
        let buckets = Stats.buckets([entry(date(16, 9, 30), date(16, 11))], in: day, by: Period.day.bucket, calendar: utc, now: date(30))
        #expect(buckets.count == 24)
        #expect(buckets[9].duration == 1800)
        #expect(buckets[10].duration == 3600)
        #expect(buckets.map(\.duration).reduce(0, +) == 5400)
    }

    @Test func monthHasOneBucketPerDay() {
        let month = Period.month.interval(containing: date(16), calendar: utc)
        #expect(Stats.buckets([], in: month, by: .day, calendar: utc, now: date(30)).count == 30)
        #expect(Period.month.shift(date(16), by: 1, calendar: utc) == utc.date(from: DateComponents(year: 2026, month: 12, day: 16)))
    }

    @Test func totalsByTask() {
        let entries = [entry(date(16, 9), date(16, 10), task: 1), entry(date(16, 10), date(16, 10, 30), task: 2),
                       entry(date(16, 13), date(16, 14), task: 1)]
        #expect(Stats.totalsByTask(entries, in: allTime, now: date(30)) == [1: 7200, 2: 1800])
    }

    @Test func formatting() {
        #expect(Format.duration(0) == "0m")
        #expect(Format.duration(59 * 60) == "59m")
        #expect(Format.duration(3600) == "1h")
        #expect(Format.duration(3 * 3600 + 20 * 60 + 59) == "3h 20m")
        #expect(Format.clock(3909, showSeconds: true) == "1:05:09")
        #expect(Format.clock(3909, showSeconds: false) == "1:05")
    }
}

@Suite struct UpdateTests {
    @Test func versionsCompareNumerically() throws {
        let v = { (s: String) in try #require(AppVersion(s)) }
        #expect(try v("1.10.0") > v("1.9.3"))
        #expect(try v("v2.0") == v("2.0.0"))
        #expect(try v("0.0.0") < v("0.0.1"))
        #expect(try v("1.2.3").description == "1.2.3")
        #expect(AppVersion("1.x") == nil)
        #expect(AppVersion("") == nil)
        #expect(AppVersion("1.2-beta") == nil)
    }

    private func payload(tag: String = "v1.4.0", page: String = "https://github.com/zahidcakici/hoopoe/releases/tag/v1.4.0",
                         assets: [(String, String)]) -> Data {
        let list = assets.map { #"{"name":"\#($0.0)","browser_download_url":"\#($0.1)"}"# }.joined(separator: ",")
        return Data(#"{"tag_name":"\#(tag)","html_url":"\#(page)","body":"notes","assets":[\#(list)]}"#.utf8)
    }

    @Test func parsesTheLatestRelease() throws {
        let base = "https://github.com/zahidcakici/hoopoe/releases/download/v1.4.0/"
        let data = payload(assets: [("Hoopoe-1.4.0.dmg", base + "Hoopoe-1.4.0.dmg"), ("Hoopoe-1.4.0.zip", base + "Hoopoe-1.4.0.zip")])
        let release = try UpdateFeed.parse(data, repository: "zahidcakici/hoopoe")
        #expect(release.version == AppVersion("1.4.0"))
        #expect(release.archiveURL?.absoluteString == base + "Hoopoe-1.4.0.zip")
    }

    @Test func ignoresDownloadsFromOtherPlaces() throws {
        let data = payload(assets: [("Hoopoe-1.4.0.zip", "https://evil.example/Hoopoe-1.4.0.zip"),
                                    ("Hoopoe-1.4.0.zip", "https://github.com/someone/else/releases/download/v1/Hoopoe-1.4.0.zip")])
        #expect(try UpdateFeed.parse(data, repository: "zahidcakici/hoopoe").archiveURL == nil)
    }

    @Test func rejectsMalformedReleases() {
        #expect(throws: (any Error).self) {
            try UpdateFeed.parse(payload(tag: "nightly", assets: []), repository: "zahidcakici/hoopoe")
        }
        #expect(throws: (any Error).self) {
            try UpdateFeed.parse(payload(page: "https://evil.example/x", assets: []), repository: "zahidcakici/hoopoe")
        }
        #expect(throws: (any Error).self) {
            try UpdateFeed.parse(Data("not json".utf8), repository: "zahidcakici/hoopoe")
        }
    }
}
