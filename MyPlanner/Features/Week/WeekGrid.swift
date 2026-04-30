//
//  WeekGrid.swift
//  MyPlanner
//
//  The 7-column hour grid. Pure layout: takes the visible week start, the
//  visible hour range, the events to render, and the categories — and
//  draws columns. The parent (WeekView) handles week navigation, title,
//  and now-line tracking.
//

import SwiftUI

struct WeekGrid: View {
    let weekStart: Date            // Sunday
    let hourStart: Int
    let hourEnd: Int               // exclusive
    let instances: [EventInstance]
    let categories: [PlannerCategory]
    let now: Date
    let onTapHour: (Date) -> Void   // (hour-start date) → action
    let onTapEvent: (EventInstance) -> Void
    let onDeleteEvent: (EventInstance) -> Void

    // Visual constants
    private let hourHeight: CGFloat = 44
    private let hourLabelWidth: CGFloat = 44
    private let dayHeaderHeight: CGFloat = 36

    private let cal = Calendar.current

    var body: some View {
        let visibleHours = max(1, hourEnd - hourStart + 1)
        let totalHeight = CGFloat(visibleHours) * hourHeight

        VStack(spacing: 0) {
            // Day-of-week header stays pinned outside the scroll view so the
            // user always sees Sun/Mon/Tue/etc.
            dayHeader
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 0) {
                        hourLabelColumn(totalHeight: totalHeight)
                        ZStack(alignment: .topLeading) {
                            gridBackground(totalHeight: totalHeight)
                            ForEach(0..<7, id: \.self) { d in
                                column(dayIndex: d, totalHeight: totalHeight)
                            }
                            nowLine(totalHeight: totalHeight)
                        }
                    }
                    .background(Theme.bg)
                }
                .onAppear {
                    if cal.isDate(now, equalTo: weekStart, toGranularity: .weekOfYear) {
                        let scrollHour = max(hourStart, cal.component(.hour, from: now))
                        proxy.scrollTo("hour-\(scrollHour)", anchor: .top)
                    }
                }
            }
        }
    }

    // MARK: Header row with weekday labels

    private var dayHeader: some View {
        HStack(spacing: 0) {
            // Spacer above the hour-label column
            Color.clear.frame(width: hourLabelWidth)
            ForEach(0..<7, id: \.self) { d in
                let day = cal.date(byAdding: .day, value: d, to: weekStart) ?? weekStart
                let isToday = cal.isDateInToday(day)
                VStack(spacing: 1) {
                    Text(weekdayShort(d))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isToday ? Theme.accent : Theme.inkDim)
                    Text(dayNumber(day))
                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                        .foregroundStyle(isToday ? Theme.accent : Theme.ink)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(isToday ? Theme.accentSoft : .clear)
            }
        }
        .frame(height: dayHeaderHeight)
        .background(Theme.surface.opacity(0.6))
        .overlay(Rectangle().fill(Theme.borderSoft).frame(height: 1), alignment: .bottom)
    }

    // MARK: Hour labels (left column)

    private func hourLabelColumn(totalHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(hourStart...hourEnd, id: \.self) { h in
                Text(formatHour(h))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(Theme.inkDim)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 6)
                    .frame(height: hourHeight, alignment: .top)
                    .id("hour-\(h)")
            }
        }
        .frame(width: hourLabelWidth, height: totalHeight, alignment: .top)
    }

    // MARK: Grid lines

    private func gridBackground(totalHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(hourStart...hourEnd, id: \.self) { _ in
                Rectangle()
                    .fill(Theme.borderSoft)
                    .frame(height: 1)
                    .frame(maxWidth: .infinity)
                Spacer().frame(height: hourHeight - 1)
            }
        }
        .frame(height: totalHeight, alignment: .top)
    }

    // MARK: Single day column

    private func column(dayIndex: Int, totalHeight: CGFloat) -> some View {
        GeometryReader { geo in
            let columnWidth = geo.size.width / 7
            let day = cal.date(byAdding: .day, value: dayIndex, to: weekStart) ?? weekStart
            let isToday = cal.isDateInToday(day)
            ZStack(alignment: .topLeading) {
                // Today highlight
                if isToday {
                    Rectangle()
                        .fill(Theme.accentSoft)
                        .frame(width: columnWidth, height: totalHeight)
                        .offset(x: CGFloat(dayIndex) * columnWidth)
                }
                // Tap layers — one per hour cell so the user can long-press
                // anywhere to create an event for that hour.
                ForEach(hourStart...hourEnd, id: \.self) { h in
                    let yOffset = CGFloat(h - hourStart) * hourHeight
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .frame(width: columnWidth, height: hourHeight)
                        .offset(x: CGFloat(dayIndex) * columnWidth, y: yOffset)
                        .onTapGesture {
                            var comps = cal.dateComponents([.year, .month, .day], from: day)
                            comps.hour = h
                            comps.minute = 0
                            if let date = cal.date(from: comps) {
                                onTapHour(date)
                            }
                        }
                }
                // Event blocks falling on this day
                ForEach(eventsFor(day: day)) { inst in
                    let frame = blockFrame(for: inst, day: day, columnWidth: columnWidth)
                    EventBlock(instance: inst,
                               category: categoryFor(inst),
                               compact: true)
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: CGFloat(dayIndex) * columnWidth + 1,
                                y: frame.y)
                        .onTapGesture { onTapEvent(inst) }
                        .contextMenu {
                            Button {
                                onTapEvent(inst)
                            } label: {
                                Label("Edit", systemImage: "square.and.pencil")
                            }
                            Divider()
                            Button(role: .destructive) {
                                onDeleteEvent(inst)
                            } label: {
                                Label(inst.isRecurring
                                      ? "Delete All Repeats"
                                      : "Delete Event",
                                      systemImage: "trash")
                            }
                        }
                }
            }
        }
        .frame(height: totalHeight)
    }

    // MARK: Now line

    @ViewBuilder
    private func nowLine(totalHeight: CGFloat) -> some View {
        // Only show if "now" is within the visible week.
        if cal.isDate(now, equalTo: weekStart, toGranularity: .weekOfYear) {
            let dayIdx = cal.dateComponents([.day], from: cal.startOfDay(for: weekStart),
                                            to: cal.startOfDay(for: now)).day ?? 0
            if dayIdx >= 0 && dayIdx < 7 {
                let nowComps = cal.dateComponents([.hour, .minute], from: now)
                let hourFloat = Double(nowComps.hour ?? 0) + Double(nowComps.minute ?? 0) / 60
                if hourFloat >= Double(hourStart) && hourFloat <= Double(hourEnd) {
                    let y = (hourFloat - Double(hourStart)) * Double(hourHeight)
                    GeometryReader { geo in
                        let columnWidth = geo.size.width / 7
                        ZStack(alignment: .leading) {
                            Circle()
                                .fill(Theme.accent)
                                .frame(width: 6, height: 6)
                                .offset(x: CGFloat(dayIdx) * columnWidth - 1)
                            Rectangle()
                                .fill(Theme.accent)
                                .frame(width: columnWidth, height: 1.5)
                                .offset(x: CGFloat(dayIdx) * columnWidth + 2)
                        }
                        .offset(y: CGFloat(y) - 3)
                    }
                    .frame(height: totalHeight)
                    .allowsHitTesting(false)
                }
            }
        }
    }

    // MARK: Helpers

    private func eventsFor(day: Date) -> [EventInstance] {
        instances.filter { cal.isDate($0.start, inSameDayAs: day) }
            .sorted { $0.start < $1.start }
    }

    private func categoryFor(_ inst: EventInstance) -> PlannerCategory? {
        guard let cid = inst.categoryID else { return nil }
        return categories.first(where: { $0.id == cid })
    }

    private func blockFrame(for inst: EventInstance,
                            day: Date,
                            columnWidth: CGFloat) -> (width: CGFloat, height: CGFloat, y: CGFloat) {
        let dayStart = cal.startOfDay(for: day)
        let startHour = inst.start.timeIntervalSince(dayStart) / 3600.0
        let endHour = inst.end.timeIntervalSince(dayStart) / 3600.0
        let visibleStart = max(startHour, Double(hourStart))
        let visibleEnd = min(endHour, Double(hourEnd) + 1)
        let y = (visibleStart - Double(hourStart)) * Double(hourHeight)
        let h = max(18, (visibleEnd - visibleStart) * Double(hourHeight) - 2)
        return (max(8, columnWidth - 2), CGFloat(h), CGFloat(y))
    }

    private func weekdayShort(_ d: Int) -> String {
        ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"][d]
    }

    private func dayNumber(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f.string(from: d)
    }

    private func formatHour(_ h: Int) -> String {
        // 0 → "12am", 13 → "1pm"
        let suffix = h < 12 ? "am" : "pm"
        let display = h == 0 ? 12 : (h <= 12 ? h : h - 12)
        return "\(display)\(suffix)"
    }
}
