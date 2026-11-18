import MapKit
import SwiftUI
import UIKit

@MainActor
func dismissMajungKeyboard() {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) {
        // Commit marked IME text and resign active responders across main and sheet hierarchies.
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene,
                  windowScene.activationState == .foregroundActive else { continue }
            for window in windowScene.windows where window.isKeyWindow {
                window.endEditing(true)
            }
        }
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

@MainActor
func dismissMajungKeyboard(_ resetFocus: () -> Void) {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) {
        resetFocus()
    }
    dismissMajungKeyboard()
}

@MainActor
private enum MajungKeyboardTapRegistry {
    static let preservedViews = NSHashTable<UIView>.weakObjects()
}

private final class MajungPreserveHostView: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            MajungKeyboardTapRegistry.preservedViews.add(self)
        } else {
            MajungKeyboardTapRegistry.preservedViews.remove(self)
        }
    }
}

private struct MajungTapPreserveFrameBridge: UIViewRepresentable {
    func makeUIView(context: Context) -> MajungPreserveHostView {
        let view = MajungPreserveHostView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: MajungPreserveHostView, context: Context) {}

    static func dismantleUIView(_ uiView: MajungPreserveHostView, coordinator: ()) {
        MajungKeyboardTapRegistry.preservedViews.remove(uiView)
    }
}

private final class MajungDismisserHostView: UIView {
    var onHierarchyMove: (@MainActor (UIView) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onHierarchyMove?(self)
    }
}

private struct MajungOutsideTapKeyboardDismisser: UIViewRepresentable {
    let isActive: Bool
    let onTapOutsideDismiss: @MainActor () -> Void
    let onSystemKeyboardHide: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onTapOutsideDismiss: onTapOutsideDismiss,
            onSystemKeyboardHide: onSystemKeyboardHide
        )
    }

    func makeUIView(context: Context) -> MajungDismisserHostView {
        let view = MajungDismisserHostView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.onHierarchyMove = { hostView in
            context.coordinator.attachIfNeeded(from: hostView)
        }
        return view
    }

    func updateUIView(_ uiView: MajungDismisserHostView, context: Context) {
        let wasActive = context.coordinator.isActive
        context.coordinator.onTapOutsideDismiss = onTapOutsideDismiss
        context.coordinator.onSystemKeyboardHide = onSystemKeyboardHide
        context.coordinator.isActive = isActive
        context.coordinator.attachIfNeeded(from: uiView, justActivated: !wasActive && isActive)
    }

    static func dismantleUIView(_ uiView: MajungDismisserHostView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var isActive = false {
            didSet {
                tapRecognizer.isEnabled = isActive
                panRecognizer.isEnabled = isActive
                if !isActive {
                    panDismissedCurrentGesture = false
                }
            }
        }
        var onTapOutsideDismiss: @MainActor () -> Void
        var onSystemKeyboardHide: @MainActor () -> Void
        private weak var attachedWindow: UIWindow?
        private var hideObserver: NSObjectProtocol?
        private var panDismissedCurrentGesture = false
        private lazy var tapRecognizer: UITapGestureRecognizer = configureDismissGesture(
            UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        )
        private lazy var panRecognizer: UIPanGestureRecognizer = configureDismissGesture(
            UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        )

        private func configureDismissGesture<Gesture: UIGestureRecognizer>(_ recognizer: Gesture) -> Gesture {
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = self
            recognizer.isEnabled = false
            return recognizer
        }

        init(
            onTapOutsideDismiss: @escaping @MainActor () -> Void,
            onSystemKeyboardHide: @escaping @MainActor () -> Void
        ) {
            self.onTapOutsideDismiss = onTapOutsideDismiss
            self.onSystemKeyboardHide = onSystemKeyboardHide
            super.init()
        }

        func attachIfNeeded(from hostView: UIView, justActivated: Bool = false) {
            guard let window = hostView.window else { return }
            let windowChanged = attachedWindow !== window
            if windowChanged {
                attachedWindow?.removeGestureRecognizer(tapRecognizer)
                attachedWindow?.removeGestureRecognizer(panRecognizer)
                window.addGestureRecognizer(tapRecognizer)
                window.addGestureRecognizer(panRecognizer)
                attachedWindow = window
            }
            if hideObserver == nil {
                hideObserver = NotificationCenter.default.addObserver(
                    forName: UIResponder.keyboardWillHideNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self, self.isActive else { return }
                        self.onSystemKeyboardHide()
                    }
                }
            }
            if windowChanged || isActive {
                enableImmediateScrollDismiss(from: hostView)
                if windowChanged || justActivated {
                    Task { @MainActor [weak self, weak hostView] in
                        guard let self, let hostView else { return }
                        self.enableImmediateScrollDismiss(from: hostView)
                    }
                }
            }
            tapRecognizer.isEnabled = isActive
            panRecognizer.isEnabled = isActive
        }

        func detach() {
            tapRecognizer.isEnabled = false
            panRecognizer.isEnabled = false
            attachedWindow?.removeGestureRecognizer(tapRecognizer)
            attachedWindow?.removeGestureRecognizer(panRecognizer)
            attachedWindow = nil
            if let hideObserver {
                NotificationCenter.default.removeObserver(hideObserver)
                self.hideObserver = nil
            }
        }

        private func enableImmediateScrollDismiss(from hostView: UIView) {
            var root: UIView? = hostView
            var responder: UIResponder? = hostView
            while let next = responder?.next {
                if let vc = next as? UIViewController {
                    root = vc.view
                }
                responder = next
            }
            guard let rootView = root ?? hostView.window else { return }
            applyDragDismissIfNeeded(in: rootView)
        }

        private func applyDragDismissIfNeeded(in view: UIView) {
            if view is MKMapView || view is UITextInput {
                return
            }
            if let scrollView = view as? UIScrollView {
                // Deliver quick button taps inside nested scroll views without UIKit's 150ms delay.
                if scrollView.delaysContentTouches {
                    scrollView.delaysContentTouches = false
                }
                if scrollView.keyboardDismissMode != .onDrag,
                   (scrollView is UICollectionView || scrollView is UITableView || scrollView.alwaysBounceVertical || scrollView.contentSize.height > scrollView.bounds.height) {
                    scrollView.keyboardDismissMode = .onDrag
                }
            }
            for child in view.subviews {
                applyDragDismissIfNeeded(in: child)
            }
        }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, isActive else { return }
            onTapOutsideDismiss()
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .began:
                panDismissedCurrentGesture = false
            case .changed:
                guard isActive, !panDismissedCurrentGesture else { return }
                let translation = recognizer.translation(in: attachedWindow)
                if abs(translation.y) >= 12 && abs(translation.y) > abs(translation.x) * 1.25 {
                    panDismissedCurrentGesture = true
                    onTapOutsideDismiss()
                }
            case .ended, .cancelled, .failed:
                panDismissedCurrentGesture = false
            default:
                break
            }
        }

        nonisolated func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            MainActor.assumeIsolated {
                guard isActive, let attachedWindow, touch.window === attachedWindow else {
                    return false
                }
                for view in MajungKeyboardTapRegistry.preservedViews.allObjects {
                    guard view.window === attachedWindow, !view.isHidden, view.alpha > 0 else {
                        continue
                    }
                    if view.bounds.contains(touch.location(in: view)) {
                        return false
                    }
                }
                let ignoreMaps = (gestureRecognizer === panRecognizer)
                var current = touch.view
                while let view = current {
                    if view is UITextInput || view is UIControl {
                        return false
                    }
                    if ignoreMaps, view is MKMapView {
                        return false
                    }
                    current = view.superview
                }
                return true
            }
        }

        nonisolated func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

struct MajungClearInputButton: View {
    @Binding var text: String
    var accessibilityLabel: String = "입력 내용 지우기"

    var body: some View {
        if !text.isEmpty {
            Button {
                text = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
        }
    }
}

extension View {
    func majungKeyboardDismiss(isFocused: FocusState<Bool>.Binding) -> some View {
        majungKeyboardDismissContainer(isActive: isFocused.wrappedValue) {
            isFocused.wrappedValue = false
        }
    }

    func majungKeyboardDismiss<Field: Hashable>(focusedField: FocusState<Field?>.Binding) -> some View {
        majungKeyboardDismissContainer(isActive: focusedField.wrappedValue != nil) {
            focusedField.wrappedValue = nil
        }
    }

    func majungPreserveKeyboardOnTap() -> some View {
        background(MajungTapPreserveFrameBridge())
    }

    func majungInputSurface(cornerRadius: CGFloat = 12) -> some View {
        padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                Color(uiColor: .tertiarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .majungPreserveKeyboardOnTap()
    }

    @ViewBuilder
    func majungGlassCapsule() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            self
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(.primary.opacity(0.12), lineWidth: 0.75)
                )
                .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
        }
    }

    private func majungKeyboardDismissContainer(
        isActive: Bool,
        dismiss: @escaping @MainActor () -> Void
    ) -> some View {
        let clearFocusOnly: @MainActor () -> Void = {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                dismiss()
            }
        }
        let performDismiss: @MainActor () -> Void = {
            dismissMajungKeyboard(dismiss)
        }
        return scrollDismissesKeyboard(.immediately)
            .onChange(of: isActive) { wasActive, nowActive in
                if wasActive && !nowActive {
                    dismissMajungKeyboard()
                }
            }
            .background(
                MajungOutsideTapKeyboardDismisser(
                    isActive: isActive,
                    onTapOutsideDismiss: performDismiss,
                    onSystemKeyboardHide: clearFocusOnly
                )
            )
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isActive {
                    HStack {
                        Spacer()
                        majungKeyboardDismissButton(action: performDismiss)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .padding(.top, 4)
                }
            }
    }

    @ViewBuilder
    private func majungKeyboardDismissButton(action: @escaping @MainActor () -> Void) -> some View {
        let label = Label("키보드 닫기", systemImage: "keyboard.chevron.compact.down")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)

        Group {
            if #available(iOS 26.0, *) {
                Button(action: action) {
                    label
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
            } else {
                Button(action: action) {
                    label
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .contentShape(Capsule())
                        .majungGlassCapsule()
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityLabel("키보드 닫기")
    }
}
