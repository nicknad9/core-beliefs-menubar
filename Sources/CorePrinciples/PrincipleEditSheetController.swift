import AppKit
import CorePrinciplesLib

final class PrincipleEditSheetController: NSWindowController, NSTextViewDelegate {
    enum Mode {
        case add
        case edit(Principle)

        var initialText: String {
            if case .edit(let p) = self { return p.text }
            return ""
        }
        var title: String {
            switch self {
            case .add: return "New Principle"
            case .edit: return "Edit Principle"
            }
        }
    }

    private let mode: Mode
    private let onSave: (String) -> Void
    private var textView: NSTextView!
    private var saveButton: NSButton!

    init(mode: Mode, onSave: @escaping (String) -> Void) {
        self.mode = mode
        self.onSave = onSave

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 220),
            styleMask: [.titled],
            backing: .buffered,
            defer: false)
        window.title = mode.title

        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.autohidesScrollers = true

        textView = NSTextView()
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.string = mode.initialText
        textView.delegate = self
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView

        let cancelButton = NSButton(
            title: "Cancel",
            target: self,
            action: #selector(cancel))
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.keyEquivalent = "\u{1b}"

        saveButton = NSButton(
            title: "Save",
            target: self,
            action: #selector(save))
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        saveButton.keyEquivalent = "\r"
        saveButton.bezelStyle = .rounded
        saveButton.isEnabled = !mode.initialText
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        contentView.addSubview(scrollView)
        contentView.addSubview(cancelButton)
        contentView.addSubview(saveButton)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            scrollView.bottomAnchor.constraint(equalTo: saveButton.topAnchor, constant: -16),

            saveButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            saveButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),

            cancelButton.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -12),
            cancelButton.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor),
        ])

        window?.initialFirstResponder = textView
    }

    @objc private func save() {
        let text = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        onSave(text)
        dismiss()
    }

    @objc private func cancel() {
        dismiss()
    }

    private func dismiss() {
        guard let window = self.window, let parent = window.sheetParent else { return }
        parent.endSheet(window, returnCode: .OK)
    }

    func textDidChange(_ notification: Notification) {
        let trimmed = textView.string
            .trimmingCharacters(in: .whitespacesAndNewlines)
        saveButton.isEnabled = !trimmed.isEmpty
    }
}
