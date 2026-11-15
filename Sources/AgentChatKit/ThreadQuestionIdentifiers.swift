import Foundation

public struct ThreadQuestionIdentifiers<ID: Hashable> {
    public var question: String?
    public var context: String?
    public var answer: (ID) -> String?
    public var reply: String?
    public var waitWhat: String

    public init(question: String? = nil, context: String? = nil, answer: @escaping (ID) -> String? = { _ in nil },
                reply: String? = nil, waitWhat: String = "wait-what") {
        self.question = question
        self.context = context
        self.answer = answer
        self.reply = reply
        self.waitWhat = waitWhat
    }
}
