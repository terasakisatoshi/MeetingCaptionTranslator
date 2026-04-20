import AppKit
import Combine
import SwiftUI

@MainActor
protocol OverlayWindowManaging: AnyObject {
    func show()
}

struct OverlayWindowChromeConfiguration: Equatable {
    let styleMask: NSWindow.StyleMask
    let titleVisibility: NSWindow.TitleVisibility
    let titlebarAppearsTransparent: Bool
    let hidesStandardWindowButtons: Bool

    static let defaultConfiguration = OverlayWindowChromeConfiguration(
        styleMask: [.titled, .fullSizeContentView, .resizable],
        titleVisibility: .hidden,
        titlebarAppearsTransparent: true,
        hidesStandardWindowButtons: true
    )

    @MainActor
    func apply(to window: NSWindow) {
        window.titleVisibility = titleVisibility
        window.titlebarAppearsTransparent = titlebarAppearsTransparent
        if hidesStandardWindowButtons {
            [.closeButton, .miniaturizeButton, .zoomButton].forEach { button in
                window.standardWindowButton(button)?.isHidden = true
            }
        }
    }
}

struct OverlayInteractionConfiguration: Equatable {
    let ignoresMouseEvents: Bool
    let isMovableByWindowBackground: Bool

    static let defaultConfiguration = OverlayInteractionConfiguration(
        ignoresMouseEvents: false,
        isMovableByWindowBackground: true
    )
}

@MainActor
final class OverlayWindowManager: OverlayWindowManaging {
    private static let screenInset: CGFloat = 40

    private let window: NSWindow
    private let onSizeChange: @MainActor (CGSize) -> Void
    private var cancellables: Set<AnyCancellable> = []
    private var isApplyingProgrammaticResize = false

    init(
        viewModel: OverlayViewModel,
        onSizeChange: @escaping @MainActor (CGSize) -> Void
    ) {
        self.onSizeChange = onSizeChange

        let screenFrame = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 720)
        let panelSize = Self.clampedPanelSize(
            width: viewModel.overlayWidth,
            height: viewModel.overlayHeight,
            visibleFrame: screenFrame
        )
        let panelFrame = CGRect(
            x: screenFrame.minX + Self.screenInset,
            y: screenFrame.minY + Self.screenInset,
            width: panelSize.width,
            height: panelSize.height
        )

        window = NSWindow(
            contentRect: panelFrame,
            styleMask: OverlayWindowChromeConfiguration.defaultConfiguration.styleMask,
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.minSize = CGSize(
            width: AppSettings.overlayWidthRange.lowerBound,
            height: AppSettings.overlayHeightRange.lowerBound
        )
        window.maxSize = CGSize(
            width: AppSettings.overlayWidthRange.upperBound,
            height: AppSettings.overlayHeightRange.upperBound
        )
        window.isRestorable = false
        window.contentView = NSHostingView(rootView: OverlayView(viewModel: viewModel))
        OverlayWindowChromeConfiguration.defaultConfiguration.apply(to: window)
        applyInteractionConfiguration(.defaultConfiguration)

        viewModel.$overlayWidth
            .combineLatest(viewModel.$overlayHeight)
            .sink { [weak self] width, height in
                self?.updatePanelSize(width: width, height: height)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(
            for: NSWindow.didEndLiveResizeNotification,
            object: window
        )
        .sink { [weak self] _ in
            self?.syncOverlaySizeFromPanel()
        }
        .store(in: &cancellables)
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
    }

    private func applyInteractionConfiguration(_ configuration: OverlayInteractionConfiguration) {
        window.ignoresMouseEvents = configuration.ignoresMouseEvents
        window.isMovableByWindowBackground = configuration.isMovableByWindowBackground
    }

    private func updatePanelSize(width: Double, height: Double) {
        let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? window.frame
        let clampedSize = Self.clampedPanelSize(width: width, height: height, visibleFrame: visibleFrame)
        var frame = window.frame
        frame.size = clampedSize
        frame.origin.x = min(
            max(visibleFrame.minX + Self.screenInset, frame.origin.x),
            visibleFrame.maxX - clampedSize.width - Self.screenInset
        )
        frame.origin.y = min(
            max(visibleFrame.minY + Self.screenInset, frame.origin.y),
            visibleFrame.maxY - clampedSize.height - Self.screenInset
        )
        isApplyingProgrammaticResize = true
        window.setFrame(frame, display: true)
        isApplyingProgrammaticResize = false
    }

    private func syncOverlaySizeFromPanel() {
        guard !isApplyingProgrammaticResize else {
            return
        }

        onSizeChange(window.frame.size)
    }

    private static func clampedPanelSize(
        width: Double,
        height: Double,
        visibleFrame: CGRect
    ) -> CGSize {
        let availableWidth = max(320, visibleFrame.width - screenInset * 2)
        let availableHeight = max(160, visibleFrame.height - screenInset * 2)

        return CGSize(
            width: min(CGFloat(width), availableWidth),
            height: min(CGFloat(height), availableHeight)
        )
    }
}
