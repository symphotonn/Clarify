import QuartzCore

final class DoublePressDetector: @unchecked Sendable {
    private var lastPressTime: CFTimeInterval = 0
    private let threshold: TimeInterval

    init(threshold: TimeInterval = Constants.doublePressInterval) {
        self.threshold = threshold
    }

    /// Records a key press and returns `true` if it was a double-press.
    func recordPress() -> Bool {
        let now = CACurrentMediaTime()
        let elapsed = now - lastPressTime
        lastPressTime = now

        return elapsed < threshold && elapsed > 0.05 // Debounce very fast repeats
    }

    func reset() {
        lastPressTime = 0
    }
}
