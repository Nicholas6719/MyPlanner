//
//  Event.swift
//  MyPlanner
//
//  SwiftData model for a calendar event. Designed to be CloudKit-friendly:
//  every property has a default value or is optional, no relationships,
//  no enums stored directly. Categories are referenced by UUID instead of
//  via a SwiftData relationship so the schema can be turned on with CloudKit
//  later without restructuring.
//

import Foundation
import SwiftData

@Model
final class Event {
    var id: UUID = UUID()
    var title: String = ""
    var startDate: Date = Date()
    var endDate: Date = Date().addingTimeInterval(3600)

    /// Soft reference to a Category — not a SwiftData relationship.
    var categoryID: UUID?

    var notes: String = ""

    // MARK: Recurrence (weekly only for v1)
    var recurrenceEnabled: Bool = false
    /// 0=Sunday, 6=Saturday.
    var recurrenceByDay: [Int] = []
    var recurrenceUntil: Date?

    /// Reminders are stored as minute offsets BEFORE the start time.
    /// e.g. [15, 60] = "remind me 15 minutes before, and 1 hour before".
    var reminderOffsetsMin: [Int] = []

    /// Original natural-language text the user typed, for debugging.
    var sourceText: String = ""
    var createdAt: Date = Date()

    init(id: UUID = UUID(),
         title: String = "",
         startDate: Date = Date(),
         endDate: Date = Date().addingTimeInterval(3600),
         categoryID: UUID? = nil,
         notes: String = "",
         recurrenceEnabled: Bool = false,
         recurrenceByDay: [Int] = [],
         recurrenceUntil: Date? = nil,
         reminderOffsetsMin: [Int] = [],
         sourceText: String = "",
         createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.categoryID = categoryID
        self.notes = notes
        self.recurrenceEnabled = recurrenceEnabled
        self.recurrenceByDay = recurrenceByDay
        self.recurrenceUntil = recurrenceUntil
        self.reminderOffsetsMin = reminderOffsetsMin
        self.sourceText = sourceText
        self.createdAt = createdAt
    }
}

// MARK: - EventInstance
//
// A lightweight value type representing a single occurrence of an event in
// time. Recurring events expand into many instances; non-recurring events
// produce one. We never store these — we compute them on demand for
// rendering Week/Day views and for scheduling notifications.

struct EventInstance: Identifiable, Hashable {
    /// Unique per (eventID, startDate) so SwiftUI can identify them in lists.
    var id: String { "\(eventID.uuidString)-\(start.timeIntervalSince1970)" }
    let eventID: UUID
    let title: String
    let categoryID: UUID?
    let isRecurring: Bool
    let start: Date
    let end: Date
}
