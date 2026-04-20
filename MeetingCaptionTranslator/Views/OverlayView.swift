import AppKit
import SwiftUI

struct OverlayView: View {
    @ObservedObject var viewModel: OverlayViewModel

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                OverlayWindowDragStrip()
                Capsule()
                    .fill(.white.opacity(0.18))
                    .frame(width: 46, height: 4)
            }
            .frame(height: 26)

            OverlayTranscriptTextView(
                rows: viewModel.rows,
                fontSize: viewModel.fontSize,
                statusText: viewModel.statusText
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.black.opacity(viewModel.overlayOpacity))
        )
    }
}

private final class OverlayWindowDragStripView: NSView {
    override var mouseDownCanMoveWindow: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

enum OverlayWindowDragStripComponents {
    @MainActor
    static func make() -> NSView {
        let view = OverlayWindowDragStripView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        return view
    }
}

struct OverlayWindowDragStrip: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        OverlayWindowDragStripComponents.make()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
    }
}
