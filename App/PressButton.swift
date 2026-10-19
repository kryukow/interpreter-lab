import SwiftUI
import UIKit

// Native touch events keep push-to-talk precise while recognition is arming.
struct PressButton: UIViewRepresentable {
    let title: String
    let subtitle: String
    let pressed: Bool
    let enabled: Bool
    let begin: () -> Void
    let end: () -> Void
    let cancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> GraphitePressControl {
        let button = GraphitePressControl(frame: .zero)
        context.coordinator.connect(button)
        return button
    }
    func updateUIView(_ button: GraphitePressControl, context: Context) {
        context.coordinator.parent = self
        // Keep the active native tracking alive through asynchronous arming.
        button.isEnabled = enabled || context.coordinator.isHolding
        button.configure(title: title, subtitle: subtitle, pressed: pressed)
    }
    static func dismantleUIView(_ button: GraphitePressControl, coordinator: Coordinator) {
        coordinator.abort()
        button.removeTarget(coordinator, action: nil, for: .allEvents)
    }

    final class Coordinator: NSObject {
        var parent: PressButton
        private(set) var isHolding = false
        private weak var button: GraphitePressControl?
        init(_ parent: PressButton) {
            self.parent = parent
            super.init()
            NotificationCenter.default.addObserver(self, selector: #selector(abort),
                                                   name: UIApplication.willResignActiveNotification, object: nil)
        }
        deinit { NotificationCenter.default.removeObserver(self) }
        func connect(_ button: GraphitePressControl) {
            self.button = button
            button.addTarget(self, action: #selector(down), for: .touchDown)
            button.addTarget(self, action: #selector(up), for: [.touchUpInside, .touchUpOutside])
            button.addTarget(self, action: #selector(abort), for: .touchCancel)
        }
        @objc func down() {
            guard !isHolding, parent.enabled else { return }
            isHolding = true
            button?.touchHeld = true
            parent.begin()
        }
        @objc func up() {
            guard isHolding else { return }
            isHolding = false
            button?.touchHeld = false
            parent.end()
        }
        @objc func abort() {
            guard isHolding else { return }
            isHolding = false
            button?.touchHeld = false
            parent.cancel()
        }
    }
}

/// The material responds to the finger immediately, before speech permission or
/// recognizer preparation completes. Speech state can independently sustain it.
final class GraphitePressControl: UIButton {
    private let graphite = CAGradientLayer()
    private let rim = CAGradientLayer()
    private let rimMask = CAShapeLayer()
    private var speechPressed = false
    var touchHeld = false { didSet { updateMaterial() } }
    override var isHighlighted: Bool { didSet { updateMaterial() } }
    override var isEnabled: Bool { didSet { updateMaterial() } }
    var illuminated: Bool { touchHeld || isHighlighted || speechPressed }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isExclusiveTouch = true
        layer.cornerRadius = 22
        clipsToBounds = true
        graphite.startPoint = CGPoint(x: 0, y: 0)
        graphite.endPoint = CGPoint(x: 0.9, y: 1)
        layer.insertSublayer(graphite, at: 0)
        rim.startPoint = CGPoint(x: 0.15, y: 0)
        rim.endPoint = CGPoint(x: 0.9, y: 1)
        rim.mask = rimMask
        rimMask.fillColor = UIColor.clear.cgColor
        rimMask.strokeColor = UIColor.white.cgColor
        rimMask.lineWidth = 1
        layer.insertSublayer(rim, above: graphite)
        // UIButton otherwise adds its own highlighted tint behind the material.
        configurationUpdateHandler = { _ in }
        updateMaterial()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        graphite.frame = bounds
        rim.frame = bounds
        rimMask.frame = bounds
        rimMask.path = UIBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 21.5).cgPath
        CATransaction.commit()
    }

    func configure(title: String, subtitle: String, pressed: Bool) {
        speechPressed = pressed
        var config = UIButton.Configuration.plain()
        config.title = title
        config.image = UIImage(systemName: "mic")
        config.preferredSymbolConfigurationForImage = .init(pointSize: 21, weight: .regular)
        config.imagePlacement = .leading
        config.imagePadding = 11
        config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 13, bottom: 14, trailing: 13)
        config.baseForegroundColor = UIColor(red: 0.84, green: 0.87, blue: 0.90, alpha: 1)
        config.titleTextAttributesTransformer = .init { incoming in
            var attributes = incoming
            attributes.font = .systemFont(ofSize: 15, weight: .medium)
            return attributes
        }
        configuration = config
        titleLabel?.numberOfLines = 1
        titleLabel?.adjustsFontSizeToFitWidth = true
        titleLabel?.minimumScaleFactor = 0.8
        accessibilityLabel = title + ". " + subtitle
        accessibilityHint = "Удерживай, дождись вибросигнала, говори. Отпусти для перевода."
        updateMaterial()
    }

    private func updateMaterial() {
        let active = illuminated
        let top = active ? UIColor(red: 0.23, green: 0.28, blue: 0.35, alpha: 1)
                         : UIColor(red: 0.14, green: 0.16, blue: 0.20, alpha: 1)
        let bottom = active ? UIColor(red: 0.11, green: 0.15, blue: 0.20, alpha: 1)
                            : UIColor(red: 0.06, green: 0.08, blue: 0.10, alpha: 1)
        CATransaction.begin()
        CATransaction.setAnimationDuration(UIAccessibility.isReduceMotionEnabled ? 0 : 0.24)
        graphite.colors = [top.cgColor, bottom.cgColor]
        rim.colors = [UIColor(white: active ? 0.77 : 0.49, alpha: active ? 0.80 : 0.48).cgColor,
                      UIColor(white: active ? 0.56 : 0.29, alpha: 0.45).cgColor]
        CATransaction.commit()
        alpha = isEnabled ? 1 : 0.42
    }
}
