//
//  ComposerBar.swift
//  MyPlanner
//
//  The bottom-of-screen text input where the user types things like
//  "Working Monday 7am to 3:30pm". Shows a live ParsePreview as the user
//  types, commits on Enter or send tap.
//

import SwiftUI
import SwiftData

struct ComposerBar: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var categories: [PlannerCategory]

    @State private var text: String = ""
    @State private var typeOverride: PreviewKind?
    @State private var parsed: ParsedInput?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            if !text.isEmpty, let parsed {
                ParsePreview(parsed: parsed,
                             categories: categories,
                             typeOverride: $typeOverride)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            inputRow
        }
        .padding(.horizontal, Theme.Spacing.outer)
        .padding(.bottom, Theme.Spacing.tight)
        .background(
            // Pull a subtle gradient over the system blur so the composer
            // visually separates from the content behind it.
            LinearGradient(
                colors: [Color.clear, Theme.bg.opacity(0.95)],
                startPoint: .top,
                endPoint: .bottom)
                .allowsHitTesting(false)
        )
        .onChange(of: text) { _, new in
            recomputePreview(new)
        }
        .animation(.easeOut(duration: 0.18), value: text.isEmpty)
    }

    private var inputRow: some View {
        HStack(spacing: 10) {
            HStack {
                TextField("Try \"Working Monday 7am to 3:30pm\" or \"Math homework due Friday\"",
                          text: $text)
                    .focused($focused)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.ink)
                    .submitLabel(.send)
                    .onSubmit { commit() }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Theme.surface2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(focused ? Theme.accent : Theme.border, lineWidth: 1)
            )
            .shadow(color: focused ? Theme.accentGlow : .clear,
                    radius: focused ? 6 : 0)

            Button(action: commit) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(text.isEmpty ? Theme.inkDim : Color.black)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(text.isEmpty ? Theme.surface3 : Theme.accent)
                    )
            }
            .buttonStyle(.plain)
            .disabled(text.isEmpty)
        }
    }

    // MARK: - Logic

    private func recomputePreview(_ new: String) {
        let trimmed = new.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { parsed = nil; return }
        let parserCats = categories.map { ParserCategory(id: $0.id, name: $0.name) }
        parsed = NLParser.parse(trimmed, categories: parserCats)
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let parserCats = categories.map { ParserCategory(id: $0.id, name: $0.name) }
        let result = NLParser.parse(trimmed, categories: parserCats)

        // Apply the user's type-override if they flipped Event/Task in the
        // preview.
        let finalKind: PreviewKind = {
            if let o = typeOverride { return o }
            switch result {
            case .event: return .event
            case .task:  return .task
            case .error: return .task
            }
        }()

        switch (finalKind, result) {
        case (.event, .event(let title, let s, let e, let recurrence, let cat)):
            insertEvent(title: title, start: s, end: e, recurrence: recurrence, category: cat)
        case (.event, .task(let title, let due, let cat)):
            // User overrode Task → Event. Use due as start, +1h as end.
            let s = due ?? Date()
            insertEvent(title: title, start: s, end: s.addingTimeInterval(3600),
                        recurrence: nil, category: cat)
        case (.task, .task(let title, let due, let cat)):
            insertTask(title: title, due: due, category: cat)
        case (.task, .event(let title, let s, _, _, let cat)):
            // User overrode Event → Task. Use start as due.
            insertTask(title: title, due: s, category: cat)
        default:
            break
        }

        // Re-schedule notifications now that we've added something.
        Task { await rescheduleNotifications() }

        // Reset.
        text = ""
        typeOverride = nil
        parsed = nil
    }

    private func insertEvent(title: String,
                             start: Date,
                             end: Date,
                             recurrence: Recurrence?,
                             category: UUID?) {
        let event = Event(title: title,
                          startDate: start,
                          endDate: end,
                          categoryID: category,
                          recurrenceEnabled: recurrence != nil,
                          recurrenceByDay: recurrence?.byDay ?? [],
                          sourceText: text)
        modelContext.insert(event)
        try? modelContext.save()
    }

    private func insertTask(title: String,
                            due: Date?,
                            category: UUID?) {
        let task = TaskItem(title: title,
                            dueDate: due,
                            categoryID: category,
                            sourceText: text)
        modelContext.insert(task)
        try? modelContext.save()
    }

    private func rescheduleNotifications() async {
        let events = (try? modelContext.fetch(FetchDescriptor<Event>())) ?? []
        let tasks = (try? modelContext.fetch(FetchDescriptor<TaskItem>())) ?? []
        await NotificationScheduler.reschedule(events: events, tasks: tasks)
    }
}
