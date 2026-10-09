import SwiftUI
import UniformTypeIdentifiers
import TransCore

/// The small window: drop zone and settings tiles, then progress with live text, then the transcript with copy,
/// save and share. Each stage replaces the previous one out of a blur. A new version of Slovo is offered above every
/// stage but a running transcription.
struct ContentView: View {
    @EnvironmentObject var transcriber: Transcriber
    @EnvironmentObject var modelStore: ModelStore
    @EnvironmentObject var updater: Updater
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var debug = DebugHooks.State.shared
    @State private var dragTargeted = false

    private var dropTargeted: Bool { dragTargeted || debug.dropTargeted }

    var body: some View {
        VStack(spacing: Layout.spacing) {
            if showsUpdate {
                UpdateCard()
                    .transition(.blurAppear(reduceMotion: reduceMotion))
            }
            ZStack {
                switch transcriber.phase {
                case .idle:
                    IdleView(isTargeted: dropTargeted)
                        .transition(.blurAppear(reduceMotion: reduceMotion))
                case .working:
                    WorkingView()
                        .transition(.blurAppear(reduceMotion: reduceMotion))
                case .done:
                    ResultView()
                        .transition(.blurAppear(reduceMotion: reduceMotion))
                }
            }
        }
        .padding([.horizontal, .bottom], Layout.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay {
            if dropTargeted && transcriber.phase != .idle {
                DropOverlay()
                    .transition(.opacity)
            }
        }
        .blackWindow()
        .animation(Motion.animation(Motion.spring, reduceMotion: reduceMotion), value: transcriber.phase)
        .animation(Motion.animation(Motion.spring, reduceMotion: reduceMotion), value: showsUpdate)
        .animation(Motion.animation(Motion.quick, reduceMotion: reduceMotion), value: dropTargeted)
        .onDrop(of: [.fileURL], delegate: FileDrop(transcriber: transcriber, isTargeted: $dragTargeted))
        .alert(L("Не получилось"), isPresented: Binding(
            get: { transcriber.errorMessage != nil },
            set: { if !$0 { transcriber.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(transcriber.errorMessage ?? "")
        }
        .onChange(of: transcriber.modelManagerRequested) { requested in
            guard requested else { return }
            transcriber.modelManagerRequested = false
            openWindow(id: "models")
        }
        .onChange(of: debug.openWindow) { id in
            guard let id else { return }
            debug.openWindow = nil
            openWindow(id: id)
        }
        .onChange(of: modelStore.installed) { _ in
            transcriber.ensureValidModelSelection()
        }
        .onChange(of: updater.freshOffer) { _ in noteOffer() }
        .onChange(of: transcriber.phase) { _ in noteOffer() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in noteOffer() }
        .onAppear {
            // In the background the models window waits for the main one (`MainWindow.show`).
            if !modelStore.hasAnyModel && !MainWindow.inBackground { openWindow(id: "models") }
        }
    }

    /// A new version, its download and installation, a failed update: on the card above every stage but a transcription.
    private var showsUpdate: Bool {
        guard transcriber.phase != .working else { return false }
        switch updater.state {
        case .available, .downloading, .installing, .failed(_, .some): return true
        default: return false
        }
    }

    /// A version an automatic check has found is on the card (its state is `.available`) as soon as the window is in
    /// sight and no transcription runs: that is when it counts as shown.
    private func noteOffer() {
        guard updater.freshOffer != nil, transcriber.phase != .working, !MainWindow.inBackground,
              MainWindow.window?.isVisible == true else { return }
        updater.offerShown()
    }
}

/// A file dragged onto the window. While an update is being installed it is refused, and macOS shows the usual
/// refusal: a "not allowed" pointer and the file sliding back.
private struct FileDrop: DropDelegate {
    let transcriber: Transcriber
    @Binding var isTargeted: Bool

    func validateDrop(info: DropInfo) -> Bool {
        !transcriber.isUpdating && info.hasItemsConforming(to: [.fileURL])
    }

    func dropEntered(info: DropInfo) {
        isTargeted = validateDrop(info: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: validateDrop(info: info) ? .copy : .forbidden)
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        guard validateDrop(info: info), let provider = info.itemProviders(for: [.fileURL]).first else { return false }
        let transcriber = self.transcriber
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            onMain { transcriber.open(url) }
        }
        return true
    }
}

/// Shown over the transcript while a new file is dragged in.
private struct DropOverlay: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.72))
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Brand.color, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            Label(L("Отпустите, чтобы распознать"), systemImage: "waveform")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Brand.ink)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Capsule().fill(Brand.color))
        }
        .padding(8)
        .allowsHitTesting(false)
    }
}

/// The file: its icon, name and details on one line each, buttons on the right.
struct FileRow<Trailing: View>: View {
    let url: URL
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .interpolation(.high)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)
                    .help(subtitle)
            }
            Spacer(minLength: 6)
            HStack(spacing: 6) { trailing }
        }
        .padding(.leading, 10)
        .padding(.trailing, 10)
        .frame(height: 52)
    }
}
