import Foundation

public struct LLMQuestionGenerator: QuestionGenerator {
    public typealias Runner = (_ binaryPath: String, _ arguments: [String]) throws -> (stdout: String, exitCode: Int32)

    public let binaryPath: String
    public let model: String
    public var runner: Runner

    public init(
        binaryPath: String,
        model: String = "claude-sonnet-4-6",
        runner: @escaping Runner = LLMQuestionGenerator.defaultRunner
    ) {
        self.binaryPath = binaryPath
        self.model = model
        self.runner = runner
    }

    public func generate(prompt: String) throws -> String {
        let result = try runner(binaryPath, ["-m", model, prompt])
        guard result.exitCode == 0 else {
            throw QuestionGeneratorError.nonzeroExit(result.exitCode)
        }
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw QuestionGeneratorError.emptyOutput
        }
        return trimmed
    }

    public static let defaultRunner: Runner = { binaryPath, arguments in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: data, encoding: .utf8) ?? ""
        return (stdout: stdout, exitCode: process.terminationStatus)
    }
}
