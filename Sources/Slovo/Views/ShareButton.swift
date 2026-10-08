import SwiftUI
import AppKit
import TransCore

/// Opens the standard macOS share menu (AirDrop, Messages, Mail, Notes, …) under a round button.
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
            RoundIcon(symbol: "square.and.arrow.up", size: 30)
                .background(AnchorView(anchor: anchor.anchor))
        }
        .buttonStyle(PressStyle())
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
