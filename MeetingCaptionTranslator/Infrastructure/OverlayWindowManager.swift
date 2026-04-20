import AppKit
import Combine
import SwiftUI

@MainActor
protocol OverlayWindowManaging: AnyObject {
    func show()
}

struct OverlayInteractionConfiguration: Equatable {
    let ignoresMouseEvents: Bool
    let isMovableByWindowBackground: Bool

    static func make(isClickThroughEnabled: Bool) -> OverlayInteractionConfiguration {
        OverlayInteractionConfiguration(
            ignoresMouseEvents: isClickThroughEnabled,
            isMovableByWindowBackground: !isClickThroughEnabled
        )
    }
}

@MainActor
final class OverlayWindowManager: OverlayWindowManaging {
    private let panel: NSPanel
    private var cancellables: Set<AnyCancellable> = []

    init(viewModel: OverlayViewModel) {
        let screenFrame = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 720)
        let panelFrame = CGRect(
            x: screenFrame.minX + 40,
            y: screenFrame.minY + 40,
            width: min(960, screenFrame.width - 80),
            height: 220
        )

        panel = NSPanel(
            contentRect: panelFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: OverlayView(viewModel: viewModel))
        applyInteractionConfiguration(
            OverlayInteractionConfiguration.make(isClickThroughEnabled: viewModel.isClickThroughEnabled)
        )

        viewModel.$isClickThroughEnabled
            .sink { [weak panel] isClickThroughEnabled in
                let configuration = OverlayInteractionConfiguration.make(isClickThroughEnabled: isClickThroughEnabled)
                panel?.ignoresMouseEvents = configuration.ignoresMouseEvents
                panel?.isMovableByWindowBackground = configuration.isMovableByWindowBackground
            }
            .store(in: &cancellables)
    }

    func show() {
        panel.orderFrontRegardless()
    }

    private func applyInteractionConfiguration(_ configuration: OverlayInteractionConfiguration) {
        panel.ignoresMouseEvents = configuration.ignoresMouseEvents
        panel.isMovableByWindowBackground = configuration.isMovableByWindowBackground
    }
}
