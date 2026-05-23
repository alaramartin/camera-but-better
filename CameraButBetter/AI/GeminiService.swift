import Foundation

actor GeminiService {
    private let session: URLSession
    private let endpoint = "https://generativelanguage.googleapis.com/v1beta/models"

    init(session: URLSession = .shared) {
        self.session = session
    }

    func analyze(imageBase64: String, currentISO: String, currentShutter: String) async throws -> FeedbackResult {
        guard let apiKey = KeychainService.shared.readAPIKey(), !apiKey.isEmpty else {
            throw GeminiError.missingAPIKey
        }

        let promptText = Constants.Gemini.systemPrompt
            .replacingOccurrences(of: "{iso}", with: currentISO)
            .replacingOccurrences(of: "{shutter}", with: currentShutter)

        let request = GeminiRequest(
            contents: [
                .init(parts: [
                    .init(text: promptText, inlineData: nil),
                    .init(text: nil, inlineData: .init(mimeType: "image/jpeg", data: imageBase64)),
                ])
            ],
            generationConfig: .init(
                temperature: 0.4,
                maxOutputTokens: 512,
                thinkingConfig: .init(thinkingBudget: 0)
            )
        )

        let urlString = "\(endpoint)/\(Constants.Gemini.model):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else { throw GeminiError.invalidResponse }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw GeminiError.requestFailed(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw GeminiError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            print("[Gemini] HTTP \(http.statusCode) — \(body ?? "<no body>")")
            throw GeminiError.httpStatus(http.statusCode, body)
        }

        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
        let text = decoded.candidates?
            .compactMap { $0.content?.parts?.compactMap { $0.text }.joined() }
            .joined(separator: "\n") ?? ""

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GeminiError.emptyText }

        print("[Gemini] raw text:\n\(trimmed)\n[/Gemini]")
        let suggestions = Self.parseSuggestions(from: trimmed)
        print("[Gemini] parsed \(suggestions.count) suggestion(s)")
        return FeedbackResult(suggestions: suggestions, timestamp: Date())
    }

    static func parseSuggestions(from text: String) -> [FeedbackSuggestion] {
        let cleaned = text.replacingOccurrences(of: "\\n", with: "\n")
        let categoryKeywords = FeedbackCategory.allCases.map { $0.rawValue }
        let pattern = "(?=\\b(" + categoryKeywords.joined(separator: "|") + ")\\b)"
        let chunks: [String]
        if let regex = try? NSRegularExpression(pattern: pattern) {
            chunks = splitOnRegex(cleaned, regex: regex)
        } else {
            chunks = cleaned.split(whereSeparator: { $0.isNewline }).map(String.init)
        }

        var result: [FeedbackSuggestion] = []
        for raw in chunks {
            guard let suggestion = parseSingle(raw) else { continue }
            result.append(suggestion)
            if result.count == 3 { break }
        }
        return result
    }

    private static func splitOnRegex(_ text: String, regex: NSRegularExpression) -> [String] {
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        let matches = regex.matches(in: text, range: range)
        guard !matches.isEmpty else { return [text] }
        var pieces: [String] = []
        var lastIndex = 0
        for match in matches {
            let loc = match.range.location
            if loc > lastIndex {
                pieces.append(ns.substring(with: NSRange(location: lastIndex, length: loc - lastIndex)))
            }
            lastIndex = loc
        }
        if lastIndex < ns.length {
            pieces.append(ns.substring(with: NSRange(location: lastIndex, length: ns.length - lastIndex)))
        }
        return pieces
    }

    private static func parseSingle(_ raw: String) -> FeedbackSuggestion? {
        var line = raw
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        while let first = line.first, first.isNumber || "-•.):# ".contains(first) {
            line.removeFirst()
        }
        line = line.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let colonIndex = line.firstIndex(of: ":") else { return nil }
        let prefix = line[..<colonIndex].uppercased().trimmingCharacters(in: .whitespaces)
        var body = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
        body = body.replacingOccurrences(of: "\n", with: " ")
        guard !body.isEmpty else { return nil }
        guard let category = FeedbackCategory.allCases.first(where: { prefix.contains($0.rawValue) }) else {
            return nil
        }
        return FeedbackSuggestion(category: category, text: body)
    }
}
