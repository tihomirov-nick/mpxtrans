import SwiftUI
import AppKit
import TransCore

/// Opens the standard macOS share menu (AirDrop, Messages, Mail, Notes, …) under the button.
struct ShareButton: View {
    /// Text to share, read at the moment of the click.
    let text: () -> String
    /// Subject for services that support one (Mail).
    let subject: String
    @State private var anchor = SharingAnchor()

    var body: some View {
        Button {
            anchor.share(text(), subject: subject)
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 14, weight: .medium))
                .frame(width: 20, height: 20)
        }
        .background(AnchorView(anchor: anchor.anchor))
        .help(L("Поделиться"))
        .accessibilityLabel(L("Поделиться"))
    }
}

/// Shows the share menu at an AppKit view and fills in the subject for Mail.
final class SharingAnchor: NSObject, NSSharingServicePickerDelegate {
    let anchor = ViewAnchor()
    private var subject = ""

    func share(_ text: String, subject: String) {
        guard let view = anchor.view else { return }
        self.subject = subject
        let picker = NSSharingServicePicker(items: [text])
        picker.delegate = self
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        service?.subject = subject
    }
}

/// Weak reference to an AppKit view placed behind a SwiftUI control (to attach menus to it).
final class ViewAnchor {
    weak var view: NSView?
}

struct AnchorView: NSViewRepresentable {
    let anchor: ViewAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        anchor.view = view
    }
}
