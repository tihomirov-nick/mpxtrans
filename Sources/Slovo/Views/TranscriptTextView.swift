import SwiftUI
import AppKit

/// Text of the transcript: appended without jumping while recognition runs, editable afterwards,
/// with the system find bar (⌘F).
struct TranscriptTextView: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool
    /// Keep the end in view as text arrives (unless the user scrolled up to read).
    var followsEnd: Bool
    /// When it changes, the new text is shown from the top (another format). Other changes, such as another case
    /// and punctuation variant, keep the place in the text and the cursor.
    var document: AnyHashable?

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
        textView.textContainerInset = NSSize(width: 10, height: 12)
        textView.insertionPointColor = .white
        // The selection is a grey under the white text (the brand white would hide it).
        textView.selectedTextAttributes = [.backgroundColor: Brand.nsColor.withAlphaComponent(0.28)]
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
        let otherDocument = context.coordinator.document != document
        context.coordinator.document = document
        let current = textView.string
        // A letter being composed (an accent, an input method) is left alone until it is done.
        guard current != text, !textView.hasMarkedText() else { return }
        let wasAtEnd = Self.isScrolledToEnd(scrollView)
        if !current.isEmpty, text.hasPrefix(current) {
            // New phrases: append, so the view does not jump and a selection survives.
            let tail = String(text.dropFirst(current.count))
            textView.textStorage?.append(NSAttributedString(string: tail, attributes: Self.attributes))
        } else if otherDocument {
            textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: Self.attributes))
            Self.forgetUndo(textView)
            textView.scroll(.zero)
        } else {
            Self.replaceChanges(in: textView, with: text)
        }
        if followsEnd && wasAtEnd {
            textView.scrollToEndOfDocument(nil)
            // Once more after the layout pass that the new text triggers.
            DispatchQueue.main.async { textView.scrollToEndOfDocument(nil) }
        }
    }

    /// Replaces only the part that differs (the capitals and marks of another variant, a typed letter the variant
    /// changes), so the place in the text and the cursor stay.
    static func replaceChanges(in textView: NSTextView, with text: String) {
        guard let storage = textView.textStorage, let clipView = textView.enclosingScrollView?.contentView else { return }
        let old = Array(storage.string.utf16), new = Array(text.utf16)
        var prefix = 0
        while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < old.count - prefix, suffix < new.count - prefix,
              old[old.count - 1 - suffix] == new[new.count - 1 - suffix] { suffix += 1 }
        // Not between the two halves of an emoji.
        if prefix > 0, prefix < old.count, UTF16.isTrailSurrogate(old[prefix]) { prefix -= 1 }
        if suffix > 0, UTF16.isTrailSurrogate(old[old.count - suffix]) { suffix -= 1 }
        let changed = NSRange(location: prefix, length: old.count - prefix - suffix)
        let replacement = String(decoding: new[prefix..<(new.count - suffix)], as: UTF16.self)
        let insertedLength = new.count - prefix - suffix
        func moved(_ position: Int) -> Int {
            if position <= changed.location { return position }
            if position >= changed.upperBound { return position + insertedLength - changed.length }
            return changed.location + min(position - changed.location, insertedLength)
        }
        let selection = textView.selectedRange()
        let origin = clipView.bounds.origin
        storage.replaceCharacters(in: changed, with: NSAttributedString(string: replacement, attributes: attributes))
        let start = moved(selection.location)
        textView.setSelectedRange(NSRange(location: start, length: max(0, moved(selection.upperBound) - start)))
        clipView.scroll(to: origin)
        textView.enclosingScrollView?.reflectScrolledClipView(clipView)
        forgetUndo(textView)
    }

    /// Undo steps refer to the old text.
    private static func forgetUndo(_ textView: NSTextView) {
        textView.undoManager?.removeAllActions(withTarget: textView.textStorage as Any)
        textView.undoManager?.removeAllActions(withTarget: textView)
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
            .foregroundColor: NSColor.white.withAlphaComponent(0.92),
            .paragraphStyle: paragraph,
        ]
    }()

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TranscriptTextView
        var document: AnyHashable?

        init(_ parent: TranscriptTextView) {
            self.parent = parent
            document = parent.document
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            // The text may come back changed by the case and punctuation variant ("А" typed in lowercase): show it
            // right away, before the next key.
            let shown = parent.text
            if shown != textView.string, !textView.hasMarkedText() {
                TranscriptTextView.replaceChanges(in: textView, with: shown)
            }
        }
    }
}

/// A file dropped onto the text is a new recording to recognize, not text to insert: the window handles it.
final class FileDropPassingTextView: NSTextView {
    override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
        super.acceptableDragTypes.filter { $0 != .fileURL && $0 != .URL && $0.rawValue != "NSFilenamesPboardType" }
    }
}
