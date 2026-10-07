import SwiftUI
import AppKit

/// Text of the transcript: appended without jumping while recognition runs, editable afterwards,
/// with the system find bar (⌘F).
struct TranscriptTextView: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool
    /// Keep the end in view as text arrives (unless the user scrolled up to read).
    var followsEnd: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        // TextKit 1: the view's height follows the text right away, so scrolling to the end is exact.
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        let textView = FileDropPassingTextView(frame: .zero, textContainer: container)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.typingAttributes = Self.attributes
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: Self.attributes))

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.isEditable != isEditable {
            textView.isEditable = isEditable
            textView.updateDragTypeRegistration()
        }
        let current = textView.string
        guard current != text else { return }
        let wasAtEnd = Self.isScrolledToEnd(scrollView)
        if !current.isEmpty, text.hasPrefix(current) {
            // New phrases: append, so the view does not jump and a selection survives.
            let tail = String(text.dropFirst(current.count))
            textView.textStorage?.append(NSAttributedString(string: tail, attributes: Self.attributes))
        } else {
            textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: Self.attributes))
            // Undo steps refer to the old text.
            textView.undoManager?.removeAllActions(withTarget: textView.textStorage as Any)
            textView.undoManager?.removeAllActions(withTarget: textView)
            textView.scroll(.zero)
        }
        if followsEnd && wasAtEnd {
            textView.scrollToEndOfDocument(nil)
            // Once more after the layout pass that the new text triggers.
            DispatchQueue.main.async { textView.scrollToEndOfDocument(nil) }
        }
    }

    static func isScrolledToEnd(_ scrollView: NSScrollView) -> Bool {
        guard let document = scrollView.documentView else { return true }
        let visible = scrollView.contentView.documentVisibleRect
        return visible.maxY >= document.bounds.height - 40
    }

    static let attributes: [NSAttributedString.Key: Any] = {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = 2
        return [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
    }()

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TranscriptTextView

        init(_ parent: TranscriptTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

/// A file dropped onto the text is a new recording to recognize, not text to insert: the window handles it.
final class FileDropPassingTextView: NSTextView {
    override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
        super.acceptableDragTypes.filter { $0 != .fileURL && $0 != .URL && $0.rawValue != "NSFilenamesPboardType" }
    }
}
