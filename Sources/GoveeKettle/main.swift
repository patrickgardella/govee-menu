import AppKit
import Foundation

// Manual app bootstrap for an SPM-built menu bar agent.
// (No bundle needed; produces a background menu bar utility.)

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        switch KettleAPI.loadConfig() {
        case .success(let config):
            let controller = MenuBarController(api: KettleAPI(config: config))
            controller.start()
            menuBarController = controller
        case .failure(let error):
            let alert = NSAlert()
            alert.messageText = "Govee Kettle configuration error"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Quit")
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
