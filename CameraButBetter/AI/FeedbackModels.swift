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

enum FeedbackFailureKind {
    case client
    case userDailyLimit
    case transient
}

struct FeedbackErrorState {
    let message: String
    let canRetryGemma: Bool
    let canSwitchToGemini: Bool
}

enum FeedbackError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case httpStatus(Int, String?)
    case emptyText
    case requestFailed(String)

    var failureKind: FeedbackFailureKind {
        switch self {
        case .missingAPIKey:
            return .client
        case .httpStatus(let code, let body):
            switch code {
            case 429 where OpenRouterErrorBody.isDailyLimit(body):
                return .userDailyLimit
            case 429, 500...599:
                return .transient
            case 400, 401, 403:
                return .client
            default:
                return .transient
            }
        case .invalidResponse, .emptyText, .requestFailed:
            return .transient
        }
    }

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "No OpenRouter API key configured."
        case .invalidResponse: return "OpenRouter returned an unreadable response."
        case .httpStatus(let code, let body):
            let detail = OpenRouterErrorBody.parseMessage(body)
            switch code {
            case 429 where OpenRouterErrorBody.isDailyLimit(body):
                return "You've used today's free AI feedback limit. It resets at midnight UTC — try again then."
            case 429:
                return "AI feedback is busy right now — the free model is getting too much traffic. Wait a few seconds and tap again."
            case 401, 403:
                return detail ?? "OpenRouter rejected the API key (HTTP \(code))."
            case 400:
                return detail ?? "Bad request (HTTP 400)."
            case 500...599:
                return "OpenRouter is unavailable (HTTP \(code)). Retrying next tick."
            default:
                if let detail { return "OpenRouter error (\(code)): \(detail)" }
                return "OpenRouter error (HTTP \(code))."
            }
        case .emptyText: return "OpenRouter returned no text."
        case .requestFailed(let message): return "Network error: \(message)"
        }
    }
}

private struct OpenRouterErrorEnvelope: Decodable {
    struct Inner: Decodable {
        struct Metadata: Decodable {
            let raw: String?
        }
        let code: Int?
        let message: String?
        let metadata: Metadata?
    }
    let error: Inner?
}

enum OpenRouterErrorBody {
    static func isDailyLimit(_ body: String?) -> Bool {
        guard let body, !body.isEmpty, let data = body.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(OpenRouterErrorEnvelope.self, from: data) else {
            return false
        }
        let raw = envelope.error?.metadata?.raw?.lowercased() ?? ""
        let message = envelope.error?.message?.lowercased() ?? ""
        if raw.contains("upstream") { return false }
        return message.contains("per-day") || message.contains("per day") || message.contains("daily")
    }

    static func parseMessage(_ body: String?) -> String? {
        guard let body, !body.isEmpty, let data = body.data(using: .utf8) else { return nil }
        guard let envelope = try? JSONDecoder().decode(OpenRouterErrorEnvelope.self, from: data) else { return nil }
        let raw = envelope.error?.metadata?.raw
        let message = raw?.isEmpty == false ? raw : envelope.error?.message
        guard let message, !message.isEmpty else { return nil }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 200 ? String(trimmed.prefix(200)) + "…" : trimmed
    }
}

struct ChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: [ContentPart]
    }
    struct ContentPart: Encodable {
        let type: String
        let text: String?
        let imageUrl: ImageURL?

        enum CodingKeys: String, CodingKey {
            case type
            case text
            case imageUrl = "image_url"
        }
    }
    struct ImageURL: Encodable {
        let url: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
    let maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
    }
}

struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }
        let message: Message?
    }
    let choices: [Choice]?
}
