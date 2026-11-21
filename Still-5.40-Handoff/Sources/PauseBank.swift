import Foundation

struct PauseBank: Codable {
    private(set) var available: TimeInterval = 300
    private(set) var pausedAt: Date?
    private(set) var wasPaused = false
    func remaining(at now: Date) -> TimeInterval {
        max(0, available - (pausedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0))
    }
    mutating func pause(at now: Date) {
        guard pausedAt == nil else { return }
        wasPaused = true; pausedAt = now
    }
    mutating func preserveMultiplier(wasPaused previous: Bool) { wasPaused = previous }
    mutating func resume(at now: Date) { available = remaining(at: now); pausedAt = nil }
}
