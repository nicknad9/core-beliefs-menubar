import AppKit
import CorePrinciplesLib

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let llmBinaryPathKey = "llmBinaryPath"
    static let llmModelKey = "llmModel"
    static let defaultModel = "gpt-5"

    private var statusItem: NSStatusItem!
    private var dataService: DataService?
    private var scheduler: DailyQuestionScheduler?
    private var popoverController: MorningPopoverController?
    private var windowController: PrinciplesWindowController?
    private var rightClickMenu: NSMenu!

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

        let binaryPath: String
        do {
            binaryPath = try LLMPathResolver().resolve()
            UserDefaults.standard.set(binaryPath, forKey: Self.llmBinaryPathKey)
        } catch {
            showFatalAlert(
                title: "Install the llm CLI",
                message: """
                Core Principles needs the `llm` CLI to generate daily questions.

                1. Install:  brew install llm
                2. Set key:  llm keys set openai
                3. Quit and reopen Core Principles.
                """)
            return
        }

        let model = UserDefaults.standard.string(forKey: Self.llmModelKey) ?? Self.defaultModel
        let generator = LLMQuestionGenerator(binaryPath: binaryPath, model: model)
        let scheduler = DailyQuestionScheduler(dataService: service, generator: generator)
        self.scheduler = scheduler

        let popoverController = MorningPopoverController(dataService: service, scheduler: scheduler)
        popoverController.onOpenPrinciples = { [weak self] in self?.openPrinciplesWindow(nil) }
        self.popoverController = popoverController

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "CP"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        rightClickMenu = NSMenu()
        let principlesItem = NSMenuItem(
            title: "Principles…",
            action: #selector(openPrinciplesWindow(_:)),
            keyEquivalent: "")
        principlesItem.target = self
        rightClickMenu.addItem(principlesItem)
        rightClickMenu.addItem(NSMenuItem.separator())
        rightClickMenu.addItem(NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"))
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            statusItem.menu = rightClickMenu
            button.performClick(nil)
            statusItem.menu = nil
        } else {
            popoverController?.toggle(relativeTo: button)
        }
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
