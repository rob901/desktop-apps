import AppKit

/// Rich-text formatting and find for a note.
extension NoteController {
    func toggleTrait(_ trait: NSFontTraitMask) {
        guard let storage = textView.textStorage else { return }
        let fm = NSFontManager.shared
        let range = textView.selectedRange()
        if range.length == 0 {
            var attrs = textView.typingAttributes
            let f = attrs[.font] as? NSFont ?? NotePrefs.font
            attrs[.font] = fm.traits(of: f).contains(trait) ? fm.convert(f, toNotHaveTrait: trait) : fm.convert(f, toHaveTrait: trait)
            textView.typingAttributes = attrs
            return
        }
        let first = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? NotePrefs.font
        let removing = fm.traits(of: first).contains(trait)
        guard textView.shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range) { value, sub, _ in
            let f = value as? NSFont ?? NotePrefs.font
            storage.addAttribute(.font, value: removing ? fm.convert(f, toNotHaveTrait: trait) : fm.convert(f, toHaveTrait: trait), range: sub)
        }
        storage.endEditing()
        textView.didChangeText()
    }

    func adjustFontSize(by delta: CGFloat) {
        guard let storage = textView.textStorage else { return }
        var range = textView.selectedRange()
        if range.length == 0 { range = NSRange(location: 0, length: storage.length) }   // whole note
        let fm = NSFontManager.shared
        if range.length > 0, textView.shouldChangeText(in: range, replacementString: nil) {
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: range) { value, sub, _ in
                let f = value as? NSFont ?? NotePrefs.font
                storage.addAttribute(.font, value: fm.convert(f, toSize: max(8, min(72, f.pointSize + delta))), range: sub)
            }
            storage.endEditing()
            textView.didChangeText()
        }
        var attrs = textView.typingAttributes
        let f = attrs[.font] as? NSFont ?? NotePrefs.font
        attrs[.font] = fm.convert(f, toSize: max(8, min(72, f.pointSize + delta)))
        textView.typingAttributes = attrs
    }

    func showFind() {
        if collapsed { window.setCollapsed(false) }
        let item = NSMenuItem()
        item.tag = NSTextFinder.Action.showFindInterface.rawValue
        textView.performTextFinderAction(item)
    }
}
