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

    enum Gemini {
        static let model = "gemini-2.0-flash"
        static let frameInterval: TimeInterval = 5
        static let inactivityTimeout: TimeInterval = 300
        static let inactivityDismissDelay: TimeInterval = 30
        static let systemPrompt = """
            You are a real-time photography coach. Analyze this camera frame and give \
            2-3 short, actionable suggestions. Categorize each one as COMPOSITION, \
            EXPOSURE, or SETTINGS. Use imperative phrases. Be concise. Examples:
            "COMPOSITION: Apply rule of thirds — subject is too centered"
            "EXPOSURE: Highlights are blown — lower ISO or increase shutter speed"
            "SETTINGS: For this indoor scene, try ISO 400 at 1/60s"

            Current camera settings: ISO {iso}, Shutter {shutter}.
            Never exceed 3 suggestions. Never use markdown.
            """
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
