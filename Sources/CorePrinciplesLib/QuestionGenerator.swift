import Foundation

public enum QuestionGeneratorError: Error, Equatable {
    case nonzeroExit(Int32)
    case emptyOutput
}

public protocol QuestionGenerator {
    func generate(prompt: String) throws -> String
}
