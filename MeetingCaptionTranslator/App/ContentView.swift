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
                Text("Source")
                    .font(.headline)

                Picker("Source", selection: $viewModel.selectedTargetID) {
                    ForEach(viewModel.availableTargets) { target in
                        Text("\(target.title) • \(target.subtitle)").tag(Optional(target.id))
                    }
                }
                .pickerStyle(.menu)

                Text(viewModel.selectedTargetDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle("Overlay Click-Through", isOn: Binding(
                get: { viewModel.overlayViewModel.isClickThroughEnabled },
                set: { viewModel.updateOverlayClickThrough($0) }
            ))

            HStack(spacing: 12) {
                Button("Refresh Sources") {
                    Task {
                        await viewModel.refreshTargets()
                    }
                }

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

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            Spacer()
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 340)
        .task {
            viewModel.initialize()
        }
    }
}
