import Foundation

struct TimerHeartbeat: Codable {
    var version = 1
    let timestamp: Date
    let elapsed: TimeInterval
    let duration: TimeInterval
    let mode: Int
    let sessionID: UUID
    let archetype: FocusArchetype?
    let tier: IntensityTier?
    let running: Bool
    let pauseBank: PauseBank
    let sessions: Int
    var valid: Bool {
        version == 1 && (0...1).contains(mode) && duration.isFinite && duration >= 60 && duration <= 10800 &&
        elapsed.isFinite && elapsed >= 0 && elapsed < duration && timestamp.timeIntervalSince1970.isFinite &&
        (mode != 0 || (archetype != nil && tier != nil)) && (0...300).contains(pauseBank.available)
    }
    func graceRemaining(at now: Date) -> TimeInterval {
        guard valid, timestamp.timeIntervalSince(now) <= 5 else { return 0 }
        let recovery = max(0, 180 - max(0, now.timeIntervalSince(timestamp)))
        if !running && mode == 0 && tier != .zen { return min(recovery, pauseBank.remaining(at: now)) }
        return recovery
    }
}

// This actor performs encoding and atomic file I/O away from the main actor.
// Revisions prevent an older queued write from resurrecting a cleared session.
actor TimerHeartbeatStore {
    let url: URL
    private var revision = 0
    init(url: URL) { self.url = url }
    func load() -> TimerHeartbeat? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 16384,
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(TimerHeartbeat.self, from: data), snapshot.valid else { return nil }
        return snapshot
    }
    @discardableResult func save(_ snapshot: TimerHeartbeat, revision next: Int) -> Bool {
        guard next > revision else { return true }
        revision = next
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: .atomic)
            return true
        } catch { return false }
    }
    @discardableResult func clear(revision next: Int) -> Bool {
        guard next > revision else { return true }
        revision = next
        do {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            return true
        } catch { return false }
    }
}

@MainActor extension FocusModel {
    func persistHeartbeat(at now: Date = Date(), force: Bool = false) {
        guard !heartbeatShuttingDown, !recoveryChecking, recoverySnapshot == nil,
              hasProgress, !completed, let store=heartbeatStore else {return}
        let mark=ProcessInfo.processInfo.systemUptime
        guard force || mark-lastHeartbeatMark >= 3 else {return}
        lastHeartbeatMark=mark
        let snapshot=TimerHeartbeat(timestamp:now,elapsed:max(0,clock.duration-clock.seconds(at:now)),duration:clock.duration,
                                    mode:mode,sessionID:sessionID,archetype:sessionArchetype,tier:sessionTier,
                                    running:clock.running,pauseBank:pauseBank,sessions:sessions)
        guard snapshot.valid else {return}
        heartbeatRevision += 1;let revision=heartbeatRevision
        Task { [weak self] in
            let saved=await store.save(snapshot,revision:revision)
            if !saved, let self, !self.heartbeatStorageFailed {
                self.heartbeatStorageFailed=true
                self.message="Couldn’t save recovery data on this Mac. Your timer can continue."
            }
        }
    }
    func clearHeartbeat() {
        lastHeartbeatMark = -Double.infinity
        guard let store=heartbeatStore else {return}
        heartbeatRevision += 1;let revision=heartbeatRevision
        Task {await store.clear(revision:revision)}
    }
    func flushHeartbeatClear() async {
        heartbeatShuttingDown=true
        guard let store=heartbeatStore else {return}
        heartbeatRevision += 1
        await store.clear(revision:heartbeatRevision)
    }
    func loadRecovery(at now: Date = Date()) async {
        guard let store=heartbeatStore else {recoveryChecking=false;return}
        let saved=await store.load()
        guard !heartbeatShuttingDown else {recoveryChecking=false;return}
        guard let snapshot=saved else {clearHeartbeat();recoveryChecking=false;return}
        if journey.records.contains(where:{$0.id==snapshot.sessionID}) || journey.endedSessions.contains(snapshot.sessionID) || journey.failures.contains(where:{$0.id==snapshot.sessionID}) {
            clearHeartbeat();recoveryChecking=false;return
        }
        recoverySnapshot=snapshot;recoverySeconds=snapshot.graceRemaining(at:now);recoveryChecking=false
        if recoverySeconds > 0 {startPulse()} else {discardRecovery(at:now,expired:true)}
    }
    private func restoreContext(_ snapshot:TimerHeartbeat,at now:Date) {
        sessionID=snapshot.sessionID;mode=snapshot.mode
        sessionArchetype=snapshot.archetype;sessionTier=snapshot.tier
        if let path=snapshot.archetype {selectedArchetype=path}
        if let tier=snapshot.tier {selectedTier=tier}
        clock=SessionClock(duration:snapshot.duration,remaining:snapshot.duration-snapshot.elapsed)
        remaining=clock.remaining;completed=false;sessions=snapshot.sessions
        pauseBank=snapshot.pauseBank;pauseRemaining=pauseBank.remaining(at:now)
        lastTick=Int(snapshot.elapsed/300);awardSummary=nil
    }
    func resumeRecovery(at now:Date = Date()) {
        guard let snapshot=recoverySnapshot else {return}
        guard snapshot.graceRemaining(at:now)>0 else {discardRecovery(at:now,expired:true);return}
        stopPulse();confirmRecoveryEnd=false;recoverySnapshot=nil;recoverySeconds=0
        restoreContext(snapshot,at:now)
        // Recovery is not a voluntary pause: retain the snapshot's XP-tax flag.
        pauseBank.resume(at:now);pauseRemaining=pauseBank.remaining(at:now)
        clock.start(at:now);startPulse();message=nil
        if selectedID != nil && audioEnabled {playAudio()}
        persistHeartbeat(at:now,force:true);onChange?()
    }
    func discardRecovery(at now:Date = Date(),expired:Bool = false) {
        guard let snapshot=recoverySnapshot else {return}
        stopPulse();confirmRecoveryEnd=false;recoverySnapshot=nil;recoverySeconds=0
        restoreContext(snapshot,at:now)
        endSession()
        message=expired ? "Recovery window expired. The interrupted session ended under its normal rules." : "Interrupted session ended."
    }
}
