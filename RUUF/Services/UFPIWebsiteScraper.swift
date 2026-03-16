import Foundation

enum UFPIWebsiteScraperError: LocalizedError {
    case invalidResponse
    case decodingFailed
    case noCampusLinksFound

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Resposta inválida ao buscar página da UFPI."
        case .decodingFailed:
            return "Não foi possível ler o conteúdo da página da UFPI."
        case .noCampusLinksFound:
            return "Nenhum link de cardápio foi encontrado na seção CARDÁPIOS."
        }
    }
}

final class UFPIWebsiteScraper {
    private let pageURL = URL(string: "https://www.ufpi.br/restaurante-universitario")!

    func fetchCampusMenuLinks() async throws -> [Campus: URL] {
        let (data, response) = try await URLSession.shared.data(from: pageURL)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw UFPIWebsiteScraperError.invalidResponse
        }

        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw UFPIWebsiteScraperError.decodingFailed
        }

        let sectionHTML = extractCardapiosSection(from: html)
        let anchors = extractAnchors(from: sectionHTML)

        var results: [Campus: URL] = [:]

        for anchor in anchors {
            let normalizedText = anchor.text.normalizedForMatching()
            guard normalizedText.contains("cardapio") else { continue }

            guard let campus = Campus.allCases.first(where: { campus in
                campus.normalizedKeywords.contains(where: { normalizedText.contains($0) })
            }) else {
                continue
            }

            guard anchor.href.lowercased().contains(".pdf") else { continue }
            guard let absoluteURL = makeAbsoluteURL(from: anchor.href) else { continue }

            if results[campus] == nil {
                results[campus] = absoluteURL
            }
        }

        guard !results.isEmpty else {
            throw UFPIWebsiteScraperError.noCampusLinksFound
        }

        return results
    }

    private func extractCardapiosSection(from html: String) -> String {
        let startPattern = "(?i)CARD[ÁA]PIOS"

        guard
            let startRange = html.range(of: startPattern, options: .regularExpression)
        else {
            return html
        }

        let suffix = String(html[startRange.lowerBound...])

        if let endRange = suffix.range(of: "(?i)Endere[cç]o", options: .regularExpression) {
            return String(suffix[..<endRange.lowerBound])
        }

        return suffix
    }

    private func makeAbsoluteURL(from href: String) -> URL? {
        if let absolute = URL(string: href), absolute.host != nil {
            return absolute
        }

        let base = URL(string: "https://www.ufpi.br")
        return URL(string: href, relativeTo: base)?.absoluteURL
    }

    private func extractAnchors(from html: String) -> [Anchor] {
        let pattern = #"<a\s+[^>]*href\s*=\s*"([^"]+)"[^>]*>(.*?)</a>"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }

        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex.matches(in: html, options: [], range: nsRange)

        return matches.compactMap { match in
            guard
                let hrefRange = Range(match.range(at: 1), in: html),
                let textRange = Range(match.range(at: 2), in: html)
            else {
                return nil
            }

            let href = String(html[hrefRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let rawText = String(html[textRange])
            let text = rawText
                .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "&nbsp;", with: " ")
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return Anchor(href: href, text: text)
        }
    }

    private struct Anchor {
        let href: String
        let text: String
    }
}
