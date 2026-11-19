import Foundation


/// The welcome window's steps, in order.
public enum OnboardingStep: Int, CaseIterable, Sendable {
    case welcome, permission, connect, menu, tryIt
}

/// What the app knows right now; each step ticks off when its part is true.
public struct OnboardingStatus: Equatable, Sendable {
    public var permission = false
    public var scriptInstalled = false
    public var connected = false
    public var panelOpened = false
    public var menuChosen = false

    public init() {}

    public func isDone(_ step: OnboardingStep) -> Bool {
        switch step {
        case .welcome: return true
        case .permission: return permission
        case .connect: return connected
        case .menu: return menuChosen
        case .tryIt: return panelOpened
        }
    }
}

public enum Onboarding {
    /// Only for new users: no config file when the app started, and not finished or skipped before.
    public static func showOnLaunch(configExisted: Bool, done: Bool) -> Bool {
        !configExisted && !done
    }
}

/// Live's own devices offered as a first menu.
public enum StarterSet {
    public static let effects = ["EQ Eight", "Compressor", "Glue Compressor", "Reverb", "Delay", "Utility", "Saturator", "Limiter"]
    public static let instruments = ["Drift", "Operator", "Simpler", "Drum Rack"]
}

public extension LauncherConfig {
    /// Adds the starter devices that exist in this Live (effects → "Effects", instruments → "Instruments");
    /// returns how many were new.
    @discardableResult
    mutating func addStarterSet(from items: [PluginItem]) -> Int {
        let effectsID = (categories.first { $0.name == "Effects" } ?? categories.last { !$0.isFavorites })?.id
        let instrumentsID = (categories.first { $0.name == "Instruments" } ?? categories.first { !$0.isFavorites })?.id
        var added = 0
        func add(_ names: [String], source: ItemSource, to id: UUID?) {
            guard let id else { return }
            for name in names {
                guard let item = items.first(where: { $0.source == source && $0.name == name }) else { continue }
                let before = categories.first { $0.id == id }?.entries.count ?? 0
                addEntry(item, to: id)
                if (categories.first { $0.id == id }?.entries.count ?? 0) > before { added += 1 }
            }
        }
        add(StarterSet.effects, source: .audioEffects, to: effectsID)
        add(StarterSet.instruments, source: .instruments, to: instrumentsID)
        return added
    }
}
