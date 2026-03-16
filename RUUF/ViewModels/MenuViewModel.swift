import Foundation
import Combine

@MainActor
final class MenuViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var menu: WeeklyMenu?
    @Published var campusLinks: [Campus: URL] = [:]
    @Published var displayMode: MenuDisplayMode = .porDia
    @Published var selectedDay: Weekday = .segunda
    @Published var remindersEnabled: [Weekday: Bool] = [:]

    private let scraper = UFPIWebsiteScraper()
    private let parser = PDFMenuParser()
    private let reminderService = ReminderService()

    func load() async {
        isLoading = true
        errorMessage = nil

        do {
            let links = try await scraper.fetchCampusMenuLinks()
            campusLinks = links

            guard let teresinaURL = links[.teresina] else {
                throw NSError(
                    domain: "RUUF",
                    code: 404,
                    userInfo: [NSLocalizedDescriptionKey: "Link de Teresina não encontrado na página da UFPI."]
                )
            }

            let (pdfData, response) = try await URLSession.shared.data(from: teresinaURL)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                throw NSError(
                    domain: "RUUF",
                    code: 500,
                    userInfo: [NSLocalizedDescriptionKey: "Falha ao baixar o PDF de Teresina."]
                )
            }

            let parsedMenu = try parser.parseWeeklyMenu(from: pdfData, campus: .teresina, sourceURL: teresinaURL)
            menu = parsedMenu

            if !parsedMenu.dailyMenus.contains(where: { $0.day == selectedDay }) {
                selectedDay = .segunda
            }

            await refreshReminderStatus()
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    func toggleReminder(for day: Weekday) async {
        do {
            if remindersEnabled[day] == true {
                reminderService.cancelReminder(for: day)
            } else {
                try await reminderService.scheduleReminder(for: day)
            }

            remindersEnabled[day] = await reminderService.isReminderEnabled(for: day)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func menuForSelectedDay() -> DailyMenu? {
        menu?.dailyMenus.first(where: { $0.day == selectedDay })
    }

    private func refreshReminderStatus() async {
        var status: [Weekday: Bool] = [:]
        for day in Weekday.allCases {
            status[day] = await reminderService.isReminderEnabled(for: day)
        }
        remindersEnabled = status
    }
}
