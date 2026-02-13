import Foundation

final class ExplanationBuffer {
    private var buffer: [StreamingExplanation] = []
    private let capacity: Int

    init(capacity: Int = Constants.explanationBufferCapacity) {
        self.capacity = capacity
    }

    func push(_ explanation: StreamingExplanation) {
        buffer.append(explanation)
        if buffer.count > capacity {
            buffer.removeFirst()
        }
    }

    func last() -> StreamingExplanation? {
        buffer.last
    }

    func clear() {
        buffer.removeAll()
    }

    var count: Int { buffer.count }
}
