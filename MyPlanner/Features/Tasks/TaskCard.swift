//
//  TaskCard.swift
//  MyPlanner
//
//  Single task row used in the Tasks list. Tapping anywhere except the
//  checkbox opens the editor; tapping the checkbox toggles completion
//  with a small scale animation.
//

import SwiftUI

struct TaskCard: View {
    let task: TaskItem
    let category: PlannerCategory?
    let now: Date
    let onToggle: () -> Void
    let onTapBody: () -> Void

    @State private var checkScale: CGFloat = 1.0

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Checkbox
            Button {
                withAnimation(.easeOut(duration: 0.14)) { checkScale = 1.15 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                    withAnimation(.easeOut(duration: 0.14)) { checkScale = 1.0 }
                }
                onToggle()
            } label: {
                ZStack {
                    Circle()
                        .stroke(task.completed ? Theme.accent : Theme.inkDim, lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                    if task.completed {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.accent)
                    }
                }
                .scaleEffect(checkScale)
            }
            .buttonStyle(.plain)

            // Body
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(task.completed ? Theme.inkDim : Theme.ink)
                    .strikethrough(task.completed, color: Theme.inkDim)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    urgencyBadge
                    if let category {
                        HStack(spacing: 4) {
                            Circle().fill(Color(hex: category.colorHex))
                                .frame(width: 6, height: 6)
                            Text(category.name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.inkSecondary)
                        }
                    }
                    if task.priority != "med" {
                        Image(systemName: priorityIcon)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(priorityColor)
                    }
                    if !task.reminderOffsetsMin.isEmpty {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.inkDim)
                    }
                    if !task.notes.isEmpty {
                        Image(systemName: "note.text")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.inkDim)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { onTapBody() }

            // Right-edge priority bar
            Rectangle()
                .fill(priorityColor)
                .frame(width: 4)
                .clipShape(RoundedRectangle(cornerRadius: 2))
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
        .opacity(task.completed ? 0.5 : 1.0)
        .animation(.easeOut(duration: 0.18), value: task.completed)
    }

    // MARK: - Urgency

    private var urgencyBadge: some View {
        let label = urgencyLabel
        return Text(label.text)
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
            .foregroundStyle(label.fg)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(label.bg))
    }

    private struct UrgencyLabel { let text: String; let fg: Color; let bg: Color }

    private var urgencyLabel: UrgencyLabel {
        guard let due = task.dueDate else {
            return UrgencyLabel(text: "No date", fg: Theme.inkDim, bg: Theme.surface3)
        }
        let cal = Calendar.current
        let dueDay = cal.startOfDay(for: due)
        let today = cal.startOfDay(for: now)
        let days = cal.dateComponents([.day], from: today, to: dueDay).day ?? 0
        if days < 0 {
            let abs = -days
            return UrgencyLabel(text: "\(abs)d overdue",
                                fg: Theme.overdue, bg: Theme.overdueSoft)
        }
        if days == 0 {
            return UrgencyLabel(text: "Today",
                                fg: Theme.today, bg: Theme.todaySoft)
        }
        if days <= 3 {
            return UrgencyLabel(text: "In \(days)d",
                                fg: Theme.soon, bg: Theme.soonSoft)
        }
        // Just show the date
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return UrgencyLabel(text: f.string(from: due),
                            fg: Theme.inkSecondary, bg: Theme.surface3)
    }

    // MARK: - Priority styling

    private var priorityColor: Color {
        switch task.priority {
        case "high": return Theme.priorityHigh
        case "low":  return Theme.priorityLow
        default:     return Theme.priorityMed
        }
    }

    private var priorityIcon: String {
        switch task.priority {
        case "high": return "flag.fill"
        case "low":  return "flag"
        default:     return "flag"
        }
    }
}
