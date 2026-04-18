import AppKit
import CorePrinciplesLib

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let llmBinaryPathKey = "llmBinaryPath"

    private var statusItem: NSStatusItem!
    private var dataService: DataService?
    private var windowController: PrinciplesWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let service: DataService
        do {
            let appDb = try AppDatabase()
            service = DataService(dbQueue: appDb.dbQueue)
        } catch {
            showFatalAlert(
                title: "Database Error",
                message: "Could not initialize database: \(error.localizedDescription)")
            return
        }
        self.dataService = service

        do {
            let path = try LLMPathResolver().resolve()
            UserDefaults.standard.set(path, forKey: Self.llmBinaryPathKey)
        } catch {
            showFatalAlert(
                title: "Install the llm CLI",
                message: """
                Core Principles needs the `llm` CLI to generate daily questions.

                1. Install:  brew install llm
                2. Set key:  llm keys set anthropic
                3. Quit and reopen Core Principles.
                """)
            return
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "CP"

        let menu = NSMenu()
        let principlesItem = NSMenuItem(
            title: "Principles…",
            action: #selector(openPrinciplesWindow(_:)),
            keyEquivalent: "")
        principlesItem.target = self
        menu.addItem(principlesItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func openPrinciplesWindow(_ sender: Any?) {
        guard let service = dataService else { return }
        if windowController == nil {
            windowController = PrinciplesWindowController(dataService: service)
        }
        windowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showFatalAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
        NSApp.terminate(nil)
    }
}
