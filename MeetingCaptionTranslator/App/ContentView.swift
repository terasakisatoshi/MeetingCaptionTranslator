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

            Toggle("Overlay Click-Through", isOn: Binding(
                get: { viewModel.overlayViewModel.isClickThroughEnabled },
                set: { viewModel.updateOverlayClickThrough($0) }
            ))

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
        .frame(minWidth: 420, minHeight: 280)
        .task {
            viewModel.initialize()
        }
    }
}
