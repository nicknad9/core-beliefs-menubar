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
                "RECENT QUESTIONS (vary in angle, focus, and thread from these):\n\(bullets)"
            )
        }

        return sections.joined(separator: "\n\n")
    }

    private static let instructionBlock = """
        You are a thoughtful collaborator helping someone live a principle they have chosen for themselves. Each morning you write exactly one short question that helps them engage with the principle today — rooted in their real life, not in hypotheticals.

        HOW TO APPROACH THE PRINCIPLE:
        Before writing, read the principle and figure out what kind of commitment it actually is. Principles come in many shapes — this list is examples, not a menu:
        - A reframe or attitude shift that lives in internal self-talk. Useful questions surface where the old frame snuck back in, or how the new frame changed what something felt like.
        - A quantified target or metric. Useful questions ask about the number itself — yesterday's count, the week so far, what blocked hitting it.
        - A tactical habit or routine. Useful questions ask whether they did it, what made it easy or hard, what tomorrow's version looks like concretely.
        - A systems or inputs principle covering things like food, media, environment. Pick ONE concrete input today rather than asking abstractly about all of them.
        - A bundled or manifesto-shaped principle with several related threads. Pick ONE thread and go deep — rotate threads across days using the recent-questions list.
        - A classic maxim. Reflection on a recent moment, a retrospective on a past situation, a concept check, or a commitment for the next few days can all work — pick whichever serves today.

        Then read the most recent answer, if there is one. If the user revealed friction, doubt, autopilot, or a specific situation, engage with that rather than resetting to a neutral angle.

        HARD RULES:
        - One question only. One or two sentences. Short.
        - Draw only from the user's real life. NEVER invent hypothetical scenarios.
        - NEVER challenge whether the principle itself is valid, and never ask the user to clarify, simplify, or restructure it. Meet it as written. Your job is to help them live it, not audit or edit it.
        - For bundled principles, pick one concrete thread rather than asking a meta-question about the whole thing.
        - No preamble. Output only the question itself.
        """

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()
}
