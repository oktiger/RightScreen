import Foundation
import Observation

@MainActor
@Observable
final class HotKeySettingsStore {
    private static let bindingsKey = "hotKeyBindings"
    private static let hasSavedKey = "hotKeyBindingsSaved"

    private(set) var bindings: [HotKeyAction: KeyChord]
    var onChange: (([HotKeyAction: KeyChord]) -> Void)?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.bindings = Self.load(from: defaults)
    }

    func chord(for action: HotKeyAction) -> KeyChord? {
        bindings[action]
    }

    /// 返回冲突提示；成功则返回 nil。
    @discardableResult
    func setChord(_ chord: KeyChord?, for action: HotKeyAction) -> String? {
        if let chord, let other = KeyChord.conflictingAction(for: chord, excluding: action, in: bindings) {
            return "快捷键已被「\(other.title)」占用"
        }

        if let chord {
            bindings[action] = chord
        } else {
            bindings.removeValue(forKey: action)
        }
        persist()
        onChange?(bindings)
        return nil
    }

    private func persist() {
        let payload = Dictionary(uniqueKeysWithValues: bindings.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(payload) {
            defaults.set(data, forKey: Self.bindingsKey)
        }
        defaults.set(true, forKey: Self.hasSavedKey)
    }

    private static func load(from defaults: UserDefaults) -> [HotKeyAction: KeyChord] {
        guard defaults.bool(forKey: hasSavedKey) else {
            return KeyChord.defaultBindings()
        }
        guard
            let data = defaults.data(forKey: bindingsKey),
            let decoded = try? JSONDecoder().decode([String: KeyChord].self, from: data)
        else {
            return [:]
        }

        var loaded: [HotKeyAction: KeyChord] = [:]
        for (rawValue, chord) in decoded {
            guard let action = HotKeyAction(rawValue: rawValue) else { continue }
            loaded[action] = chord
        }
        return loaded
    }
}
