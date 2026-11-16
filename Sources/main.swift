// SendKey for Claude — a tiny menu bar helper for the Claude desktop app.
//
//   Enter                -> new line  (Claude receives it as Shift+Enter)
//   ⌘+Enter (default)    -> send      (Claude receives it as plain Enter)
//   or, if you pick it:
//   Shift+Enter          -> send, and ⌘+Enter is left to Claude
//
// What this program does, and nothing more:
//   * It waits, doing nothing, until the Claude app is opened.
//   * While Claude is running (and a swap is chosen, not "Enter to send") it holds
//     a keyboard hook (macOS calls it an "event tap"). The hook only asks one
//     question about each key press: "is this the Return/Enter key, and is Claude
//     in front?" The rules are in Sources/KeyMap.swift.
//   * When Claude quits, the hook and the menu bar item are removed.
//
// It never stores, prints or sends any key. There is no network code.
// The only things it saves are which send key you chose (in UserDefaults).
//
// Other files: Sources/KeyMap.swift (the key rules), Sources/Icons.swift (the
// drawings), Sources/MenuRows.swift (the switch rows), tools/make_icon.swift
// (draws the app icon at build time only).

import AppKit

let claudeBundleID = "com.anthropic.claudefordesktop"
let returnKey: Int64 = 36          // the main Return key
let keypadEnterKey: Int64 = 76     // Enter on the number pad (or fn+Return)
let enabledKey = "swapEnabled"     // saved: is a swap on (false = "Enter to send")
let shortcutKey = "sendShortcut"   // saved: which swap ("cmd" or "shift")
let accessibilityPane = URL(string:
    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

final class Helper: NSObject, NSMenuDelegate {
    var claudeRunning = false
    var askedForPermission = false     // show the macOS permission prompt only once per run
    var tap: CFMachPort?               // the keyboard hook; nil = no keyboard access at all
    var tapSource: CFRunLoopSource?
    var retryTimer: Timer?             // runs only while we wait for the permission
    var statusItem: NSStatusItem?      // the menu bar item, made once, shown only while Claude is open
    var cmdRow: SwitchRow!             // "⌘ Command + Enter to send" switch
    var shiftRow: SwitchRow!           // "⇧ Shift + Enter to send" switch
    var enterRow: SwitchRow!           // "Enter to send" switch (only one of the three is on)
    var accessRow: InfoRow!            // Accessibility: Granted / Not granted

    /// Is a swap on? Remembered between launches.
    /// false = "Enter to send": Claude's normal keys, no keyboard hook at all.
    var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Which swap: ⌘ + Enter (default) or Shift + Enter. Remembered between launches,
    /// also while "Enter to send" is on, so turning a swap back on brings back your choice.
    var shortcut: SendShortcut {
        get { SendShortcut(rawValue: UserDefaults.standard.string(forKey: shortcutKey) ?? "") ?? .cmd }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: shortcutKey) }
    }

    // MARK: - Watching for Claude

    func start() {
        UserDefaults.standard.register(defaults: [enabledKey: true,      // a swap is on by default
                                                  shortcutKey: "cmd"])    // ⌘ + Enter by default
        // Ask macOS to tell us when any app opens or quits. This is not keyboard access.
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(self, selector: #selector(appOpenedOrQuit(_:)), name: name, object: nil)
        }
        // The menu bar item is made once, here, and then only shown or hidden.
        // (Removing it and making a new one each time Claude opens made macOS
        // sometimes give the new one zero width, so it was invisible.)
        createMenuBarItem()
        // Claude may already be open when we start.
        claudeRunning = !NSRunningApplication
            .runningApplications(withBundleIdentifier: claudeBundleID).isEmpty
        refresh()
    }

    @objc func appOpenedOrQuit(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == claudeBundleID else { return }   // ignore every other app
        let quit = note.name == NSWorkspace.didTerminateApplicationNotification
        claudeRunning = NSRunningApplication
            .runningApplications(withBundleIdentifier: claudeBundleID)
            .contains { !$0.isTerminated && !(quit && $0 == app) }
        refresh()
        // Claude adds its own menu bar icon while it starts. Check ours again a
        // little later, once the menu bar has settled.
        if !quit {
            for delay in [1.5, 4.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.refresh()
                    self?.fixInvisibleMenuBarItem()
                }
            }
        }
    }

    /// The single place that decides what should exist right now:
    /// the keyboard hook, the retry timer and the menu bar item.
    @objc func refresh() {
        let trusted = AXIsProcessTrusted()   // has the user granted Accessibility?

        // First time Claude is open without the permission: let macOS show its prompt.
        if claudeRunning && !trusted && !askedForPermission {
            askedForPermission = true
            let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
        }

        // Keyboard hook: only while Claude runs, a swap is on, and we are allowed.
        if claudeRunning && enabled && trusted { startTap() } else { stopTap() }

        // If the hook should exist but does not (permission missing), check again every 2 s.
        let waiting = claudeRunning && enabled && tap == nil
        if waiting && retryTimer == nil {
            retryTimer = Timer.scheduledTimer(timeInterval: 2, target: self,
                selector: #selector(refresh), userInfo: nil, repeats: true)
        } else if !waiting {
            retryTimer?.invalidate()
            retryTimer = nil
        }

        if claudeRunning { showMenuBarItem(trusted: trusted) } else { removeMenuBarItem() }
    }

    // MARK: - The keyboard hook

    func startTap() {
        guard tap == nil else { return }
        // We ask only for key-down and key-up events. No mouse, no text content.
        let keys = CGEventMask(1 << CGEventType.keyDown.rawValue | 1 << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, me in
            Unmanaged<Helper>.fromOpaque(me!).takeUnretainedValue().handle(type, event)
        }
        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: keys, callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            NSLog("SendKey: macOS refused the keyboard hook (permission problem)")
            return
        }
        tap = newTap
        tapSource = CFMachPortCreateRunLoopSource(nil, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), tapSource, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        NSLog("SendKey: keyboard hook started")
    }

    func stopTap() {
        guard let oldTap = tap else { return }
        CGEvent.tapEnable(tap: oldTap, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes)
        CFMachPortInvalidate(oldTap)      // the hook is now completely gone
        tap = nil
        tapSource = nil
        NSLog("SendKey: keyboard hook removed")
    }

    /// Called by macOS for every key event while the hook exists.
    /// Returns the event, changed or not. Nothing is kept.
    func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let untouched = Unmanaged.passUnretained(event)

        // macOS can switch a hook off by itself. Switch it back on, unless the
        // permission was taken away: then remove the hook properly.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if AXIsProcessTrusted(), let tap = tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            } else {
                DispatchQueue.main.async { self.refresh() }
            }
            return untouched
        }

        // Any key that is not Return/Enter passes straight through.
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        guard key == returnKey || key == keypadEnterKey else { return untouched }
        // Only when Claude is the app in front. Other apps are never changed.
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == claudeBundleID
        else { return untouched }

        // Change the modifier keys as the chosen shortcut says (see KeyMap.swift).
        if let newFlags = remap(event.flags, for: shortcut) {
            event.flags = newFlags
        }
        return untouched
    }

    // MARK: - Menu bar

    /// Makes the menu bar item and its menu once, hidden. showMenuBarItem and
    /// removeMenuBarItem only switch it on and off after that.
    func createMenuBarItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "SendKeyItem"
        item.isVisible = false
        item.button?.toolTip = "SendKey for Claude"

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        // "Send key" header (small grey title).
        let header: NSMenuItem
        if #available(macOS 14.0, *) {
            header = NSMenuItem.sectionHeader(title: "Send key")
        } else {
            header = NSMenuItem(title: "Send key", action: nil, keyEquivalent: "")
            header.isEnabled = false
        }

        // Three switches, only one is on: turning one on turns the others off.
        // Turning the active one off falls back to "Enter to send"; turning
        // "Enter to send" off brings back the last swap you used.
        cmdRow = SwitchRow(icon: Icons.glyph(.command, bold: true), italic: "⌘ Command + Enter", rest: " to send",
                           subtitle: "Enter adds a new line") { [weak self] on in
            self?.choose(on ? .cmd : nil) }
        shiftRow = SwitchRow(icon: Icons.glyph(.shift, bold: true), italic: "⇧ Shift + Enter", rest: " to send",
                             subtitle: "Enter adds a new line · ⌘ + Enter untouched") { [weak self] on in
            self?.choose(on ? .shift : nil) }
        enterRow = SwitchRow(icon: Icons.enterArrow(), italic: "Enter", rest: " to send",
                             subtitle: "Claude's normal keys") { [weak self] on in
            guard let self = self else { return }
            self.choose(on ? nil : self.shortcut) }
        accessRow = InfoRow(icon: Icons.symbol("accessibility"), label: "Accessibility")

        let settings = NSMenuItem(title: "Open Accessibility Settings…",
                                  action: #selector(openSettings), keyEquivalent: "")
        settings.image = Icons.symbol("gearshape")
        let quit = NSMenuItem(title: "Quit SendKey for Claude",
                              action: #selector(quitHelper), keyEquivalent: "q")
        quit.image = Icons.symbol("power")
        settings.target = self
        quit.target = self

        let rows = [header, viewItem(cmdRow), viewItem(shiftRow), viewItem(enterRow), .separator(),
                    viewItem(accessRow), settings, .separator(), quit]
        rows.forEach { menu.addItem($0) }
        item.menu = menu
        statusItem = item
    }

    private func viewItem(_ view: NSView) -> NSMenuItem {
        let menuItem = NSMenuItem()
        menuItem.view = view
        return menuItem
    }

    /// Updates the menu bar icon and the menu to match the current state.
    func showMenuBarItem(trusted: Bool) {
        createMenuBarItem()
        let working = tap != nil
        let broken = enabled && trusted && !working       // permission on, but macOS refused the hook
        // Icon: star in the arrow. Dimmed in "Enter to send" mode.
        // A small "!" in the star's centre while the permission is missing or not working.
        // 22 points: about as tall as Claude's own menu bar icon.
        statusItem?.button?.image = Icons.glyph(.star, warning: !trusted || broken, size: 22)
        statusItem?.button?.appearsDisabled = !enabled

        cmdRow.isOn = enabled && shortcut == .cmd
        shiftRow.isOn = enabled && shortcut == .shift
        enterRow.isOn = !enabled
        accessRow.iconView.image = Icons.symbol("accessibility")
        accessRow.iconView.contentTintColor = (trusted && !broken) ? .systemGreen : .tertiaryLabelColor
        accessRow.statusField.stringValue = !trusted ? "Not granted"
            : (broken ? "Not working: remove and add it again" : "Granted")

        if statusItem?.isVisible == false { statusItem?.isVisible = true }
    }

    /// Hides the item (it is not deleted, so it comes back reliably).
    func removeMenuBarItem() {
        if statusItem?.isVisible == true { statusItem?.isVisible = false }
    }

    /// If macOS shows the item with zero width (invisible), hide and show it again.
    func fixInvisibleMenuBarItem() {
        guard claudeRunning, let item = statusItem, item.isVisible,
              (item.button?.window?.frame.width ?? 0) < 1 else { return }
        NSLog("SendKey: menu bar item had zero width, showing it again")
        item.isVisible = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { item.isVisible = true }
    }

    /// Refresh the texts each time the menu is opened (the permission may have changed).
    func menuNeedsUpdate(_ menu: NSMenu) { refresh() }

    /// Pick the send key: .cmd, .shift, or nil for "Enter to send" (no swap).
    func choose(_ choice: SendShortcut?) {
        if let choice = choice { shortcut = choice }
        enabled = choice != nil
        refresh()
    }
    @objc func openSettings() { NSWorkspace.shared.open(accessibilityPane) }
    @objc func quitHelper() { stopTap(); NSApp.terminate(nil) }
}

// MARK: - Program start

let app = NSApplication.shared
app.setActivationPolicy(.accessory)    // no Dock icon, no main window

// Only one copy may run: two copies would change the same key twice.
if let myID = Bundle.main.bundleIdentifier,
   NSRunningApplication.runningApplications(withBundleIdentifier: myID)
       .contains(where: { $0 != NSRunningApplication.current }) {
    exit(0)
}

let helper = Helper()
helper.start()
app.run()                              // sleep until macOS has something for us
