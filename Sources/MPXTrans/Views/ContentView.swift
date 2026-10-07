import SwiftUI
import UniformTypeIdentifiers
import TransCore

/// The small window: drop zone → progress with live text → transcript with copy, save and share.
struct ContentView: View {
    @EnvironmentObject var transcriber: Transcriber
    @EnvironmentObject var modelStore: ModelStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var debug = DebugHooks.State.shared
    @State private var dragTargeted = false

    private var dropTargeted: Bool { dragTargeted || debug.dropTargeted }

    var body: some View {
        ZStack {
            switch transcriber.phase {
            case .idle:
                IdleView(isTargeted: dropTargeted)
                    .transition(phaseTransition)
            case .working:
                WorkingView()
                    .transition(phaseTransition)
            case .done:
                ResultView()
                    .transition(phaseTransition)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Backdrop())
        .overlay {
            if dropTargeted && transcriber.phase != .idle {
                DropOverlay()
                    .transition(.opacity)
            }
        }
        .animation(Motion.animation(Motion.standard, reduceMotion: reduceMotion), value: transcriber.phase)
        .animation(Motion.animation(Motion.quick, reduceMotion: reduceMotion), value: dropTargeted)
        .onDrop(of: [.fileURL], isTargeted: $dragTargeted) { providers in
            handleDrop(providers)
        }
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
        .onChange(of: modelStore.installed) { _ in
            transcriber.ensureValidModelSelection()
        }
        .onAppear {
            if !modelStore.hasAnyModel { openWindow(id: "models") }
        }
    }

    private var phaseTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97))
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }
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
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            Label(L("Отпустите, чтобы распознать"), systemImage: "waveform")
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .glassSurface(in: Capsule())
        }
        .padding(8)
        .allowsHitTesting(false)
    }
}

/// File icon, name and details in a glass capsule; buttons on the right.
struct FileHeader<Trailing: View>: View {
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
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            trailing
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 7)
        .glassSurface(in: Capsule())
    }
}
