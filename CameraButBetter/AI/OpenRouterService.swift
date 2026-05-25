import Foundation

actor OpenRouterService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func analyze(imageBase64: String, currentISO: String, currentShutter: String) async throws -> FeedbackResult {
        let apiKey = Config.openRouterAPIKey
        guard !apiKey.isEmpty else { throw FeedbackError.missingAPIKey }

        let promptText = Constants.Feedback.systemPrompt
            .replacingOccurrences(of: "{iso}", with: currentISO)
            .replacingOccurrences(of: "{shutter}", with: currentShutter)

        let request = ChatRequest(
            model: Constants.OpenRouter.model,
            messages: [
                .init(role: "user", content: [
                    .init(type: "text", text: promptText, imageUrl: nil),
                    .init(type: "image_url", text: nil,
                          imageUrl: .init(url: "data:image/jpeg;base64,\(imageBase64)")),
                ])
            ],
            temperature: 0.4,
            maxTokens: 512
        )

        guard let url = URL(string: Constants.OpenRouter.endpoint) else {
            throw FeedbackError.invalidResponse
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw FeedbackError.requestFailed(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw FeedbackError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            print("[OpenRouter] HTTP \(http.statusCode) — \(body ?? "<no body>")")
            throw FeedbackError.httpStatus(http.statusCode, body)
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        let text = decoded.choices?
            .compactMap { $0.message?.content }
            .joined(separator: "\n") ?? ""

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw FeedbackError.emptyText }

        print("[OpenRouter] raw text:\n\(trimmed)\n[/OpenRouter]")
        let suggestions = Self.parseSuggestions(from: trimmed)
        print("[OpenRouter] parsed \(suggestions.count) suggestion(s)")
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
