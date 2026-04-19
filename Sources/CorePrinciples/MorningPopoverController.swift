import AppKit
import CorePrinciplesLib

final class MorningPopoverController: NSObject, NSPopoverDelegate {
    var onOpenPrinciples: (() -> Void)?

    private let dataService: DataService
    private let scheduler: DailyQuestionScheduler

    private let popover: NSPopover
    private let viewController: MorningViewController

    init(dataService: DataService, scheduler: DailyQuestionScheduler) {
        self.dataService = dataService
        self.scheduler = scheduler

        let vc = MorningViewController()
        self.viewController = vc

        let popover = NSPopover()
        popover.contentViewController = vc
        popover.behavior = .transient
        popover.animates = true
        self.popover = popover

        super.init()
        popover.delegate = self

        vc.onSubmit = { [weak self] content in self?.handleSubmit(content: content) }
        vc.onOpenPrinciplesRequested = { [weak self] in
            self?.popover.performClose(nil)
            self?.onOpenPrinciples?()
        }
    }

    func toggle(relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        loadToday()
    }

    private func loadToday() {
        viewController.showLoading()
        scheduler.today { [weak self] outcome in
            guard let self = self else { return }
            switch outcome {
            case .ready(let principle, let question, let answer):
                if let answer = answer {
                    self.viewController.showAnswered(principle: principle, question: question, answer: answer)
                } else {
                    self.viewController.showActive(principle: principle, question: question)
                }
            case .empty:
                self.viewController.showEmpty()
            case .failed(let error):
                self.popover.performClose(nil)
                self.presentAlert(error: error)
            }
        }
    }

    private func handleSubmit(content: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let principleId = viewController.currentPrincipleId else { return }
        do {
            _ = try dataService.insertAnswer(principleId: principleId, content: trimmed)
            popover.performClose(nil)
        } catch {
            presentAlert(error: error)
        }
    }

    private func presentAlert(error: Error) {
        let alert = NSAlert()
        alert.messageText = "Could not generate today's question"
        alert.informativeText = "\(error.localizedDescription)\n\nCheck your network and that `llm` is configured (`llm keys set anthropic`), then try again."
        alert.alertStyle = .warning
        alert.runModal()
    }
}

private final class MorningViewController: NSViewController {
    var onSubmit: ((String) -> Void)?
    var onOpenPrinciplesRequested: (() -> Void)?

    private(set) var currentPrincipleId: Int64?

    private var container: NSView!
    private var loadingView: NSView!
    private var activeView: NSView!
    private var answeredView: NSView!
    private var emptyView: NSView!

    private var principleLabel: NSTextField!
    private var questionLabel: NSTextField!
    private var answerTextView: NSTextView!
    private var submitButton: NSButton!

    private var answeredPrincipleLabel: NSTextField!
    private var answeredQuestionLabel: NSTextField!
    private var answeredAnswerLabel: NSTextField!

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 320))
        root.translatesAutoresizingMaskIntoConstraints = false

        container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(container)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            container.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            container.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            container.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
        ])

        loadingView = buildLoadingView()
        activeView = buildActiveView()
        answeredView = buildAnsweredView()
        emptyView = buildEmptyView()

        self.view = root
        showLoading()
    }

    // MARK: - State transitions

    func showLoading() {
        swapTo(loadingView)
    }

    func showActive(principle: Principle, question: Entry) {
        currentPrincipleId = principle.id
        principleLabel.stringValue = principle.text
        questionLabel.stringValue = question.content
        answerTextView.string = ""
        swapTo(activeView)
        view.window?.makeFirstResponder(answerTextView)
    }

    func showAnswered(principle: Principle, question: Entry, answer: Entry) {
        currentPrincipleId = principle.id
        answeredPrincipleLabel.stringValue = principle.text
        answeredQuestionLabel.stringValue = question.content
        answeredAnswerLabel.stringValue = answer.content
        swapTo(answeredView)
    }

    func showEmpty() {
        currentPrincipleId = nil
        swapTo(emptyView)
    }

    private func swapTo(_ next: NSView) {
        for sub in container.subviews { sub.removeFromSuperview() }
        next.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(next)
        NSLayoutConstraint.activate([
            next.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            next.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            next.topAnchor.constraint(equalTo: container.topAnchor),
            next.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    // MARK: - Subviews

    private func buildLoadingView() -> NSView {
        let v = NSView()
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimation(nil)

        let label = NSTextField(labelWithString: "Generating today's question…")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.textColor = .secondaryLabelColor

        v.addSubview(spinner)
        v.addSubview(label)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: v.centerYAnchor, constant: -16),
            label.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            label.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 12),
        ])
        return v
    }

    private func buildActiveView() -> NSView {
        let v = NSView()

        let header = NSTextField(labelWithString: "Today's principle")
        header.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        header.textColor = .secondaryLabelColor
        header.translatesAutoresizingMaskIntoConstraints = false

        principleLabel = NSTextField(wrappingLabelWithString: "")
        principleLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        principleLabel.translatesAutoresizingMaskIntoConstraints = false
        principleLabel.maximumNumberOfLines = 0

        let questionHeader = NSTextField(labelWithString: "Question")
        questionHeader.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        questionHeader.textColor = .secondaryLabelColor
        questionHeader.translatesAutoresizingMaskIntoConstraints = false

        questionLabel = NSTextField(wrappingLabelWithString: "")
        questionLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        questionLabel.translatesAutoresizingMaskIntoConstraints = false
        questionLabel.maximumNumberOfLines = 0

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true

        answerTextView = NSTextView()
        answerTextView.isRichText = false
        answerTextView.font = NSFont.systemFont(ofSize: 13)
        answerTextView.autoresizingMask = [.width]
        answerTextView.isVerticallyResizable = true
        answerTextView.textContainer?.widthTracksTextView = true
        scrollView.documentView = answerTextView

        submitButton = NSButton(title: "Submit", target: self, action: #selector(submitTapped))
        submitButton.translatesAutoresizingMaskIntoConstraints = false
        submitButton.bezelStyle = .rounded
        submitButton.keyEquivalent = "\r"

        v.addSubview(header)
        v.addSubview(principleLabel)
        v.addSubview(questionHeader)
        v.addSubview(questionLabel)
        v.addSubview(scrollView)
        v.addSubview(submitButton)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: v.topAnchor),
            header.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: v.trailingAnchor),

            principleLabel.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4),
            principleLabel.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            principleLabel.trailingAnchor.constraint(equalTo: v.trailingAnchor),

            questionHeader.topAnchor.constraint(equalTo: principleLabel.bottomAnchor, constant: 16),
            questionHeader.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            questionHeader.trailingAnchor.constraint(equalTo: v.trailingAnchor),

            questionLabel.topAnchor.constraint(equalTo: questionHeader.bottomAnchor, constant: 4),
            questionLabel.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            questionLabel.trailingAnchor.constraint(equalTo: v.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: questionLabel.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: submitButton.topAnchor, constant: -12),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 80),

            submitButton.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            submitButton.bottomAnchor.constraint(equalTo: v.bottomAnchor),
        ])

        return v
    }

    private func buildAnsweredView() -> NSView {
        let v = NSView()

        let header = NSTextField(labelWithString: "Today's principle")
        header.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        header.textColor = .secondaryLabelColor
        header.translatesAutoresizingMaskIntoConstraints = false

        answeredPrincipleLabel = NSTextField(wrappingLabelWithString: "")
        answeredPrincipleLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        answeredPrincipleLabel.translatesAutoresizingMaskIntoConstraints = false
        answeredPrincipleLabel.maximumNumberOfLines = 0

        let questionHeader = NSTextField(labelWithString: "Today's question")
        questionHeader.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        questionHeader.textColor = .secondaryLabelColor
        questionHeader.translatesAutoresizingMaskIntoConstraints = false

        answeredQuestionLabel = NSTextField(wrappingLabelWithString: "")
        answeredQuestionLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        answeredQuestionLabel.translatesAutoresizingMaskIntoConstraints = false
        answeredQuestionLabel.maximumNumberOfLines = 0

        let answerHeader = NSTextField(labelWithString: "Your answer")
        answerHeader.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        answerHeader.textColor = .secondaryLabelColor
        answerHeader.translatesAutoresizingMaskIntoConstraints = false

        answeredAnswerLabel = NSTextField(wrappingLabelWithString: "")
        answeredAnswerLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        answeredAnswerLabel.translatesAutoresizingMaskIntoConstraints = false
        answeredAnswerLabel.maximumNumberOfLines = 0
        answeredAnswerLabel.isSelectable = true

        v.addSubview(header)
        v.addSubview(answeredPrincipleLabel)
        v.addSubview(questionHeader)
        v.addSubview(answeredQuestionLabel)
        v.addSubview(answerHeader)
        v.addSubview(answeredAnswerLabel)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: v.topAnchor),
            header.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: v.trailingAnchor),

            answeredPrincipleLabel.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4),
            answeredPrincipleLabel.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            answeredPrincipleLabel.trailingAnchor.constraint(equalTo: v.trailingAnchor),

            questionHeader.topAnchor.constraint(equalTo: answeredPrincipleLabel.bottomAnchor, constant: 16),
            questionHeader.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            questionHeader.trailingAnchor.constraint(equalTo: v.trailingAnchor),

            answeredQuestionLabel.topAnchor.constraint(equalTo: questionHeader.bottomAnchor, constant: 4),
            answeredQuestionLabel.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            answeredQuestionLabel.trailingAnchor.constraint(equalTo: v.trailingAnchor),

            answerHeader.topAnchor.constraint(equalTo: answeredQuestionLabel.bottomAnchor, constant: 16),
            answerHeader.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            answerHeader.trailingAnchor.constraint(equalTo: v.trailingAnchor),

            answeredAnswerLabel.topAnchor.constraint(equalTo: answerHeader.bottomAnchor, constant: 4),
            answeredAnswerLabel.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            answeredAnswerLabel.trailingAnchor.constraint(equalTo: v.trailingAnchor),
        ])

        return v
    }

    private func buildEmptyView() -> NSView {
        let v = NSView()

        let title = NSTextField(labelWithString: "No principles yet")
        title.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false
        title.alignment = .center

        let body = NSTextField(wrappingLabelWithString:
            "Add the principles you want to return to. The app will ask you one question a day about them.")
        body.font = NSFont.systemFont(ofSize: 12)
        body.textColor = .secondaryLabelColor
        body.translatesAutoresizingMaskIntoConstraints = false
        body.alignment = .center
        body.maximumNumberOfLines = 0

        let cta = NSButton(title: "Add your first principle", target: self, action: #selector(openPrinciplesTapped))
        cta.translatesAutoresizingMaskIntoConstraints = false
        cta.bezelStyle = .rounded
        cta.keyEquivalent = "\r"

        v.addSubview(title)
        v.addSubview(body)
        v.addSubview(cta)

        NSLayoutConstraint.activate([
            title.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            title.centerYAnchor.constraint(equalTo: v.centerYAnchor, constant: -40),

            body.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            body.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 20),
            body.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -20),

            cta.topAnchor.constraint(equalTo: body.bottomAnchor, constant: 16),
            cta.centerXAnchor.constraint(equalTo: v.centerXAnchor),
        ])

        return v
    }

    @objc private func submitTapped() {
        onSubmit?(answerTextView.string)
    }

    @objc private func openPrinciplesTapped() {
        onOpenPrinciplesRequested?()
    }
}
