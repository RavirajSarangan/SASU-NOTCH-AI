@preconcurrency import EventKit
import Foundation
import NovaKit

/// Calendar and Reminders on this Mac (EventKit). Access is asked for only
/// the first time you use it; events never leave the Mac. EventKit calls run
/// on their own queue (they can be slow), never on the main thread.
final class CalendarService: @unchecked Sendable {
    private let store = EKEventStore()
    private let queue = DispatchQueue(label: "nova.calendar")

    var eventsAllowed: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }
    var remindersAllowed: Bool { EKEventStore.authorizationStatus(for: .reminder) == .fullAccess }
    var eventsDenied: Bool { [.denied, .restricted].contains(EKEventStore.authorizationStatus(for: .event)) }
    var remindersDenied: Bool { [.denied, .restricted].contains(EKEventStore.authorizationStatus(for: .reminder)) }

    /// Asks once. (The async API is used, not a completion closure, so the
    /// answer can't land on the wrong thread.)
    func requestEvents() async -> Bool {
        if eventsAllowed { return true }
        guard !eventsDenied else { return false }
        return (try? await store.requestFullAccessToEvents()) ?? false
    }

    func requestReminders() async -> Bool {
        if remindersAllowed { return true }
        guard !remindersDenied else { return false }
        return (try? await store.requestFullAccessToReminders()) ?? false
    }

    /// Events between two dates, with any meeting link found.
    func events(from start: Date, to end: Date) async -> [AgendaItem] {
        guard eventsAllowed else { return [] }
        return await withCheckedContinuation { continuation in
            queue.async { [self] in
                let store = self.store
                let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
                let items = store.events(matching: predicate)
                    .filter { $0.status != .canceled }
                    .map { event in
                        AgendaItem(title: event.title?.isEmpty == false ? event.title! : "Untitled event",
                                   start: event.startDate, end: event.endDate, allDay: event.isAllDay,
                                   joinURL: Agenda.joinURL(in: [event.url?.absoluteString, event.location, event.notes]))
                    }
                continuation.resume(returning: items.sorted { $0.start < $1.start })
            }
        }
    }

    /// Adds a reminder (with an alert at `date`) to your default list.
    func addReminder(_ title: String, at date: Date?) async -> Bool {
        guard remindersAllowed else { return false }
        return await withCheckedContinuation { continuation in
            queue.async { [self] in
                let store = self.store
                guard let list = store.defaultCalendarForNewReminders() else { continuation.resume(returning: false); return }
                let reminder = EKReminder(eventStore: store)
                reminder.title = title
                reminder.calendar = list
                if let date {
                    reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                    reminder.addAlarm(EKAlarm(absoluteDate: date))
                }
                continuation.resume(returning: (try? store.save(reminder, commit: true)) != nil)
            }
        }
    }
}
