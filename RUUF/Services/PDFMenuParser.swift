import Foundation
import PDFKit

enum PDFMenuParserError: LocalizedError {
    case unreadablePDF
    case missingPage
    case missingDayColumns

    var errorDescription: String? {
        switch self {
        case .unreadablePDF:
            return "Não foi possível abrir o PDF do cardápio."
        case .missingPage:
            return "O PDF não possui páginas válidas."
        case .missingDayColumns:
            return "Não foi possível identificar as colunas de dias no PDF."
        }
    }
}

final class PDFMenuParser {
    func parseWeeklyMenu(from pdfData: Data, campus: Campus, sourceURL: URL) throws -> WeeklyMenu {
        guard let document = PDFDocument(data: pdfData) else {
            throw PDFMenuParserError.unreadablePDF
        }

        guard let firstPage = document.page(at: 0) else {
            throw PDFMenuParserError.missingPage
        }

        let rawText = document.selectionForEntireDocument?.string ?? ""
        let lines = extractLines(from: document, on: firstPage)
        let columns = try extractDayColumns(from: lines)
        let categoryAnchors = extractCategoryAnchors(from: lines, firstColumnCenterX: columns[0].centerX)

        var bucket: [ColumnKey: [MenuCategory: [PDFLine]]] = [:]
        let dayHeaderY = columns.map(\.headerY).max() ?? .greatestFiniteMagnitude

        for line in lines {
            guard isCandidateTableLine(
                line,
                firstColumnCenterX: columns[0].centerX,
                anchors: categoryAnchors,
                dayHeaderY: dayHeaderY
            ) else {
                continue
            }

            guard let category = category(for: line.y, anchors: categoryAnchors) else {
                continue
            }

            let nearestColumn = nearestDayColumn(for: line.centerX, columns: columns)
            let key = ColumnKey(index: nearestColumn.index)
            bucket[key, default: [:]][category, default: []].append(line)
        }

        // Vegetariano costuma ficar abaixo da tabela principal, em faixa separada.
        for line in lines where isCandidateVegetarianLine(line, firstColumnCenterX: columns[0].centerX) {
            let nearestColumn = nearestDayColumn(for: line.centerX, columns: columns)
            let key = ColumnKey(index: nearestColumn.index)
            bucket[key, default: [:]][.vegetariano, default: []].append(line)
        }

        var dayAccumulator = Dictionary(uniqueKeysWithValues: Weekday.allCases.map { ($0, DayAccumulator()) })

        for column in columns {
            let key = ColumnKey(index: column.index)
            let categories = bucket[key] ?? [:]

            for category in MenuCategory.ordered {
                let items = composeItems(from: categories[category] ?? [], category: category)
                guard !items.isEmpty else { continue }

                if column.meal == .almoco {
                    dayAccumulator[column.day]?.lunch[category] = items
                } else {
                    dayAccumulator[column.day]?.dinner[category] = items
                }
            }
        }

        let dailyMenus: [DailyMenu] = Weekday.allCases.map { day in
            let accumulator = dayAccumulator[day] ?? DayAccumulator()
            let dinnerMenu: MealMenu? = day == .sabado ? nil : MealMenu(itemsByCategory: accumulator.dinner)
            return DailyMenu(day: day, lunch: MealMenu(itemsByCategory: accumulator.lunch), dinner: dinnerMenu)
        }

        let periodLabel = extractPeriodLabel(from: rawText)
        let periodBounds = extractPeriodBounds(from: periodLabel)

        return WeeklyMenu(
            campus: campus,
            sourceURL: sourceURL,
            periodLabel: periodLabel,
            periodStartDate: periodBounds.start,
            periodEndDate: periodBounds.end,
            rawText: normalizeRawText(rawText),
            dailyMenus: dailyMenus
        )
    }
}

private extension PDFMenuParser {
    struct PDFLine {
        let text: String
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat

        var centerX: CGFloat { x + (width / 2) }
    }

    struct DayColumn {
        enum Meal {
            case almoco
            case jantar
        }

        let index: Int
        let day: Weekday
        let meal: Meal
        let centerX: CGFloat
        let headerY: CGFloat
    }

    struct CategoryAnchor {
        let category: MenuCategory
        let y: CGFloat
    }

    struct ColumnKey: Hashable {
        let index: Int
    }

    struct DayAccumulator {
        var lunch: [MenuCategory: [String]] = [:]
        var dinner: [MenuCategory: [String]] = [:]
    }

    func extractLines(from document: PDFDocument, on page: PDFPage) -> [PDFLine] {
        guard let selection = document.selectionForEntireDocument else {
            return []
        }

        return selection.selectionsByLine().compactMap { lineSelection in
            guard lineSelection.pages.contains(page) else {
                return nil
            }

            let text = (lineSelection.string ?? "")
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !text.isEmpty else {
                return nil
            }

            let bounds = lineSelection.bounds(for: page)
            return PDFLine(text: text, x: bounds.origin.x, y: bounds.origin.y, width: bounds.width)
        }
    }

    func extractDayColumns(from lines: [PDFLine]) throws -> [DayColumn] {
        let weekdayCandidates: [(line: PDFLine, day: Weekday)] = lines.compactMap { line in
            guard let day = weekday(from: line.text) else { return nil }
            let normalized = line.text.normalizedForMatching()

            // Ignorar trechos de horário de funcionamento, que também contêm "2ª a 6ª feira".
            if normalized.contains("de 2") || normalized.contains("sabado fechado") {
                return nil
            }

            return (line, day)
        }

        guard !weekdayCandidates.isEmpty else {
            throw PDFMenuParserError.missingDayColumns
        }

        let groupedByYBand = Dictionary(grouping: weekdayCandidates) { candidate in
            Int((candidate.line.y / 4).rounded())
        }

        guard
            let bestBand = groupedByYBand.max(by: { $0.value.count < $1.value.count })?.value,
            bestBand.count >= 10
        else {
            throw PDFMenuParserError.missingDayColumns
        }

        let referenceY = bestBand.map(\.line.y).reduce(0, +) / CGFloat(bestBand.count)
        let alignedHeaders = weekdayCandidates
            .filter { abs($0.line.y - referenceY) <= 6 }
            .sorted { $0.line.centerX < $1.line.centerX }

        guard alignedHeaders.count >= 10 else {
            throw PDFMenuParserError.missingDayColumns
        }

        let normalizedHeaders: [(line: PDFLine, day: Weekday)] = {
            if alignedHeaders.count >= 11 {
                return Array(alignedHeaders.prefix(11))
            }
            return Array(alignedHeaders.prefix(10))
        }()

        if normalizedHeaders.count == 10 {
            return normalizedHeaders.enumerated().map { index, header in
                let meal: DayColumn.Meal = index < 5 ? .almoco : .jantar
                return DayColumn(
                    index: index,
                    day: header.day,
                    meal: meal,
                    centerX: header.line.centerX,
                    headerY: header.line.y
                )
            }
        }

        return normalizedHeaders.enumerated().map { index, header in
            let meal: DayColumn.Meal = index < 6 ? .almoco : .jantar
            return DayColumn(
                index: index,
                day: header.day,
                meal: meal,
                centerX: header.line.centerX,
                headerY: header.line.y
            )
        }
    }

    func extractCategoryAnchors(from lines: [PDFLine], firstColumnCenterX: CGFloat) -> [CategoryAnchor] {
        let leftLines = lines.filter { $0.x < firstColumnCenterX - 25 && $0.y > 210 && $0.y < 470 }

        let saladaY = leftLines.first(where: { $0.text.normalizedForMatching() == "salada" })?.y ?? 440
        let pratoY = leftLines
            .filter {
                let normalized = $0.text.normalizedForMatching()
                return normalized == "prato" || normalized == "principal" || normalized.contains("prato principal")
            }
            .map(\.y)
            .max() ?? 380
        let guarnicaoY = leftLines.first(where: { $0.text.normalizedForMatching() == "guarnicao" })?.y ?? 322
        let acompanhamentoY = leftLines.first(where: { $0.text.normalizedForMatching().hasPrefix("acompanhamento") })?.y ?? 295
        let sobremesaY = leftLines.first(where: { $0.text.normalizedForMatching() == "sobremesa" })?.y ?? 260
        var anchors: [CategoryAnchor] = [
            CategoryAnchor(category: .salada, y: saladaY),
            CategoryAnchor(category: .pratoPrincipal, y: pratoY),
            CategoryAnchor(category: .guarnicao, y: guarnicaoY),
            CategoryAnchor(category: .acompanhamento, y: acompanhamentoY),
            CategoryAnchor(category: .sobremesa, y: sobremesaY)
        ]

        if let sucoY = leftLines.first(where: { $0.text.normalizedForMatching().hasPrefix("suco") })?.y {
            anchors.append(CategoryAnchor(category: .suco, y: sucoY))
        }

        return anchors
    }

    func category(for y: CGFloat, anchors: [CategoryAnchor]) -> MenuCategory? {
        let map = Dictionary(uniqueKeysWithValues: anchors.map { ($0.category, $0.y) })

        guard
            let saladaY = map[.salada],
            let pratoY = map[.pratoPrincipal],
            let guarnicaoY = map[.guarnicao],
            let acompanhamentoY = map[.acompanhamento],
            let sobremesaY = map[.sobremesa]
        else {
            return nil
        }

        // Em alguns PDFs (ex: Bom Jesus) o rótulo "Prato Principal" aparece abaixo dos itens.
        // Por isso, limitar salada por proximidade à âncora de salada, não pelo ponto médio simples.
        let saladaToPratoDistance = max(0, saladaY - pratoY)
        let saladaBoundary = saladaY - max(6, saladaToPratoDistance * 0.30)
        if y >= saladaBoundary {
            return .salada
        }

        // Prato costuma ocupar mais altura e pode quebrar em múltiplas linhas até perto da guarnição.
        let pratoBoundary = guarnicaoY + ((pratoY - guarnicaoY) * 0.35)
        if y > pratoBoundary {
            return .pratoPrincipal
        }

        let guarnicaoBoundary = (guarnicaoY + acompanhamentoY) / 2
        if y > guarnicaoBoundary {
            return .guarnicao
        }

        let acompanhamentoBoundary = (acompanhamentoY + sobremesaY) / 2
        if y > acompanhamentoBoundary {
            return .acompanhamento
        }

        if let sucoY = map[.suco] {
            let sobremesaBoundary = (sobremesaY + sucoY) / 2
            if y > sobremesaBoundary {
                return .sobremesa
            }
            return .suco
        }

        return .sobremesa
    }

    func nearestDayColumn(for centerX: CGFloat, columns: [DayColumn]) -> DayColumn {
        columns.min(by: { abs($0.centerX - centerX) < abs($1.centerX - centerX) }) ?? columns[0]
    }

    func isCandidateTableLine(
        _ line: PDFLine,
        firstColumnCenterX: CGFloat,
        anchors: [CategoryAnchor],
        dayHeaderY: CGFloat
    ) -> Bool {
        guard line.x > firstColumnCenterX - 40 else {
            return false
        }

        // Impede que rótulos "2ª Feira", "3ª Feira"... sejam tratados como comida.
        guard line.y < dayHeaderY - 6 else {
            return false
        }

        guard let topY = anchors.first?.y, let bottomY = anchors.last?.y else {
            return false
        }

        guard line.y <= topY + 28 && line.y >= bottomY - 6 else {
            return false
        }

        let normalized = line.text.normalizedForMatching()

        if normalized.isEmpty {
            return false
        }

        let blockedTokens = [
            "almoco", "jantar", "estrutura do", "cardapio", "prato", "principal",
            "guarnicao", "acompanhamento", "sobremesa", "suco"
        ]

        return !blockedTokens.contains(normalized)
    }

    func isCandidateVegetarianLine(_ line: PDFLine, firstColumnCenterX: CGFloat) -> Bool {
        guard line.x > firstColumnCenterX - 40 else {
            return false
        }

        guard line.y > 136 && line.y < 182 else {
            return false
        }

        let normalized = line.text.normalizedForMatching()

        if normalized.contains("atencao") || normalized.contains("avisos") || normalized.contains("horario") {
            return false
        }

        return !normalized.isEmpty
    }

    func composeItems(from lines: [PDFLine], category: MenuCategory) -> [String] {
        guard !lines.isEmpty else {
            return []
        }

        let ordered = lines.sorted {
            if $0.y == $1.y {
                return $0.x < $1.x
            }
            return $0.y > $1.y
        }

        if category == .salada {
            return deduplicated(ordered.map { cleanItemText($0.text) }.filter { !$0.isEmpty })
        }

        var result: [String] = []
        var current = cleanItemText(ordered[0].text)
        var last = ordered[0]

        for line in ordered.dropFirst() {
            let text = cleanItemText(line.text)
            guard !text.isEmpty else { continue }

            let verticalGap = abs(last.y - line.y)
            let horizontalGap = abs(last.x - line.x)
            let shouldMerge = verticalGap <= 12.5 && horizontalGap <= 24

            if shouldMerge {
                current = "\(current) \(text)"
            } else {
                result.append(current)
                current = text
            }

            last = line
        }

        if !current.isEmpty {
            result.append(current)
        }

        return deduplicated(result.map { cleanItemText($0) }.filter { !$0.isEmpty })
    }

    func cleanItemText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "- -", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func deduplicated(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var output: [String] = []

        for value in values {
            let key = value.normalizedForMatching()
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            output.append(value)
        }

        return output
    }

    func weekday(from text: String) -> Weekday? {
        let normalized = text.normalizedForMatching()

        if normalized.contains("sabado") { return .sabado }
        guard normalized.contains("feira") else { return nil }
        if normalized.contains("2 feira") { return .segunda }
        if normalized.contains("3 feira") { return .terca }
        if normalized.contains("4 feira") { return .quarta }
        if normalized.contains("5 feira") { return .quinta }
        if normalized.contains("6 feira") { return .sexta }

        return nil
    }

    func extractPeriodLabel(from text: String) -> String {
        let patterns = [
            #"(?i)CARD[ÁA]PIO\s+SEMANAL\s+DE\s+([^\n]+)"#,
            #"(?i)CARD[ÁA]PIO\s+SEMANAL\s*[–\-:]\s*([^\n]+)"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
                  let range = Range(match.range(at: 1), in: text) else {
                continue
            }

            return text[range]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"^DE\s+"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        }

        return "Período não identificado"
    }

    func extractPeriodBounds(from periodLabel: String) -> (start: Date?, end: Date?) {
        if let captures = firstMatch(
            pattern: #"(?i)(\d{1,2})\s*/\s*(\d{1,2})\s*/\s*(\d{2,4})\s*[Aa]\s*(\d{1,2})\s*/\s*(\d{1,2})\s*/\s*(\d{2,4})"#,
            in: periodLabel
        ), captures.count == 6 {
            let start = buildDate(day: captures[0], month: captures[1], year: captures[2])
            let end = buildDate(day: captures[3], month: captures[4], year: captures[5])
            return (start, end)
        }

        if let captures = firstMatch(
            pattern: #"(?i)(\d{1,2})\s*[Aa]\s*(\d{1,2})\s*/\s*(\d{1,2})\s*/\s*(\d{2,4})"#,
            in: periodLabel
        ), captures.count == 4 {
            let endDay = captures[1]
            let month = captures[2]
            let year = captures[3]
            let start = buildDate(day: captures[0], month: month, year: year)
            let end = buildDate(day: endDay, month: month, year: year)
            return (start, end)
        }

        if let captures = firstMatch(
            pattern: #"(?i)(\d{1,2})\s*[Aa]\s*(\d{1,2})\s+DE\s+([[:alpha:]çÇãÃõÕáÁéÉíÍóÓúÚâÂêÊôÔ]+)\s+DE\s+(\d{4})"#,
            in: periodLabel
        ), captures.count == 4 {
            let startDay = Int(captures[0])
            let endDay = Int(captures[1])
            let month = monthNumber(fromPortugueseName: captures[2])
            let year = Int(captures[3])

            guard let startDay, let endDay, let month, let year else {
                return (nil, nil)
            }

            let start = buildDate(day: startDay, month: month, year: year)
            let end = buildDate(day: endDay, month: month, year: year)
            return (start, end)
        }

        return (nil, nil)
    }

    func firstMatch(pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: nsRange) else {
            return nil
        }

        guard match.numberOfRanges > 1 else {
            return nil
        }

        var captures: [String] = []
        for index in 1..<match.numberOfRanges {
            guard let range = Range(match.range(at: index), in: text) else {
                return nil
            }
            captures.append(String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return captures
    }

    func buildDate(day: String, month: String, year: String) -> Date? {
        guard let dayValue = Int(day), let monthValue = Int(month), let yearValue = Int(year) else {
            return nil
        }
        return buildDate(day: dayValue, month: monthValue, year: yearValue)
    }

    func buildDate(day: Int, month: Int, year: Int) -> Date? {
        let adjustedYear = year < 100 ? (2000 + year) : year
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = adjustedYear
        components.month = month
        components.day = day
        components.hour = 12
        return components.date
    }

    func monthNumber(fromPortugueseName monthName: String) -> Int? {
        let normalized = monthName
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
            .lowercased()

        let mapping: [String: Int] = [
            "janeiro": 1,
            "fevereiro": 2,
            "marco": 3,
            "abril": 4,
            "maio": 5,
            "junho": 6,
            "julho": 7,
            "agosto": 8,
            "setembro": 9,
            "outubro": 10,
            "novembro": 11,
            "dezembro": 12
        ]

        return mapping[normalized]
    }

    func normalizeRawText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{000C}", with: "\n")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
