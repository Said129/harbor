import XCTest
@testable import Harbor

final class F10SportsFootballTests: XCTestCase {
    private func feed(_ json: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    }

    func testPlaysOfOnePeriodRunFromTheHigherClockDown() throws {
        let data = try feed("""
        {"drives": {"previous": [{"plays": [
          {"id": "a", "text": "Late play", "period": {"number": 1}, "clock": {"displayValue": "10:00"}},
          {"id": "b", "text": "Early play", "period": {"number": 1}, "clock": {"displayValue": "14:00"}}
        ]}]}}
        """)
        let entries = SportsFootballPlays.timeline(data)
        XCTAssertEqual(entries.map(\.text), ["Early play", "Late play"])
        XCTAssertEqual(entries.first?.clock, "Q1 \u{00B7} 14:00")
    }

    func testSequenceNumberDecidesTheOrderWhenPresent() throws {
        let data = try feed("""
        {"drives": {"previous": [{"plays": [
          {"id": "a", "text": "Second", "sequenceNumber": "20", "period": {"number": 1}, "clock": {"displayValue": "14:00"}},
          {"id": "b", "text": "First", "sequenceNumber": "10", "period": {"number": 1}, "clock": {"displayValue": "02:00"}}
        ]}]}}
        """)
        XCTAssertEqual(SportsFootballPlays.timeline(data).map(\.text), ["First", "Second"])
    }

    func testOvertimePeriodsAreNumberedFromOne() throws {
        let data = try feed("""
        {"drives": {"current": {"plays": [
          {"id": "ot", "text": "Overtime kickoff", "period": {"number": 5}, "clock": {"displayValue": "15:00"}}
        ]}}}
        """)
        XCTAssertEqual(SportsFootballPlays.timeline(data).first?.clock, "OT1 \u{00B7} 15:00")
    }

    func testScoringPlaysAreUsedWhenNoDrivePlayIsPublished() throws {
        let data = try feed("""
        {"drives": {"previous": []},
         "scoringPlays": [{"id": "s1", "text": "Touchdown", "period": {"number": 2}, "clock": {"displayValue": "03:12"}}]}
        """)
        let entries = SportsFootballPlays.timeline(data)
        XCTAssertEqual(entries.map(\.text), ["Touchdown"])
        XCTAssertEqual(entries.first?.clock, "Q2 \u{00B7} 03:12")
    }

    func testPlaysWithoutTextAreDropped() throws {
        let data = try feed("""
        {"drives": {"previous": [{"plays": [
          {"id": "empty", "text": "   ", "period": {"number": 1}, "clock": {"displayValue": "12:00"}},
          {"id": "kept", "text": "Kickoff", "period": {"number": 1}, "clock": {"displayValue": "11:00"}}
        ]}]}}
        """)
        XCTAssertEqual(SportsFootballPlays.timeline(data).map(\.text), ["Kickoff"])
    }

    func testRepeatedPlayIsKeptOnce() throws {
        let data = try feed("""
        {"drives": {"previous": [{"plays": [
          {"id": "same", "text": "Pass complete", "period": {"number": 1}, "clock": {"displayValue": "09:00"}}
        ]}, {"plays": [
          {"id": "same", "text": "Pass complete, corrected", "period": {"number": 1}, "clock": {"displayValue": "09:00"}}
        ]}]}}
        """)
        let entries = SportsFootballPlays.timeline(data)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.text, "Pass complete, corrected")
    }

    func testParticipantComesFromTheFirstAthlete() throws {
        let data = try feed("""
        {"drives": {"previous": [{"plays": [
          {"id": "p", "text": "Run for 5 yards", "period": {"number": 3}, "clock": {"displayValue": "07:30"},
           "participants": [{"athlete": {"displayName": "Runner Name"}}]}
        ]}]}}
        """)
        XCTAssertEqual(SportsFootballPlays.timeline(data).first?.participant, "Runner Name")
    }

    func testEmptyFeedGivesNoTimeline() throws {
        XCTAssertTrue(SportsFootballPlays.timeline(try feed("{}")).isEmpty)
    }
}
