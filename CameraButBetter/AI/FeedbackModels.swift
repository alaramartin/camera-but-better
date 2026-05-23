import SwiftUI

enum FeedbackCategory: String, Codable, CaseIterable {
    case composition = "COMPOSITION"
    case exposure = "EXPOSURE"
    case settings = "SETTINGS"

    var color: Color {
        switch self {
        case .composition: return Constants.UI.compositionColor
        case .exposure: return Constants.UI.exposureColor
        case .settings: return Constants.UI.settingsColor
        }
    }
}

struct FeedbackSuggestion: Identifiable, Hashable {
    let id = UUID()
    let category: FeedbackCategory
    let text: String
}

struct FeedbackResult: Identifiable, Hashable {
    let id = UUID()
    let suggestions: [FeedbackSuggestion]
    let timestamp: Date
}

enum GeminiError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case httpStatus(Int, String?)
    case emptyText
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Add a Gemini API key in Settings to enable AI feedback."
        case .invalidResponse: return "Gemini returned an unreadable response."
        case .httpStatus(let code, let body):
            let detail = GeminiErrorBody.parseMessage(body)
            switch code {
            case 429:
                return detail ?? "Gemini rate limit hit. Try again in a minute."
            case 401, 403:
                return detail ?? "Gemini rejected the API key (HTTP \(code))."
            case 400:
                return detail ?? "Bad request (HTTP 400)."
            case 500...599:
                return "Gemini is unavailable (HTTP \(code)). Retrying next tick."
            default:
                if let detail { return "Gemini error (\(code)): \(detail)" }
                return "Gemini error (HTTP \(code))."
            }
        case .emptyText: return "Gemini returned no text."
        case .requestFailed(let message): return "Network error: \(message)"
        }
    }
}

private struct GeminiErrorEnvelope: Decodable {
    struct Inner: Decodable {
        let code: Int?
        let message: String?
        let status: String?
    }
    let error: Inner?
}

enum GeminiErrorBody {
    static func parseMessage(_ body: String?) -> String? {
        guard let body, !body.isEmpty, let data = body.data(using: .utf8) else { return nil }
        guard let envelope = try? JSONDecoder().decode(GeminiErrorEnvelope.self, from: data),
              let message = envelope.error?.message, !message.isEmpty else { return nil }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 200 ? String(trimmed.prefix(200)) + "…" : trimmed
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
        let thinkingConfig: ThinkingConfig?

        enum CodingKeys: String, CodingKey {
            case temperature
            case maxOutputTokens
            case thinkingConfig
        }
    }
    struct ThinkingConfig: Encodable {
        let thinkingBudget: Int
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
