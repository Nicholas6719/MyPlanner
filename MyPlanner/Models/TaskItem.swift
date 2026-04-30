//
//  TaskItem.swift
//  MyPlanner
//
//  We use the name `TaskItem` instead of `Task` because Swift Concurrency
//  already owns `Task`. The same CloudKit-friendly rules apply: every
//  property has a default, priority is stored as a string, no relationships.
//

import Foundation
import SwiftData

@Model
final class TaskItem {
    var id: UUID = UUID()
    var title: String = ""
    /// Optional — tasks without a due date are valid (filter "No date").
    var dueDate: Date?
    var categoryID: UUID?
    /// "low" | "med" | "high". Stored as a string so CloudKit doesn't trip
    /// on enum schema changes.
    var priority: String = "med"
    var notes: String = ""
    var completed: Bool = false
    var completedAt: Date?
    /// Minutes before `dueDate` to fire a reminder.
    var reminderOffsetsMin: [Int] = []
    var sourceText: String = ""
    var createdAt: Date = Date()

    init(id: UUID = UUID(),
         title: String = "",
         dueDate: Date? = nil,
         categoryID: UUID? = nil,
         priority: String = "med",
         notes: String = "",
         completed: Bool = false,
         completedAt: Date? = nil,
         reminderOffsetsMin: [Int] = [],
         sourceText: String = "",
         createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
        self.categoryID = categoryID
        self.priority = priority
        self.notes = notes
        self.completed = completed
        self.completedAt = completedAt
        self.reminderOffsetsMin = reminderOffsetsMin
        self.sourceText = sourceText
        self.createdAt = createdAt
    }
}

// MARK: - Priority Helpers

enum TaskPriority: String, CaseIterable {
    case low, med, high
    var label: String {
        switch self {
        case .low:  return "Low"
        case .med:  return "Med"
        case .high: return "High"
        }
    }
}
