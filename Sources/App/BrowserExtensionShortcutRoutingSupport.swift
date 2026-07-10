import AppKit

/// Whether the responder chain passes through a browser web view, so
/// web-extension shortcut commands (e.g. Bitwarden autofill) may claim the event.
func cmuxRespondersContainBrowserWebView(_ responder: NSResponder?) -> Bool {
    var current: NSResponder? = responder
    while let next = current {
        if next is CmuxWebView { return true }
        if let view = next as? NSView {
            var ancestor: NSView? = view.superview
            while let candidate = ancestor {
                if candidate is CmuxWebView { return true }
                ancestor = candidate.superview
            }
        }
        current = next.nextResponder
    }
    return false
}
