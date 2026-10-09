import SwiftUI
import AppKit
import TransCore

/// Opens the standard macOS share menu (AirDrop, Messages, Mail, Notes, …) under a round button.
struct ShareButton: View {
    /// Text to share, read at the moment of the click.
    let text: () -> String
    /// Subject for services that support one (Mail).
    let subject: String
    /// Runs once a service has sent the text.
    var shared: () -> Void = {}
    @State private var anchor = SharingAnchor()

    var body: some View {
        Button {
            anchor.share(text(), subject: subject, shared: shared)
        } label: {
            RoundIcon(symbol: "square.and.arrow.up", size: 30)
                .background(AnchorView(anchor: anchor.anchor))
        }
        .buttonStyle(PressStyle())
        .help(L("Поделиться"))
        .accessibilityLabel(L("Поделиться"))
    }
}

/// Shows the share menu at an AppKit view, fills in the subject for Mail and sounds once the text is sent.
final class SharingAnchor: NSObject, NSSharingServicePickerDelegate, NSSharingServiceDelegate {
    let anchor = ViewAnchor()
    private var subject = ""
    private var shared: () -> Void = {}

    func share(_ text: String, subject: String, shared: @escaping () -> Void = {}) {
        guard let view = anchor.view else { return }
        self.subject = subject
        self.shared = shared
        let picker = NSSharingServicePicker(items: [text])
        picker.delegate = self
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        service?.subject = subject
    }

    /// The anchor follows the chosen service to hear when it has sent the text.
    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker,
                              delegateFor sharingService: NSSharingService) -> NSSharingServiceDelegate? {
        self
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        let shared = self.shared
        onMain {
            shared()
            SoundEffects.play(.send)
        }
    }

    // A service shows its window (Messages, AirDrop) at the share button, where the menu was.

    func sharingService(_ sharingService: NSSharingService, sourceWindowForShareItems items: [Any],
                        sharingContentScope: UnsafeMutablePointer<NSSharingService.SharingContentScope>) -> NSWindow? {
        anchor.view?.window
    }

    func anchoringView(for sharingService: NSSharingService, showRelativeTo positioningRect: UnsafeMutablePointer<NSRect>,
                       preferredEdge: UnsafeMutablePointer<NSRectEdge>) -> NSView? {
        guard let view = anchor.view else { return nil }
        positioningRect.pointee = view.bounds
        preferredEdge.pointee = .minY
        return view
    }
}
