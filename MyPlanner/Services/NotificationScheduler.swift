//
//  NotificationScheduler.swift
//  MyPlanner
//
//  Wraps UNUserNotificationCenter for scheduling local reminders.
//
//  Strategy on every save (or app foreground):
//   1. Cancel ALL notifications we previously scheduled (we tag every
//      identifier with a known prefix so we don't clobber other apps' or
//      OS-level notifications).
//   2. Re-schedule from the current state of the database.
//
//  We deliberately re-schedule from scratch rather than tracking deltas;
//  the user has at most a few hundred reminders, so this is fast and
//  trivially correct.
//

import Foundation
import UserNotifications

enum NotificationScheduler {

    /// Identifier prefix so we can cancel only the notifications we own.
    static let prefix = "myplanner."

    // MARK: - Authorization

    /// Returns the current authorization status without prompting.
    static func currentStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }

    /// Request permission. Idempotent — safe to call repeatedly. Returns
    /// the granted status.
    @discardableResult
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    // MARK: - Scheduling

    /// Cancel every notification owned by this app and then re-schedule
    /// from the current event/task state.
    static func reschedule(events: [Event],
                           tasks: [TaskItem]) async {
        let status = await currentStatus()
        guard status == .authorized || status == .provisional else {
            // No permission yet — nothing to do. We won't pester the user
            // about this; the app prompts for permission at the right time.
            return
        }

        let center = UNUserNotificationCenter.current()

        // 1. Remove our existing requests.
        let pending = await center.pendingNotificationRequests()
        let toCancel = pending
            .filter { $0.identifier.hasPrefix(prefix) }
            .map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: toCancel)

        let now = Date()

        // 2. Schedule task reminders.
        for task in tasks where !task.completed {
            guard let due = task.dueDate else { continue }
            for offsetMin in task.reminderOffsetsMin {
                let fire = due.addingTimeInterval(-Double(offsetMin) * 60)
                guard fire > now else { continue }
                let id = "\(prefix)task-\(task.id.uuidString)-\(offsetMin)"
                let content = makeContent(title: task.title,
                                          fireDate: fire,
                                          referenceDate: due,
                                          isEvent: false)
                schedule(id: id, content: content, fire: fire)
            }
        }

        // 3. Schedule event-instance reminders for the next 30 days.
        let horizon = now.addingTimeInterval(30 * 24 * 3600)
        let instances = Recurrence_.instances(of: events, from: now, to: horizon)
        for inst in instances {
            // Find the event's reminder offsets (we passed in `events`).
            guard let event = events.first(where: { $0.id == inst.eventID }) else { continue }
            let isoStr = ISO8601DateFormatter().string(from: inst.start)
            for offsetMin in event.reminderOffsetsMin {
                let fire = inst.start.addingTimeInterval(-Double(offsetMin) * 60)
                guard fire > now else { continue }
                let id = "\(prefix)event-\(event.id.uuidString)-\(isoStr)-\(offsetMin)"
                let content = makeContent(title: inst.title,
                                          fireDate: fire,
                                          referenceDate: inst.start,
                                          isEvent: true)
                schedule(id: id, content: content, fire: fire)
            }
        }
    }

    // MARK: - Internal helpers

    private static func schedule(id: String,
                                 content: UNNotificationContent,
                                 fire: Date) {
        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: fire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: id,
                                            content: content,
                                            trigger: trigger)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    private static func makeContent(title: String,
                                    fireDate: Date,
                                    referenceDate: Date,
                                    isEvent: Bool) -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title.isEmpty ? "Reminder" : title

        // Build a body like "Starts in 15 min · 11:00am" or "Due in 1 hour".
        let interval = referenceDate.timeIntervalSince(fireDate)   // seconds until ref
        let leading = isEvent ? "Starts" : "Due"
        let humanOffset = humanizeOffset(seconds: interval)
        let timeStr = formatTime(referenceDate)
        if isEvent {
            content.body = "\(leading) in \(humanOffset) · \(timeStr)"
        } else {
            content.body = "\(leading) in \(humanOffset)"
        }
        content.sound = .default
        return content
    }

    private static func humanizeOffset(seconds: TimeInterval) -> String {
        let m = max(0, Int(round(seconds / 60)))
        if m < 60 { return "\(m) min" }
        let h = m / 60
        let rem = m % 60
        if rem == 0 { return h == 1 ? "1 hour" : "\(h) hours" }
        return "\(h)h \(rem)m"
    }

    private static func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mma"
        f.amSymbol = "am"
        f.pmSymbol = "pm"
        return f.string(from: date)
    }
}
