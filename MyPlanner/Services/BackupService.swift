//
//  BackupService.swift
//  MyPlanner
//
//  Encodes the entire database to JSON for export, and decodes a JSON
//  backup back into SwiftData. This is our manual sync mechanism while
//  CloudKit is disabled (free Apple Developer account constraint).
//
//  The schema is kept stable and explicit (Codable structs that mirror
//  the @Model classes) so backups remain readable even if we change
//  internal model details.
//

import Foundation
import SwiftData

// MARK: - Codable mirrors of the SwiftData models

private struct EventBackup: Codable {
    let id: UUID
    let title: String
    let startDate: Date
    let endDate: Date
    let categoryID: UUID?
    let notes: String
    let recurrenceEnabled: Bool
    let recurrenceByDay: [Int]
    let recurrenceUntil: Date?
    let reminderOffsetsMin: [Int]
    let sourceText: String
    let createdAt: Date
}

private struct TaskBackup: Codable {
    let id: UUID
    let title: String
    let dueDate: Date?
    let categoryID: UUID?
    let priority: String
    let notes: String
    let completed: Bool
    let completedAt: Date?
    let reminderOffsetsMin: [Int]
    let sourceText: String
    let createdAt: Date
}

private struct CategoryBackup: Codable {
    let id: UUID
    let name: String
    let colorHex: String
    let createdAt: Date
}

private struct PlannerBackup: Codable {
    let version: Int
    let exportedAt: Date
    let events: [EventBackup]
    let tasks: [TaskBackup]
    let categories: [CategoryBackup]
}

// MARK: - Service

enum BackupService {
    static let currentVersion = 1

    /// Serialize the entire database to pretty-printed JSON Data.
    static func export(events: [Event],
                       tasks: [TaskItem],
                       categories: [PlannerCategory]) throws -> Data {
        let payload = PlannerBackup(
            version: currentVersion,
            exportedAt: Date(),
            events: events.map {
                EventBackup(id: $0.id,
                            title: $0.title,
                            startDate: $0.startDate,
                            endDate: $0.endDate,
                            categoryID: $0.categoryID,
                            notes: $0.notes,
                            recurrenceEnabled: $0.recurrenceEnabled,
                            recurrenceByDay: $0.recurrenceByDay,
                            recurrenceUntil: $0.recurrenceUntil,
                            reminderOffsetsMin: $0.reminderOffsetsMin,
                            sourceText: $0.sourceText,
                            createdAt: $0.createdAt)
            },
            tasks: tasks.map {
                TaskBackup(id: $0.id,
                           title: $0.title,
                           dueDate: $0.dueDate,
                           categoryID: $0.categoryID,
                           priority: $0.priority,
                           notes: $0.notes,
                           completed: $0.completed,
                           completedAt: $0.completedAt,
                           reminderOffsetsMin: $0.reminderOffsetsMin,
                           sourceText: $0.sourceText,
                           createdAt: $0.createdAt)
            },
            categories: categories.map {
                CategoryBackup(id: $0.id,
                               name: $0.name,
                               colorHex: $0.colorHex,
                               createdAt: $0.createdAt)
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    /// Replace all data in the given context with the contents of `data`.
    /// On any error, throws — the caller should wrap this in a confirmation
    /// alert so accidental imports can't silently destroy data.
    static func importReplacing(_ data: Data, into context: ModelContext) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(PlannerBackup.self, from: data)

        // Wipe existing data
        try context.delete(model: Event.self)
        try context.delete(model: TaskItem.self)
        try context.delete(model: PlannerCategory.self)

        // Insert categories first so categoryID references match.
        for c in payload.categories {
            context.insert(PlannerCategory(id: c.id,
                                           name: c.name,
                                           colorHex: c.colorHex,
                                           createdAt: c.createdAt))
        }
        for e in payload.events {
            context.insert(Event(id: e.id,
                                 title: e.title,
                                 startDate: e.startDate,
                                 endDate: e.endDate,
                                 categoryID: e.categoryID,
                                 notes: e.notes,
                                 recurrenceEnabled: e.recurrenceEnabled,
                                 recurrenceByDay: e.recurrenceByDay,
                                 recurrenceUntil: e.recurrenceUntil,
                                 reminderOffsetsMin: e.reminderOffsetsMin,
                                 sourceText: e.sourceText,
                                 createdAt: e.createdAt))
        }
        for t in payload.tasks {
            context.insert(TaskItem(id: t.id,
                                    title: t.title,
                                    dueDate: t.dueDate,
                                    categoryID: t.categoryID,
                                    priority: t.priority,
                                    notes: t.notes,
                                    completed: t.completed,
                                    completedAt: t.completedAt,
                                    reminderOffsetsMin: t.reminderOffsetsMin,
                                    sourceText: t.sourceText,
                                    createdAt: t.createdAt))
        }
        try context.save()
    }

    /// Write the export data to a temp file and return the URL — used by
    /// the Share Sheet so the user can AirDrop / save / mail the file.
    static func writeExportToTempFile(_ data: Data) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        let name = "MyPlanner-Backup-\(formatter.string(from: Date())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }
}
