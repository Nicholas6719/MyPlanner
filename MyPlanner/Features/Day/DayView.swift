//
//  DayView.swift
//  MyPlanner
//
//  Single-day version of the week grid: bigger event cards, plus a strip
//  at the top showing tasks due that day.
//

import SwiftUI
import SwiftData
import Combine

struct DayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var events: [Event]
    @Query private var tasks: [TaskItem]
    @Query private var categories: [PlannerCategory]

    @AppStorage(AppSettingsKeys.hourRangeStart) private var hourStart: Int = AppSettingsDefaults.hourRangeStart
    @AppStorage(AppSettingsKeys.hourRangeEnd) private var hourEnd: Int = AppSettingsDefaults.hourRangeEnd

    @State private var day: Date = Calendar.current.startOfDay(for: Date())
    @State private var now: Date = Date()
    @State private var editingEvent: Event?
    @State private var newEventDraft: Event?
    @State private var editingTask: TaskItem?

    private let nowTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private let cal = Calendar.current
    private let hourHeight: CGFloat = 54

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                tasksDueStrip
                Divider().background(Theme.borderSoft)
                hourStack
            }
        }
        .background(Theme.bg)
        .onReceive(nowTimer) { _ in now = Date() }
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dx) > abs(dy) * 1.5 else { return }
                    if dx < -50 { goToDay(offset: 1) }
                    else if dx > 50 { goToDay(offset: -1) }
                }
        )
        .sheet(item: $editingEvent) { e in EventEditorView(event: e, isNew: false) }
        .sheet(item: $newEventDraft) { e in EventEditorView(event: e, isNew: true) }
        .sheet(item: $editingTask)  { t in TaskEditorView(task: t, isNew: false) }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Button { goToDay(offset: -1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Theme.surface2))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(weekdayLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.inkDim)
                Text(dateLabel)
                    .font(.system(size: 18, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.ink)
                    .headingKerning()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button { goToDay(offset: 1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Theme.surface2))
            }
            .buttonStyle(.plain)

            Button {
                day = cal.startOfDay(for: Date())
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

    private var weekdayLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f.string(from: day).uppercased()
    }

    private var dateLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: day)
    }

    // MARK: - Tasks-due-today strip

    private var tasksDueStrip: some View {
        let due = tasks.filter {
            !$0.completed && ($0.dueDate.map { cal.isDate($0, inSameDayAs: day) } ?? false)
        }
        return Group {
            if due.isEmpty {
                Text("No tasks due this day")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Spacing.outer)
                    .padding(.vertical, 10)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(due) { task in
                            compactTaskCard(task)
                                .onTapGesture { editingTask = task }
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.outer)
                    .padding(.vertical, 10)
                }
            }
        }
    }

    private func compactTaskCard(_ task: TaskItem) -> some View {
        let cat = categories.first(where: { $0.id == task.categoryID })
        return HStack(spacing: 8) {
            if let cat {
                Circle().fill(Color(hex: cat.colorHex)).frame(width: 8, height: 8)
            }
            Text(task.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface2))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
    }

    // MARK: - Hour stack (single-column)

    private var hourStack: some View {
        let dayEnd = cal.date(byAdding: .day, value: 1, to: day) ?? day
        let instances = Recurrence_.instances(of: events, from: day, to: dayEnd)
            .sorted(by: { $0.start < $1.start })
        let visibleHours = max(1, hourEnd - hourStart + 1)
        let totalHeight = CGFloat(visibleHours) * hourHeight

        return ZStack(alignment: .topLeading) {
            // Hour rows
            VStack(spacing: 0) {
                ForEach(hourStart...hourEnd, id: \.self) { h in
                    HStack(alignment: .top, spacing: 0) {
                        Text(formatHour(h))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(Theme.inkDim)
                            .frame(width: 56, alignment: .trailing)
                            .padding(.trailing, 8)
                            .padding(.top, 2)
                        Rectangle()
                            .fill(Theme.borderSoft)
                            .frame(height: 1)
                            .padding(.top, 8)
                    }
                    .frame(height: hourHeight, alignment: .top)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        var comps = cal.dateComponents([.year, .month, .day], from: day)
                        comps.hour = h
                        comps.minute = 0
                        if let date = cal.date(from: comps) {
                            newEventDraft = Event(title: "",
                                                  startDate: date,
                                                  endDate: date.addingTimeInterval(3600))
                        }
                    }
                }
            }
            // Event blocks
            ForEach(instances) { inst in
                let frame = blockFrame(inst: inst, totalHeight: totalHeight)
                EventBlock(instance: inst,
                           category: categories.first(where: { $0.id == inst.categoryID }),
                           compact: false)
                    .frame(height: frame.height)
                    .padding(.leading, 64)
                    .padding(.trailing, 12)
                    .offset(y: frame.y)
                    .onTapGesture {
                        if let e = events.first(where: { $0.id == inst.eventID }) {
                            editingEvent = e
                        }
                    }
            }
            // Now line
            if cal.isDateInToday(day) {
                let nowComps = cal.dateComponents([.hour, .minute], from: now)
                let hourFloat = Double(nowComps.hour ?? 0) + Double(nowComps.minute ?? 0) / 60
                if hourFloat >= Double(hourStart) && hourFloat <= Double(hourEnd) {
                    let y = (hourFloat - Double(hourStart)) * Double(hourHeight)
                    HStack(spacing: 0) {
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 7, height: 7)
                            .padding(.leading, 60)
                        Rectangle()
                            .fill(Theme.accent)
                            .frame(height: 1.5)
                    }
                    .offset(y: CGFloat(y) - 3)
                    .allowsHitTesting(false)
                }
            }
        }
        .frame(height: totalHeight, alignment: .top)
    }

    private func blockFrame(inst: EventInstance, totalHeight: CGFloat) -> (height: CGFloat, y: CGFloat) {
        let dayStart = cal.startOfDay(for: day)
        let startHour = inst.start.timeIntervalSince(dayStart) / 3600.0
        let endHour = inst.end.timeIntervalSince(dayStart) / 3600.0
        let visibleStart = max(startHour, Double(hourStart))
        let visibleEnd = min(endHour, Double(hourEnd) + 1)
        let y = (visibleStart - Double(hourStart)) * Double(hourHeight)
        let h = max(28, (visibleEnd - visibleStart) * Double(hourHeight) - 4)
        return (CGFloat(h), CGFloat(y))
    }

    private func goToDay(offset: Int) {
        if let d = cal.date(byAdding: .day, value: offset, to: day) {
            day = d
        }
    }

    private func formatHour(_ h: Int) -> String {
        let suffix = h < 12 ? "am" : "pm"
        let display = h == 0 ? 12 : (h <= 12 ? h : h - 12)
        return "\(display)\(suffix)"
    }
}

