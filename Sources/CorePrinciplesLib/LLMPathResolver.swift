import Foundation

public struct LLMPathResolver {
    public enum ResolveError: Error, Equatable {
        case notFound
        case nonzeroExit(Int32)
    }

    public typealias Runner = () throws -> (stdout: String, exitCode: Int32)

    public var runWhichLLM: Runner

    public init(runWhichLLM: @escaping Runner = LLMPathResolver.defaultRunner) {
        self.runWhichLLM = runWhichLLM
    }

    public func resolve() throws -> String {
        let result = try runWhichLLM()
        guard result.exitCode == 0 else {
            throw ResolveError.nonzeroExit(result.exitCode)
        }
        let firstNonEmpty = result.stdout
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        guard let path = firstNonEmpty else {
            throw ResolveError.notFound
        }
        return path
    }

    public static let defaultRunner: Runner = {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "which llm"]

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
