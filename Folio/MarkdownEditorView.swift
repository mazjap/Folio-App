import SwiftUI

enum EditorAction {
    /// Replace current selection (or insert at cursor) with literal text.
    case insertText(String)
    /// Wrap selection with prefix/suffix; insert prefix+placeholder+suffix when nothing is selected,
    /// then select the placeholder so the user can type over it immediately.
    case wrap(prefix: String, suffix: String, placeholder: String)
    /// Insert `prefix` at the start of the line the cursor is on.
    case prependLine(String)
}

// MARK: - macOS

#if os(macOS)
struct MarkdownEditorView: NSViewRepresentable {
    @Binding var text: String
    @Binding var pendingAction: EditorAction?
    var highlightRanges: [NSRange] = []

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textContainerInset = CGSize(width: 4, height: 8)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.delegate = context.coordinator

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView
        return scrollView
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        (scrollView.documentView as? NSTextView)?.delegate = nil
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self

        // Programmatic text update — suppress textDidChange to avoid a round-trip.
        if textView.string != text {
            context.coordinator.isUpdating = true
            let savedRanges = textView.selectedRanges
            textView.string = text
            let length = textView.string.utf16.count
            textView.selectedRanges = savedRanges.map {
                let r = $0.rangeValue
                let loc = min(r.location, length)
                return NSValue(range: NSRange(location: loc, length: min(r.length, length - loc)))
            }
            context.coordinator.isUpdating = false
        }

        // Clear the binding BEFORE mutating the text view so that the
        // textDidChange → updateNSView re-entry sees nil and doesn't act again.
        if let action = pendingAction {
            pendingAction = nil
            apply(action, to: textView)
        }

        // Apply diff highlights only when the set of ranges actually changed.
        if context.coordinator.lastHighlightRanges != highlightRanges {
            context.coordinator.lastHighlightRanges = highlightRanges
            applyHighlights(highlightRanges, to: textView)
        }
    }

    private func applyHighlights(_ ranges: [NSRange], to textView: NSTextView) {
        guard let lm = textView.layoutManager else { return }
        let docLen = textView.string.utf16.count
        if docLen > 0 {
            lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: docLen))
        }
        for range in ranges where range.length > 0 && range.location + range.length <= docLen {
            lm.addTemporaryAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.25), forCharacterRange: range)
        }
    }

    private func apply(_ action: EditorAction, to textView: NSTextView) {
        let nsString = textView.string as NSString
        let sel = textView.selectedRange()

        switch action {
        case .insertText(let snippet):
            textView.insertText(snippet, replacementRange: sel)

        case .wrap(let prefix, let suffix, let placeholder):
            if sel.length > 0 {
                let selected = nsString.substring(with: sel)
                textView.insertText(prefix + selected + suffix, replacementRange: sel)
            } else {
                textView.insertText(prefix + placeholder + suffix, replacementRange: sel)
                // Select placeholder so the user can type over it immediately.
                let newStart = sel.location + prefix.utf16.count
                textView.setSelectedRange(NSRange(location: newStart, length: placeholder.utf16.count))
            }

        case .prependLine(let prefix):
            let lineRange = nsString.lineRange(for: NSRange(location: sel.location, length: 0))
            // Insert at line start; NSTextView auto-shifts the cursor forward.
            textView.insertText(prefix, replacementRange: NSRange(location: lineRange.location, length: 0))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditorView
        var isUpdating = false
        var lastHighlightRanges: [NSRange] = []
        init(_ parent: MarkdownEditorView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}

// MARK: - iOS

#else
struct MarkdownEditorView: UIViewRepresentable {
    @Binding var text: String
    @Binding var pendingAction: EditorAction?
    var highlightRanges: [NSRange] = []

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.font = .monospacedSystemFont(ofSize: UIFont.systemFontSize, weight: .regular)
        tv.backgroundColor = .clear
        tv.autocorrectionType = .no
        tv.autocapitalizationType = .none
        tv.delegate = context.coordinator
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        if tv.text != text {
            context.coordinator.isUpdating = true
            let sel = tv.selectedRange
            tv.text = text
            if sel.location <= tv.text.utf16.count { tv.selectedRange = sel }
            context.coordinator.isUpdating = false
        }

        if let action = pendingAction {
            pendingAction = nil
            apply(action, to: tv)
        }
    }

    private func apply(_ action: EditorAction, to tv: UITextView) {
        let nsString = tv.text as NSString
        let sel = tv.selectedRange

        switch action {
        case .insertText(let snippet):
            tv.insertText(snippet)

        case .wrap(let prefix, let suffix, let placeholder):
            if sel.length > 0 {
                let selected = nsString.substring(with: sel)
                // Move cursor to selection end first so insertText replaces it.
                tv.insertText(prefix + selected + suffix)
            } else {
                tv.insertText(prefix + placeholder + suffix)
                // Select placeholder.
                let newStart = sel.location + prefix.utf16.count
                tv.selectedRange = NSRange(location: newStart, length: placeholder.utf16.count)
            }

        case .prependLine(let prefix):
            let lineRange = nsString.lineRange(for: NSRange(location: sel.location, length: 0))
            tv.selectedRange = NSRange(location: lineRange.location, length: 0)
            tv.insertText(prefix)
            // Restore original cursor offset by prefix length.
            tv.selectedRange = NSRange(location: sel.location + prefix.utf16.count, length: sel.length)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: MarkdownEditorView
        var isUpdating = false
        init(_ parent: MarkdownEditorView) { self.parent = parent }

        func textViewDidChange(_ tv: UITextView) {
            guard !isUpdating else { return }
            parent.text = tv.text
        }
    }
}
#endif
