import Cocoa

// Must retain the controller for the app lifetime. Discarding it (`_ = …`) leaves a
// zombie NSStatusItem in the menu bar that ignores clicks and never animates.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = StatusController()
app.run()
