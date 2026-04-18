import AppKit
import CorePrinciplesLib

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var dataService: DataService?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let appDb = try AppDatabase()
            dataService = DataService(dbQueue: appDb.dbQueue)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Database Error"
            alert.informativeText = "Could not initialize database: \(error.localizedDescription)"
            alert.runModal()
            NSApplication.shared.terminate(nil)
            return
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "CP"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
