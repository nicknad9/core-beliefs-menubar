import Foundation

public enum PromptBuilder {
    public static func build(
        principle: Principle,
        history: [Entry],
        lastQuestionBodies: [String],
        date: Date
    ) -> String {
        var sections: [String] = []

        sections.append(Self.instructionBlock)

        sections.append("PRINCIPLE:\n\(principle.text)")

        sections.append("DATE:\n\(Self.dateFormatter.string(from: date))")

        if history.isEmpty {
            sections.append(
                "HISTORY:\nThis is the first time you're asking about this principle. "
                + "There is no prior history to avoid repeating."
            )
        } else {
            let lines = history.map { entry -> String in
                let label = entry.kind == .question ? "Q" : "A"
                let stamp = Self.dateFormatter.string(from: entry.createdAt)
                return "[\(stamp)] \(label): \(entry.content)"
            }
            sections.append("HISTORY (last 30 days):\n" + lines.joined(separator: "\n"))
        }

        if !lastQuestionBodies.isEmpty {
            let bullets = lastQuestionBodies.map { "- \($0)" }.joined(separator: "\n")
            sections.append(
                "AVOID REPEATING THE SHAPE OR TYPE OF THESE RECENT QUESTIONS:\n\(bullets)"
            )
        }

        return sections.joined(separator: "\n\n")
    }

    private static let instructionBlock = """
        You are a thoughtful interviewer helping someone stay aligned with a principle they have already chosen to live by. Generate exactly one short question.

        QUESTION TYPES (pick one):
        1. Reflection — "Where did this principle show up for you this week? Did you notice yourself applying it, or resisting it?"
        2. Concept — "What's the core of this principle in your own words right now? Why does it still matter to you?"
        3. Retrospective — "Think of the last time you were in X kind of situation. How did you handle it? Would this principle change anything next time?"
        4. Commitment — "What's one situation in the next few days where you want to lead with this principle?"

        Prefer Commitment when the last question was Retrospective, to close the experiment loop.

        HARD RULES:
        - Draw only from the user's real life. NEVER invent hypothetical scenarios.
        - NEVER challenge whether the principle itself is valid. The user has committed to it. Help them apply it, not audit it.
        - One question only. No multi-part questions.
        - One or two sentences. Short.
        - No preamble. Output only the question itself.
        - No clinical vocabulary. Use the structure of the type, not the name.
        """

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()
}
