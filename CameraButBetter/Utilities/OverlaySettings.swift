import SwiftUI

final class OverlaySettings: ObservableObject {
    private enum Key {
        static let level = "overlay.level"
        static let grid = "overlay.grid"
        static let centerCross = "overlay.centerCross"
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

    init() {
        let defaults = UserDefaults.standard
        showLevel = defaults.bool(forKey: Key.level)
        showGrid = defaults.bool(forKey: Key.grid)
        showCenterCross = defaults.bool(forKey: Key.centerCross)
    }
}
