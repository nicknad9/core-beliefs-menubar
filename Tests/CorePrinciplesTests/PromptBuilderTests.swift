import XCTest
@testable import CorePrinciplesLib

final class PromptBuilderTests: XCTestCase {
    private func principle(_ text: String = "Be patient with slow things.") -> Principle {
        var p = Principle(text: text)
        p.id = 1
        return p
    }

    private func entry(_ kind: EntryKind, _ content: String, daysAgo: Int = 0) -> Entry {
        let createdAt = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        var e = Entry(principleId: 1, kind: kind, content: content, createdAt: createdAt)
        e.id = Int64(daysAgo + 100)
        return e
    }

    func test_build_includesPrincipleText_andInstructionBlock() {
        let prompt = PromptBuilder.build(
            principle: principle("Move slowly and finish."),
            history: [],
            lastQuestionBodies: [],
            date: Date()
        )

        XCTAssertTrue(prompt.contains("Move slowly and finish."), "principle text must appear")
        XCTAssertTrue(prompt.contains("Reflection"), "type catalog must appear")
        XCTAssertTrue(prompt.contains("Commitment"), "type catalog must appear")
        XCTAssertTrue(prompt.contains("NEVER invent hypothetical"), "anti-hypothetical rule must appear")
        XCTAssertTrue(prompt.contains("NEVER challenge whether the principle itself is valid"),
                      "no-validity-challenge rule must appear")
        XCTAssertTrue(prompt.contains("One question only"), "single-question rule must appear")
        XCTAssertTrue(prompt.contains("No preamble"), "no-preamble rule must appear")
    }

    func test_build_withHistory_includesRecentEntries() {
        let history = [
            entry(.question, "Where did patience show up this week?", daysAgo: 7),
            entry(.answer, "I waited out a tense moment with a coworker.", daysAgo: 7),
        ]
        let prompt = PromptBuilder.build(
            principle: principle(),
            history: history,
            lastQuestionBodies: [],
            date: Date()
        )

        XCTAssertTrue(prompt.contains("HISTORY (last 30 days):"), "history block header must appear")
        XCTAssertTrue(prompt.contains("Where did patience show up this week?"))
        XCTAssertTrue(prompt.contains("I waited out a tense moment with a coworker."))
        XCTAssertTrue(prompt.contains("Q: "), "question rows must be labeled")
        XCTAssertTrue(prompt.contains("A: "), "answer rows must be labeled")
        XCTAssertFalse(prompt.contains("This is the first time"),
                       "first-time instruction must NOT appear when history exists")
    }

    func test_build_emptyHistory_addsFirstTimeInstruction_andOmitsHistoryBody() {
        let prompt = PromptBuilder.build(
            principle: principle(),
            history: [],
            lastQuestionBodies: [],
            date: Date()
        )

        XCTAssertTrue(prompt.contains("This is the first time you're asking about this principle."),
                      "first-time instruction must appear when history is empty")
        XCTAssertFalse(prompt.contains("HISTORY (last 30 days):"),
                       "history-body header must NOT appear when empty")
    }

    func test_build_withLastTwoQuestions_includesAntiRepeatBlock() {
        let lastTwo = [
            "What's one situation in the next few days where you want to lead with this?",
            "Where did this principle show up this week?",
        ]
        let prompt = PromptBuilder.build(
            principle: principle(),
            history: [],
            lastQuestionBodies: lastTwo,
            date: Date()
        )

        XCTAssertTrue(prompt.contains("AVOID REPEATING THE SHAPE OR TYPE OF THESE RECENT QUESTIONS:"),
                      "anti-repeat header must appear")
        for body in lastTwo {
            XCTAssertTrue(prompt.contains(body), "last-two question body '\(body)' must appear")
        }
    }

    func test_build_emptyLastTwoQuestions_omitsAntiRepeatBlock() {
        let prompt = PromptBuilder.build(
            principle: principle(),
            history: [],
            lastQuestionBodies: [],
            date: Date()
        )

        XCTAssertFalse(prompt.contains("AVOID REPEATING"),
                       "anti-repeat block must NOT appear when lastQuestionBodies is empty")
    }
}
