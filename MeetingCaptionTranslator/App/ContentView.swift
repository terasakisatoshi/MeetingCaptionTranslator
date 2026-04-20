import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Live Caption Translator")
                    .font(.title.bold())

                Text("English system audio to Japanese overlay subtitles")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Audio Input")
                    .font(.headline)

                Text(viewModel.selectedTargetDescription)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Overlay")
                    .font(.headline)

                Text("Resize the overlay window directly from its edges or corners.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                overlaySlider(
                    title: "Opacity",
                    value: Binding(
                        get: { viewModel.overlayViewModel.overlayOpacity },
                        set: { viewModel.updateOverlayOpacity($0) }
                    ),
                    range: AppSettings.overlayOpacityRange,
                    step: 0.02,
                    valueFormatter: { String(format: "%.0f%%", (1 - $0) * 100) }
                )

                overlaySlider(
                    title: "Font Size",
                    value: Binding(
                        get: { viewModel.overlayViewModel.fontSize },
                        set: { viewModel.updateOverlayFontSize($0) }
                    ),
                    range: AppSettings.fontSizeRange,
                    step: 1,
                    valueFormatter: { "\(Int($0)) pt" }
                )
            }

            HStack(spacing: 12) {
                Button("Start") {
                    viewModel.start()
                }
                .buttonStyle(.borderedProminent)

                Button("Stop") {
                    viewModel.stop()
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Status")
                    .font(.headline)
                Text(viewModel.appState.statusText)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Diagnostics")
                    .font(.headline)
                SelectableMessageText(
                    viewModel.diagnosticsText,
                    textColor: .secondaryLabelColor,
                    font: .monospacedSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .caption1).pointSize, weight: .regular)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let errorMessage = viewModel.errorMessage {
                SelectableMessageText(
                    errorMessage,
                    textColor: .systemRed,
                    font: .preferredFont(forTextStyle: .callout)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
        .padding(24)
        .frame(minWidth: 460, minHeight: 460)
        .task {
            viewModel.initialize()
        }
    }

    private func overlaySlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        valueFormatter: @escaping (Double) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(valueFormatter(value.wrappedValue))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Slider(value: value, in: range, step: step)
        }
    }
}
