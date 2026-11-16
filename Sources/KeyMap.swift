// The key rules, kept apart from everything else so they are easy to read and test.

import CoreGraphics

/// Which key combination sends the message while the swap is on.
enum SendShortcut: String {
    case cmd     // ⌘ + Enter sends (default)
    case shift   // ⇧ Shift + Enter sends; ⌘ + Enter is left to Claude
}

/// What a Return/Enter press in Claude should become.
/// Returns the new modifier flags, or nil to leave the key exactly as it is.
///
///   ⌘ mode:      Enter -> Shift+Enter (new line)    ⌘+Enter -> Enter (send)
///   Shift mode:  Enter -> Shift+Enter (new line)    Shift+Enter -> Enter (send)
///                ⌘+Enter is not touched, so Claude gets its own ⌘+Enter.
/// Any other combination (Ctrl, Option, two modifiers…) is never changed.
func remap(_ flags: CGEventFlags, for shortcut: SendShortcut) -> CGEventFlags? {
    let modifiers = flags.intersection([.maskShift, .maskControl, .maskAlternate, .maskCommand])
    var changed = flags
    switch (shortcut, modifiers) {
    case (_, []):
        changed.insert(.maskShift)            // Enter -> new line
    case (.cmd, .maskCommand):
        changed.remove(.maskCommand)          // ⌘+Enter -> send
    case (.shift, .maskShift):
        changed.remove(.maskShift)            // Shift+Enter -> send
    default:
        return nil                            // everything else passes untouched
    }
    return changed
}
