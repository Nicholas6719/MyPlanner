//
//  MyPlannerTests.swift
//  MyPlannerTests
//
//  Unit tests for the natural-language parser.
//

import Testing
import Foundation
@testable import MyPlanner

@MainActor
struct NLParserTests {

    /// Anchor "now" to a known weekday so tests are deterministic.
    /// This is Sunday, May 3, 2026 at 09:00 local time.
    private var fixedNow: Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 5; comps.day = 3
        comps.hour = 9; comps.minute = 0
        return Calendar.current.date(from: comps)!
    }

    private func parse(_ text: String) -> ParsedInput {
        NLParser.parse(text, now: fixedNow)
    }

    // MARK: - Spec cases

    @Test func workingMondayRange() {
        let result = parse("Working Monday 7am to 3:30pm")
        guard case let .event(title, start, end, recurrence, _) = result else {
            Issue.record("Expected event, got \(result)"); return
        }
        #expect(title.localizedCaseInsensitiveContains("working"))
        #expect(recurrence == nil)
        let cal = Calendar.current
        #expect(cal.component(.hour, from: start) == 7)
        #expect(cal.component(.minute, from: start) == 0)
        #expect(cal.component(.hour, from: end) == 15)
        #expect(cal.component(.minute, from: end) == 30)
        // Monday is weekday 2 (1=Sunday)
        #expect(cal.component(.weekday, from: start) == 2)
    }

    @Test func mathHomeworkDueFriday() {
        let result = parse("Math homework due Friday")
        guard case let .task(title, due, _) = result else {
            Issue.record("Expected task, got \(result)"); return
        }
        #expect(title.localizedCaseInsensitiveContains("math"))
        #expect(title.localizedCaseInsensitiveContains("homework"))
        #expect(due != nil)
        let cal = Calendar.current
        if let due { #expect(cal.component(.weekday, from: due) == 6) }   // Friday = 6
    }

    @Test func recurringTueThu() {
        let result = parse("Every Tuesday and Thursday 11am to 2pm class")
        guard case let .event(_, start, end, recurrence, _) = result else {
            Issue.record("Expected event, got \(result)"); return
        }
        #expect(recurrence != nil)
        if let r = recurrence {
            #expect(r.byDay.contains(2) && r.byDay.contains(4))
        }
        let cal = Calendar.current
        #expect(cal.component(.hour, from: start) == 11)
        #expect(cal.component(.hour, from: end) == 14)
    }

    @Test func doctorAppointmentSpecificDate() {
        let result = parse("Doctor appointment Nov 15 at 2pm")
        guard case let .event(_, start, _, _, _) = result else {
            Issue.record("Expected event, got \(result)"); return
        }
        let cal = Calendar.current
        #expect(cal.component(.month, from: start) == 11)
        #expect(cal.component(.day, from: start) == 15)
        #expect(cal.component(.hour, from: start) == 14)
    }

    @Test func gymTomorrowAt6() {
        let result = parse("gym tomorrow at 6pm")
        guard case let .event(_, start, _, _, _) = result else {
            Issue.record("Expected event, got \(result)"); return
        }
        #expect(Calendar.current.component(.hour, from: start) == 18)
    }

    @Test func everyMondayGym() {
        let result = parse("every monday gym 7am")
        guard case let .event(_, start, _, recurrence, _) = result else {
            Issue.record("Expected event, got \(result)"); return
        }
        #expect(recurrence != nil)
        if let r = recurrence { #expect(r.byDay == [1]) }
        #expect(Calendar.current.component(.hour, from: start) == 7)
    }

    @Test func pickUpGroceriesSaturday() {
        let result = parse("Pick up groceries Saturday")
        guard case let .task(title, due, _) = result else {
            Issue.record("Expected task, got \(result)"); return
        }
        #expect(title.localizedCaseInsensitiveContains("pick up groceries"))
        #expect(due != nil)
        if let due { #expect(Calendar.current.component(.weekday, from: due) == 7) }
    }

    @Test func callMomThisWeekend() {
        // No specific time → task. `due` may or may not be present;
        // the test only requires it to be classified as a task.
        let result = parse("Call mom this weekend")
        if case .task(let title, _, _) = result {
            #expect(title.localizedCaseInsensitiveContains("call"))
        } else {
            Issue.record("Expected task, got \(result)")
        }
    }

    // MARK: - Category inference

    @Test func categoryInference() {
        let work = ParserCategory(id: UUID(), name: "Work")
        let result = NLParser.parse("Working Monday 9am to 5pm",
                                    now: fixedNow,
                                    categories: [work])
        if case let .event(_, _, _, _, cat) = result {
            #expect(cat == work.id)
        } else {
            Issue.record("Expected event")
        }
    }

    // MARK: - Empty input

    @Test func emptyInputErrors() {
        let result = parse("   ")
        if case .error = result {} else {
            Issue.record("Expected error, got \(result)")
        }
    }

    // MARK: - Short AM/PM markers

    @Test func shortAmMarker() {
        let result = parse("workout 7a")
        guard case let .event(_, start, _, _, _) = result else {
            Issue.record("Expected event, got \(result)"); return
        }
        #expect(Calendar.current.component(.hour, from: start) == 7)
    }

    @Test func shortPmMarker() {
        let result = parse("call 3:30p tomorrow")
        guard case let .event(_, start, _, _, _) = result else {
            Issue.record("Expected event, got \(result)"); return
        }
        #expect(Calendar.current.component(.hour, from: start) == 15)
        #expect(Calendar.current.component(.minute, from: start) == 30)
    }

    @Test func mixedShortMarkers() {
        let result = parse("Working Monday 7a to 3:30p")
        guard case let .event(_, start, end, _, _) = result else {
            Issue.record("Expected event, got \(result)"); return
        }
        let cal = Calendar.current
        #expect(cal.component(.hour, from: start) == 7)
        #expect(cal.component(.hour, from: end) == 15)
        #expect(cal.component(.minute, from: end) == 30)
    }

    // MARK: - Range without a connector

    @Test func rangeWithoutToConnector() {
        // "7am 3:30pm" — no "to" between the two times
        let result = parse("Working Monday 7am 3:30pm")
        guard case let .event(_, start, end, _, _) = result else {
            Issue.record("Expected event, got \(result)"); return
        }
        let cal = Calendar.current
        #expect(cal.component(.hour, from: start) == 7)
        #expect(cal.component(.hour, from: end) == 15)
        #expect(cal.component(.minute, from: end) == 30)
    }

    @Test func rangeWithBareEndTime() {
        // "7am 3:30" — the bare 3:30 should be promoted to PM since it
        // comes after 7am and 3:30 < 7:00 in the morning would be silly.
        let result = parse("Working Monday 7am 3:30")
        guard case let .event(_, start, end, _, _) = result else {
            Issue.record("Expected event, got \(result)"); return
        }
        let cal = Calendar.current
        #expect(cal.component(.hour, from: start) == 7)
        #expect(cal.component(.hour, from: end) == 15)
        #expect(cal.component(.minute, from: end) == 30)
    }

    // MARK: - "7 a" should NOT match (avoids "7 days a week" false positive)

    @Test func bareLetterAfterSpaceDoesNotMatch() {
        // "Read for 7 a few times" — "7 a" should NOT be parsed as "7am".
        // We expect this to be a Task with no time component (not an event).
        let result = parse("Read for 7 a few times")
        if case .event = result {
            Issue.record("'7 a' should not be parsed as a time")
        }
    }

    // MARK: - Past-time inputs should land on the right day

    /// fixedNow is Sunday May 3 2026 at 09:00. A bare "5a-6a" is in the
    /// past (5–6am < 9am), so the parser should schedule it for TOMORROW,
    /// not 7 days from now.
    @Test func timeOnlyInPastBumpsToTomorrow() {
        let result = parse("Gym 5a-6a")
        guard case let .event(_, start, end, _, _) = result else {
            Issue.record("Expected event, got \(result)"); return
        }
        let cal = Calendar.current
        // Tomorrow = May 4 (Monday)
        #expect(cal.component(.month, from: start) == 5)
        #expect(cal.component(.day, from: start) == 4)
        #expect(cal.component(.hour, from: start) == 5)
        #expect(cal.component(.hour, from: end) == 6)
    }

    /// "Working Monday 7am to 3:30pm" — when fixedNow is a Sunday, the
    /// next Monday is tomorrow (May 4). Make sure the start is on that
    /// Monday and never lands on a previous Monday.
    @Test func weekdayEventGoesToNextOccurrence() {
        let result = parse("Working Monday 7am to 3:30pm")
        guard case let .event(_, start, _, _, _) = result else {
            Issue.record("Expected event, got \(result)"); return
        }
        let cal = Calendar.current
        // May 4 2026 is a Monday.
        #expect(cal.component(.month, from: start) == 5)
        #expect(cal.component(.day, from: start) == 4)
        #expect(cal.component(.weekday, from: start) == 2)   // Monday = 2
    }

    /// "Gym 11pm" at fixedNow 9am — 11pm is still in the future today,
    /// so we should NOT bump.
    @Test func timeOnlyInFutureStaysToday() {
        let result = parse("Gym 11pm")
        guard case let .event(_, start, _, _, _) = result else {
            Issue.record("Expected event, got \(result)"); return
        }
        let cal = Calendar.current
        #expect(cal.component(.month, from: start) == 5)
        #expect(cal.component(.day, from: start) == 3)        // today
        #expect(cal.component(.hour, from: start) == 23)
    }

    // MARK: - Compact HHMM time format ("430p", "1130am")

    @Test func compactTimeWithShortMarker() {
        // "Gym 430p" — short for 4:30pm.
        let result = parse("Gym 430p")
        guard case let .event(_, start, _, _, _) = result else {
            Issue.record("Expected event, got \(result)"); return
        }
        let cal = Calendar.current
        #expect(cal.component(.hour, from: start) == 16)
        #expect(cal.component(.minute, from: start) == 30)
    }

    @Test func compactTimeRange() {
        // "Study for Math Test 430p-530p" — should be a 1-hour event from
        // 4:30pm to 5:30pm.
        let result = parse("Study for Math Test 430p-530p")
        guard case let .event(title, start, end, _, _) = result else {
            Issue.record("Expected event, got \(result)"); return
        }
        #expect(title.localizedCaseInsensitiveContains("study"))
        let cal = Calendar.current
        #expect(cal.component(.hour, from: start) == 16)
        #expect(cal.component(.minute, from: start) == 30)
        #expect(cal.component(.hour, from: end) == 17)
        #expect(cal.component(.minute, from: end) == 30)
    }

    @Test func compactTimeWithLongMarker() {
        // "1130am" — eleven thirty AM.
        let result = parse("Standup 1130am")
        guard case let .event(_, start, _, _, _) = result else {
            Issue.record("Expected event, got \(result)"); return
        }
        let cal = Calendar.current
        #expect(cal.component(.hour, from: start) == 11)
        #expect(cal.component(.minute, from: start) == 30)
    }

    @Test func compactTimeRejectsInvalidHour() {
        // "9999p" is bogus and must NOT match. This ensures the parser
        // doesn't classify a number-heavy string as an event by accident.
        let result = parse("Order 9999p widgets")
        if case .event = result {
            Issue.record("'9999p' should not match as a time")
        }
    }
}

// MARK: - Recurrence expansion tests

@MainActor
struct RecurrenceTests {
    @Test func nonRecurringSingleInstance() {
        let cal = Calendar.current
        let start = cal.date(from: DateComponents(year: 2026, month: 5, day: 4, hour: 9))!
        let end   = cal.date(from: DateComponents(year: 2026, month: 5, day: 4, hour: 10))!
        let event = Event(title: "Standup",
                          startDate: start,
                          endDate: end)
        let from = cal.date(from: DateComponents(year: 2026, month: 5, day: 1))!
        let to   = cal.date(from: DateComponents(year: 2026, month: 5, day: 8))!
        let instances = Recurrence_.instances(of: event, from: from, to: to)
        #expect(instances.count == 1)
    }

    @Test func weeklyExpands() {
        let cal = Calendar.current
        let start = cal.date(from: DateComponents(year: 2026, month: 5, day: 4, hour: 11))!
        let end   = cal.date(from: DateComponents(year: 2026, month: 5, day: 4, hour: 14))!
        let event = Event(title: "Class",
                          startDate: start,
                          endDate: end,
                          recurrenceEnabled: true,
                          recurrenceByDay: [1, 3])   // Mon + Wed
        let from = cal.date(from: DateComponents(year: 2026, month: 5, day: 4))!
        let to   = cal.date(from: DateComponents(year: 2026, month: 5, day: 18))!
        let instances = Recurrence_.instances(of: event, from: from, to: to)
        // 2 weeks × 2 days = 4 instances.
        #expect(instances.count == 4)
    }
}
