//
//  WeekView.swift
//  MyPlanner
//
//  The Week tab. Shows the 7-day grid with events. Owns the visible week
//  state and renders header controls (prev / next / today / range label).
//

import SwiftUI
import SwiftData
import Combine

struct WeekView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var events: [Event]
    @Query private var categories: [PlannerCategory]

    @AppStorage(AppSettingsKeys.hourRangeStart) private var hourStart: Int = AppSettingsDefaults.hourRangeStart
    @AppStorage(AppSettingsKeys.hourRangeEnd) private var hourEnd: Int = AppSettingsDefaults.hourRangeEnd

    @State private var weekStart: Date = WeekView.startOfThisWeek()
    @State private var now: Date = Date()
    @State private var editingEvent: Event?
    @State private var newEventDraft: Event?
    @State private var pendingDelete: Event?

    // 60-second tick for the "now" line
    private let nowTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private let cal = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            header
            grid
        }
        .background(Theme.bg)
        .onReceive(nowTimer) { _ in now = Date() }
        // simultaneousGesture so we don't steal vertical scrolls from the
        // hour grid; we only act on swipes that are clearly horizontal.
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dx) > abs(dy) * 1.5 else { return }
                    if dx < -50 { goToWeek(offset: 1) }
                    else if dx > 50 { goToWeek(offset: -1) }
                }
        )
        .sheet(item: $editingEvent) { event in
            EventEditorView(event: event, isNew: false)
        }
        .sheet(item: $newEventDraft) { draft in
            EventEditorView(event: draft, isNew: true)
        }
        .alert("Delete this event?",
               isPresented: Binding(get: { pendingDelete != nil },
                                    set: { if !$0 { pendingDelete = nil } })) {
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button(pendingDelete?.recurrenceEnabled == true
                   ? "Delete All" : "Delete",
                   role: .destructive) {
                if let e = pendingDelete { delete(e) }
                pendingDelete = nil
            }
        } message: {
            Text(pendingDelete?.recurrenceEnabled == true
                 ? "Delete this event and all repeats?"
                 : "This cannot be undone.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                goToWeek(offset: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Theme.surface2))
            }
            .buttonStyle(.plain)

            Text(weekRangeLabel)
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.ink)
                .headingKerning()
                .frame(maxWidth: .infinity)

            Button {
                goToWeek(offset: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Theme.surface2))
            }
            .buttonStyle(.plain)

            Button {
                weekStart = WeekView.startOfThisWeek()
            } label: {
                Text("TODAY")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Theme.accentSoft))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Spacing.outer)
        .padding(.vertical, 10)
        .background(Theme.surface.opacity(0.4))
    }

    // MARK: - Grid

    private var grid: some View {
        let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        let instances = Recurrence_.instances(of: events, from: weekStart, to: weekEnd)
        return WeekGrid(weekStart: weekStart,
                        hourStart: hourStart,
                        hourEnd: hourEnd,
                        instances: instances,
                        categories: categories,
                        now: now,
                        onTapHour: handleTapHour,
                        onTapEvent: handleTapEvent,
                        onDeleteEvent: handleDeleteEvent)
    }

    // MARK: - Actions

    private func goToWeek(offset: Int) {
        if let d = cal.date(byAdding: .day, value: 7 * offset, to: weekStart) {
            weekStart = d
        }
    }

    private func handleTapHour(_ hourDate: Date) {
        let draft = Event(title: "",
                          startDate: hourDate,
                          endDate: hourDate.addingTimeInterval(3600))
        newEventDraft = draft
    }

    private func handleTapEvent(_ inst: EventInstance) {
        if let event = events.first(where: { $0.id == inst.eventID }) {
            editingEvent = event
        }
    }

    private func handleDeleteEvent(_ inst: EventInstance) {
        if let event = events.first(where: { $0.id == inst.eventID }) {
            pendingDelete = event
        }
    }

    private func delete(_ event: Event) {
        modelContext.delete(event)
        try? modelContext.save()
        Task {
            let events = (try? modelContext.fetch(FetchDescriptor<Event>())) ?? []
            let tasks = (try? modelContext.fetch(FetchDescriptor<TaskItem>())) ?? []
            await NotificationScheduler.reschedule(events: events, tasks: tasks)
        }
    }

    // MARK: - Helpers

    private var weekRangeLabel: String {
        let weekEnd = cal.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let f = DateFormatter()
        if cal.component(.month, from: weekStart) == cal.component(.month, from: weekEnd) {
            f.dateFormat = "MMM d"
            let s = f.string(from: weekStart)
            f.dateFormat = "d, yyyy"
            let e = f.string(from: weekEnd)
            return "\(s) – \(e)"
        } else {
            f.dateFormat = "MMM d"
            let s = f.string(from: weekStart)
            f.dateFormat = "MMM d, yyyy"
            let e = f.string(from: weekEnd)
            return "\(s) – \(e)"
        }
    }

    /// First instant of the current Sunday (start of week per spec).
    private static func startOfThisWeek() -> Date {
        var cal = Calendar.current
        cal.firstWeekday = 1   // 1 = Sunday
        let now = Date()
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        return cal.date(from: comps) ?? cal.startOfDay(for: now)
    }
}

