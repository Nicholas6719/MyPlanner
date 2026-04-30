//
//  ParsePreview.swift
//  MyPlanner
//
//  The live preview card shown above the composer input as the user types.
//  Pure presentation — receives a ParsedInput and a list of categories,
//  reports the user's "type override" toggle back via a binding.
//

import SwiftUI

enum PreviewKind: String, Hashable {
    case event, task
}

struct ParsePreview: View {
    let parsed: ParsedInput
    let categories: [PlannerCategory]
    @Binding var typeOverride: PreviewKind?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Type")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.inkDim)
                Spacer()
                SegmentedToggle(
                    options: [
                        (label: "Event", value: PreviewKind.event),
                        (label: "Task",  value: PreviewKind.task),
                    ],
                    selection: Binding(
                        get: { effectiveKind },
                        set: { typeOverride = $0 }
                    )
                )
                .frame(width: 140)
            }

            if let title = displayTitle {
                row("Title", title)
            }
            if let when = displayWhen {
                row(effectiveKind == .task ? "Due" : "When", when)
            }
            if let cat = displayCategory {
                HStack(spacing: 6) {
                    Text("Category")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.inkDim)
                        .frame(width: 64, alignment: .leading)
                    Circle()
                        .fill(Color(hex: cat.colorHex))
                        .frame(width: 8, height: 8)
                    Text(cat.name)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.ink)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .fill(Theme.surface2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    private var effectiveKind: PreviewKind {
        if let override = typeOverride { return override }
        switch parsed {
        case .event: return .event
        case .task:  return .task
        case .error: return .task
        }
    }

    private var displayTitle: String? {
        switch parsed {
        case .event(let t, _, _, _, _): return t
        case .task(let t, _, _):        return t
        case .error: return nil
        }
    }

    private var displayWhen: String? {
        switch parsed {
        case .event(_, let s, let e, let r, _):
            if let r {
                return formatRecurringRange(byDay: r.byDay, start: s, end: e)
            }
            return formatRange(start: s, end: e)
        case .task(_, let due, _):
            guard let due else { return "No date" }
            return formatTaskDue(due)
        case .error: return nil
        }
    }

    private var displayCategory: PlannerCategory? {
        let id: UUID?
        switch parsed {
        case .event(_, _, _, _, let c): id = c
        case .task(_, _, let c):        id = c
        case .error: id = nil
        }
        guard let id else { return nil }
        return categories.first(where: { $0.id == id })
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.inkDim)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
        }
    }

    // MARK: - Date formatting helpers

    private func formatRange(start: Date, end: Date) -> String {
        let dayLabel = humanDayLabel(start)
        return "\(dayLabel) · \(timeStr(start)) – \(timeStr(end))"
    }

    private func formatRecurringRange(byDay: [Int], start: Date, end: Date) -> String {
        let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let names = byDay.sorted().map { dayNames[$0] }.joined(separator: ", ")
        return "Every \(names) · \(timeStr(start)) – \(timeStr(end))"
    }

    private func formatTaskDue(_ d: Date) -> String {
        let cal = Calendar.current
        let now = Date()
        let day = humanDayLabel(d)
        // Include time only if it's not midnight (i.e. user provided one).
        let comps = cal.dateComponents([.hour, .minute], from: d)
        if (comps.hour ?? 0) == 0 && (comps.minute ?? 0) == 0 {
            return day
        }
        _ = now
        return "\(day) · \(timeStr(d))"
    }

    private func humanDayLabel(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInTomorrow(d) { return "Tomorrow" }
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: d)
    }

    private func timeStr(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mma"
        f.amSymbol = "am"
        f.pmSymbol = "pm"
        return f.string(from: d)
    }
}
