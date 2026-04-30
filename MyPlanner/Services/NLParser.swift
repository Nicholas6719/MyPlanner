//
//  NLParser.swift
//  MyPlanner
//
//  Natural-language parser for the composer bar. Takes free text like
//  "Working Monday 7am to 3:30pm" and returns a structured ParsedInput.
//
//  Strategy:
//   1. NSDataDetector finds date phrases and (optionally) durations.
//   2. Custom regex finds recurrence keywords ("every", "weekly", …) and
//      weekday names.
//   3. We classify the input as Event vs Task using a small rule cascade.
//   4. We strip the matched phrases (date, weekdays, connectives) from the
//      original text to produce a clean title.
//
//  This file is intentionally readable rather than micro-optimized. The
//  unit tests in MyPlannerTests cover the cases the spec calls out.
//

import Foundation

// MARK: - Public Types

struct Recurrence: Hashable {
    /// 0 = Sunday, 6 = Saturday.
    var byDay: [Int]
}

enum ParsedInput {
    case event(title: String,
               start: Date,
               end: Date,
               recurrence: Recurrence?,
               categoryID: UUID?)
    case task(title: String,
              due: Date?,
              categoryID: UUID?)
    case error(String)
}

/// Lightweight category-resolution input. The parser does not own SwiftData,
/// so the caller passes the user's current categories in.
struct ParserCategory {
    let id: UUID
    let name: String        // case-insensitive match on this
}

// MARK: - Parser

struct NLParser {

    /// Built-in category keywords (case-insensitive, word-boundary matched).
    /// The parser will match a built-in keyword to a category whose name
    /// matches the bucket. The user's actual category names are also
    /// matched directly, ahead of the built-ins.
    private static let builtInKeywords: [(bucket: String, words: [String])] = [
        ("Work",     ["work", "working", "shift", "meeting", "office", "standup"]),
        ("Class",    ["class", "lecture", "lab", "study", "homework", "exam", "quiz"]),
        ("Health",   ["gym", "workout", "doctor", "run", "running", "yoga"]),
        ("Personal", ["lunch", "dinner", "call", "birthday", "party", "movie", "groceries"]),
    ]

    private static let weekdayMap: [(name: String, idx: Int)] = [
        ("sunday", 0), ("sun", 0),
        ("monday", 1), ("mon", 1),
        ("tuesday", 2), ("tues", 2), ("tue", 2),
        ("wednesday", 3), ("weds", 3), ("wed", 3),
        ("thursday", 4), ("thurs", 4), ("thur", 4), ("thu", 4),
        ("friday", 5), ("fri", 5),
        ("saturday", 6), ("sat", 6),
    ]

    private static let recurrenceWordPattern =
        #"\b(every|each|weekly|recurring|repeat|repeats)\b"#

    /// Words to strip from the title after extraction (connectives etc.).
    private static let stripWords: Set<String> = [
        "at", "from", "to", "on", "due", "by",
        "every", "each", "weekly", "recurring", "repeat", "repeats",
        "this", "next", "the",
    ]

    // MARK: Entry point

    static func parse(_ text: String,
                      now: Date = Date(),
                      categories: [ParserCategory] = []) -> ParsedInput {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .error("Empty input") }

        let lower = trimmed.lowercased()

        // 1. Recurrence?
        let recurrenceFlag = (lower.range(of: Self.recurrenceWordPattern,
                                          options: .regularExpression) != nil)

        // 2. Weekday matches in the text → indices.
        let weekdayMatches = findWeekdays(in: lower)

        // 3. Date detection — NSDataDetector returns the best match plus
        //    a duration if the phrase included an end time.
        let detectorResult = detectDate(in: trimmed, now: now)

        // 4. Category inference
        let categoryID = inferCategory(text: lower, categories: categories)

        // 4b. Time-of-day fallback. NSDataDetector sometimes misses bare
        //     time phrases like "7am" when they appear alongside other text.
        //     Scan with a simple regex to recover them.
        let timeMatches = findTimeOfDay(in: lower)

        // 5. Classify event vs task
        // Decision cascade per spec:
        //   - recurrence → event
        //   - actual time range present → event
        //   - "due" keyword → task
        //   - specific time of day detected → event
        //   - else task
        //
        // We require `hasTime` (a real time-of-day match) before treating
        // the duration as evidence of an event. NSDataDetector sometimes
        // returns a 24-hour duration for a bare weekday like "Friday",
        // which would otherwise misclassify "X due Friday" as an event.
        let hasDue = lower.range(of: #"\bdue\b"#, options: .regularExpression) != nil
        let hasTime = (detectorResult?.hasTime ?? false) || !timeMatches.isEmpty
        let hasDuration = (detectorResult?.duration ?? 0) > 0
                          && (detectorResult?.hasTime ?? false)

        let isEvent: Bool = {
            if recurrenceFlag { return true }
            if hasDuration { return true }
            if hasDue { return false }
            if hasTime { return true }
            return false
        }()

        // 6. Title extraction — strip everything we recognized.
        let title = extractTitle(from: trimmed,
                                 dateRange: detectorResult?.range,
                                 weekdayRanges: weekdayMatches.map(\.range))

        // 7. Build result.
        if isEvent {
            // Resolve start/end.
            // - If recurrence, start is the next upcoming weekday in byDay
            //   (preserving time-of-day from the parsed match if available),
            //   end is start + duration (default 1 hour if no duration).
            // - If non-recurring, use detectorResult start + end (or default
            //   1 hour duration).

            // Prefer the detector's time if it had one; otherwise use the
            // first regex match.
            let timeOfDay: TimeOfDay?
            if let r = detectorResult, r.hasTime {
                timeOfDay = TimeOfDay(date: r.date)
            } else if let first = timeMatches.first {
                timeOfDay = first
            } else {
                timeOfDay = nil
            }

            let duration: TimeInterval = {
                // Use detector duration only if it included a time (so it's
                // a real range like "7am to 3:30pm").
                if let r = detectorResult, r.duration > 0, r.hasTime {
                    return r.duration
                }
                // Otherwise: if we found two time-of-day matches via regex,
                // treat them as a range.
                if timeMatches.count >= 2 {
                    let s = timeMatches[0]; let e = timeMatches[1]
                    let m1 = s.hour * 60 + s.minute
                    let m2 = e.hour * 60 + e.minute
                    if m2 > m1 { return TimeInterval((m2 - m1) * 60) }
                }
                return 3600   // default 1 hour
            }()

            let byDay: [Int] = {
                if !weekdayMatches.isEmpty {
                    return Array(Set(weekdayMatches.map(\.idx))).sorted()
                }
                if let r = detectorResult {
                    let cal = Calendar.current
                    let wd = cal.component(.weekday, from: r.date) - 1   // 1..7 → 0..6
                    return [wd]
                }
                return []
            }()

            let start: Date
            if recurrenceFlag, !byDay.isEmpty {
                start = nextOccurrence(of: byDay,
                                       from: now,
                                       timeOfDay: timeOfDay)
            } else if let r = detectorResult {
                start = r.date
            } else {
                // No date AND no recurrence — fall back to now + 1h, on the hour
                start = roundedHour(after: now)
            }
            let end = start.addingTimeInterval(duration)

            let recurrence: Recurrence? = recurrenceFlag ? Recurrence(byDay: byDay) : nil

            return .event(title: title.isEmpty ? "Untitled" : title,
                          start: start,
                          end: end,
                          recurrence: recurrence,
                          categoryID: categoryID)
        } else {
            // Task — `due` may be nil if no date phrase was detected.
            //
            // We prefer a weekday-name match over NSDataDetector's date for
            // bare phrases like "due Friday", because NSDataDetector
            // sometimes returns the day-before-midnight when given a bare
            // weekday word, which throws off the weekday by one.
            var due: Date?
            if let detector = detectorResult {
                if !weekdayMatches.isEmpty, !detector.hasTime {
                    let targetWeekdays = Array(Set(weekdayMatches.map(\.idx))).sorted()
                    due = nextOccurrence(of: targetWeekdays, from: now, timeOfDay: nil)
                } else {
                    due = detector.date
                }
            }
            return .task(title: title.isEmpty ? "Untitled" : title,
                         due: due,
                         categoryID: categoryID)
        }
    }

    // MARK: - Helpers

    /// Wraps NSDataDetector output. `hasTime` tells us whether the user
    /// actually included a time of day (vs just a bare date).
    private struct DetectorResult {
        let date: Date
        let duration: TimeInterval
        let range: Range<String.Index>
        let hasTime: Bool
    }

    private static func detectDate(in text: String, now: Date) -> DetectorResult? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return nil
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        // We pass a reference date so "Friday" resolves relative to `now`.
        let matches = detector.matches(in: text, options: [], range: nsRange)
        guard let m = matches.first, let date = m.date,
              let swiftRange = Range(m.range, in: text) else {
            return nil
        }
        // NSDataDetector returns 12:00 for date-only matches (sometimes,
        // depending on system). Heuristic: examine the matched substring
        // for digits + am/pm or h:mm to decide if a time was specified.
        let phrase = text[swiftRange].lowercased()
        let hasTime = (phrase.range(of: #"\d{1,2}(:\d{2})?\s*(am|pm)"#,
                                    options: .regularExpression) != nil)
                   || (phrase.range(of: #"\d{1,2}:\d{2}"#,
                                    options: .regularExpression) != nil)
                   || (phrase.range(of: #"\b(noon|midnight)\b"#,
                                    options: .regularExpression) != nil)

        // Adjust the detected date to be relative to `now` if the date
        // looks like it might be in the past (NSDataDetector occasionally
        // returns a past day-of-week if the current weekday is the same
        // as the parsed weekday). Push forward by a week.
        var resolved = date
        if resolved < now.addingTimeInterval(-60) {
            // Try +7 days first; if that overshoots into the future too far
            // we leave it alone.
            let plusWeek = resolved.addingTimeInterval(7 * 24 * 3600)
            if plusWeek > now {
                resolved = plusWeek
            }
        }

        return DetectorResult(date: resolved,
                              duration: m.duration,
                              range: swiftRange,
                              hasTime: hasTime)
    }

    private struct WeekdayMatch {
        let idx: Int
        let range: Range<String.Index>
    }

    private static func findWeekdays(in lower: String) -> [WeekdayMatch] {
        var results: [WeekdayMatch] = []
        for (name, idx) in weekdayMap {
            // Word-boundary match.
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: name))\\b"
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            let nsRange = NSRange(lower.startIndex..<lower.endIndex, in: lower)
            re.enumerateMatches(in: lower, options: [], range: nsRange) { match, _, _ in
                if let m = match, let r = Range(m.range, in: lower) {
                    results.append(WeekdayMatch(idx: idx, range: r))
                }
            }
        }
        // Deduplicate overlapping matches: prefer longer name (e.g. prefer
        // "monday" over "mon"). Sort by start, then drop matches that are
        // entirely inside an earlier match.
        results.sort { $0.range.lowerBound < $1.range.lowerBound }
        var deduped: [WeekdayMatch] = []
        for m in results {
            if let last = deduped.last,
               m.range.lowerBound >= last.range.lowerBound,
               m.range.upperBound <= last.range.upperBound {
                continue   // contained in previous, skip
            }
            // Also remove a previous match that's contained in this one
            if let last = deduped.last,
               last.range.lowerBound >= m.range.lowerBound,
               last.range.upperBound <= m.range.upperBound {
                deduped.removeLast()
            }
            deduped.append(m)
        }
        return deduped
    }

    private static func inferCategory(text: String,
                                      categories: [ParserCategory]) -> UUID? {
        // 1. Match user's own categories by name first.
        for c in categories {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: c.name.lowercased()))\\b"
            if text.range(of: pattern, options: .regularExpression) != nil {
                return c.id
            }
        }
        // 2. Fall back to built-in keyword buckets, mapped to a category
        //    whose name matches the bucket (case-insensitive).
        for (bucket, words) in builtInKeywords {
            for w in words {
                let pattern = "\\b\(w)\\b"
                if text.range(of: pattern, options: .regularExpression) != nil {
                    if let match = categories.first(where: {
                        $0.name.caseInsensitiveCompare(bucket) == .orderedSame
                    }) {
                        return match.id
                    }
                }
            }
        }
        return nil
    }

    private static func extractTitle(from text: String,
                                     dateRange: Range<String.Index>?,
                                     weekdayRanges: [Range<String.Index>]) -> String {
        // Convert every range we want to remove into a position-based
        // half-open interval over the underlying scalars. This avoids
        // String.Index invalidation (and overlap) issues entirely:
        // we mark positions to drop in a Bool array, then rebuild.
        let chars = Array(text)
        var keep = [Bool](repeating: true, count: chars.count)

        func mark(_ r: Range<String.Index>) {
            let lo = text.distance(from: text.startIndex, to: r.lowerBound)
            let hi = text.distance(from: text.startIndex, to: r.upperBound)
            for i in lo..<min(hi, keep.count) where i >= 0 { keep[i] = false }
        }

        if let r = dateRange { mark(r) }
        for r in weekdayRanges { mark(r) }

        var stripped = ""
        stripped.reserveCapacity(chars.count)
        for (i, c) in chars.enumerated() {
            stripped.append(keep[i] ? c : " ")
        }

        // Strip filler words.
        let parts = stripped
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !stripWords.contains($0.lowercased()) }
            .filter { !$0.isEmpty }

        return parts.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Helper struct for "carry the time-of-day forward to a different date".
    fileprivate struct TimeOfDay {
        let hour: Int
        let minute: Int
        init(date: Date) {
            let cal = Calendar.current
            self.hour = cal.component(.hour, from: date)
            self.minute = cal.component(.minute, from: date)
        }
        init(hour: Int, minute: Int) {
            self.hour = hour
            self.minute = minute
        }
    }

    /// Scan the text for time-of-day phrases like "7am", "11am", "3:30pm",
    /// "14:00", "noon", "midnight". Returns matches in order of appearance.
    /// Used as a fallback when NSDataDetector misses a time embedded in a
    /// busy phrase like "every monday gym 7am".
    private static func findTimeOfDay(in lower: String) -> [TimeOfDay] {
        var results: [(idx: Int, tod: TimeOfDay)] = []
        // 12-hour with am/pm
        let p1 = #"\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b"#
        if let re = try? NSRegularExpression(pattern: p1) {
            let nsRange = NSRange(lower.startIndex..<lower.endIndex, in: lower)
            re.enumerateMatches(in: lower, range: nsRange) { m, _, _ in
                guard let m, let r = Range(m.range, in: lower) else { return }
                let hRange = Range(m.range(at: 1), in: lower)!
                var h = Int(lower[hRange]) ?? 0
                var min = 0
                if m.range(at: 2).location != NSNotFound,
                   let mr = Range(m.range(at: 2), in: lower) {
                    min = Int(lower[mr]) ?? 0
                }
                let ampRange = Range(m.range(at: 3), in: lower)!
                let ap = String(lower[ampRange])
                if ap == "pm" && h != 12 { h += 12 }
                if ap == "am" && h == 12 { h = 0 }
                let off = lower.distance(from: lower.startIndex, to: r.lowerBound)
                results.append((off, TimeOfDay(hour: h, minute: min)))
            }
        }
        // 24-hour HH:MM (only if no am/pm match in the same range)
        let p2 = #"\b([01]?\d|2[0-3]):([0-5]\d)\b(?!\s*(am|pm))"#
        if let re = try? NSRegularExpression(pattern: p2) {
            let nsRange = NSRange(lower.startIndex..<lower.endIndex, in: lower)
            re.enumerateMatches(in: lower, range: nsRange) { m, _, _ in
                guard let m, let r = Range(m.range, in: lower) else { return }
                let hRange = Range(m.range(at: 1), in: lower)!
                let mr     = Range(m.range(at: 2), in: lower)!
                let h = Int(lower[hRange]) ?? 0
                let min = Int(lower[mr]) ?? 0
                let off = lower.distance(from: lower.startIndex, to: r.lowerBound)
                results.append((off, TimeOfDay(hour: h, minute: min)))
            }
        }
        // Word forms
        if let r = lower.range(of: #"\bnoon\b"#, options: .regularExpression) {
            let off = lower.distance(from: lower.startIndex, to: r.lowerBound)
            results.append((off, TimeOfDay(hour: 12, minute: 0)))
        }
        if let r = lower.range(of: #"\bmidnight\b"#, options: .regularExpression) {
            let off = lower.distance(from: lower.startIndex, to: r.lowerBound)
            results.append((off, TimeOfDay(hour: 0, minute: 0)))
        }
        results.sort { $0.idx < $1.idx }
        return results.map(\.tod)
    }

    /// For recurring events, find the next future date (>= now) whose
    /// weekday is in `byDay`, and apply `timeOfDay` if provided.
    private static func nextOccurrence(of byDay: [Int],
                                       from now: Date,
                                       timeOfDay: TimeOfDay?) -> Date {
        let cal = Calendar.current
        var best: Date?
        for offset in 0..<14 {     // search a 2-week window — overkill but safe
            guard let candidate = cal.date(byAdding: .day, value: offset, to: now) else { continue }
            let wd = cal.component(.weekday, from: candidate) - 1
            guard byDay.contains(wd) else { continue }
            // Apply time of day, if provided.
            var comps = cal.dateComponents([.year, .month, .day], from: candidate)
            comps.hour   = timeOfDay?.hour   ?? cal.component(.hour, from: now)
            comps.minute = timeOfDay?.minute ?? 0
            comps.second = 0
            if let resolved = cal.date(from: comps), resolved > now.addingTimeInterval(-60) {
                if best == nil || resolved < best! {
                    best = resolved
                }
            }
        }
        return best ?? now.addingTimeInterval(3600)
    }

    private static func roundedHour(after now: Date) -> Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day, .hour], from: now)
        comps.hour = (comps.hour ?? 0) + 1
        comps.minute = 0
        return cal.date(from: comps) ?? now.addingTimeInterval(3600)
    }
}
