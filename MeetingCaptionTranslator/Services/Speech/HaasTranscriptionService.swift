@preconcurrency import AVFoundation
import Foundation

// Short energy windows preserve the start of an utterance and end it after a pause.
struct HaasSegmenter {
    let sampleRate: Int
    private var pending: [Float] = []
    private var utterance: [Float] = []
    private var silence = 0
    private var active = false

    mutating func append(_ samples: [Float]) -> [[Float]] {
        pending.append(contentsOf: samples)
        let window = max(1, sampleRate / 50)
        var result: [[Float]] = []
        while pending.count >= window {
            let block = Array(pending.prefix(window))
            pending.removeFirst(window)
            let rms = sqrt(block.reduce(Float.zero) { $0 + $1 * $1 } / Float(window))
            if rms > 0.012 {
                active = true
                silence = 0
            } else if active {
                silence += window
            }
            if active {
                utterance.append(contentsOf: block)
                if silence >= sampleRate * 7 / 10 || utterance.count >= sampleRate * 12 {
                    result.append(utterance)
                    utterance.removeAll(keepingCapacity: true)
                    silence = 0
                    active = false
                }
            }
        }
        return result
    }
}

enum HaasTranscriptionError: LocalizedError {
    case executableMissing
    case worker(String)
    var errorDescription: String? {
        switch self {
        case .executableMissing: "speech.cpp not found. Install speech.cpp 0.9.3 or later; see README."
        case .worker(let message): "speech.cpp: \(message)"
        }
    }
}

actor HaasTranscriptionService: AppViewModelTranscriptionServicing {
    private let converter = AudioBufferConverter()
    private let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    private var segmenter = HaasSegmenter(sampleRate: 16000)
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var pendingOutput = Data()
    private var handler: (@Sendable (TranscriptEvent) async -> Void)?
    private var errorHandler: (@Sendable (Error) async -> Void)?
    private var stopping = false
    private var failed = false
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var ready = false

    nonisolated static func executablePath(bundledPath: String?, home: String, isExecutable: (String) -> Bool) -> String? {
        let paths = [bundledPath, "\(home)/.local/bin/speech", "/opt/homebrew/bin/speech", "/usr/local/bin/speech"].compactMap { $0 }
        return paths.first(where: isExecutable)
    }

    func start(eventHandler: @escaping @Sendable (TranscriptEvent) async -> Void, errorHandler: @escaping @Sendable (Error) async -> Void) async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard let path = Self.executablePath(
            bundledPath: Bundle.main.resourceURL?.appendingPathComponent("speech").path,
            home: home,
            isExecutable: { FileManager.default.isExecutableFile(atPath: $0) }
        ) else {
            throw HaasTranscriptionError.executableMissing
        }
        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["worker", "haas-ja-v1.0"]
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        self.handler = eventHandler
        self.errorHandler = errorHandler
        stopping = false
        failed = false
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { await self?.receive(data) }
        }
        process.terminationHandler = { [weak self] _ in
            Task { await self?.terminated() }
        }
        try process.run()
        self.process = process
        input = stdin.fileHandleForWriting
        output = stdout.fileHandleForReading
        try await withCheckedThrowingContinuation { continuation in
            if ready { continuation.resume() }
            else if failed { continuation.resume(throwing: HaasTranscriptionError.worker("Worker failed to start")) }
            else { readyContinuation = continuation }
        }
    }

    func append(frame: CapturedAudioFrame) async {
        guard !failed, input != nil else { return }
        do {
            let buffer = try converter.convert(frame.buffer, to: format)
            guard let data = buffer.floatChannelData?[0] else { return }
            let samples = Array(UnsafeBufferPointer(start: data, count: Int(buffer.frameLength)))
            for segment in segmenter.append(samples) {
                var pcm = Data(capacity: segment.count * 2)
                for sample in segment {
                    var value = Int16(max(-32768, min(32767, Int(sample * 32767)))).littleEndian
                    withUnsafeBytes(of: &value) { pcm.append(contentsOf: $0) }
                }
                let id = UUID().uuidString
                try send(["type": "chunk", "id": id, "seq": 0, "pcm": pcm.base64EncodedString()])
                try send(["type": "transcribe", "id": id, "sample_rate": 16000])
            }
        } catch { await fail(error) }
    }

    private func send(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(10)
        try input?.write(contentsOf: data)
    }

    private func receive(_ data: Data) async {
        guard !stopping, !data.isEmpty else { return }
        pendingOutput.append(data)
        while let end = pendingOutput.firstIndex(of: 10) {
            let line = Data(pendingOutput[..<end])
            pendingOutput.removeSubrange(...end)
            guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any], let type = object["type"] as? String else {
                await fail(HaasTranscriptionError.worker("Invalid worker response")); return
            }
            if type == "ready" {
                ready = true
                readyContinuation?.resume()
                readyContinuation = nil
            } else if type == "end", let text = object["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await handler?(TranscriptEvent(sourceText: text, state: .final))
            } else if type == "error" || type == "fatal" {
                let message = (object["error"] as? [String: Any])?["message"] as? String ?? "Worker failed"
                await fail(HaasTranscriptionError.worker(message))
            }
        }
    }

    private func terminated() async {
        if !stopping { await fail(HaasTranscriptionError.worker("Worker exited unexpectedly")) }
    }

    private func fail(_ error: Error) async {
        guard !failed, !stopping else { return }
        failed = true
        if let continuation = readyContinuation {
            readyContinuation = nil
            continuation.resume(throwing: error)
        } else if ready {
            await errorHandler?(error)
        }
    }

    func stop() async {
        stopping = true
        readyContinuation?.resume(throwing: CancellationError())
        readyContinuation = nil
        ready = false
        output?.readabilityHandler = nil
        try? input?.close()
        if let process, process.isRunning { process.terminate() }
        process = nil
        input = nil
        output = nil
        handler = nil
        errorHandler = nil
        pendingOutput.removeAll()
        segmenter = HaasSegmenter(sampleRate: 16000)
        converter.reset()
    }
}
