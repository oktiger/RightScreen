import AppKit
import SwiftUI

@MainActor
@Observable
final class HotKeyRecorder {
    var recordingAction: HotKeyAction?
    var conflictMessage: String?

    private var monitor: Any?
    private let store: HotKeySettingsStore
    private let onRecordingChange: (Bool) -> Void

    init(store: HotKeySettingsStore, onRecordingChange: @escaping (Bool) -> Void) {
        self.store = store
        self.onRecordingChange = onRecordingChange
    }

    func begin(_ action: HotKeyAction) {
        cancel()
        conflictMessage = nil
        recordingAction = action
        onRecordingChange(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handle(event)
            }
            return nil
        }
    }

    func cancel() {
        finish(save: .cancel)
    }

    func stop() {
        finish(save: .cancel)
    }

    func clear(_ action: HotKeyAction) {
        if recordingAction == action {
            finish(save: .clear)
            return
        }
        conflictMessage = nil
        _ = store.setChord(nil, for: action)
    }

    private enum RecordingResult {
        case chord(KeyChord)
        case clear
        case cancel
    }

    private func handle(_ event: NSEvent) {
        guard let chord = KeyChord(event: event) else { return }
        if chord.isEscape {
            finish(save: .cancel)
            return
        }
        if chord.isClearKey {
            finish(save: .clear)
            return
        }
        guard chord.hasModifier else { return }
        finish(save: .chord(chord))
    }

    private func finish(save result: RecordingResult) {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

        let action = recordingAction
        let wasRecording = action != nil
        recordingAction = nil
        if wasRecording {
            onRecordingChange(false)
        }

        guard let action else { return }
        switch result {
        case .cancel:
            break
        case .clear:
            conflictMessage = nil
            _ = store.setChord(nil, for: action)
        case .chord(let chord):
            if let message = store.setChord(chord, for: action) {
                conflictMessage = message
            } else {
                conflictMessage = nil
            }
        }
    }
}

struct HotKeySettingsView: View {
    @Bindable var store: HotKeySettingsStore
    @Bindable var recorder: HotKeyRecorder

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(HotKeySettingsSection.allCases, id: \.self) { section in
                VStack(alignment: .leading, spacing: 12) {
                    Text(section.title)
                        .font(.headline)

                    ForEach(section.actions, id: \.self) { action in
                        HotKeyBindingRow(
                            action: action,
                            chord: store.chord(for: action),
                            isRecording: recorder.recordingAction == action,
                            onRecord: { recorder.begin(action) },
                            onCancel: { recorder.cancel() },
                            onClear: { recorder.clear(action) }
                        )
                    }

                    if let footer = section.footer {
                        Text(footer)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let conflictMessage = recorder.conflictMessage {
                Text(conflictMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(20)
        .frame(minWidth: 420, alignment: .leading)
        .onDisappear {
            recorder.stop()
        }
    }
}

private struct HotKeyBindingRow: View {
    let action: HotKeyAction
    let chord: KeyChord?
    let isRecording: Bool
    let onRecord: () -> Void
    let onCancel: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack {
            Text(action.title)
                .frame(width: 88, alignment: .leading)

            Text(isRecording ? "按下快捷键…" : (chord?.displayString ?? "未设置"))
                .font(.body.monospaced())
                .foregroundStyle(isRecording ? Color.accentColor : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if chord != nil, !isRecording {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("移除快捷键")
                .accessibilityLabel("移除快捷键")
            }

            Button(isRecording ? "取消" : "设置") {
                if isRecording {
                    onCancel()
                } else {
                    onRecord()
                }
            }
            .frame(width: 56)
        }
        .padding(.vertical, 4)
    }
}
