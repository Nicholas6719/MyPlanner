//
//  TasksView.swift
//  MyPlanner
//
//  The Tasks tab. Filter chip row, search field, list of tasks with
//  swipe actions, and inline editing via sheet.
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
    @State private var query: String = ""
    @State private var pendingDelete: TaskItem?

    private let nowTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            searchField
            filtersRow
            content
        }
        .background(Theme.bg)
        .onReceive(nowTimer) { _ in now = Date() }
        .sheet(item: $editingTask) { t in
            TaskEditorView(task: t, isNew: false)
        }
        .alert("Delete this task?",
               isPresented: Binding(get: { pendingDelete != nil },
                                    set: { if !$0 { pendingDelete = nil } })) {
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Delete", role: .destructive) {
                if let t = pendingDelete { delete(t) }
                pendingDelete = nil
            }
        } message: {
            Text("This cannot be undone.")
        }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.inkDim)
            TextField("Search tasks", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.inkDim)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(Theme.surface2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1)
        )
        .padding(.horizontal, Theme.Spacing.outer)
        .padding(.top, 10)
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
        // Count is over the *filter*, not the search — the chip badges
        // describe the underlying buckets, independent of what the user
        // is searching for.
        f.apply(to: tasks, now: now).count
    }

    // MARK: - Body content

    @ViewBuilder
    private var content: some View {
        let filtered = applySearch(to: filter.apply(to: tasks, now: now))
        if filtered.isEmpty {
            emptyState
        } else {
            // Use a List so we get native swipeActions. Visual styling is
            // matched to the rest of the app via .listRowBackground and
            // hidden separators.
            List {
                ForEach(filtered) { task in
                    TaskCard(task: task,
                             category: categories.first(where: { $0.id == task.categoryID }),
                             now: now,
                             onToggle: { toggleComplete(task) },
                             onTapBody: { editingTask = task })
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4,
                                                  leading: Theme.Spacing.outer,
                                                  bottom: 4,
                                                  trailing: Theme.Spacing.outer))
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                pendingDelete = task
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                toggleComplete(task)
                            } label: {
                                Label(task.completed ? "Reopen" : "Complete",
                                      systemImage: task.completed
                                                   ? "arrow.uturn.left"
                                                   : "checkmark")
                            }
                            .tint(Theme.accent)
                        }
                        .contextMenu {
                            Button {
                                editingTask = task
                            } label: {
                                Label("Edit", systemImage: "square.and.pencil")
                            }
                            Button {
                                toggleComplete(task)
                            } label: {
                                Label(task.completed ? "Mark Incomplete" : "Mark Complete",
                                      systemImage: task.completed
                                                   ? "arrow.uturn.left"
                                                   : "checkmark.circle")
                            }
                            Divider()
                            Button(role: .destructive) {
                                pendingDelete = task
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
        }
    }

    private func applySearch(to tasks: [TaskItem]) -> [TaskItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return tasks }
        return tasks.filter {
            $0.title.localizedCaseInsensitiveContains(q)
            || $0.notes.localizedCaseInsensitiveContains(q)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: query.isEmpty ? "checkmark.circle" : "magnifyingglass")
                .font(.system(size: 60, weight: .light))
                .foregroundStyle(Theme.inkFaint)
            Text(query.isEmpty ? filter.emptyHeading() : "No matches for \"\(query)\"")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
            if query.isEmpty {
                Text("Use the bar below to add a task.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkDim)
            }
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

    private func delete(_ task: TaskItem) {
        modelContext.delete(task)
        try? modelContext.save()
        Task { await rescheduleNotifications() }
    }

    private func rescheduleNotifications() async {
        let events = (try? modelContext.fetch(FetchDescriptor<Event>())) ?? []
        let allTasks = (try? modelContext.fetch(FetchDescriptor<TaskItem>())) ?? []
        await NotificationScheduler.reschedule(events: events, tasks: allTasks)
    }
}
