import Foundation

public enum SchedulerOutcome {
    case ready(Principle, Entry, answer: Entry?)
    case empty
    case failed(Error)
}

public final class DailyQuestionScheduler {
    private let dataService: DataService
    private let generator: QuestionGenerator
    private let queue: DispatchQueue
    private let completionQueue: DispatchQueue

    public init(
        dataService: DataService,
        generator: QuestionGenerator,
        completionQueue: DispatchQueue = .main
    ) {
        self.dataService = dataService
        self.generator = generator
        self.queue = DispatchQueue(label: "coreprinciples.scheduler")
        self.completionQueue = completionQueue
    }

    public func today(completion: @escaping (SchedulerOutcome) -> Void) {
        queue.async { [dataService, generator, completionQueue] in
            let outcome = Self.resolve(dataService: dataService, generator: generator)
            completionQueue.async { completion(outcome) }
        }
    }

    private static func resolve(
        dataService: DataService,
        generator: QuestionGenerator
    ) -> SchedulerOutcome {
        do {
            if let existing = try dataService.todaysQuestion() {
                guard let principle = try dataService.findPrinciple(id: existing.principleId) else {
                    return .failed(SchedulerError.principleMissing(id: existing.principleId))
                }
                let answer = try dataService.todaysAnswer()
                return .ready(principle, existing, answer: answer)
            }

            guard let principle = try dataService.pickTodaysPrinciple(), let principleId = principle.id else {
                return .empty
            }

            let historyCutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date())
                ?? Date.distantPast
            let history = try dataService.recentEntries(principleId: principleId, since: historyCutoff)
            let lastTwo = try dataService.lastQuestionBodies(principleId: principleId, limit: 2)

            let prompt = PromptBuilder.build(
                principle: principle,
                history: history,
                lastQuestionBodies: lastTwo,
                date: Date()
            )

            let text: String
            do {
                text = try generator.generate(prompt: prompt)
            } catch {
                return .failed(error)
            }

            let question = try dataService.insertQuestion(principleId: principleId, content: text)
            let updatedPrinciple = (try? dataService.findPrinciple(id: principleId)) ?? principle
            return .ready(updatedPrinciple, question, answer: nil)
        } catch {
            return .failed(error)
        }
    }

    public enum SchedulerError: Error, Equatable {
        case principleMissing(id: Int64)
    }
}
