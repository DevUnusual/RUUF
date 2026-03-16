import Foundation
import Combine

@MainActor
final class MenuViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var menu: WeeklyMenu?
    @Published var campusLinks: [Campus: URL] = [:]
    @Published var selectedCampus: Campus = .teresina
    @Published var displayMode: MenuDisplayMode = .porDia
    @Published var selectedDay: Weekday = .segunda
    @Published var remindersEnabled: [Weekday: Bool] = [:]

    private let scraper = UFPIWebsiteScraper()
    private let parser = PDFMenuParser()
    private let reminderService = ReminderService()
    private var menuCache: [Campus: WeeklyMenu] = [:]

    func load() async {
        isLoading = true
        errorMessage = nil

        do {
            try await ensureCampusLinks(forceRefresh: campusLinks.isEmpty)
            let selectedMenu = try await fetchMenu(for: selectedCampus, forceReload: false)
            apply(menu: selectedMenu)
            await refreshReminderStatus()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func reloadCurrentCampus() async {
        isLoading = true
        errorMessage = nil

        do {
            try await ensureCampusLinks(forceRefresh: true)
            let selectedMenu = try await fetchMenu(for: selectedCampus, forceReload: true)
            apply(menu: selectedMenu)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func selectCampus(_ campus: Campus) async {
        guard campus != selectedCampus || menu == nil else { return }

        selectedCampus = campus
        isLoading = true
        errorMessage = nil

        do {
            try await ensureCampusLinks(forceRefresh: campusLinks.isEmpty)
            let selectedMenu = try await fetchMenu(for: campus, forceReload: false)
            apply(menu: selectedMenu)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
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

    private func ensureCampusLinks(forceRefresh: Bool) async throws {
        if forceRefresh || campusLinks.isEmpty {
            campusLinks = try await scraper.fetchCampusMenuLinks()
            if forceRefresh {
                menuCache.removeAll()
            }
        }
    }

    private func fetchMenu(for campus: Campus, forceReload: Bool) async throws -> WeeklyMenu {
        if !forceReload, let cached = menuCache[campus] {
            return cached
        }

        guard let campusURL = campusLinks[campus] else {
            throw NSError(
                domain: "RUUF",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Link do campus \(campus.rawValue) não encontrado na página da UFPI."]
            )
        }

        let (pdfData, response) = try await URLSession.shared.data(from: campusURL)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NSError(
                domain: "RUUF",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Falha ao baixar o PDF de \(campus.rawValue)."]
            )
        }

        let parsedMenu = try parser.parseWeeklyMenu(from: pdfData, campus: campus, sourceURL: campusURL)
        menuCache[campus] = parsedMenu
        return parsedMenu
    }

    private func apply(menu: WeeklyMenu) {
        self.menu = menu

        if !menu.dailyMenus.contains(where: { $0.day == selectedDay }) {
            selectedDay = .segunda
        }
    }

    private func refreshReminderStatus() async {
        var status: [Weekday: Bool] = [:]
        for day in Weekday.allCases {
            status[day] = await reminderService.isReminderEnabled(for: day)
        }
        remindersEnabled = status
    }
}
