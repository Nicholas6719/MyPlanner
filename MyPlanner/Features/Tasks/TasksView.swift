//
//  TasksView.swift
//  MyPlanner
//
//  The Tasks tab. Filter chip row, list of tasks, empty states, and
//  inline task editing via sheet.
//

import SwiftUI
import SwiftData
import Combine

struct TasksView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var tasks: [TaskItem]
    @Query private var categories: [PlannerCategory]

    @State private var filter: TaskFilter = .all
    @State private var now: Date = Date()
    @State private var editingTask: TaskItem?

    private let nowTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            filtersRow
            content
        }
        .background(Theme.bg)
        .onReceive(nowTimer) { _ in now = Date() }
        .sheet(item: $editingTask) { t in
            TaskEditorView(task: t, isNew: false)
        }
    }

    // MARK: - Chips row

    private var filtersRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TaskFilter.allCases) { f in
                    Chip(title: f.title,
                         count: count(for: f),
                         isSelected: filter == f) {
                        filter = f
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.outer)
            .padding(.vertical, 10)
        }
    }

    private func count(for f: TaskFilter) -> Int? {
        let matched = f.apply(to: tasks, now: now).count
        return matched
    }

    // MARK: - Body content

    @ViewBuilder
    private var content: some View {
        let filtered = filter.apply(to: tasks, now: now)
        if filtered.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(filtered) { task in
                        TaskCard(task: task,
                                 category: categories.first(where: { $0.id == task.categoryID }),
                                 now: now,
                                 onToggle: { toggleComplete(task) },
                                 onTapBody: { editingTask = task })
                    }
                }
                .padding(.horizontal, Theme.Spacing.outer)
                .padding(.bottom, 8)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 60, weight: .light))
                .foregroundStyle(Theme.inkFaint)
            Text(filter.emptyHeading())
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
            Text("Use the bar below to add a task.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkDim)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func toggleComplete(_ task: TaskItem) {
        task.completed.toggle()
        task.completedAt = task.completed ? Date() : nil
        try? modelContext.save()
        Task { await rescheduleNotifications() }
    }

    private func rescheduleNotifications() async {
        let events = (try? modelContext.fetch(FetchDescriptor<Event>())) ?? []
        let allTasks = (try? modelContext.fetch(FetchDescriptor<TaskItem>())) ?? []
        await NotificationScheduler.reschedule(events: events, tasks: allTasks)
    }
}
