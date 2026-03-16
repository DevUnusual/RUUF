import Foundation

enum Campus: String, CaseIterable, Identifiable {
    case teresina = "Teresina"
    case picos = "Picos"
    case floriano = "Floriano"
    case bomJesus = "Bom Jesus"

    var id: String { rawValue }

    var normalizedKeywords: [String] {
        switch self {
        case .teresina:
            return ["teresina"]
        case .picos:
            return ["picos"]
        case .floriano:
            return ["floriano"]
        case .bomJesus:
            return ["bom jesus", "bomjesus"]
        }
    }
}

enum Weekday: Int, CaseIterable, Identifiable {
    case segunda = 2
    case terca = 3
    case quarta = 4
    case quinta = 5
    case sexta = 6
    case sabado = 7

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .segunda:
            return "Segunda"
        case .terca:
            return "Terça"
        case .quarta:
            return "Quarta"
        case .quinta:
            return "Quinta"
        case .sexta:
            return "Sexta"
        case .sabado:
            return "Sábado"
        }
    }
}

enum MenuCategory: String, CaseIterable, Identifiable {
    case salada = "Salada"
    case pratoPrincipal = "Prato Principal"
    case guarnicao = "Guarnição"
    case acompanhamento = "Acompanhamento"
    case sobremesa = "Sobremesa"
    case suco = "Suco"
    case vegetariano = "Vegetariano"

    var id: String { rawValue }

    static var ordered: [MenuCategory] {
        [.salada, .pratoPrincipal, .guarnicao, .acompanhamento, .sobremesa, .suco, .vegetariano]
    }
}

struct MealMenu: Equatable {
    var itemsByCategory: [MenuCategory: [String]] = [:]

    func items(for category: MenuCategory) -> [String] {
        itemsByCategory[category] ?? []
    }
}

struct DailyMenu: Identifiable, Equatable {
    let day: Weekday
    let lunch: MealMenu
    let dinner: MealMenu?

    var id: Weekday { day }
}

struct WeeklyMenu: Equatable {
    let campus: Campus
    let sourceURL: URL
    let periodLabel: String
    let rawText: String
    let dailyMenus: [DailyMenu]
}

enum MenuDisplayMode: String, CaseIterable, Identifiable {
    case geral = "Geral"
    case porDia = "Por dia"

    var id: String { rawValue }
}
