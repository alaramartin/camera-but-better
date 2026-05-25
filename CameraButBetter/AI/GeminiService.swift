import Foundation

actor GeminiService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func analyze(imageBase64: String, currentISO: String, currentShutter: String) async throws -> FeedbackResult {
        let apiKey = Config.geminiAPIKey
        guard !apiKey.isEmpty else { throw GeminiError.missingAPIKey }

        let promptText = Constants.Feedback.systemPrompt
            .replacingOccurrences(of: "{iso}", with: currentISO)
            .replacingOccurrences(of: "{shutter}", with: currentShutter)

        let request = GeminiRequest(
            contents: [
                .init(parts: [
                    .init(text: promptText, inlineData: nil),
                    .init(text: nil, inlineData: .init(mimeType: "image/jpeg", data: imageBase64)),
                ])
            ],
            generationConfig: .init(temperature: 0.4, maxOutputTokens: 512)
        )

        let endpoint = "\(Constants.Gemini.endpointBase)/\(Constants.Gemini.model):generateContent"
        guard let url = URL(string: endpoint) else { throw GeminiError.invalidResponse }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
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
        let suggestions = OpenRouterService.parseSuggestions(from: trimmed)
        print("[Gemini] parsed \(suggestions.count) suggestion(s)")
        return FeedbackResult(suggestions: suggestions, timestamp: Date())
    }
}

enum GeminiError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case httpStatus(Int, String?)
    case emptyText
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No Gemini API key configured."
        case .invalidResponse:
            return "Gemini returned an unreadable response."
        case .httpStatus(let code, _):
            switch code {
            case 429:
                return "You've reached your Gemini free-tier quota. Try again later."
            case 400, 401, 403:
                return "Gemini rejected the request (HTTP \(code)). Check the API key."
            case 500...599:
                return "Gemini is unavailable (HTTP \(code)). Try again shortly."
            default:
                return "Gemini error (HTTP \(code))."
            }
        case .emptyText:
            return "Gemini returned no text."
        case .requestFailed(let message):
            return "Network error: \(message)"
        }
    }
}

struct GeminiRequest: Encodable {
    struct Content: Encodable {
        let parts: [Part]
    }
    struct Part: Encodable {
        let text: String?
        let inlineData: InlineData?

        enum CodingKeys: String, CodingKey {
            case text
            case inlineData = "inline_data"
        }
    }
    struct InlineData: Encodable {
        let mimeType: String
        let data: String

        enum CodingKeys: String, CodingKey {
            case mimeType = "mime_type"
            case data
        }
    }
    struct GenerationConfig: Encodable {
        let temperature: Double
        let maxOutputTokens: Int
    }

    let contents: [Content]
    let generationConfig: GenerationConfig
}

struct GeminiResponse: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            struct Part: Decodable {
                let text: String?
            }
            let parts: [Part]?
        }
        let content: Content?
    }
    let candidates: [Candidate]?
}
