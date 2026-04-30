//
//  TaskFilters.swift
//  MyPlanner
//
//  The filter chip row at the top of the Tasks view, plus the predicate
//  logic that powers each filter.
//

import Foundation

enum TaskFilter: String, CaseIterable, Identifiable {
    case all, today, overdue, upcoming, noDate, completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:       return "All"
        case .today:     return "Today"
        case .overdue:   return "Overdue"
        case .upcoming:  return "Upcoming"
        case .noDate:    return "No date"
        case .completed: return "Completed"
        }
    }

    /// Returns the tasks matching this filter, sorted per spec:
    ///   undated last, then by due date asc, then priority high→low,
    ///   then alphabetical.
    func apply(to tasks: [TaskItem], now: Date) -> [TaskItem] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)

        let matched = tasks.filter { t in
            switch self {
            case .all:
                return !t.completed
            case .today:
                guard let d = t.dueDate, !t.completed else { return false }
                return cal.isDate(d, inSameDayAs: today)
            case .overdue:
                guard let d = t.dueDate, !t.completed else { return false }
                return cal.startOfDay(for: d) < today
            case .upcoming:
                guard let d = t.dueDate, !t.completed else { return false }
                return cal.startOfDay(for: d) > today
            case .noDate:
                return t.dueDate == nil && !t.completed
            case .completed:
                return t.completed
            }
        }

        return matched.sorted { Self.sort($0, $1) }
    }

    /// Empty-state heading per filter.
    func emptyHeading() -> String {
        switch self {
        case .all:       return "No tasks"
        case .today:     return "No tasks due today"
        case .overdue:   return "Nothing overdue"
        case .upcoming:  return "Nothing upcoming"
        case .noDate:    return "No tasks without a date"
        case .completed: return "Nothing completed yet"
        }
    }

    static func sort(_ a: TaskItem, _ b: TaskItem) -> Bool {
        // Undated last
        switch (a.dueDate, b.dueDate) {
        case (nil, nil):
            break
        case (nil, .some):
            return false
        case (.some, nil):
            return true
        case let (aD?, bD?):
            if aD != bD { return aD < bD }
        }
        // Priority: high < med < low (high should sort first)
        let pri: (String) -> Int = {
            switch $0 { case "high": return 0; case "med": return 1; default: return 2 }
        }
        if pri(a.priority) != pri(b.priority) {
            return pri(a.priority) < pri(b.priority)
        }
        // Alphabetical fallback
        return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
    }
}
