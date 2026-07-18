import AVFoundation
import SwiftUI

enum Constants {
    enum Camera {
        static let isoMin: Double = 54
        static let isoMax: Double = 3200
        static let colorTemperatureMin: Float = 2000
        static let colorTemperatureMax: Float = 8000
        static let exposureBiasMin: Double = -8.0
        static let exposureBiasMax: Double = 8.0
    }

    enum UI {
        static let compositionColor = Color(hex: "4A9EFF")
        static let exposureColor = Color(hex: "FFB347")
        static let settingsColor = Color(hex: "7ED957")
    }

    enum Bloom {
        static let threshold: Float = 0.75
        static let radiusFraction: Float = 0.01
        static let minRadius: Float = 2
        static let gain: Float = 1.8
    }

    enum Recording {
        static let videoCodec = AVVideoCodecType.hevc
        static let videoBitRate = 12_000_000
        static let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 44_100,
            AVEncoderBitRateKey: 96_000
        ]
        static let buttonRingSize: CGFloat = 56
        static let buttonInnerSize: CGFloat = 42
        static let buttonStopSize: CGFloat = 24
        static let buttonStopCornerRadius: CGFloat = 6
        static let recordColor = Color(hex: "FF3B30")
    }

    enum Zoom {
        static let maxDisplay: CGFloat = 15.0
        static let pointsPerZoom: CGFloat = 30
        static let momentumDecay: CGFloat = 3.5
        static let momentumMinVelocity: CGFloat = 0.1
        static let momentumFrameInterval: Double = 1.0 / 90.0
        static let collapsedWidth: CGFloat = 70
        static let expandedWidth: CGFloat = 300
        static let collapsedOpacity: Double = 0.35
        static let expandedOpacity: Double = 1.0
        static let baselineHeight: CGFloat = 0.75
        static let tickWidth: CGFloat = 0.75
        static let minorTickHeight: CGFloat = 6
        static let halfTickHeight: CGFloat = 9
        static let wholeTickHeight: CGFloat = 14
        static let edgeFadeFraction: Double = 0.08
        static let lineColor = Color.white
        static let tickColor = Color.white
    }

    enum Portrait {
        // stopIndex is 2 * log2(aperture), so whole photographic stops land on integers:
        // 1 = f/1.4, 2 = f/2, 3 = f/2.8 ... 8 = f/16. Detents are then just Int(value) changes.
        static let stopIndexMin: Double = 1
        static let stopIndexMax: Double = 8
        static let defaultStopIndex: Double = 3

        static let wheelRadius: CGFloat = 130
        static let arcStartDegrees: Double = 180
        static let arcEndDegrees: Double = 270
        static let indicatorDegrees: Double = 225
        static let degreesPerStop: Double = 30
        static let pointsPerStop: CGFloat = 44
        static let ticksPerStop: Int = 3

        static let revealDelay: Double = 0.25
        static let revealDistance: CGFloat = 8

        static let buttonSize: CGFloat = 44
        static let buttonInset: CGFloat = 12
        static let collapsedOpacity: Double = 0.55
        static let expandedOpacity: Double = 1.0
        static let baselineWidth: CGFloat = 0.75
        static let tickWidth: CGFloat = 0.75
        static let minorTickLength: CGFloat = 6
        static let majorTickLength: CGFloat = 14
        static let lineColor = Color.white
        static let tickColor = Color.white
        static let activeColor = Color(hex: "FFD60A")

        // The live preview approximates the capture's CIDepthBlurEffect with a masked blur,
        // so these two are a calibration pair: tune them together until preview matches capture.
        static let previewRadiusFraction: Float = 0.02
        static let previewMinRadius: Float = 2
        static let coreImageApertureMax: Float = 22

        // Depth maps carry outlier pixels reading far nearer than anything real. Normalising
        // the mask against raw min/max lets one such pixel flatten every real value to "far",
        // so the range is taken between percentiles instead, then eased frame to frame so a
        // shifting outlier cannot make the background pulse.
        static let disparityHistogramBins = 256
        static let disparityLowPercentile: Float = 0.02
        static let disparityHighPercentile: Float = 0.98
        static let disparityRangeSmoothing: Float = 0.2
        // Below this the scene is effectively flat, and normalising would amplify sensor noise
        // into full-scale blur.
        static let minDisparitySpan: Float = 0.02
        // Fraction of the disparity range nearest the camera that stays fully sharp. Without
        // it only the subject's single nearest plane is at zero blur, and its sides, back and
        // silhouette ramp all pick up partial blur.
        static let focusBandFraction: Float = 0.3

        // Measured in depth-map pixels, so they hold as the upscale factor changes. The depth
        // map is roughly a twentieth of the frame's resolution and is least reliable exactly at
        // object boundaries, so its edges land as a soft ramp straddling each silhouette —
        // which blurs the subject's own outline. Eroding pushes the whole ramp out into the
        // background; the subject keeps a hard edge, at the cost of a thin sharp halo around it.
        static let maskErosionDepthPixels: Float = 1.5
        static let maskSofteningDepthPixels: Float = 0.75
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
            You are an expert photography coach reviewing a single camera frame. 
            Analyze what you actually see in the image and give exactly 3 actionable 
            instructions — one per category.

            COMPOSITION: Make ONE definitive decision. Do not offer alternatives or 
            say "either/or". Look at where the subject actually is, then give a single 
            specific direction: which way to move, how much to tilt, what to include 
            or exclude from the frame. If composition is already strong, say what 
            specifically is working and what small refinement would improve it.

            EXPOSURE: Describe what you see — blown highlights, crushed shadows, 
            flat midtones, correct exposure. If there is a problem, be specific 
            about which setting is at fault and how to adjust it. Only suggest a 
            change if the image actually needs one. If exposure looks correct for 
            the scene, say so instead of inventing a problem.

            SETTINGS: ISO {iso} and shutter {shutter} are the current settings. 
            Judge whether these are appropriate for what you see in the frame — 
            the lighting, motion, and subject. Only flag a setting if it is 
            genuinely causing a visible problem in this specific image. If the 
            settings look right for the scene, confirm that instead of suggesting 
            a change. If there is a problem, be specific about which setting is 
            at fault and how to adjust it.

            Output format — exactly 3 lines, nothing else:
            COMPOSITION: <specific instruction>
            EXPOSURE: <what you see, and instruction only if needed>
            SETTINGS: <judgment of current settings, and change only if needed>

            Rules:
            - No markdown, bold, asterisks, quotes, bullets, or numbering.
            - No preamble or explanation. Output only the 3 lines.
            - Never say "either/or". Make a decision.
            - Never give generic advice. Every suggestion must be specific to this image.
            - Each suggestion must fit on 1-2 lines in a narrow mobile panel. 
              Be concise but specific. No padding words.
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
