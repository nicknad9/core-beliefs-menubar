import AppKit
import CorePrinciplesLib

final class PrinciplesWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let dataService: DataService
    private var principles: [Principle] = []
    private var filter: PrincipleState? = .active

    private var tableView: NSTableView!
    private var filterControl: NSSegmentedControl!
    private var archiveButton: NSButton!
    private var editButton: NSButton!

    private var editSheetController: PrincipleEditSheetController?

    init(dataService: DataService) {
        self.dataService = dataService

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false)
        window.title = "Principles"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        buildUI()
        reload()
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        filterControl = NSSegmentedControl(
            labels: ["Active", "Archived", "All"],
            trackingMode: .selectOne,
            target: self,
            action: #selector(filterChanged))
        filterControl.translatesAutoresizingMaskIntoConstraints = false
        filterControl.selectedSegment = 0

        let exportButton = NSButton(
            title: "Export JSON",
            target: self,
            action: #selector(exportClicked))
        exportButton.translatesAutoresizingMaskIntoConstraints = false
        exportButton.bezelStyle = .rounded

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        tableView = NSTableView()
        tableView.usesAutomaticRowHeights = true
        tableView.allowsMultipleSelection = false
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(editClicked)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("text"))
        column.title = "Principle"
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        scrollView.documentView = tableView

        let addButton = NSButton(
            title: "+ Add",
            target: self,
            action: #selector(addClicked))
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.bezelStyle = .rounded

        editButton = NSButton(
            title: "Edit",
            target: self,
            action: #selector(editClicked))
        editButton.translatesAutoresizingMaskIntoConstraints = false
        editButton.bezelStyle = .rounded

        archiveButton = NSButton(
            title: "Archive",
            target: self,
            action: #selector(toggleArchiveClicked))
        archiveButton.translatesAutoresizingMaskIntoConstraints = false
        archiveButton.bezelStyle = .rounded

        contentView.addSubview(filterControl)
        contentView.addSubview(exportButton)
        contentView.addSubview(scrollView)
        contentView.addSubview(addButton)
        contentView.addSubview(editButton)
        contentView.addSubview(archiveButton)

        NSLayoutConstraint.activate([
            filterControl.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            filterControl.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),

            exportButton.centerYAnchor.constraint(equalTo: filterControl.centerYAnchor),
            exportButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            scrollView.topAnchor.constraint(equalTo: filterControl.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            scrollView.bottomAnchor.constraint(equalTo: addButton.topAnchor, constant: -12),

            addButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            addButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),

            editButton.leadingAnchor.constraint(equalTo: addButton.trailingAnchor, constant: 12),
            editButton.centerYAnchor.constraint(equalTo: addButton.centerYAnchor),

            archiveButton.leadingAnchor.constraint(equalTo: editButton.trailingAnchor, constant: 12),
            archiveButton.centerYAnchor.constraint(equalTo: addButton.centerYAnchor),
        ])
    }

    private func reload() {
        do {
            principles = try dataService.listPrinciples(state: filter)
            tableView.reloadData()
            updateButtonStates()
        } catch {
            showError(error)
        }
    }

    private func selectedPrinciple() -> Principle? {
        let row = tableView.selectedRow
        guard row >= 0, row < principles.count else { return nil }
        return principles[row]
    }

    private func updateButtonStates() {
        let selected = selectedPrinciple()
        editButton.isEnabled = selected != nil
        archiveButton.isEnabled = selected != nil
        archiveButton.title = (selected?.state == .archived) ? "Unarchive" : "Archive"
    }

    @objc private func filterChanged() {
        switch filterControl.selectedSegment {
        case 0: filter = .active
        case 1: filter = .archived
        default: filter = nil
        }
        reload()
    }

    @objc private func addClicked() {
        presentSheet(mode: .add) { [weak self] text in
            guard let self = self else { return }
            do {
                _ = try self.dataService.addPrinciple(text: text)
                self.reload()
            } catch {
                self.showError(error)
            }
        }
    }

    @objc private func editClicked() {
        guard let p = selectedPrinciple(), let id = p.id else { return }
        presentSheet(mode: .edit(p)) { [weak self] text in
            guard let self = self else { return }
            do {
                try self.dataService.updatePrinciple(id: id, text: text)
                self.reload()
            } catch {
                self.showError(error)
            }
        }
    }

    @objc private func toggleArchiveClicked() {
        guard let p = selectedPrinciple(), let id = p.id else { return }
        let newState: PrincipleState = (p.state == .archived) ? .active : .archived
        do {
            try dataService.setState(id: id, state: newState)
            reload()
        } catch {
            showError(error)
        }
    }

    @objc private func exportClicked() {
        do {
            let data = try dataService.exportAll()
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyyMMdd"
            let filename = "principles-export-\(fmt.string(from: Date())).json"

            let docsURL = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false)
            let fileURL = docsURL.appendingPathComponent(filename)

            try data.write(to: fileURL, options: .atomic)

            let alert = NSAlert()
            alert.messageText = "Export complete"
            alert.informativeText = "Wrote \(fileURL.path)"
            alert.runModal()
        } catch {
            showError(error)
        }
    }

    private func presentSheet(
        mode: PrincipleEditSheetController.Mode,
        onSave: @escaping (String) -> Void
    ) {
        guard let parent = self.window else { return }
        let sheet = PrincipleEditSheetController(mode: mode, onSave: onSave)
        self.editSheetController = sheet
        if let sheetWindow = sheet.window {
            parent.beginSheet(sheetWindow) { [weak self] _ in
                self?.editSheetController = nil
            }
        }
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Error"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        principles.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("TextCell")
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier
            let textField = NSTextField(wrappingLabelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byWordWrapping
            textField.maximumNumberOfLines = 0
            cell.addSubview(textField)
            cell.textField = textField
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                textField.topAnchor.constraint(equalTo: cell.topAnchor, constant: 4),
                textField.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -4),
            ])
        }
        cell.textField?.stringValue = principles[row].text
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateButtonStates()
    }
}
