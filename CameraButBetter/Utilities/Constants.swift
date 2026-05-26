import SwiftUI

enum Constants {
    enum Camera {
        static let isoMin: Double = 54
        static let isoMax: Double = 3200
        static let colorTemperatureMin: Float = 2000
        static let colorTemperatureMax: Float = 8000
    }

    enum UI {
        static let compositionColor = Color(hex: "4A9EFF")
        static let exposureColor = Color(hex: "FFB347")
        static let settingsColor = Color(hex: "7ED957")
    }

    enum Overlay {
        static let levelAlignedThresholdDegrees: Double = 1.0
        static let levelLineLength: CGFloat = 90
        static let lineWidth: CGFloat = 0.75
        static let gridLineColor = Color.white.opacity(0.5)
        static let centerCrossLength: CGFloat = 14
        static let alignedColor = Color.green
        static let unalignedColor = Color.white
    }

    enum OpenRouter {
        static let endpoint = "https://openrouter.ai/api/v1/chat/completions"
        static let model = "google/gemma-4-26b-a4b-it:free"
    }

    enum Gemini {
        static let endpointBase = "https://generativelanguage.googleapis.com/v1beta/models"
        static let model = "gemini-2.5-flash"
    }

    enum Feedback {
        static let systemPrompt = """
            You are a real-time photography coach. Analyze this camera frame and give \
            exactly 3 short, actionable suggestions — one per category in this order: \
            COMPOSITION, EXPOSURE, SETTINGS. Use imperative phrases. Be concise.

            Output format: exactly 3 lines, each on its own line, in this shape:
            COMPOSITION: <suggestion>
            EXPOSURE: <suggestion>
            SETTINGS: <suggestion>

            Rules:
            - No markdown. No bold, no asterisks, no quotes, no bullets, no numbering.
            - No preamble. No explanations. Output only the 3 lines.
            - Each suggestion fits on a single line (under 100 characters).

            Current camera settings: ISO {iso}, Shutter {shutter}.
            """
    }
}

enum PreviewAspectRatio: String, CaseIterable, Identifiable {
    case fourThree
    case threeTwo
    case sixteenNine
    case oneOne

    var id: String { rawValue }

    var portraitRatio: CGFloat {
        switch self {
        case .fourThree: return 3.0 / 4.0
        case .threeTwo: return 2.0 / 3.0
        case .sixteenNine: return 9.0 / 16.0
        case .oneOne: return 1.0
        }
    }

    var label: String {
        switch self {
        case .fourThree: return "4:3"
        case .threeTwo: return "3:2"
        case .sixteenNine: return "16:9"
        case .oneOne: return "1:1"
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
