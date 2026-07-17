import SwiftUI

enum PhotoFormat: String, CaseIterable, Identifiable {
    case jpeg
    case raw

    var id: String { rawValue }

    var label: String {
        switch self {
        case .jpeg: return "JPEG"
        case .raw: return "RAW"
        }
    }
}

final class OverlaySettings: ObservableObject {
    private enum Key {
        static let level = "overlay.level"
        static let grid = "overlay.grid"
        static let centerCross = "overlay.centerCross"
        static let aspectRatio = "composition.aspectRatio"
        static let photoFormat = "capture.photoFormat"
        static let bloomIntensity = "effect.bloomIntensity"
        static let portraitStopIndex = "effect.portraitStopIndex"
    }

    @Published var showLevel: Bool {
        didSet { UserDefaults.standard.set(showLevel, forKey: Key.level) }
    }

    @Published var showGrid: Bool {
        didSet { UserDefaults.standard.set(showGrid, forKey: Key.grid) }
    }

    @Published var showCenterCross: Bool {
        didSet { UserDefaults.standard.set(showCenterCross, forKey: Key.centerCross) }
    }

    @Published var aspectRatio: PreviewAspectRatio {
        didSet { UserDefaults.standard.set(aspectRatio.rawValue, forKey: Key.aspectRatio) }
    }

    @Published var photoFormat: PhotoFormat {
        didSet { UserDefaults.standard.set(photoFormat.rawValue, forKey: Key.photoFormat) }
    }

    @Published var bloomIntensity: Double {
        didSet { UserDefaults.standard.set(bloomIntensity, forKey: Key.bloomIntensity) }
    }

    @Published var portraitStopIndex: Double {
        didSet { UserDefaults.standard.set(portraitStopIndex, forKey: Key.portraitStopIndex) }
    }

    var portraitAperture: Double {
        pow(2, portraitStopIndex / 2)
    }

    var portraitApertureLabel: String {
        String(format: portraitAperture >= 8 ? "f/%.0f" : "f/%.1f", portraitAperture)
    }

    // 0 at f/16, 1 at f/1.4. Both the preview blur radius and the capture's inputAperture
    // derive from this one value so they cannot drift apart.
    var portraitBlurAmount: Float {
        let span = Constants.Portrait.stopIndexMax - Constants.Portrait.stopIndexMin
        return Float((Constants.Portrait.stopIndexMax - portraitStopIndex) / span)
    }

    init() {
        let defaults = UserDefaults.standard
        showLevel = defaults.bool(forKey: Key.level)
        showGrid = defaults.bool(forKey: Key.grid)
        showCenterCross = defaults.bool(forKey: Key.centerCross)
        aspectRatio = defaults.string(forKey: Key.aspectRatio)
            .flatMap(PreviewAspectRatio.init(rawValue:)) ?? .fourThree
        photoFormat = defaults.string(forKey: Key.photoFormat)
            .flatMap(PhotoFormat.init(rawValue:)) ?? .jpeg
        bloomIntensity = defaults.double(forKey: Key.bloomIntensity)
        // An unset double reads back as 0, which is a valid bloom intensity but would mean f/1.0 here.
        let storedStopIndex = defaults.double(forKey: Key.portraitStopIndex)
        portraitStopIndex = storedStopIndex == 0 ? Constants.Portrait.defaultStopIndex : storedStopIndex
    }
}
