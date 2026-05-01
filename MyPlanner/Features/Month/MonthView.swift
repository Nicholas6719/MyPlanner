//
//  MonthView.swift
//  MyPlanner
//
//  Calendar-style month grid: 6 rows × 7 columns of day cells, with
//  today's date highlighted, the currently selected day outlined, and
//  up to 3 colored event dots per day. Tapping a day jumps to the Day
//  tab focused on that date.
//
//  Inspired by Apple Calendar's month view, adapted to our dark theme.
//

import SwiftUI
import SwiftData
import Combine

struct MonthView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var events: [Event]
    @Query private var categories: [PlannerCategory]

    /// Shared with DayView via RootShell — when the user taps a day here,
    /// we update this and call `onSelectDay` so RootShell can switch tabs.
    @Binding var selectedDay: Date
    let onSelectDay: () -> Void

    /// First instant of the currently displayed month. Independent of
    /// `selectedDay` so the user can browse months without losing the
    /// selection.
    @State private var displayMonth: Date = MonthView.startOfMonth(Date())
    @State private var now: Date = Date()

    /// Re-evaluate "today" once a minute so the highlight rolls over at
    /// midnight without requiring the user to navigate away.
    private let nowTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private let cal = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            header
            weekdayLabels
            grid
            Spacer(minLength: 0)
        }
        .background(Theme.bg)
        .onReceive(nowTimer) { _ in now = Date() }
        // Horizontal swipe = month nav. Same gesture pattern as Week/Day:
        // require horizontal-dominant motion so vertical scrolls (none
        // here, but consistent with the rest of the app) aren't hijacked.
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dx) > abs(dy) * 1.5 else { return }
                    if dx < -50 { goToMonth(offset: 1) }
                    else if dx > 50 { goToMonth(offset: -1) }
                }
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Button { goToMonth(offset: -1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Theme.surface2))
            }
            .buttonStyle(.plain)

            Text(monthLabel)
                .font(.system(size: 16, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.ink)
                .headingKerning()
                .frame(maxWidth: .infinity)

            Button { goToMonth(offset: 1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Theme.surface2))
            }
            .buttonStyle(.plain)

            Button {
                displayMonth = MonthView.startOfMonth(Date())
                selectedDay = cal.startOfDay(for: Date())
            } label: {
                Text("TODAY")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(Theme.accentSoft))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Spacing.outer)
        .padding(.vertical, 10)
        .background(Theme.surface.opacity(0.4))
    }

    private var monthLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: displayMonth)
    }

    // MARK: - Weekday labels (S M T W T F S)

    private var weekdayLabels: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { d in
                Text(["SUN","MON","TUE","WED","THU","FRI","SAT"][d])
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.inkDim)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 8)
        .overlay(Rectangle().fill(Theme.borderSoft).frame(height: 1),
                 alignment: .bottom)
    }

    // MARK: - 6×7 grid

    private var grid: some View {
        let cells = monthCells
        let instancesByDay = expandedInstancesByDay(in: cells)

        return GeometryReader { geo in
            // 6 rows, equal heights. Row height = total / 6.
            let rowHeight = geo.size.height / 6
            VStack(spacing: 0) {
                ForEach(0..<6, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { col in
                            let date = cells[row * 7 + col]
                            MonthDayCell(
                                date: date,
                                inCurrentMonth: cal.isDate(date,
                                                            equalTo: displayMonth,
                                                            toGranularity: .month),
                                isToday: cal.isDateInToday(date),
                                isSelected: cal.isDate(date,
                                                        inSameDayAs: selectedDay),
                                events: instancesByDay[cal.startOfDay(for: date)] ?? [],
                                categories: categories
                            )
                            .frame(maxWidth: .infinity, minHeight: rowHeight,
                                   maxHeight: rowHeight)
                            .onTapGesture {
                                selectedDay = cal.startOfDay(for: date)
                                onSelectDay()
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Data shaping

    /// 42 dates: leading days from the previous month, all of the current
    /// month, then trailing days from the next month — enough to fill a
    /// 6-row grid.
    private var monthCells: [Date] {
        let firstOfMonth = displayMonth
        // weekday: 1=Sunday … 7=Saturday. We want the grid to start on
        // Sunday, so leading days = (weekday - 1).
        let weekday = cal.component(.weekday, from: firstOfMonth)
        let leadingDays = weekday - 1
        let gridStart = cal.date(byAdding: .day,
                                 value: -leadingDays,
                                 to: firstOfMonth) ?? firstOfMonth
        return (0..<42).compactMap {
            cal.date(byAdding: .day, value: $0, to: gridStart)
        }
    }

    /// Group event instances (recurrence-expanded) by their start day so
    /// each cell can look its events up in O(1).
    private func expandedInstancesByDay(in cells: [Date]) -> [Date: [EventInstance]] {
        guard let first = cells.first, let last = cells.last else { return [:] }
        let from = cal.startOfDay(for: first)
        let to = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: last)) ?? last
        let instances = Recurrence_.instances(of: events, from: from, to: to)
        return Dictionary(grouping: instances) { cal.startOfDay(for: $0.start) }
            .mapValues { $0.sorted { $0.start < $1.start } }
    }

    // MARK: - Actions

    private func goToMonth(offset: Int) {
        if let d = cal.date(byAdding: .month, value: offset, to: displayMonth) {
            displayMonth = MonthView.startOfMonth(d)
        }
    }

    /// First instant of the calendar month containing `date`.
    private static func startOfMonth(_ date: Date) -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: date)
        return cal.date(from: comps) ?? cal.startOfDay(for: date)
    }
}

// MARK: - Single Day Cell

private struct MonthDayCell: View {
    let date: Date
    let inCurrentMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let events: [EventInstance]
    let categories: [PlannerCategory]

    private let cal = Calendar.current

    var body: some View {
        VStack(spacing: 4) {
            dayNumber
                .padding(.top, 6)
            eventDots
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(Rectangle()
                    .fill(Theme.borderSoft)
                    .frame(height: 0.5),
                 alignment: .top)
        .overlay(Rectangle()
                    .fill(Theme.borderSoft)
                    .frame(width: 0.5),
                 alignment: .leading)
        .contentShape(Rectangle())   // tap targets entire cell, not just text
    }

    // MARK: - Day number with optional today / selected ring

    private var dayNumber: some View {
        ZStack {
            if isToday {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 26, height: 26)
            } else if isSelected {
                Circle()
                    .stroke(Theme.accent, lineWidth: 1.5)
                    .frame(width: 26, height: 26)
            }
            Text(numberString)
                .font(.system(size: 13,
                              weight: isToday ? .bold : .regular)
                        .monospacedDigit())
                .foregroundStyle(numberColor)
        }
    }

    private var numberString: String {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f.string(from: date)
    }

    private var numberColor: Color {
        if isToday { return .black }
        if !inCurrentMonth { return Theme.inkFaint }
        return Theme.ink
    }

    // MARK: - Event dots

    private var eventDots: some View {
        // Show up to 3 colored dots, then a "+N" marker if there are
        // more. Colors come from each event's category (uncategorized
        // events get the slate color so they don't masquerade as Work).
        HStack(spacing: 3) {
            ForEach(events.prefix(3), id: \.id) { inst in
                Circle()
                    .fill(color(for: inst))
                    .frame(width: 5, height: 5)
            }
            if events.count > 3 {
                Text("+\(events.count - 3)")
                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.inkDim)
            }
        }
        .frame(height: 8)
        .opacity(inCurrentMonth ? 1.0 : 0.4)
    }

    private func color(for inst: EventInstance) -> Color {
        if let cid = inst.categoryID,
           let cat = categories.first(where: { $0.id == cid }) {
            return Color(hex: cat.colorHex)
        }
        return Theme.uncategorized
    }
}
