import XCTest
@testable import CorePrinciplesLib

final class LLMPathResolverTests: XCTestCase {
    func testResolveReturnsTrimmedPathOnSuccess() throws {
        let resolver = LLMPathResolver(runWhichLLM: {
            (stdout: "/opt/homebrew/bin/llm\n", exitCode: 0)
        })
        XCTAssertEqual(try resolver.resolve(), "/opt/homebrew/bin/llm")
    }

    func testResolveThrowsNotFoundWhenStdoutEmpty() {
        let resolver = LLMPathResolver(runWhichLLM: {
            (stdout: "", exitCode: 0)
        })
        XCTAssertThrowsError(try resolver.resolve()) { error in
            XCTAssertEqual(error as? LLMPathResolver.ResolveError, .notFound)
        }
    }

    func testResolveThrowsNotFoundWhenStdoutOnlyWhitespace() {
        let resolver = LLMPathResolver(runWhichLLM: {
            (stdout: "   \n\t\n", exitCode: 0)
        })
        XCTAssertThrowsError(try resolver.resolve()) { error in
            XCTAssertEqual(error as? LLMPathResolver.ResolveError, .notFound)
        }
    }

    func testResolveThrowsNonzeroExit() {
        let resolver = LLMPathResolver(runWhichLLM: {
            (stdout: "", exitCode: 1)
        })
        XCTAssertThrowsError(try resolver.resolve()) { error in
            XCTAssertEqual(error as? LLMPathResolver.ResolveError, .nonzeroExit(1))
        }
    }

    func testResolveReturnsFirstNonEmptyLine() throws {
        let resolver = LLMPathResolver(runWhichLLM: {
            (stdout: "\n  /usr/local/bin/llm  \nshellrc warning: ...\n", exitCode: 0)
        })
        XCTAssertEqual(try resolver.resolve(), "/usr/local/bin/llm")
    }

    func testResolveSurfacesRunnerError() {
        struct FakeError: Error {}
        let resolver = LLMPathResolver(runWhichLLM: {
            throw FakeError()
        })
        XCTAssertThrowsError(try resolver.resolve()) { error in
            XCTAssertTrue(error is FakeError)
        }
    }
}
