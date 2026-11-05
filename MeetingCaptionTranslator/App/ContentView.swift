import AppKit
import AVFoundation
import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Live Caption Translator")
                    .font(.title.bold())

                Text("Audio to bilingual overlay subtitles")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Audio Input")
                    .font(.headline)

                Picker("Audio Input", selection: Binding(
                    get: { viewModel.audioInput },
                    set: { viewModel.updateAudioInput($0) }
                )) {
                    ForEach(AudioInput.allCases) { input in
                        Text(input.title).tag(input)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(viewModel.appState.isRunning || viewModel.appState == .preparing || viewModel.isPreparingAppleSpeechModel)

                if viewModel.audioInput == .microphone {
                    Picker("Microphone", selection: Binding(
                        get: { viewModel.selectedMicrophoneID },
                        set: { viewModel.updateMicrophoneDevice($0) }
                    )) {
                        Text("System Default").tag("")
                        ForEach(viewModel.microphoneDevices) { device in
                            Text(device.name).tag(device.id)
                        }
                        if !viewModel.selectedMicrophoneID.isEmpty &&
                            !viewModel.microphoneDevices.contains(where: { $0.id == viewModel.selectedMicrophoneID }) {
                            Text("Selected microphone unavailable").tag(viewModel.selectedMicrophoneID)
                        }
                    }
                    .disabled(viewModel.appState.isRunning || viewModel.appState == .preparing || viewModel.isPreparingAppleSpeechModel)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Language Direction")
                    .font(.headline)

                Picker(
                    "Language Direction",
                    selection: Binding(
                        get: { viewModel.languagePair },
                        set: { viewModel.updateLanguagePair($0) }
                    )
                ) {
                    ForEach(CaptionLanguagePair.supportedPairs) { pair in
                        Text(pair.displayTitle).tag(pair)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(viewModel.appState.isRunning || viewModel.appState == .preparing || viewModel.isPreparingAppleSpeechModel)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Speech Recognition").font(.headline)
                Picker("Speech Recognition", selection: Binding(
                    get: { viewModel.transcriptionEngine },
                    set: { viewModel.updateTranscriptionEngine($0) }
                )) {
                    ForEach(TranscriptionEngine.allCases) { engine in
                        Text(engine == .apple ? "Apple Speech" : (viewModel.languagePair.sourceLanguage == "ja" ? "Haas-ja (speech.cpp)" : "Qwen3-ASR (speech.cpp)"))
                            .tag(engine)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(viewModel.languagePair.isAutomatic || viewModel.appState.isRunning || viewModel.appState == .preparing || viewModel.isPreparingAppleSpeechModel)

                if viewModel.languagePair.isAutomatic {
                    Text("Auto always uses Qwen3-ASR (speech.cpp).")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if viewModel.transcriptionEngine == .apple {
                    HStack(spacing: 8) {
                        Button("Download Apple Speech Model") {
                            viewModel.prepareAppleSpeechModel()
                        }
                        .disabled(viewModel.appState.isRunning || viewModel.appState == .preparing || viewModel.isPreparingAppleSpeechModel)
                        if viewModel.isPreparingAppleSpeechModel {
                            ProgressView().controlSize(.small)
                            Text("Preparing model…").foregroundStyle(.secondary)
                        } else if let message = viewModel.appleSpeechModelMessage {
                            Text(message).foregroundStyle(.secondary)
                        }
                    }
                }
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
                .disabled(viewModel.isPreparingAppleSpeechModel || viewModel.appState.isRunning || viewModel.appState == .preparing)

                Button("Stop") {
                    viewModel.stop()
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Status")
                    .font(.headline)
                HStack {
                    if viewModel.appState == .preparing {
                        ProgressView().controlSize(.small)
                    }
                    Text(viewModel.appState.statusText)
                        .foregroundStyle(.secondary)
                }
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
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasConnectedNotification)) { _ in
            viewModel.refreshMicrophoneDevices()
        }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasDisconnectedNotification)) { _ in
            viewModel.refreshMicrophoneDevices()
        }
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
