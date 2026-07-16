import AppKit

@MainActor
final class UpdateStatusWindowController: NSWindowController {
    struct ButtonConfiguration {
        let title: String
        let action: () -> Void
    }

    struct ButtonConfigurations {
        let primary: ButtonConfiguration?
        let secondary: ButtonConfiguration?

        init(primary: ButtonConfiguration? = nil, secondary: ButtonConfiguration? = nil) {
            self.primary = primary
            self.secondary = secondary
        }
    }

    private let titleLabel = NSTextField(labelWithString: "")
    private let progressIndicator = NSProgressIndicator()
    private let primaryButton = NSButton()
    private let secondaryButton = NSButton()
    private var primaryAction: (() -> Void)?
    private var secondaryAction: (() -> Void)?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 150),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = Constants.appName
        window.isReleasedWhenClosed = false
        super.init(window: window)
        configureContent()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show(
        title: String,
        progress progressValue: Double?,
        buttons: ButtonConfigurations = ButtonConfigurations()
    ) {
        titleLabel.stringValue = title
        configureProgress(progressValue)
        configure(button: primaryButton, configuration: buttons.primary)
        configure(button: secondaryButton, configuration: buttons.secondary)
        primaryAction = buttons.primary?.action
        secondaryAction = buttons.secondary?.action
        focus()
    }

    func update(progress value: Double) {
        progressIndicator.isIndeterminate = false
        progressIndicator.doubleValue = min(1, max(0, value))
    }

    func focus() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func configureContent() {
        titleLabel.font = .boldSystemFont(ofSize: 18)
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 1

        primaryButton.target = self
        primaryButton.action = #selector(primaryPressed)
        primaryButton.bezelStyle = .rounded
        secondaryButton.target = self
        secondaryButton.action = #selector(secondaryPressed)
        secondaryButton.bezelStyle = .rounded

        let buttons = NSStackView(views: [secondaryButton, primaryButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.alignment = .centerY

        let stack = NSStackView(views: [titleLabel, progressIndicator, buttons])
        stack.orientation = .vertical
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView()
        window?.contentView = contentView
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    private func configureProgress(_ value: Double?) {
        progressIndicator.isIndeterminate = value == nil
        if let value {
            progressIndicator.stopAnimation(nil)
            progressIndicator.doubleValue = min(1, max(0, value))
        } else {
            progressIndicator.startAnimation(nil)
        }
    }

    private func configure(button: NSButton, configuration: ButtonConfiguration?) {
        button.isHidden = configuration == nil
        button.title = configuration?.title ?? ""
        button.isEnabled = configuration != nil
    }

    @objc private func primaryPressed() {
        primaryAction?()
    }

    @objc private func secondaryPressed() {
        secondaryAction?()
    }
}
