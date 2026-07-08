import Foundation

struct CLIPIndexProgress: Codable, Equatable, Sendable {
    let type: String
    let stage: String
    let done: Int
    let total: Int
    let message: String

    var displayMessage: String {
        guard total > 0 else { return message }
        return "\(message)"
    }

    static func decode(line: String) -> CLIPIndexProgress? {
        guard line.contains("\"type\":\"progress\"") || line.contains("\"type\": \"progress\"") else {
            return nil
        }
        guard let data = line.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CLIPIndexProgress.self, from: data)
    }
}

/// Runs the Python CLIP helper and returns the path to its JSON output plus captured logs.
final class CLIPIndexRunner {
    static let overrideKey = "MANDOLINE_CLIP_INDEXER_PATH"
    static let pythonPathKey = "MANDOLINE_CLIP_PYTHON_PATH"
    static let allowDownloadsKey = "MANDOLINE_CLIP_ALLOW_DOWNLOADS"

    struct RunResult: Equatable {
        let helperURL: URL
        let outputURL: URL
        let stdout: String
        let stderr: String
        let exitCode: Int32
        let isTemporaryOutput: Bool
    }

    enum RunnerError: LocalizedError {
        case noInputs
        case helperUnavailable([String])
        case launchFailed(URL, Error)
        case helperFailed(URL, Int32, String, String)
        case outputMissing(URL)

        var errorDescription: String? {
            switch self {
            case .noInputs:
                return "No media files were available for CLIP auto-categories."
            case let .helperUnavailable(candidates):
                let searched = candidates.isEmpty ? "No candidate paths were available." : candidates.joined(separator: "\n")
                return "CLIP auto-categories require the Python helper. Set \(CLIPIndexRunner.overrideKey) in the environment or UserDefaults, install the helper at ~/Library/Application Support/Mandoline/CLIP/index_folder.py, or add tools/clip/index_folder.py in a development checkout. Searched:\n\(searched)"
            case let .launchFailed(helperURL, error):
                return "Could not launch the CLIP helper at \(helperURL.path): \(error.localizedDescription). Set \(CLIPIndexRunner.pythonPathKey) to the Python executable for the CLIP virtual environment if Mandoline is launched outside an activated shell."
            case let .helperFailed(_, exitCode, stderr, stdout):
                let details = stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? stdout : stderr
                return "CLIP helper failed with exit code \(exitCode). \(details.trimmingCharacters(in: .whitespacesAndNewlines))"
            case let .outputMissing(outputURL):
                return "CLIP helper finished, but did not create the expected JSON output at \(outputURL.path)."
            }
        }
    }

    private struct PythonInvocation {
        let executableURL: URL
        let leadingArguments: [String]
    }

    private let fileManager: FileManager
    private let userDefaults: UserDefaults
    private let environment: [String: String]

    init(
        fileManager: FileManager = .default,
        userDefaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.fileManager = fileManager
        self.userDefaults = userDefaults
        self.environment = environment
    }

    func isAvailable() -> Bool {
        (try? resolveHelper()) != nil
    }

    func run(
        inputs: [URL],
        folderRoots: [URL] = [],
        outputURL requestedOutputURL: URL? = nil,
        labels: [String]? = nil,
        maxImages: Int? = nil,
        clusters: Int? = nil,
        progress: (@Sendable (CLIPIndexProgress) -> Void)? = nil
    ) async throws -> RunResult {
        let standardizedInputs = inputs.map(\.standardizedFileURL)
        let standardizedFolderRoots = folderRoots.map(\.standardizedFileURL)
        guard !standardizedInputs.isEmpty || !standardizedFolderRoots.isEmpty else { throw RunnerError.noInputs }

        let helperURL = try resolveHelper()
        let pythonInvocation = resolvePythonInvocation()
        let outputURL = requestedOutputURL ?? defaultOutputURL()
        let isTemporaryOutput = requestedOutputURL == nil
        try prepareOutputLocation(outputURL)

        let process = Process()
        process.executableURL = pythonInvocation.executableURL
        process.arguments = pythonInvocation.leadingArguments + [helperURL.path] + arguments(
            fileInputs: standardizedInputs,
            folderRoots: standardizedFolderRoots,
            outputURL: outputURL,
            labels: labels,
            maxImages: maxImages,
            clusters: clusters
        )
        process.environment = processEnvironment()

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutBuffer = LockedDataBuffer()
        let stderrBuffer = LockedDataBuffer()
        let cancellationFlag = LockedFlag()

        let stdoutLineBuffer = LockedLineBuffer()
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                stdoutBuffer.append(data)
                for line in stdoutLineBuffer.append(data) {
                    if let event = CLIPIndexProgress.decode(line: line) {
                        progress?(event)
                    }
                }
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { stderrBuffer.append(data) }
        }

        let result: RunResult = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { terminatedProcess in
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    let finalStdoutData = stdoutPipe.fileHandleForReading.availableData
                    stdoutBuffer.append(finalStdoutData)
                    for line in stdoutLineBuffer.append(finalStdoutData) {
                        if let event = CLIPIndexProgress.decode(line: line) {
                            progress?(event)
                        }
                    }
                    for line in stdoutLineBuffer.flush() {
                        if let event = CLIPIndexProgress.decode(line: line) {
                            progress?(event)
                        }
                    }
                    stderrBuffer.append(stderrPipe.fileHandleForReading.availableData)

                    let stdout = stdoutBuffer.stringValue
                    let stderr = stderrBuffer.stringValue
                    let exitCode = terminatedProcess.terminationStatus

                    if cancellationFlag.isSet {
                        self.removeTemporaryOutputIfNeeded(outputURL, isTemporary: isTemporaryOutput)
                        continuation.resume(throwing: CancellationError())
                        return
                    }

                    guard exitCode == 0 else {
                        self.removeTemporaryOutputIfNeeded(outputURL, isTemporary: isTemporaryOutput)
                        continuation.resume(throwing: RunnerError.helperFailed(helperURL, exitCode, stderr, stdout))
                        return
                    }

                    guard self.fileManager.fileExists(atPath: outputURL.path) else {
                        continuation.resume(throwing: RunnerError.outputMissing(outputURL))
                        return
                    }

                    continuation.resume(returning: RunResult(
                        helperURL: helperURL,
                        outputURL: outputURL,
                        stdout: stdout,
                        stderr: stderr,
                        exitCode: exitCode,
                        isTemporaryOutput: isTemporaryOutput
                    ))
                }

                do {
                    try process.run()
                } catch {
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    self.removeTemporaryOutputIfNeeded(outputURL, isTemporary: isTemporaryOutput)
                    continuation.resume(throwing: RunnerError.launchFailed(helperURL, error))
                }
            }
        } onCancel: {
            cancellationFlag.set()
            removeTemporaryOutputIfNeeded(outputURL, isTemporary: isTemporaryOutput)
            if process.isRunning {
                process.terminate()
            }
        }

        return result
    }

    private func removeTemporaryOutputIfNeeded(_ outputURL: URL, isTemporary: Bool) {
        guard isTemporary, fileManager.fileExists(atPath: outputURL.path) else { return }
        try? fileManager.removeItem(at: outputURL)
    }

    private func arguments(
        fileInputs: [URL],
        folderRoots: [URL],
        outputURL: URL,
        labels: [String]?,
        maxImages: Int?,
        clusters: Int?
    ) -> [String] {
        var arguments: [String] = []
        let helperInputs = folderRoots.isEmpty ? fileInputs : folderRoots
        for input in helperInputs {
            arguments.append("--input")
            arguments.append(input.path)
        }
        arguments.append(contentsOf: ["--output", outputURL.path])

        if shouldRunOffline() {
            arguments.append("--offline")
        }
        if let labels, !labels.isEmpty {
            arguments.append(contentsOf: ["--labels", labels.joined(separator: ",")])
        }
        if let maxImages {
            arguments.append(contentsOf: ["--max-images", String(maxImages)])
        }
        if let clusters {
            arguments.append(contentsOf: ["--clusters", String(clusters)])
        }

        return arguments
    }

    private func resolveHelper() throws -> URL {
        let candidates = helperCandidates()
        for candidate in candidates {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                continue
            }
            guard fileManager.isReadableFile(atPath: candidate.path) else { continue }
            return candidate.standardizedFileURL
        }

        throw RunnerError.helperUnavailable(candidates.map(\.path))
    }

    private func helperCandidates() -> [URL] {
        var candidates: [URL] = []

        if let environmentOverride = trimmedEnvironmentValue(Self.overrideKey) {
            candidates.append(fileURL(expandingTildeIn: environmentOverride, isDirectory: false))
        }

        if let defaultsOverride = trimmedDefaultsString(Self.overrideKey) {
            candidates.append(fileURL(expandingTildeIn: defaultsOverride, isDirectory: false))
        }

        candidates.append(
            fileURL(
                expandingTildeIn: "~/Library/Application Support/Mandoline/CLIP/index_folder.py",
                isDirectory: false
            )
        )

        if let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            candidates.append(
                applicationSupportURL
                    .appendingPathComponent("Mandoline", isDirectory: true)
                    .appendingPathComponent("CLIP", isDirectory: true)
                    .appendingPathComponent("index_folder.py", isDirectory: false)
            )
        }

        #if DEBUG
        let cwdCandidate = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("tools/clip/index_folder.py", isDirectory: false)
        candidates.append(cwdCandidate)

        let roots = [Bundle.main.bundleURL, Bundle.main.resourceURL].compactMap { $0 }
        for root in roots {
            candidates.append(contentsOf: ancestorCandidates(from: root, relativePath: "tools/clip/index_folder.py"))
        }
        #endif

        return uniqueStandardized(candidates)
    }

    private func resolvePythonInvocation() -> PythonInvocation {
        if let configuredPath = trimmedEnvironmentValue(Self.pythonPathKey) ?? trimmedDefaultsString(Self.pythonPathKey) {
            let configuredURL = fileURL(expandingTildeIn: configuredPath, isDirectory: false)
            if fileManager.isExecutableFile(atPath: configuredURL.path) {
                return PythonInvocation(executableURL: configuredURL, leadingArguments: [])
            }
        }

        for candidate in sandboxPythonCandidates() {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                continue
            }
            guard fileManager.isExecutableFile(atPath: candidate.path) else { continue }
            return PythonInvocation(executableURL: candidate.standardizedFileURL, leadingArguments: [])
        }

        #if DEBUG
        for candidate in developmentPythonCandidates() {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                continue
            }
            guard fileManager.isExecutableFile(atPath: candidate.path) else { continue }
            return PythonInvocation(executableURL: candidate.standardizedFileURL, leadingArguments: [])
        }
        #endif

        return PythonInvocation(executableURL: URL(fileURLWithPath: "/usr/bin/env"), leadingArguments: ["python3"])
    }

    private func processEnvironment() -> [String: String] {
        var values = environment
        if values["HF_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            values["HF_HOME"] = defaultHFHome().path
        }
        if values["HUGGINGFACE_HUB_CACHE"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            values["HUGGINGFACE_HUB_CACHE"] = defaultHFHome().appendingPathComponent("hub", isDirectory: true).path
        }
        return values
    }

    private func developmentPythonCandidates() -> [URL] {
        var candidates: [URL] = []
        candidates.append(
            URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
                .appendingPathComponent(".venv-clip/bin/python3", isDirectory: false)
        )

        let roots = [Bundle.main.bundleURL, Bundle.main.resourceURL].compactMap { $0 }
        for root in roots {
            candidates.append(contentsOf: ancestorCandidates(from: root, relativePath: ".venv-clip/bin/python3"))
        }
        return uniqueStandardized(candidates)
    }

    private func sandboxPythonCandidates() -> [URL] {
        var candidates: [URL] = []
        candidates.append(
            defaultCLIPSupportDirectory()
                .appendingPathComponent(".venv-clip", isDirectory: true)
                .appendingPathComponent("bin", isDirectory: true)
                .appendingPathComponent("python3", isDirectory: false)
        )
        candidates.append(
            fileURL(
                expandingTildeIn: "~/Library/Application Support/Mandoline/CLIP/.venv-clip/bin/python3",
                isDirectory: false
            )
        )
        return candidates
    }

    private func shouldRunOffline() -> Bool {
        !truthySetting(Self.allowDownloadsKey)
    }

    private func truthySetting(_ key: String) -> Bool {
        if let value = trimmedEnvironmentValue(key) {
            return Self.isTruthy(value)
        }

        let object = userDefaults.object(forKey: key)
        if let boolValue = object as? Bool {
            return boolValue
        }
        if let stringValue = object as? String {
            return Self.isTruthy(stringValue)
        }
        if let numberValue = object as? NSNumber {
            return numberValue.boolValue
        }
        return false
    }

    private static func isTruthy(_ value: String) -> Bool {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "y", "on":
            return true
        default:
            return false
        }
    }

    private func trimmedEnvironmentValue(_ key: String) -> String? {
        let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    private func trimmedDefaultsString(_ key: String) -> String? {
        let value = userDefaults.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    private func fileURL(expandingTildeIn path: String, isDirectory: Bool) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: isDirectory)
    }

    private func ancestorCandidates(from root: URL, relativePath: String) -> [URL] {
        var candidates: [URL] = []
        var cursor = root.standardizedFileURL

        for _ in 0..<10 {
            candidates.append(cursor.appendingPathComponent(relativePath, isDirectory: false))
            let parent = cursor.deletingLastPathComponent()
            if parent.path == cursor.path { break }
            cursor = parent
        }

        return candidates
    }

    private func uniqueStandardized(_ candidates: [URL]) -> [URL] {
        var seen: Set<String> = []
        return candidates.filter { candidate in
            let path = candidate.standardizedFileURL.path
            guard !seen.contains(path) else { return false }
            seen.insert(path)
            return true
        }
    }

    private func defaultCLIPSupportDirectory() -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base
            .appendingPathComponent("Mandoline", isDirectory: true)
            .appendingPathComponent("CLIP", isDirectory: true)
    }

    private func defaultHFHome() -> URL {
        defaultCLIPSupportDirectory().appendingPathComponent("hf-home", isDirectory: true)
    }

    private func defaultOutputURL() -> URL {
        fileManager.temporaryDirectory
            .appendingPathComponent("mandoline-clip-index-\(UUID().uuidString)", isDirectory: false)
            .appendingPathExtension("json")
    }

    private func prepareOutputLocation(_ outputURL: URL) throws {
        let directory = outputURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }
    }
}

private final class LockedFlag {
    private let lock = NSLock()
    private var value = false

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }

    var isSet: Bool {
        lock.lock()
        let snapshot = value
        lock.unlock()
        return snapshot
    }
}

private final class LockedDataBuffer {
    private let lock = NSLock()
    private var data = Data()

    func append(_ newData: Data) {
        guard !newData.isEmpty else { return }
        lock.lock()
        data.append(newData)
        lock.unlock()
    }

    var stringValue: String {
        lock.lock()
        let snapshot = data
        lock.unlock()
        return String(data: snapshot, encoding: .utf8) ?? ""
    }
}

private final class LockedLineBuffer {
    private let lock = NSLock()
    private var pending = ""

    func append(_ data: Data) -> [String] {
        guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty else { return [] }
        lock.lock()
        pending += chunk
        let parts = pending.components(separatedBy: .newlines)
        pending = parts.last ?? ""
        let complete = Array(parts.dropLast()).filter { !$0.isEmpty }
        lock.unlock()
        return complete
    }

    func flush() -> [String] {
        lock.lock()
        let line = pending
        pending = ""
        lock.unlock()
        return line.isEmpty ? [] : [line]
    }
}
