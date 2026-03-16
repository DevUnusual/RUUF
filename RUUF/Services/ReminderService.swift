import Foundation
import UserNotifications

enum ReminderServiceError: LocalizedError {
    case authorizationDenied

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "Permissão de notificações negada. Ative nas configurações do iPhone."
        }
    }
}

final class ReminderService {
    private let notificationCenter = UNUserNotificationCenter.current()
    private let reminderPrefix = "br.ufpi.ruuf.reminder"

    func isReminderEnabled(for day: Weekday) async -> Bool {
        let requests = await pendingRequests()
        let identifier = reminderIdentifier(for: day)
        return requests.contains(where: { $0.identifier == identifier })
    }

    func scheduleReminder(for day: Weekday) async throws {
        let granted = try await requestAuthorizationIfNeeded()
        guard granted else {
            throw ReminderServiceError.authorizationDenied
        }

        let identifier = reminderIdentifier(for: day)
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = "Cardápio UFPI • \(day.title)"
        content.body = "Confira o cardápio do RU e planeje sua refeição."
        content.sound = .default

        var components = DateComponents()
        components.weekday = day.rawValue
        components.hour = 10
        components.minute = 30

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try await notificationCenter.add(request)
    }

    func cancelReminder(for day: Weekday) {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [reminderIdentifier(for: day)])
    }

    private func reminderIdentifier(for day: Weekday) -> String {
        "\(reminderPrefix).\(day.rawValue)"
    }

    private func requestAuthorizationIfNeeded() async throws -> Bool {
        let settings = await notificationCenter.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
        @unknown default:
            return false
        }
    }

    private func pendingRequests() async -> [UNNotificationRequest] {
        await withCheckedContinuation { continuation in
            notificationCenter.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests)
            }
        }
    }
}
