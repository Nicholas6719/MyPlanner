//
//  Recurrence.swift
//  MyPlanner
//
//  Expands recurring (and non-recurring) events into concrete instances
//  within a date range. Used by Week / Day views and the notification
//  scheduler.
//

import Foundation

enum Recurrence_ {
    /// Return every instance of `event` whose start time falls inside
    /// `[from, to)`. For non-recurring events: at most one instance.
    /// For weekly recurring events: walks day-by-day through the range,
    /// emitting one instance per matching weekday.
    static func instances(of event: Event,
                          from: Date,
                          to: Date) -> [EventInstance] {
        let cal = Calendar.current

        // Non-recurring: produce one instance if the event overlaps the
        // requested range.
        guard event.recurrenceEnabled, !event.recurrenceByDay.isEmpty else {
            if event.endDate >= from && event.startDate < to {
                return [EventInstance(eventID: event.id,
                                      title: event.title,
                                      categoryID: event.categoryID,
                                      isRecurring: false,
                                      start: event.startDate,
                                      end: event.endDate)]
            }
            return []
        }

        // Recurring: walk day-by-day through the range, looking for matches.
        let duration = event.endDate.timeIntervalSince(event.startDate)
        let timeComps = cal.dateComponents([.hour, .minute, .second],
                                           from: event.startDate)
        let originDay = cal.startOfDay(for: event.startDate)

        var results: [EventInstance] = []
        var cursor = cal.startOfDay(for: from)
        let endCursor = cal.startOfDay(for: to).addingTimeInterval(24 * 3600)

        while cursor < endCursor {
            // Stop if past `recurrenceUntil` (inclusive of that day).
            if let until = event.recurrenceUntil, cursor > cal.startOfDay(for: until) {
                break
            }
            // Only consider days on or after the original start day.
            if cursor >= originDay {
                let weekday = cal.component(.weekday, from: cursor) - 1   // 1..7 → 0..6
                if event.recurrenceByDay.contains(weekday) {
                    var comps = cal.dateComponents([.year, .month, .day], from: cursor)
                    comps.hour   = timeComps.hour
                    comps.minute = timeComps.minute
                    comps.second = timeComps.second
                    if let start = cal.date(from: comps) {
                        let end = start.addingTimeInterval(duration)
                        if end >= from && start < to {
                            results.append(EventInstance(eventID: event.id,
                                                         title: event.title,
                                                         categoryID: event.categoryID,
                                                         isRecurring: true,
                                                         start: start,
                                                         end: end))
                        }
                    }
                }
            }
            cursor = cal.date(byAdding: .day, value: 1, to: cursor) ?? cursor.addingTimeInterval(24 * 3600)
        }

        return results
    }

    /// Convenience: expand many events at once. Used by Week/Day views.
    static func instances(of events: [Event],
                          from: Date,
                          to: Date) -> [EventInstance] {
        events.flatMap { instances(of: $0, from: from, to: to) }
    }
}
