import AppKit
import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import Carbon
import Combine
import QuartzCore

struct Track: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var filename: String
}

struct ParkedNote: Codable, Identifiable {
    let id: UUID
    let text: String?
    let audioFile: String?
    let createdAt: Date
}

// Deadline based timing keeps the display accurate when the run loop is busy.
struct SessionClock {
    var duration: TimeInterval
    var remaining: TimeInterval
    var deadline: Date?
    var running: Bool { deadline != nil }
    mutating func start(at now: Date) { deadline = now.addingTimeInterval(remaining) }
    mutating func pause(at now: Date) { remaining = seconds(at: now); deadline = nil }
    func seconds(at now: Date) -> TimeInterval { max(0, deadline?.timeIntervalSince(now) ?? remaining) }
    func tickBoundary(at now: Date) -> Int { Int((duration - seconds(at: now)) / 300) }
    mutating func reset(_ seconds: TimeInterval) { duration = seconds; remaining = seconds; deadline = nil }
}

enum FocusArchetype: String, Codable, CaseIterable, Identifiable {
    case systemBuilding, skillMastery, providence, selfOvercoming, legacy
    var id: String { rawValue }
    var title: String {
        switch self {
        case .systemBuilding: return "Creation & System Building"
        case .skillMastery: return "Skill Mastery"
        case .providence: return "Providence & Protection"
        case .selfOvercoming: return "Self-Overcoming"
        case .legacy: return "Legacy & Lineage"
        }
    }
    var purpose: String {
        switch self {
        case .systemBuilding: return "Build systems that make future work easier."
        case .skillMastery: return "Practice a craft and sharpen a skill."
        case .providence: return "Care for the responsibilities that sustain your life."
        case .selfOvercoming: return "Do the difficult thing you have been avoiding."
        case .legacy: return "Create work that will matter beyond today."
        }
    }
    var symbol: String {
        switch self {
        case .systemBuilding: return "gearshape.2.fill"
        case .skillMastery: return "hammer.fill"
        case .providence: return "sun.max"
        case .selfOvercoming: return "shield.lefthalf.filled"
        case .legacy: return "leaf"
        }
    }
    func rank(at level: Int) -> String {
        let index = level >= 10 ? 3 : level >= 5 ? 2 : level >= 2 ? 1 : 0
        switch self {
        case .systemBuilding: return ["Builder", "Architect", "Systems thinker", "System steward"][index]
        case .skillMastery: return ["Learner", "Practitioner", "Specialist", "Craftsperson"][index]
        case .providence: return ["Caretaker", "Steward", "Provider", "Anchor"][index]
        case .selfOvercoming: return ["Challenger", "Wayfinder", "Trailblazer", "Pathfinder"][index]
        case .legacy: return ["Contributor", "Creator", "Mentor", "Legacy builder"][index]
        }
    }
}

enum IntensityTier: String, Codable, CaseIterable, Identifiable {
    case zen, ranked, hardcore
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var multiplier: Double { self == .zen ? 1 : self == .ranked ? 1.5 : 2 }
    var color: Color {
        switch self {
        case .zen: return Color(red: 0.65, green: 0.91, blue: 0.73)
        case .ranked: return Color(red: 0.36, green: 0.87, blue: 0.58)
        case .hardcore: return Color(red: 0.90, green: 0.48, blue: 0.20)
        }
    }
    var detail: String {
        switch self {
        case .zen: return "1× XP · No penalty for ending early"
        case .ranked: return "1.5× unbroken / 1× paused · 5 min pause bank · Ending or quitting early: lose 15% XP and reset streak"
        case .hardcore: return "2× unbroken / 1× paused · 5 min pause bank · Ending or quitting early: lose 50% XP and record a failure"
        }
    }
}

struct FailureRecord: Codable, Identifiable {
    let id: UUID
    let archetype: FocusArchetype
    let date: Date
}
struct FocusRecord: Codable, Identifiable {
    let id: UUID
    let archetype: FocusArchetype
    let minutes: Int
    let completedAt: Date
    var earnedXP: Int? = nil
    var tier: IntensityTier? = nil
    var taskLabel: String? = nil
    var wasPaused: Bool? = nil
    var achievementTag: FocusArchetype? = nil
    var pillarSchema: Int? = nil
}
struct ArchetypeProgress {
    let xp: Int
    let sessions: Int
    var level: Int { xp / 100 + 1 }
    var xpToNextLevel: Int { 100 - xp % 100 }
    var milestones: [Bool] { [sessions >= 1, xp >= 100, xp >= 500, xp >= 1000] }
}
struct FocusJourney: Codable {
    private(set) var records: [FocusRecord] = []
    var testingUnlocked = false
    var game = FocusGame()
    var endedSessions: Set<UUID> = []
    var deductions: [String: Int] = [:]
    var failures: [FailureRecord] = []
    var unlockedBadges: [String] = []
    var streak = 0
    var lastFocusDay: Date?
    enum CodingKeys: String, CodingKey { case records, deductions, failures, unlockedBadges, streak, lastFocusDay, endedSessions, game, testingUnlocked }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        testingUnlocked = try c.decodeIfPresent(Bool.self,forKey:.testingUnlocked) ?? false
        game = try c.decodeIfPresent(FocusGame.self, forKey: .game) ?? FocusGame()
        endedSessions = try c.decodeIfPresent(Set<UUID>.self, forKey: .endedSessions) ?? []
        records = try c.decodeIfPresent([FocusRecord].self, forKey: .records) ?? []
        deductions = try c.decodeIfPresent([String: Int].self, forKey: .deductions) ?? [:]
        failures = try c.decodeIfPresent([FailureRecord].self, forKey: .failures) ?? []
        unlockedBadges = try c.decodeIfPresent([String].self, forKey: .unlockedBadges) ?? []
        streak = try c.decodeIfPresent(Int.self, forKey: .streak) ?? 0
        lastFocusDay = try c.decodeIfPresent(Date.self, forKey: .lastFocusDay)
    }
    var currentStreak: Int {
        guard let last = lastFocusDay else { return 0 }
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
        return calendar.isDateInToday(last) || calendar.isDate(last, inSameDayAs: yesterday) || game.coversAbsence(from: last, to: Date()) ? streak : 0
    }
    var rankedCount: Int { records.filter { $0.tier == .ranked }.count }
    var totalXP: Int {
        var balances:[String:Int]=[:]
        for record in records {balances[FocusPillar.containing(record.archetype).rawValue,default:0] += record.earnedXP ?? record.minutes}
        for track in FocusArchetype.allCases {balances[FocusPillar.containing(track).rawValue,default:0] -= deductions[track.rawValue] ?? 0}
        return balances.values.reduce(0){$0+max(0,$1)}
    }
    mutating func tag(session:UUID,track:FocusArchetype) {
        guard let index=records.firstIndex(where:{$0.id==session}) else {return}
        records[index].achievementTag = records[index].achievementTag == track ? nil : track
    }
    func progress(for archetype: FocusArchetype) -> ArchetypeProgress {
        let matching = records.filter { $0.archetype == archetype }
        return ArchetypeProgress(xp: max(0, matching.reduce(0) { $0 + ($1.earnedXP ?? $1.minutes) } - (deductions[archetype.rawValue] ?? 0)), sessions: matching.count)
    }
    @discardableResult mutating func award(session: UUID, archetype: FocusArchetype, minutes: Int, at date: Date, tier: IntensityTier = .zen, taskLabel: String? = nil, wasPaused: Bool = false) -> Bool {
        guard minutes > 0, !endedSessions.contains(session), !records.contains(where: { $0.id == session }), !failures.contains(where: { $0.id == session }) else { return false }
        records.append(FocusRecord(id: session, archetype: archetype, minutes: minutes, completedAt: date, earnedXP: Int((Double(minutes) * (game.active?.id == session && game.active?.overclock == true ? 3 : wasPaused ? 1 : tier.multiplier)).rounded()), tier: tier, taskLabel: taskLabel, wasPaused: wasPaused || (game.active?.id == session && game.active?.paused == true), pillarSchema: 1))
        let calendar = Calendar.current
        if let last = lastFocusDay {
            if !calendar.isDate(last, inSameDayAs: date) {
                streak = calendar.isDate(last, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: date)!) || game.coversAbsence(from: last, to: date) ? streak + 1 : 1
            } else if streak == 0 { streak = 1 }
        } else { streak = 1 }
        lastFocusDay = date
        game.finish(id: session, minutes: minutes, tier: tier, wasPaused: wasPaused, at: date)
        return true
    }
    mutating func endEarly(session: UUID, archetype: FocusArchetype, tier: IntensityTier, at date: Date) {
        guard tier != .zen, !endedSessions.contains(session), !records.contains(where: { $0.id == session }), !failures.contains(where: { $0.id == session }) else { return }
        endedSessions.insert(session)
        game.fail(tier: tier, at: date)
        let loss = Int((Double(pillarProgress(for:FocusPillar.containing(archetype)).xp) * (tier == .ranked ? 0.15 : 0.50)).rounded(.down))
        deductions[archetype.rawValue, default: 0] += loss
        if tier == .ranked { streak = 0; lastFocusDay = nil }
        if tier == .hardcore { failures.append(FailureRecord(id: session, archetype: archetype, date: date)) }
    }
}

@MainActor final class FocusModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var clock = SessionClock(duration: 1500, remaining: 1500)
    @Published var remaining: TimeInterval = 1500
    @Published var mode = 0
    @Published var pillarSpin: Double = 0
    @Published var settingsTab = 0
    @Published var page = 0
    @Published var circularNotch = UserDefaults.standard.bool(forKey:"circularNotch") {didSet {UserDefaults.standard.set(circularNotch,forKey:"circularNotch")}}
    @Published var hoverToOpen = UserDefaults.standard.bool(forKey:"hoverToOpen") {didSet {UserDefaults.standard.set(hoverToOpen,forKey:"hoverToOpen")}}
    @Published var expanded = true
    @Published var reveal: Double = 1
    @Published var contentVisibility: Double = 1
    @Published var glassTransparency = UserDefaults.standard.object(forKey: "glassTransparency") as? Double ?? 0.35 { didSet { UserDefaults.standard.set(glassTransparency, forKey: "glassTransparency") } }
    @Published var audioEnabled = UserDefaults.standard.object(forKey: "audioEnabled") as? Bool ?? true { didSet { UserDefaults.standard.set(audioEnabled, forKey: "audioEnabled"); if clock.running && audioEnabled { playAudio() } else { pauseAudio() } } }
    @Published var focusMinutes = UserDefaults.standard.object(forKey: "focus") as? Int ?? 25 { didSet { saveSettings(); resetIfIdle() } }
    @Published var breakMinutes = UserDefaults.standard.object(forKey: "rest") as? Int ?? 5 { didSet { saveSettings(); resetIfIdle() } }
    @Published var tickEnabled = UserDefaults.standard.object(forKey: "tick") as? Bool ?? true { didSet { saveSettings() } }
    @Published var dingEnabled = UserDefaults.standard.object(forKey: "ding") as? Bool ?? true { didSet { saveSettings() } }
    @Published var autoStart = UserDefaults.standard.bool(forKey: "auto") { didSet { saveSettings() } }
    @Published var soundVolume = UserDefaults.standard.object(forKey: "soundVolume") as? Double ?? 0.45 { didSet { saveSettings() } }
    @Published var audioVolumeDrag: Double?
    @Published var musicVolume = UserDefaults.standard.object(forKey: "musicVolume") as? Double ?? 0.45 { didSet { player?.volume = Float(musicVolume); saveSettings() } }
    @Published var tracks: [Track] = []
    @Published var selectedID: String? = UserDefaults.standard.string(forKey: "selected")
    @Published var audioPlaying = false
    @Published var sessions = 0
    @Published var message: String?
    @Published var parkedNotes: [ParkedNote] = []
    @Published var notePendingDeletion: ParkedNote?
    @Published var confirmNoteDeletion = false
    @Published var parkingDraft = ""
    @Published var isRecordingNote = false
    var noteRecorder: AVAudioRecorder?
    var notePlayer: AVAudioPlayer?
    var recordingFile: URL?
    var parkingDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Still/ParkingLot", isDirectory: true)
    }
    func saveParkedNotes() { UserDefaults.standard.set(try? JSONEncoder().encode(parkedNotes), forKey: "parkingLot.v1") }
    func addParkedText() {
        let text = parkingDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        parkedNotes.insert(ParkedNote(id: UUID(), text: text, audioFile: nil, createdAt: Date()), at: 0)
        parkingDraft = ""; saveParkedNotes(); countParkedThought()
    }
    func countParkedThought() {
        guard mode == 0, clock.running, journey.game.active?.id == sessionID else {return}
        journey.game.active?.parkedThoughts = (journey.game.active?.parkedThoughts ?? 0) + 1
        saveJourney()
    }
    func recordNote() {
        if isRecordingNote { finishNoteRecording(); return }
        guard !importing else { return }
        importing = true
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }; self.importing = false
                guard granted else { self.message = "Microphone access is off. Allow it in System Settings to record a voice note."; return }
                guard self.page == 7 || (self.page == 0 && self.hasProgress && self.expanded) else { return }
                do {
                    try FileManager.default.createDirectory(at: self.parkingDirectory, withIntermediateDirectories: true)
                    let url = self.parkingDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
                    let recorder = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64000])
                    guard recorder.record() else { self.message = "Couldn’t start recording. Check microphone access."; return }
                    self.noteRecorder = recorder; self.recordingFile = url; self.isRecordingNote = true
                } catch { self.message = "Couldn’t start recording: \(error.localizedDescription)" }
            }
        }
    }
    func finishNoteRecording() {
        guard isRecordingNote, let url = recordingFile else { return }
        noteRecorder?.stop(); noteRecorder = nil; recordingFile = nil; isRecordingNote = false
        parkedNotes.insert(ParkedNote(id: UUID(), text: nil, audioFile: url.lastPathComponent, createdAt: Date()), at: 0); saveParkedNotes(); countParkedThought()
    }
    func playParkedNote(_ note: ParkedNote) {
        guard let filename = note.audioFile else { return }
        do {
            if notePlayer?.isPlaying == true { notePlayer?.stop(); notePlayer = nil; return }
            notePlayer = try AVAudioPlayer(contentsOf: parkingDirectory.appendingPathComponent(filename)); notePlayer?.play()
        } catch { message = "Couldn’t play this recording." }
    }
    func deleteParkedNote(_ note: ParkedNote) {
        if let filename = note.audioFile {
            do { try FileManager.default.removeItem(at: parkingDirectory.appendingPathComponent(filename)) }
            catch { message = "Couldn’t delete this recording."; return }
        }
        parkedNotes.removeAll { $0.id == note.id }; saveParkedNotes()
    }
    @Published var completed = false
    @Published var selectedArchetype: FocusArchetype = .providence
    @Published var selectedTier: IntensityTier = .zen
    @Published var journey = FocusJourney()
    @Published var rewardVisible = false
    let online = OnlineStore()
    let surfaceMotion = SurfaceMotion()
    let socialPanel = SocialPanelModel()
    let journeyPanel = JourneyPanelModel()
    let rankPanel = RankPanelModel()
    @Published var modeDrag: CGFloat = 0
    @Published var pathDrag: CGFloat = 0
    @Published var tierDrag: CGFloat = 0
    @Published var tierGlow: Double = 0
    @Published var tierGlowTier: IntensityTier = .ranked
    var tierTransitionID = 0
    let walkthrough = WalkthroughModel()
    @Published var confirmEnd = false
    @Published var pauseBank = PauseBank()
    @Published var pauseRemaining: TimeInterval = 300
    var usesPauseBank: Bool { mode == 0 && (sessionTier ?? selectedTier) != .zen }
    var sessionMultiplier: Double { if isOverclock || (!hasProgress && overclockPending) { return 3 }; return usesPauseBank && pauseBank.wasPaused ? 1 : (sessionTier ?? selectedTier).multiplier }
    var pauseTime: String { let seconds=Int(ceil(pauseRemaining)); return String(format:"%01d:%02d",seconds/60,seconds%60) }
    func expirePauseBank(at now: Date) {
        guard usesPauseBank, isPaused, pauseBank.remaining(at:now) <= 0 else { return }
        endSession()
        message="Pause bank exhausted. Session ended with the normal early-exit penalty."
    }
    var lastIntegrityWall: Date?
    var lastIntegrityUptime: TimeInterval?
    var sessionTier: IntensityTier?
    func selectTier(_ tier: IntensityTier) {
        guard !hasProgress else { return }
        guard !overclockPending || tier == .hardcore else { message = "Unequip Overclock in the shop to change intensity."; return }
        cancelEngage()
        selectedTier = tier
        UserDefaults.standard.set(tier.rawValue, forKey: "intensityTier")
    }
    func onlineEvent(_ action: String) {
        guard !journey.testingUnlocked else { return }
        guard mode == 0, let archetype = sessionArchetype, let tier = sessionTier else { return }
        online.enqueue(id: sessionID, action: action, archetype: archetype, tier: tier, seconds: Int(clock.duration))
    }
    func endSession() {
        if !completed { onlineEvent("end") }
        if mode == 0, let archetype = sessionArchetype, let tier = sessionTier, !completed {
            journey.endEarly(session: sessionID, archetype: archetype, tier: tier, at: Date()); saveJourney()
        }
        reset()
    }
    @Published var lastAwardedSession: UUID?
    @Published var awardSummary: String?
    var rewardStart: Double = 0
    var rewardEnd: Double = 0
    var rewardLevelUp = false
    var rewardBadge: String?
    var previewXP: Int {
        let minutes = mode == 0 && hasProgress ? Int(clock.duration / 60) : overclockPending ? 60 : focusMinutes
        return Int((Double(max(1, minutes)) * (hasProgress ? sessionMultiplier : overclockPending ? 3 : selectedTier.multiplier)).rounded())
    }
    var sessionID = UUID()
    var sessionArchetype: FocusArchetype?
    var selectedPillar: FocusPillar {FocusPillar.containing(selectedArchetype)}
    var selectedProgress: ArchetypeProgress {journey.pillarProgress(for:selectedPillar)}
    func selectPillar(_ pillar:FocusPillar) {
        guard !hasProgress else {return}
        if selectedPillar != pillar {pillarSpin += 360}
        selectArchetype(pillar.representative);selectTier(pillar.defaultTier)
    }
    func tagSession(_ id:UUID, track:FocusArchetype) {journey.tag(session:id,track:track);saveJourney()}
    func selectArchetype(_ archetype: FocusArchetype) {
        guard !hasProgress else { return }
        cancelEngage()
        selectedArchetype = archetype
        UserDefaults.standard.set(archetype.rawValue, forKey: "focusArchetype")
    }
    func saveJourney() {
        if let data = try? JSONEncoder().encode(journey) { UserDefaults.standard.set(data, forKey: journey.storageKey) }
    }
    func awardFocus(at date: Date) {
        onlineEvent("finish")
        let archetype = sessionArchetype ?? selectedArchetype
        let previousProgress = journey.pillarProgress(for:FocusPillar.containing(archetype))
        let previousLevel = previousProgress.level
        let previousBadges = journey.game.trophies
        let minutes = max(1, Int(clock.duration / 60))
        let tier = sessionTier ?? selectedTier
        let earned = Int((Double(minutes) * sessionMultiplier).rounded())
        if journey.award(session: sessionID, archetype: archetype, minutes: minutes, at: date, tier: tier, wasPaused: pauseBank.wasPaused) {
            lastAwardedSession=sessionID
            saveJourney()
            let updated = journey.pillarProgress(for:FocusPillar.containing(archetype))
            let level = updated.level
            rewardLevelUp = level > previousLevel
            rewardStart = Double(previousProgress.xp % 100) / 100
            rewardEnd = rewardLevelUp ? 1 : Double(updated.xp % 100) / 100
            rewardBadge = journey.game.trophies.sorted().first { !previousBadges.contains($0) }
            awardSummary = "+\(earned) XP · \(FocusPillar.containing(archetype).title)" + (level > previousLevel ? " · Level \(level) unlocked" : "")
        }
    }
    var onChange: (() -> Void)?
    var onComplete: (() -> Void)?
    var player: AVAudioPlayer?
    var tickSound: NSSound?
    var dingSound: NSSound?
    @Published var confirmRecoveryEnd = false
    @Published var recoveryChecking = false
    @Published var recoverySnapshot: TimerHeartbeat?
    @Published var recoverySeconds: TimeInterval = 0
    var heartbeatStore: TimerHeartbeatStore?
    var heartbeatRevision = 0
    var lastHeartbeatMark = -Double.infinity
    var heartbeatStorageFailed = false
    var heartbeatShuttingDown = false
    var isRecoveryGracePeriod: Bool { recoverySnapshot?.graceRemaining(at:Date()) ?? 0 > 0 }
    var pulse: Timer?
    var lastTick = 0
    var importing = false
    var audioDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Still/Audio", isDirectory: true)
    }
    var modeName: String { ["Focus", "Break"][mode] }
    var duration: TimeInterval { mode == 0 && overclockPending ? 3600 : Double([focusMinutes, breakMinutes][mode] * 60) }
    var time: String { let s = Int(ceil(remaining)); return String(format: "%02d:%02d", s / 60, s % 60) }
    var progress: Double { min(1, max(0, 1 - remaining / clock.duration)) }
    var isPaused: Bool { !clock.running && !completed && remaining > 0 && (remaining < clock.duration || sessionArchetype != nil) }
    var hasProgress: Bool { recoverySnapshot != nil || clock.running || isPaused || (sessionArchetype != nil && !completed) }
    var nextMode: Int { mode == 0 ? 1 : 0 }
    var nextModeName: String { ["focus", "break"][nextMode] }
    var primaryTitle: String { clock.running ? "Pause" : completed ? "Start \(nextModeName)" : isPaused ? "Resume" : "Start \(mode == 0 ? "focus" : "break")" }
    var stateText: String { clock.running ? "\(modeName) in progress" : completed ? "\(modeName) complete" : isPaused ? "Paused" : "Ready to \(mode == 0 ? "focus" : "take a break")" }
    func cycleDuration() {
        guard !hasProgress, !completed, !(mode == 0 && overclockPending) else {return}
        let choices = mode == 0 ? [15,25,45,60] : [3,5,10,15,30]
        let minutes = Int(clock.duration / 60)
        let next = choices.first(where: {$0 > minutes}) ?? choices[0]
        setDuration(next)
    }
    func setDuration(_ minutes: Int) { guard !hasProgress && !completed else { return }; if mode == 0 { focusMinutes = minutes } else { breakMinutes = minutes } }
    var selectedTrack: Track? { tracks.first { $0.id == selectedID } }
    override convenience init() { self.init(recoveryEnabled: !(Bundle.main.bundleIdentifier ?? "").contains(".tests.")) }
    init(recoveryEnabled: Bool) {
        super.init()
        if !UserDefaults.standard.bool(forKey:"circleHover.v1") {
            hoverToOpen=true;UserDefaults.standard.set(true,forKey:"circleHover.v1")
        }
        selectedArchetype=FocusPillar.ops.representative;selectedTier=FocusPillar.ops.defaultTier
        // Apply the standard cycle once; future custom durations remain persistent.
        if !UserDefaults.standard.bool(forKey:"pomodoroDefaults.25.5.v1") {
            focusMinutes=25;breakMinutes=5
            UserDefaults.standard.set(true,forKey:"pomodoroDefaults.25.5.v1")
        }
        clock.reset(duration); remaining = duration
        if let data = UserDefaults.standard.data(forKey: "focusJourney.v1"), let saved = try? JSONDecoder().decode(FocusJourney.self, from: data) { journey = saved }
        loadTestingProfileIfEnabled()
        if overclockPending { selectedTier = .hardcore; clock.reset(duration); remaining = duration }
        if let data = UserDefaults.standard.data(forKey: "parkingLot.v1"), let notes = try? JSONDecoder().decode([ParkedNote].self, from: data) { parkedNotes = notes }
        if let data = UserDefaults.standard.data(forKey: "tracks"), let items = try? JSONDecoder().decode([Track].self, from: data) { tracks = items }
        tickSound = NSSound(contentsOfFile: "/System/Library/Sounds/Tink.aiff", byReference: true)
        dingSound = NSSound(contentsOfFile: "/System/Library/Sounds/Glass.aiff", byReference: true)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(sleeping), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(sleeping), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        if recoveryEnabled {
            let bundle = Bundle.main.bundleIdentifier ?? "com.still.focus"
            let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Still/Recovery/" + bundle + (journey.testingUnlocked ? "/testing-heartbeat.json" : "/heartbeat.json"))
            heartbeatStore = TimerHeartbeatStore(url: url)
            recoveryChecking = true
            Task { [weak self] in await self?.loadRecovery() }
        }
    }
    func saveSettings() {
        let d = UserDefaults.standard
        d.set(focusMinutes, forKey: "focus"); d.set(breakMinutes, forKey: "rest")
        d.set(tickEnabled, forKey: "tick"); d.set(dingEnabled, forKey: "ding"); d.set(autoStart, forKey: "auto")
        d.set(soundVolume, forKey: "soundVolume"); d.set(musicVolume, forKey: "musicVolume")
    }
    func saveTracks() { UserDefaults.standard.set(try? JSONEncoder().encode(tracks), forKey: "tracks"); UserDefaults.standard.set(selectedID, forKey: "selected") }
    func resetIfIdle() { if !hasProgress && !completed { reset() } }
    func selectMode(_ value: Int) {
        guard (0...1).contains(value), value != mode, !hasProgress else { return }
        cancelEngage(); pause(); mode = value; reset()
    }
    func startPulse() {
        pulse?.invalidate()
        let interval: TimeInterval = clock.running || usesPauseBank || recoverySnapshot != nil ? 1 : 3
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in Task { @MainActor in self?.update() } }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        pulse = timer
    }
    func stopPulse() { pulse?.invalidate(); pulse = nil }
    @Published var engageStarted: TimeInterval?
    private var engageTask: Task<Void, Never>?
    var requiresEngage: Bool { !clock.running && !isPaused && (completed ? nextMode : mode) == 0 && (selectedTier != .zen || overclockPending) }
    func cancelEngage() { engageTask?.cancel(); engageTask=nil; engageStarted=nil }
    func beginEngage(requirePointer: Bool = true) {
        guard !recoveryChecking, recoverySnapshot == nil, requiresEngage, engageStarted == nil else { return }
        let start=ProcessInfo.processInfo.systemUptime
        let tier=selectedTier; let path=selectedArchetype
        engageStarted=start
        engageTask=Task { [weak self] in
            do { try await Task.sleep(for: .seconds(7)) } catch { return }
            guard let self, !Task.isCancelled, self.engageStarted == start,
                  ProcessInfo.processInfo.systemUptime-start >= 7,
                  self.expanded, (!requirePointer || NSEvent.pressedMouseButtons & 1 == 1), self.requiresEngage, self.selectedTier==tier, self.selectedArchetype==path else {return}
            self.cancelEngage(); self.toggle(engaged:true)
        }
    }
    func toggle(engaged: Bool = false) {
        guard !recoveryChecking, recoverySnapshot == nil else { return }
        if requiresEngage && !engaged { message="Hold Engage for 7 seconds to begin."; return }
        if clock.running { pause() } else {
            if usesPauseBank && isPaused {
                let now=Date()
                guard pauseBank.remaining(at:now) > 0 else {expirePauseBank(at:now);return}
                pauseBank.resume(at:now);pauseRemaining=pauseBank.remaining(at:now)
            }
            if completed { advance() }
            if mode == 0 && sessionArchetype == nil {
                let now = Date()
                let stim = overclockPending
                sessionArchetype = selectedArchetype; sessionTier = stim ? .hardcore : selectedTier
                journey.game.begin(id: sessionID, tier: sessionTier!, at: now)
                if stim { clock.reset(3600); remaining = 3600 }
                saveJourney(); onlineEvent("start")
            } else if mode == 0 { onlineEvent("resume") }
            clock.start(at: Date()); lastIntegrityWall = Date(); lastIntegrityUptime = ProcessInfo.processInfo.systemUptime; startPulse(); completed = false; message = nil
            if selectedID != nil && audioEnabled { playAudio() } else { pauseAudio() }
            persistHeartbeat(force: true)
            onChange?()
        }
    }
    func pause(at now: Date = Date()) {
        guard clock.running else {return}
        if clock.seconds(at:now) <= 0 {update(at:now);return}
        if isOverclock { endSession(); message = "Overclock ended. No pauses are allowed; the token is consumed and Hardcore penalties apply."; return }
        onlineEvent("pause");stopPulse();clock.pause(at:now);remaining=clock.remaining
        if usesPauseBank {
            let hadTax = pauseBank.wasPaused
            let shield = journey.game.active?.id == sessionID && journey.game.active?.shield == true
            pauseBank.pause(at:now)
            if shield {
                pauseBank.preserveMultiplier(wasPaused: hadTax)
                journey.game.active?.shield = false; journey.game.active?.shieldShattered = true
                journey.game.lastFailure = now; journey.game.cleanDays = []
                message = "Combo Shield shattered. Multiplier protected; pause bank is running."
            }
            journey.game.active?.paused = true
            journey.game.strictChain = 0; journey.game.lastStrictEnd = nil
            saveJourney(); pauseRemaining=pauseBank.remaining(at:now)
        }
        // A paused session still needs a liveness checkpoint, using the same pulse.
        startPulse();persistHeartbeat(force:true)
        pauseAudio();onChange?()
    }
    @objc func sleeping() { cancelEngage(); if clock.running { let overclock = isOverclock; pause(); if !overclock { message = "Paused while your Mac is away." } } else { pauseAudio() } }
    func reset() { finishNoteRecording(); if journey.game.active?.id == sessionID { journey.game.active = nil; saveJourney() }; lastIntegrityWall = nil; lastIntegrityUptime = nil; clearHeartbeat(); cancelEngage(); stopPulse(); pauseBank=PauseBank(); pauseRemaining=300; sessionID = UUID(); sessionArchetype = nil; sessionTier = nil; awardSummary = nil; clock.reset(duration); remaining = duration; completed = false; lastTick = 0; pauseAudio(); onChange?() }
    func advance() { mode = nextMode; reset() }
    func update(at now: Date = Date()) {
        let uptime = ProcessInfo.processInfo.systemUptime
        if clock.running, mode == 0, let wall = lastIntegrityWall, let previousUptime = lastIntegrityUptime,
           now.timeIntervalSince(wall) - (uptime - previousUptime) < -5 {
            journey.game.lastIntegrityEvent = now; journey.game.cleanDays = []; saveJourney()
            endSession(); message = "System clock moved backwards. Session ended under its normal rules."; return
        }
        lastIntegrityWall = now; lastIntegrityUptime = uptime
        if let pending=recoverySnapshot {
            recoverySeconds=pending.graceRemaining(at:now)
            if recoverySeconds <= 0 { discardRecovery(at:now, expired:true) }
            return
        }
        if usesPauseBank && isPaused {
            pauseRemaining=pauseBank.remaining(at:now)
            if pauseRemaining <= 0 {expirePauseBank(at:now)} else {persistHeartbeat(at:now)}
            return
        }
        guard clock.running else { if isPaused {persistHeartbeat(at:now)}; return }
        remaining = clock.seconds(at: now)
        let boundary = clock.tickBoundary(at: now)
        if remaining > 0 && boundary > lastTick {
            lastTick = boundary
            if tickEnabled { tickSound?.volume = Float(soundVolume); tickSound?.play() }
        }
        if remaining <= 0 {
            finishNoteRecording(); stopPulse(); clock.pause(at: now); remaining = 0; completed = true
            if mode == 0 { sessions += 1; awardFocus(at: now) }
            clearHeartbeat()
            fadeAudio()
            if dingEnabled { dingSound?.volume = Float(soundVolume); dingSound?.play() }
            onChange?(); onComplete?()
            if autoStart {
                let finishedSession = sessionID
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    guard let self, self.completed, self.autoStart, self.sessionID == finishedSession else { return }
                    self.advance(); self.toggle()
                }
            }
        } else {persistHeartbeat(at:now)}
    }
    func importAudio() {
        importing = true
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.audio]; panel.allowsMultipleSelection = true
        panel.prompt = "Add audio"; panel.message = "Choose music or white noise. Still keeps a local copy and loops your selected track."
        panel.level = .modalPanel
        panel.begin { [weak self] response in
            Task { @MainActor in
                guard let self else { return }; defer { self.importing = false }
                guard response == .OK else { return }
                let urls = panel.urls
                let directory = self.audioDirectory
                // File validation and copying can be slow for long music files.
                // Keep that work off the UI thread and publish the library once.
                let result = await Task.detached(priority: .userInitiated) { () -> ([Track], String?) in
                    var added: [Track] = []
                    var errorMessage: String?
                    do {
                        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                        for url in urls {
                            do {
                                _ = try AVAudioPlayer(contentsOf: url)
                                let id = UUID().uuidString
                                let filename = id + "." + url.pathExtension
                                try FileManager.default.copyItem(at: url, to: directory.appendingPathComponent(filename))
                                added.append(Track(id: id, title: url.deletingPathExtension().lastPathComponent, filename: filename))
                            } catch { errorMessage = "Couldn’t import \(url.lastPathComponent). Try MP3, M4A, WAV or AIFF." }
                        }
                    } catch { errorMessage = "Couldn’t save that audio. \(error.localizedDescription)" }
                    return (added, errorMessage)
                }.value
                self.tracks.append(contentsOf: result.0)
                if let message = result.1 { self.message = message }
                if let first = result.0.first { self.selectTrack(first) } else { self.saveTracks() }
            }
        }
    }
    func selectTrack(_ track: Track) {
        let wasPlaying = audioPlaying; player?.stop(); player = nil; audioPlaying = false
        selectedID = track.id; saveTracks()
        if wasPlaying || (clock.running && audioEnabled) { playAudio() }
    }
    func clearAudioSelection() { pauseAudio(); player = nil; selectedID = nil; saveTracks() }
    func playAudio() {
        guard let track = selectedTrack else { return }
        do {
            if player == nil { player = try AVAudioPlayer(contentsOf: audioDirectory.appendingPathComponent(track.filename)); player?.numberOfLoops = -1; player?.delegate = self }
            player?.volume = Float(musicVolume); audioPlaying = player?.play() ?? false
            if !audioPlaying { message = "This audio couldn’t be played. Try another file." }
        } catch { message = "Audio file unavailable. Remove it and import it again."; audioPlaying = false }
    }
    func pauseAudio() { player?.pause(); audioPlaying = false }
    func fadeAudio() {
        guard let current = player else { return }
        current.setVolume(0, fadeDuration: 0.6); audioPlaying = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { [weak self, weak current] in
            guard let self, !self.audioPlaying else { return }; current?.pause(); current?.volume = Float(self.musicVolume)
        }
    }
    func toggleAudio() { audioPlaying ? pauseAudio() : playAudio() }
    func removeTrack(_ track: Track) {
        let url=audioDirectory.appendingPathComponent(track.filename)
        do {
            if FileManager.default.fileExists(atPath:url.path) {try FileManager.default.trashItem(at:url,resultingItemURL:nil)}
        } catch {message="Couldn’t remove this track. Try again.";return}
        if selectedID == track.id {pauseAudio();player=nil;selectedID=nil}
        tracks.removeAll {$0.id == track.id};saveTracks()
    }
    func previewTick() { tickSound?.volume = Float(soundVolume); tickSound?.play() }
    func previewDing() { dingSound?.volume = Float(soundVolume); dingSound?.play() }
}

let mint = Color(red: 0.65, green: 0.91, blue: 0.73)

// Keep the backdrop active even while another app has keyboard focus.
struct ActiveBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .hudWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
struct NotchGlass: View {
    let reveal: Double
    let transparency: Double
    let pressure: CGFloat
    let lightPoint: CGPoint
    var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(bottomLeadingRadius: 16 + 16 * reveal, bottomTrailingRadius: 16 + 16 * reveal)
    }
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        ZStack {
            if reduceTransparency { shape.fill(.black.opacity(0.96)) }
            else {
                ActiveBackdrop().clipShape(shape)
                    .overlay { shape.fill(.black.opacity((0.75 - 0.55 * transparency) * reveal + (1 - reveal))) }
            }
            // A narrow bright lip and inset opposite reflection suggest thickness
            // without adding another backdrop or distorting readable text.
            shape.strokeBorder(LinearGradient(stops: [
                .init(color: .white.opacity((0.35 + pressure * 0.25) * reveal), location: 0),
                .init(color: .white.opacity(0.055 * reveal), location: 0.30),
                .init(color: .white.opacity(0.08 * reveal), location: 0.65),
                .init(color: .white.opacity((0.28 + pressure * 0.2) * reveal), location: 1)
            ], startPoint: UnitPoint(x: lightPoint.x * 0.4, y: 0), endPoint: UnitPoint(x: 0.6 + lightPoint.x * 0.4, y: 1)), lineWidth: 0.8)
            shape.inset(by: 1.5).strokeBorder(LinearGradient(colors: [.clear, .white.opacity((0.08 + pressure * 0.1) * reveal), .clear], startPoint: .topTrailing, endPoint: .bottomLeading), lineWidth: 1)
            // Static top sheen: a faint curved-glass falloff, no animation cost.
            shape.fill(LinearGradient(colors: [.white.opacity(0.05 * reveal), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.32)))
                .blendMode(.plusLighter)
            // Specular bloom that follows the last press. It is zero at rest and stays zero
            // under Reduce Motion (pressure is never raised), so nothing runs continuously.
            GeometryReader { proxy in
                RadialGradient(colors: [.white.opacity(0.15 * Double(pressure) * reveal), .clear],
                               center: .center, startRadius: 0,
                               endRadius: max(proxy.size.width, proxy.size.height) * 0.4)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .position(x: proxy.size.width * lightPoint.x, y: proxy.size.height * lightPoint.y)
                    .blendMode(.plusLighter)
            }.clipShape(shape).allowsHitTesting(false)
        }.accessibilityHidden(true)
    }
}

// The glow is driven only while the panel is open.
struct TierAtmosphere: View {
    let tier: IntensityTier
    var mid: Color {
        switch tier {
        case .zen: return Color(red: 0.18, green: 0.78, blue: 0.58)
        case .ranked: return Color(red: 0.10, green: 0.82, blue: 0.42)
        case .hardcore: return Color(red: 1.0, green: 0.28, blue: 0.015)
        }
    }
    var deep: Color {
        switch tier {
        case .zen: return Color(red: 0.015, green: 0.27, blue: 0.22)
        case .ranked: return Color(red: 0.015, green: 0.31, blue: 0.14)
        case .hardcore: return Color(red: 0.45, green: 0.025, blue: 0.015)
        }
    }
    var body: some View {
        GeometryReader { proxy in
            VStack(spacing:0) {
                Spacer(minLength:0)
                // One continuous optical bloom, with matching-hue transparent stops.
                // Its centre sits below the panel so no hot spot or rectangular edge is exposed.
                EllipticalGradient(stops:[
                    .init(color:mid.opacity(0.62),location:0),
                    .init(color:mid.opacity(0.52),location:0.2),
                    .init(color:mid.opacity(0.3),location:0.42),
                    .init(color:deep.opacity(0.13),location:0.66),
                    .init(color:deep.opacity(0.035),location:0.84),
                    .init(color:deep.opacity(0),location:1)
                ],center:UnitPoint(x:0.5,y:1.14),startRadiusFraction:0,endRadiusFraction:1)
                .frame(height:min(220,proxy.size.height*0.34))
                .mask(LinearGradient(stops:[.init(color:.clear,location:0),.init(color:.white,location:0.24),.init(color:.white,location:1)],startPoint:.top,endPoint:.bottom))
            }.allowsHitTesting(false)
        }.accessibilityHidden(true)
    }
}

// A short, critically damped response: starts immediately and settles without bounce.
struct NotchMotion {
    static let openDuration = 0.34
    static let closeDuration = 0.29
    static let exitGrace = 0.045

}

struct StillView: View {
    @ObservedObject var model: FocusModel
    @ObservedObject var interaction: SurfaceMotion
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let close: () -> Void
    let open: () -> Void
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Namespace private var timerMotion
    var accent: Color { model.selectedTier.color }

    func changeTier(_ tier: IntensityTier) {
        guard tier != model.selectedTier, !model.hasProgress else {return}
        model.tierTransitionID += 1
        let id=model.tierTransitionID
        // Reset the transient before changing its palette, so rapid switches never
        // interpolate a bright green bloom through brown into orange.
        var transaction=Transaction(animation:nil)
        transaction.disablesAnimations=true
        withTransaction(transaction) {model.tierGlow=0;model.tierGlowTier=tier}
        withAnimation(reduceMotion ? nil : .spring(response:0.34,dampingFraction:0.8)) {model.selectTier(tier)}
        guard !reduceMotion,tier != .zen else {return}
        DispatchQueue.main.async {
            guard model.tierTransitionID == id,model.expanded,model.page == 3 else {return}
            withAnimation(.easeOut(duration:0.2)) {model.tierGlow=1}
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+0.38) {
            guard model.tierTransitionID == id else {return}
            withAnimation(.easeInOut(duration:0.62)) {model.tierGlow=0}
        }
    }
    func showPage(_ page: Int) {
        model.cancelEngage()
        if page != 7 && model.isRecordingNote { model.finishNoteRecording() }
        if page == 0 && !model.clock.running { model.pauseAudio() }
        model.page = page
        open()
    }
    @ViewBuilder var transitionGlow: some View {
        if model.selectedTier != .zen && model.page == 3 && model.expanded {
            TierAtmosphere(tier:model.tierGlowTier).id(model.tierGlowTier).opacity(model.tierGlow * model.reveal)
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            Button(action: open) {
                if model.expanded || !model.circularNotch {
                    HStack(spacing:0) {
                        Image(systemName:"leaf.fill").font(.system(size:12,weight:.medium)).foregroundStyle(mint).frame(maxWidth:.infinity)
                        Color.clear.frame(width:notchWidth)
                        Text(model.clock.running || model.isPaused ? model.time : "still").font(.system(size:11,weight:.medium,design:.rounded)).monospacedDigit().foregroundStyle(mint).frame(maxWidth:.infinity)
                    }.frame(height:model.expanded ? notchHeight : notchHeight+3).contentShape(Rectangle())
                } else {
                    Group {
                        if model.clock.running || model.isPaused {
                            Text(model.time).font(.system(size:11,weight:.semibold,design:.rounded)).monospacedDigit()
                        } else {Image(systemName:"leaf.fill").font(.system(size:13,weight:.medium))}
                    }.foregroundStyle(mint).frame(width:32,height:32).contentShape(Circle())
                }
            }.buttonStyle(SharedPressStyle(motion:interaction)).accessibilityLabel("Open Still")

            if model.expanded {
                VStack(spacing: 16) {
                    if !(model.page == 0 && model.hasProgress) {
                        navigation.offset(x: -interaction.horizontal * interaction.pressure, y: -interaction.pressure)
                    }
                    if model.page == 1 { settings } else if model.page == 2 { library } else if model.page == 3 { archetypes } else if model.page == 4 { leaderboard } else if model.page == 5 { progressDetails } else if model.page == 6 { guide } else if model.page == 7 { parkingLot } else if model.page == 8 { rankDetails } else { timer }
                    if let message = model.message {
                        HStack(alignment: .top, spacing: 8) {
                            Text(message).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Button("Dismiss") { model.message = nil }.font(.system(size: 12))
                        }.padding(12).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }
                }.padding(24).frame(width: 420)
                    .offset(x: interaction.horizontal * interaction.pressure, y: interaction.pressure)

                    .opacity(model.contentVisibility)
                    .allowsHitTesting(model.reveal > 0.9).accessibilityHidden(model.reveal < 0.9)
            }
        }.fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background {
                if model.expanded {
                    NotchGlass(reveal:model.reveal,transparency:model.glassTransparency,pressure:interaction.pressure,lightPoint:interaction.point).overlay {transitionGlow}
                } else if model.circularNotch {Circle().fill(.black)}
                else {UnevenRoundedRectangle(bottomLeadingRadius:14,bottomTrailingRadius:14).fill(.black)}
            }
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius:model.expanded ? 16+16*model.reveal : 14,bottomTrailingRadius:model.expanded ? 16+16*model.reveal : 14))
            .coordinateSpace(name: "stillSurface")
            .preferredColorScheme(.dark)
    }
    var navigation: some View {
        HStack(spacing: 12) {
            if model.page != 0 {
                Button { showPage(model.page == 5 ? 8 : model.page == 8 ? 3 : model.page == 6 ? 1 : 0) } label: { Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold)).frame(width: 30, height: 30).contentShape(Rectangle()) }.buttonStyle(SharedPressStyle(motion: interaction)).help("Back to timer").accessibilityLabel("Back to timer")
                Text(model.page == 1 ? "Settings" : model.page == 2 ? "Audio library" : model.page == 4 ? "Leaderboard" : model.page == 5 ? "My Journey" : model.page == 6 ? "How Still works" : model.page == 7 ? "Parking Lot" : model.page == 8 ? "Ranks" : "Focus Archetypes").font(.system(size: 16, weight: .semibold))
            } else {
                Button { showPage(1) } label: {
                    Image(systemName:"gearshape").font(.system(size:16,weight:.medium)).frame(width:32,height:32).contentShape(Rectangle())
                }.buttonStyle(SharedPressStyle(motion:interaction)).foregroundStyle(.white.opacity(0.8)).help("Settings").accessibilityLabel("Settings")
            }
            Spacer()
            if model.page == 0 || model.page == 3 {
                Button { showPage(4) } label: { Image(systemName: "trophy").font(.system(size: 16, weight: .medium)).frame(width: 32, height: 32).contentShape(Rectangle()) }.buttonStyle(SharedPressStyle(motion: interaction)).foregroundStyle(accent).help("Leaderboard").accessibilityLabel("Leaderboard")
            }

        }.font(.system(size: 12))
    }
    var timer: some View {
        ZStack(alignment: .top) {
            if model.recoveryChecking {
                ProgressView().controlSize(.small).frame(height:200)
            } else if let interrupted=model.recoverySnapshot {
                VStack(spacing:16) {
                    Image(systemName:"arrow.counterclockwise.circle").font(.system(size:32)).foregroundStyle(accent)
                    Text("Session interrupted").font(.system(size:20,weight:.semibold,design:.rounded))
                    Text(String(format:"%02d:%02d",Int(ceil(interrupted.duration-interrupted.elapsed))/60,Int(ceil(interrupted.duration-interrupted.elapsed))%60))
                        .font(.system(size:48,weight:.light,design:.rounded)).monospacedDigit()
                    Text("Resume within \(Int(ceil(model.recoverySeconds)))s").font(.system(size:12)).monospacedDigit().foregroundStyle(.secondary)
                    HStack {
                        Button {model.resumeRecovery()} label:{Label("Resume",systemImage:"play.fill").frame(maxWidth:.infinity).padding(12).foregroundStyle(.black).background(accent,in:Capsule())}
                        Button {
                            if interrupted.mode == 0 && interrupted.tier != .zen {model.confirmRecoveryEnd=true} else {model.discardRecovery()}
                        } label:{Label("End",systemImage:"stop.fill").padding(12)}.help("End the interrupted session")
                    }
                    if interrupted.tier != .zen && interrupted.mode == 0 {
                        Text("Ending or letting recovery expire applies the normal early-exit penalty.").font(.system(size:11)).foregroundStyle(.secondary)
                    }
                }.buttonStyle(SharedPressStyle(motion:interaction))
                    .alert("End the interrupted session?",isPresented:$model.confirmRecoveryEnd) {
                        Button("Keep session",role:.cancel) {}
                        Button("End session",role:.destructive) {model.discardRecovery()}
                    } message: {
                        Text(interrupted.tier == .hardcore ? "Lose 50% of this path’s XP and record a failure." : "Lose 15% of this path’s XP and reset your streak.")
                    }
            } else if model.hasProgress {
                focusedTimer.transition(.opacity)
            } else {
                timerSetup.transition(.opacity)
            }
        }.animation(reduceMotion ? nil : .spring(response: 0.48, dampingFraction: 0.68), value: model.hasProgress)
    }
    var focusedTimer: some View {
        VStack(spacing:24) {
            VStack(spacing:8) {
                Text(model.time).font(.system(size:80,weight:.light,design:.rounded)).monospacedDigit().tracking(-2.8)
                    .matchedGeometryEffect(id:"clock",in:timerMotion)
                    .offset(y:-interaction.pressure*2)
                if model.isOverclock {
                    Label("Overclock",systemImage:"bolt.fill").font(.system(size:10,weight:.medium)).foregroundStyle(.white.opacity(0.45))
                }
                if model.usesPauseBank && model.isPaused && !model.isOverclock {
                    Text("Paused · \(model.pauseTime) remaining").font(.system(size:11)).monospacedDigit().foregroundStyle(.white.opacity(0.45))
                        .accessibilityLabel("Paused. \(model.pauseTime) remaining in your pause bank")
                }
            }.frame(maxWidth:.infinity).padding(.top,16).padding(.bottom,8)
            HStack(spacing:18) {
                Button {if model.isOverclock {model.confirmEnd=true} else {model.toggle()}} label: {
                    HStack(spacing:7) {
                        Image(systemName:model.isOverclock ? "stop.fill" : model.clock.running ? "pause.fill" : "play.fill").font(.system(size:13,weight:.medium))
                        if model.isPaused {Text("Resume").font(.system(size:12,weight:.medium))}
                    }.foregroundStyle(.white.opacity(0.72)).frame(width:model.isPaused ? 100 : 44,height:36)
                        .background {Capsule().fill(.white.opacity(0.045)).matchedGeometryEffect(id:"primary",in:timerMotion)}
                        .overlay {Capsule().strokeBorder(.white.opacity(0.055),lineWidth:0.6)}
                }.buttonStyle(SharedPressStyle(motion:interaction))
                    .help(model.isOverclock ? "End Overclock" : model.clock.running ? "Pause" : "Resume")
                    .accessibilityLabel(model.isOverclock ? "End Overclock" : model.clock.running ? "Pause" : "Resume")
                if model.isPaused {
                    Button("End session") {if model.mode == 0 && (model.sessionTier ?? model.selectedTier) != .zen {model.confirmEnd=true} else {model.endSession()}}
                        .font(.system(size:11)).buttonStyle(SharedPressStyle(motion:interaction)).foregroundStyle(.white.opacity(0.45))
                }
            }.frame(maxWidth:.infinity)
            VStack(spacing:16) {
                backgroundAudio.frame(maxWidth:280).opacity(0.8).matchedGeometryEffect(id:"audio",in:timerMotion)
                    .frame(maxWidth:.infinity)
                VStack(alignment:.leading,spacing:12) {
                    Button {showPage(7)} label: {
                        HStack(spacing:6) {
                            Label("Parking Lot",systemImage:"square.and.pencil").font(.system(size:14,weight:.semibold))
                            Spacer()
                            if !model.parkedNotes.isEmpty {Text("\(model.parkedNotes.count)").font(.system(size:12,weight:.medium)).monospacedDigit()}
                            Image(systemName:"chevron.right").font(.system(size:9,weight:.medium))
                        }.foregroundStyle(.white.opacity(0.78)).frame(height:24)
                    }.buttonStyle(SharedPressStyle(motion:interaction)).help("View parked thoughts").accessibilityLabel("View Parking Lot")
                    HStack(spacing:8) {
                        TextField("Park a thought…",text:$model.parkingDraft,axis:.vertical)
                            .textFieldStyle(.plain).font(.system(size:14)).lineLimit(2...3).frame(minHeight:56,alignment:.top)
                            .accessibilityLabel("Write a thought for Parking Lot")
                        Button {model.addParkedText()} label: {
                            Image(systemName:"arrow.up.circle.fill").font(.system(size:26)).foregroundStyle(accent.opacity(0.9)).frame(width:32,height:40)
                        }.buttonStyle(SharedPressStyle(motion:interaction))
                            .disabled(model.parkingDraft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty).help("Save thought").accessibilityLabel("Save thought")
                        Button {model.recordNote()} label: {
                            Image(systemName:model.isRecordingNote ? "stop.fill" : "mic.fill").font(.system(size:19,weight:.medium))
                                .foregroundStyle(model.isRecordingNote ? .orange : accent).frame(width:40,height:40)
                                .background((model.isRecordingNote ? Color.orange : accent).opacity(0.1),in:Circle())
                        }.buttonStyle(SharedPressStyle(motion:interaction)).disabled(model.importing)
                            .help(model.isRecordingNote ? "Stop and save voice note" : "Record a voice note")
                            .accessibilityLabel(model.isRecordingNote ? "Stop and save voice note" : "Record a voice note")
                    }.padding(.horizontal,14).padding(.vertical,12)
                        .background {RoundedRectangle(cornerRadius:16).fill(.white.opacity(0.045)).matchedGeometryEffect(id:"parking",in:timerMotion)}
                        .overlay {RoundedRectangle(cornerRadius:16).strokeBorder(.white.opacity(0.04),lineWidth:0.6)}
                }.padding(14).background(.white.opacity(0.025),in:RoundedRectangle(cornerRadius:22))
            }
        }.alert("End this \(model.selectedTier.title) session?", isPresented: $model.confirmEnd) {
            Button("Keep focusing", role: .cancel) { }
            Button("End session", role: .destructive) { model.endSession() }
        } message: { Text(model.selectedTier.detail) }
    }
    var timerSetup: some View {
        VStack(spacing: 16) {
            VStack(spacing: 24) {
                GeometryReader { proxy in
                    let segment = (proxy.size.width - 8) / 2
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.06))
                        Capsule().fill(.white.opacity(0.16))
                            .overlay { Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.7) }
                            .frame(width: segment, height: 40)
                            .offset(x: 4 + CGFloat(model.mode) * segment + model.modeDrag)
                            .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.72), value: model.mode)
                        HStack(spacing: 0) {
                            ForEach(0..<2, id: \.self) { mode in
                                Button { model.selectMode(mode) } label: {
                                    Label(mode == 0 ? "Focus" : "Break", systemImage: mode == 0 ? "leaf.fill" : "cup.and.saucer.fill")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(model.mode == mode ? .white : .white.opacity(0.55))
                                        .frame(maxWidth: .infinity).frame(height: 48).contentShape(Capsule())
                                }.buttonStyle(SharedPressStyle(motion: interaction)).disabled(model.hasProgress || model.completed)
                            }
                        }.padding(.horizontal, 4)
                    }.simultaneousGesture(DragGesture(minimumDistance: 4).onChanged { value in
                        guard !model.hasProgress, !model.completed,
                              value.startLocation.x >= 4 + CGFloat(model.mode) * segment,
                              value.startLocation.x <= 4 + CGFloat(model.mode + 1) * segment else { return }
                        model.modeDrag = min(CGFloat(1 - model.mode) * segment, max(-CGFloat(model.mode) * segment, value.translation.width))
                    }.onEnded { _ in
                        let next = min(1, max(0, model.mode + Int((model.modeDrag / segment).rounded())))
                        withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.72)) { model.modeDrag = 0; model.selectMode(next) }
                    })
                }.frame(height: 48)
                VStack(spacing: 8) {
                    Button { model.cycleDuration() } label: {
                        Text(model.time).font(.system(size:64,weight:.light,design:.rounded)).monospacedDigit().tracking(-2)
                            .matchedGeometryEffect(id:"clock",in:timerMotion)
                            .offset(y:-interaction.pressure*2)
                            .contentShape(Rectangle())
                    }.buttonStyle(SharedPressStyle(motion:interaction))
                        .disabled(model.hasProgress || model.completed || (model.mode == 0 && model.overclockPending))
                        .help(model.mode == 0 ? "Tap to cycle 15, 25, 45 and 60 minutes" : "Tap to change break duration")
                        .accessibilityLabel("Change duration, \(Int(model.clock.duration/60)) minutes")
                        .contextMenu {Button("Custom duration…") {showPage(1)}}
                    if model.completed { Text(model.stateText).font(.system(size: 12)).foregroundStyle(accent) }
                }
            }.padding(.horizontal,20).padding(.top,12).padding(.bottom,22)
            if model.completed, let award = model.awardSummary {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        Image(systemName: model.rewardLevelUp ? "seal.fill" : "sparkles")
                            .scaleEffect(model.rewardVisible && !reduceMotion ? 1.12 : 0.85)
                        Text(award).font(.system(size: 12, weight: .semibold)).lineLimit(2)
                    }.foregroundStyle(Color(red: 0.96, green: 0.79, blue: 0.44))
                    ProgressView(value: model.rewardVisible ? model.rewardEnd : model.rewardStart)
                        .tint(Color(red: 0.96, green: 0.75, blue: 0.32))
                        .accessibilityLabel("XP progress after this session")
                    if let badge = model.rewardBadge {
                        Label("Badge unlocked: \(badge)", systemImage: "rosette")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                    }
                }.padding(10).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                    .onAppear { model.rewardVisible = false; withAnimation(reduceMotion ? nil : .easeOut(duration: 0.85)) { model.rewardVisible = true } }
            } else if model.hasProgress {
                ProgressView(value: model.progress).tint(accent).accessibilityLabel("Session progress")
            }
            HStack(spacing: 12) {
                if model.requiresEngage {
                    engageControl
                } else {
                Button { model.toggle() } label: {
                    Label(model.primaryTitle, systemImage: model.clock.running ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.black).frame(maxWidth: .infinity).frame(height: 40)
                        .background { Capsule().fill(LinearGradient(colors: [accent.opacity(0.82), accent], startPoint: .bottom, endPoint: .top)).matchedGeometryEffect(id: "primary", in: timerMotion) }
                        .shadow(color: accent.opacity(model.selectedTier == .hardcore ? 0.24 : 0.14), radius: model.selectedTier == .hardcore ? 9 : 6, y: 2)
                }.buttonStyle(SharedPressStyle(motion: interaction))
                }
                if model.hasProgress && !model.clock.running {
                    Button("End session") { if model.mode == 0 && (model.sessionTier ?? model.selectedTier) != .zen { model.confirmEnd = true } else { model.endSession() } }.font(.system(size: 12)).buttonStyle(SharedPressStyle(motion: interaction)).foregroundStyle(.white.opacity(0.8))
                } else if model.completed {
                    Button("Focus again") { model.selectMode(0); model.reset() }.font(.system(size: 12)).buttonStyle(SharedPressStyle(motion: interaction)).foregroundStyle(.white.opacity(0.8))
                }
            }
            archetypeSummary
            HStack(spacing:12) {
                Menu {
                    Button("No audio") {model.clearAudioSelection()}
                    ForEach(model.tracks) {track in Button(track.title) {if model.selectedID != track.id {model.selectTrack(track)}}}
                    Divider()
                    Button("Manage audio…") {showPage(2)}
                } label: {
                    Label(model.selectedTrack?.title ?? "Audio",systemImage:model.audioEnabled ? "speaker.wave.2" : "speaker.slash")
                        .font(.system(size:11,weight:.medium)).foregroundStyle(.white.opacity(0.48)).lineLimit(1)
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).accessibilityLabel("Choose background audio")
                Spacer(minLength:4)
                Button {showPage(7)} label: {
                    Label("Parking Lot",systemImage:"square.and.pencil").font(.system(size:11,weight:.medium)).foregroundStyle(.white.opacity(0.48))
                }.buttonStyle(SharedPressStyle(motion:interaction)).accessibilityLabel("Parking Lot, \(model.parkedNotes.count) notes")
            }.padding(.horizontal,12).frame(height:28)

        }.alert("End this \(model.selectedTier.title) session?", isPresented: $model.confirmEnd) {
            Button("Keep focusing", role: .cancel) { }
            Button("End session", role: .destructive) { model.endSession() }
        } message: { Text(model.selectedTier.detail) }
    }
    var engageControl: some View {
        GeometryReader { proxy in
            ZStack {
                Capsule().fill(accent.opacity(0.12))
                if let start=model.engageStarted {
                    TimelineView(.animation(minimumInterval:1.0/30)) { _ in
                        let fraction=min(1,max(0,(ProcessInfo.processInfo.systemUptime-start)/7))
                        Capsule().fill(accent.opacity(0.75)).frame(width:proxy.size.width*fraction)
                            .frame(maxWidth:.infinity,alignment:.leading)
                    }.clipShape(Capsule()).allowsHitTesting(false)
                }
                Label("Engage",systemImage:"hand.point.up.left.fill").font(.system(size:14,weight:.semibold)).foregroundStyle(model.engageStarted == nil ? accent : .white)
            }.overlay {Capsule().strokeBorder(accent.opacity(0.5),lineWidth:0.8)}
                .contentShape(Capsule())
                .gesture(DragGesture(minimumDistance:0).onChanged { value in
                    if CGRect(origin:.zero,size:proxy.size).contains(value.location) {
                        if model.mode != 0 && !model.hasProgress {model.selectMode(0)}
                        model.beginEngage()
                    } else {model.cancelEngage()}
                }.onEnded { _ in model.cancelEngage() })
        }.frame(height:44).help("Hold for 7 full seconds. Releasing early resets the hold.")
            .accessibilityLabel("Engage. Press and hold for seven seconds.")
            .onDisappear {model.cancelEngage()}
    }
    var archetypeSummary: some View {
        Button {showPage(3)} label: {
            HStack(spacing:12) {
                RankEmblem(rank:PlayerRank(xp:model.journey.spendableXP),size:40)
                VStack(alignment:.leading,spacing:5) {
                    Text("Focus Archetypes").font(.system(size:13,weight:.semibold)).foregroundStyle(.white.opacity(0.9))
                    Text("\(model.journey.playerRank) · \(model.selectedPillar.title)").font(.system(size:10,weight:.medium)).foregroundStyle(accent.opacity(0.8))
                }
                Spacer()
                ZStack {
                    Circle().stroke(.white.opacity(0.1),lineWidth:2)
                    Circle().trim(from:0,to:Double(model.selectedProgress.xp%100)/100).stroke(accent.opacity(0.7),style:StrokeStyle(lineWidth:2,lineCap:.round)).rotationEffect(.degrees(-90))
                    Image(systemName:"chevron.right").font(.system(size:9,weight:.semibold)).foregroundStyle(.white.opacity(0.65))
                }.frame(width:26,height:26).accessibilityLabel("Open progression")
            }.padding(.horizontal,16).padding(.vertical,10)
                .background(.white.opacity(0.035),in:RoundedRectangle(cornerRadius:20))
                .overlay {RoundedRectangle(cornerRadius:20).strokeBorder(accent.opacity(0.15),lineWidth:0.7)}
                .contentShape(RoundedRectangle(cornerRadius:20))
        }.buttonStyle(SharedPressStyle(motion:interaction)).accessibilityLabel("Focus Archetypes. \(model.journey.playerRank), \(model.selectedPillar.title). Open progression.")
    }
    var archetypes: some View {
        let archetype = model.selectedPillar
        let progress = model.selectedProgress
        return VStack(alignment: .leading, spacing: 16) {
            GeometryReader { proxy in
                let gap: CGFloat = 8
                let width = (proxy.size.width - gap * 2) / 3
                let index = FocusPillar.allCases.firstIndex(of: archetype) ?? 0
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 24).fill(.white.opacity(0.045))
                        .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.07), lineWidth: 0.5) }
                    RoundedRectangle(cornerRadius: 20).fill(.white.opacity(0.11))
                        .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.13), lineWidth: 0.6) }
                        .frame(width: width, height: 64)
                        .offset(x: CGFloat(index) * (width + gap) + model.pathDrag)
                        .scaleEffect(x: model.pathDrag == 0 || reduceMotion ? 1 : 1.04, y: model.pathDrag == 0 || reduceMotion ? 1 : 0.94)
                        .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.68), value: index)
                    HStack(spacing: gap) {
                        ForEach(FocusPillar.allCases) { item in
                            Button { withAnimation(reduceMotion ? nil : .spring(response:0.4,dampingFraction:0.8)) { model.selectPillar(item) } } label: {
                                PillarGlyph(pillar:item,color:item == archetype ? accent : .white.opacity(0.5),size:32)
                                    .frame(maxWidth: .infinity).frame(height: 64).contentShape(Rectangle())
                                    .foregroundStyle(item == archetype ? accent : .white.opacity(0.6))
                            }.buttonStyle(SharedPressStyle(motion: interaction)).disabled(model.hasProgress).help(item.title)
                                .accessibilityLabel(item.title + (item == archetype ? ", selected" : ""))
                        }
                    }
                }.simultaneousGesture(DragGesture(minimumDistance: 4).onChanged { value in
                    let step = width + gap
                    guard !model.hasProgress, value.startLocation.x >= CGFloat(index) * step,
                          value.startLocation.x <= CGFloat(index) * step + width else { return }
                    model.pathDrag = min(CGFloat(2 - index) * step, max(-CGFloat(index) * step, value.translation.width))
                }.onEnded { _ in
                    guard model.pathDrag != 0 else { return }
                    let next = min(2, max(0, index + Int((model.pathDrag / (width + gap)).rounded())))
                    withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.68)) { model.pathDrag = 0; model.selectPillar(FocusPillar.allCases[next]) }
                })
            }.frame(height: 64)
            VStack(spacing: 12) {
                PillarMedallion(pillar:archetype,color:accent,animate:model.page == 3 && model.expanded && model.contentVisibility > 0.9 && model.clock.running)
                    .rotation3DEffect(.degrees(reduceMotion ? 0 : model.pillarSpin),axis:(x:0,y:1,z:0.08),perspective:0.35)
                    .animation(reduceMotion ? nil : .easeOut(duration:0.56),value:model.pillarSpin)
                VStack(spacing:6) {
                    Text(archetype.title).font(.system(size:24,weight:.semibold,design:.rounded)).multilineTextAlignment(.center)
                    Text(archetype.shortScope).font(.system(size:11)).foregroundStyle(.white.opacity(0.55))
                    Text("\(model.journey.playerRank) · Level \(progress.level)").font(.system(size:11,weight:.medium)).foregroundStyle(accent)
                }
                if model.overclockPending && !model.hasProgress {
                    Label("Overclock · 60 min · 3× · No pauses",systemImage:"bolt.fill").font(.system(size:11,weight:.semibold)).foregroundStyle(accent)
                } else if model.journey.game.equipped.contains(.shield) && model.selectedTier != .zen && !model.hasProgress {
                    Label("Combo Shield equipped",systemImage:"shield.lefthalf.filled").font(.system(size:11)).foregroundStyle(accent)
                }
                VStack(spacing:8) {
                    ProgressView(value:Double(progress.xp % 100),total:100).tint(accent).controlSize(.small)
                        .accessibilityLabel("\(progress.xp % 100) of 100 XP to level \(progress.level + 1)")
                    HStack {
                        Text("\(progress.xp % 100) / 100 XP").monospacedDigit()
                        Spacer()
                        Label("+\(model.previewXP) XP",systemImage:"sparkles").foregroundStyle(accent)
                            .help("Expected reward for the configured session")
                    }.font(.system(size:11,weight:.medium)).foregroundStyle(.white.opacity(0.55))
                }.padding(.top,4)
            }.padding(24).frame(maxWidth:.infinity)
                .background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:24))
                .overlay {RoundedRectangle(cornerRadius:24).strokeBorder(LinearGradient(colors:[.white.opacity(0.4),accent.opacity(0.12),accent.opacity(0.45)],startPoint:.topLeading,endPoint:.bottomTrailing),lineWidth:0.8)}
                .animation(reduceMotion ? nil : .spring(response:0.4,dampingFraction:0.8),value:archetype)
            GeometryReader { proxy in
                let gap: CGFloat = 8
                let width = (proxy.size.width - gap * 2) / 3
                let index = IntensityTier.allCases.firstIndex(of: model.selectedTier) ?? 0
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 24).fill(.white.opacity(0.045))
                        .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.07), lineWidth: 0.5) }
                    RoundedRectangle(cornerRadius: 20).fill(.white.opacity(0.12))
                        .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.2), lineWidth: 0.7) }
                        .frame(width: width, height: 64)
                        .offset(x: CGFloat(index) * (width + gap) + model.tierDrag)
                        .scaleEffect(x: model.tierDrag == 0 || reduceMotion ? 1 : 1.04, y: model.tierDrag == 0 || reduceMotion ? 1 : 0.94)
                        .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.68), value: index)
                    HStack(spacing: gap) {
                        ForEach(IntensityTier.allCases) { tier in
                            Button { changeTier(tier) } label: {
                                IntensityEmblem(tier:tier,selected:tier == model.selectedTier)
                                    .frame(maxWidth: .infinity).frame(height: 64).contentShape(Rectangle())
                                    .foregroundStyle(tier == model.selectedTier ? tier.color : .white.opacity(0.7))
                            }.buttonStyle(SharedPressStyle(motion: interaction)).disabled(model.hasProgress).help(tier.title)
                                .accessibilityLabel(tier.title + (tier == model.selectedTier ? ", selected" : ""))
                        }
                    }
                }.simultaneousGesture(DragGesture(minimumDistance: 4).onChanged { value in
                    let step = width + gap
                    guard !model.hasProgress, value.startLocation.x >= CGFloat(index) * step,
                          value.startLocation.x <= CGFloat(index) * step + width else { return }
                    model.tierDrag = min(CGFloat(2 - index) * step, max(-CGFloat(index) * step, value.translation.width))
                }.onEnded { _ in
                    guard model.tierDrag != 0 else { return }
                    let next = min(2, max(0, index + Int((model.tierDrag / (width + gap)).rounded())))
                    withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.68)) { model.tierDrag = 0; changeTier(IntensityTier.allCases[next]) }
                })
            }.frame(height: 64)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: model.selectedTier == .hardcore ? "flame.fill" : model.selectedTier == .ranked ? "chevron.up.2" : "leaf.fill")
                    Text(model.selectedTier.title)
                    Spacer()
                    Text("\(model.sessionMultiplier.formatted())× XP")
                }.font(.system(size: 14, weight: .semibold)).foregroundStyle(accent)
                Text(model.selectedTier.detail).font(.system(size: 12)).foregroundStyle(.white.opacity(0.78)).fixedSize(horizontal: false, vertical: true)
            }.frame(minHeight:68,alignment:.topLeading).padding(16).background(accent.opacity(model.selectedTier == .hardcore ? 0.1 : 0.04), in: RoundedRectangle(cornerRadius: 24))
                .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(accent.opacity(model.selectedTier == .hardcore ? 0.5 : 0.14), lineWidth: 1) }
                .scaleEffect(model.selectedTier == .hardcore && !reduceMotion ? 1+0.012*model.tierGlow : 1)
            if model.hasProgress { Text("Finish or end the session to change your choices.").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)) }
            HStack(spacing: 10) {
                Button { showPage(8) } label: {
                    RankEmblem(rank:PlayerRank(xp:model.journey.spendableXP),size:28)
                        .frame(width:56,height:44).background(.white.opacity(0.07),in:RoundedRectangle(cornerRadius:16))
                }.buttonStyle(SharedPressStyle(motion: interaction)).help("Ranks, badges and XP Shop").accessibilityLabel("Ranks, badges and XP Shop")
                if !model.hasProgress && !model.completed {
                    if model.selectedTier != .zen {
                        engageControl
                    } else {
                    Button {
                        if model.mode != 0 { model.selectMode(0) }
                        showPage(0); model.toggle()
                    } label: {
                        Image(systemName: "play.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(.black)
                            .frame(maxWidth: .infinity).frame(height: 42)
                            .background(accent, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(SharedPressStyle(motion: interaction)).accessibilityLabel("Start focus")
                    }
                }
            }
        }
    }
    var progressDetails: some View {
        JourneyPanel(state: model.journeyPanel, journey: model.journey, tagSession:model.tagSession, motion: interaction, color: accent)
    }
    var rankDetails: some View {
        RankPanel(state:model.rankPanel,journey:model.journey,enabled:!model.hasProgress && model.recoverySnapshot == nil && !model.recoveryChecking,buy:model.buyItem,equip:model.equipItem,motion:interaction,openJourney:{showPage(5)})
    }
    var guide: some View { WalkthroughView(demo: model.walkthrough, accent: accent, motion: interaction) }
    var parkingLot: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Capture now. Revisit later.").font(.system(size: 14, weight: .medium))
                    Text("Notes stay on this Mac.").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                if !model.parkedNotes.isEmpty { Text("\(model.parkedNotes.count)").font(.system(size: 12, weight: .semibold)).foregroundStyle(accent) }
            }
            HStack(spacing: 8) {
                TextField("Park an idea…", text: $model.parkingDraft, axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 13)).lineLimit(1...3)
                    .onSubmit { model.addParkedText() }
                Button { model.addParkedText() } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 23)).foregroundStyle(accent) }
                    .buttonStyle(SharedPressStyle(motion: interaction)).disabled(model.parkingDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).help("Save note").accessibilityLabel("Save note")
            }.padding(12).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            Button { model.recordNote() } label: {
                Label(model.isRecordingNote ? "Stop & save recording" : "Record voice note", systemImage: model.isRecordingNote ? "stop.circle.fill" : "mic.fill")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(model.isRecordingNote ? .orange : accent)
                    .frame(maxWidth: .infinity).frame(height: 38).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }.buttonStyle(SharedPressStyle(motion: interaction))
            if model.parkedNotes.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "square.and.pencil").font(.system(size: 25)).foregroundStyle(.white.opacity(0.4))
                    Text("Nothing parked yet").font(.system(size: 13, weight: .medium))
                    Text("Type or record a thought without leaving your session.").font(.system(size: 11)).foregroundStyle(.white.opacity(0.65)).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).padding(.vertical, 22)
            } else {
                Text("Saved thoughts").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(model.parkedNotes) { note in
                            HStack(alignment: .center, spacing: 10) {
                                if note.audioFile != nil {
                                    Button { model.playParkedNote(note) } label: { Image(systemName: "play.circle.fill").font(.system(size: 22)).foregroundStyle(accent) }
                                        .buttonStyle(SharedPressStyle(motion: interaction)).help("Play or stop voice note").accessibilityLabel("Play or stop voice note")
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(note.text ?? "Voice note").font(.system(size: 13)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                    Text(note.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                                }
                                Spacer(minLength: 4)
                                Button { model.notePendingDeletion = note; model.confirmNoteDeletion = true } label: { Image(systemName: "trash").foregroundStyle(.white.opacity(0.55)).frame(width: 28, height: 28) }
                                    .buttonStyle(SharedPressStyle(motion: interaction)).help("Delete note").accessibilityLabel("Delete note")
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }.frame(maxHeight: 260).scrollIndicators(.hidden)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .alert("Delete this thought?", isPresented: $model.confirmNoteDeletion) {
                Button("Cancel", role: .cancel) { model.notePendingDeletion = nil }
                Button("Delete", role: .destructive) {
                    if let note = model.notePendingDeletion { model.deleteParkedNote(note) }
                    model.notePendingDeletion = nil
                }
            } message: { Text("This note will be removed from your Mac.") }
    }
    var leaderboard: some View {
        SocialPanel(state: model.socialPanel, online: model.online, motion: interaction, journey:model.journey, openRanks:{showPage(8)})
    }
    var backgroundAudio: some View {
        GeometryReader {proxy in
            let level=model.audioVolumeDrag ?? model.musicVolume
            ZStack(alignment:.leading) {
                RoundedRectangle(cornerRadius:16).fill(.white.opacity(0.025))
                Rectangle().fill(model.audioEnabled ? accent.opacity(0.065) : .white.opacity(0.025))
                    .frame(width:proxy.size.width*level)
                    .allowsHitTesting(false)
                HStack(spacing:8) {
                    Button {model.audioEnabled.toggle()} label: {
                        Image(systemName:model.audioEnabled && level>0 ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .font(.system(size:13,weight:.medium)).foregroundStyle(model.audioEnabled ? .white.opacity(0.72) : .white.opacity(0.5))
                            .frame(width:28,height:32).contentShape(Rectangle())
                    }.buttonStyle(SharedPressStyle(motion:interaction))
                        .help(model.audioEnabled ? "Turn audio off" : "Turn audio on")
                        .accessibilityLabel(model.audioEnabled ? "Turn audio off" : "Turn audio on")
                    Menu {
                        Button("No audio") {model.clearAudioSelection()}
                        ForEach(model.tracks) {track in
                            Button {if model.selectedID != track.id {model.selectTrack(track)}} label: {
                                if model.selectedID == track.id {Label(track.title,systemImage:"checkmark")} else {Text(track.title)}
                            }
                        }
                        Divider()
                        Button("Import audio…") {model.importAudio()}
                        if !model.tracks.isEmpty {
                            Menu("Remove music") {
                                ForEach(model.tracks) {track in Button(track.title,role:.destructive) {model.removeTrack(track)}}
                            }
                            Button("Manage audio…") {showPage(2)}
                        }
                    } label: {
                        Text(model.selectedTrack?.title ?? "Add audio").font(.system(size:12,weight:.medium))
                            .foregroundStyle(.white.opacity(0.72)).lineLimit(1).frame(maxWidth:.infinity,alignment:.leading).frame(height:32).contentShape(Rectangle())
                    }.menuStyle(.borderlessButton).menuIndicator(.hidden)
                        .help("Choose background audio · Drag across the row to adjust volume")
                        .accessibilityLabel("Choose background audio")
                }.padding(.horizontal,8)
            }.clipShape(RoundedRectangle(cornerRadius:16))
                .overlay {RoundedRectangle(cornerRadius:16).strokeBorder(.white.opacity(0.035),lineWidth:0.7)}
                .contentShape(RoundedRectangle(cornerRadius:16))
                .highPriorityGesture(DragGesture(minimumDistance:8).onChanged {value in
                    let fraction=min(1,max(0,value.location.x/max(1,proxy.size.width)))
                    model.audioVolumeDrag=fraction
                    if !model.audioEnabled {model.audioEnabled=true}
                    model.player?.volume=Float(fraction)
                }.onEnded {value in
                    model.musicVolume=min(1,max(0,value.location.x/max(1,proxy.size.width)))
                    model.audioVolumeDrag=nil
                })
                .accessibilityElement(children:.contain)
                .accessibilityValue("Volume \(Int(level*100)) percent")
                .accessibilityAdjustableAction {direction in
                    switch direction {
                    case .increment: model.musicVolume=min(1,model.musicVolume+0.05)
                    case .decrement: model.musicVolume=max(0,model.musicVolume-0.05)
                    @unknown default: break
                    }
                }
        }.frame(height:32)
            .onDisappear {if model.audioVolumeDrag != nil {model.player?.volume=Float(model.musicVolume);model.audioVolumeDrag=nil}}
    }
    var library: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose the sound for your sessions.").font(.system(size: 14)).foregroundStyle(.white.opacity(0.75))
            if model.selectedTrack != nil {
                HStack { Image(systemName: "speaker.wave.2").foregroundStyle(accent); Slider(value: $model.musicVolume, in: 0...1).tint(accent).accessibilityLabel("Background audio volume") }
            }
            if model.tracks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "waveform").font(.system(size: 32, weight: .light)).foregroundStyle(mint)
                    Text("Add your first audio file").font(.system(size: 16, weight: .medium))
                    Text("Music or white noise will loop while your timer runs.")
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).padding(.vertical, 24)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        trackRow(title: "No audio", selected: model.selectedID == nil) { model.clearAudioSelection() }
                        ForEach(model.tracks) { track in
                            HStack(spacing:4) {
                                trackRow(title:track.title,selected:model.selectedID == track.id) {model.selectTrack(track)}
                                Button {model.removeTrack(track)} label: {Image(systemName:"trash").foregroundStyle(.white.opacity(0.6)).frame(width:32,height:36)}
                                    .buttonStyle(SharedPressStyle(motion:interaction)).help("Remove \(track.title) from Still").accessibilityLabel("Remove \(track.title) from Still")
                            }
                        }
                    }
                }.frame(height: min(CGFloat(model.tracks.count + 1) * 48, 192))
                if model.selectedTrack != nil && !model.clock.running {
                    Button(model.audioPlaying ? "Stop preview" : "Preview selected audio") { model.toggleAudio() }.font(.system(size: 12))
                }
            }
            Button { model.importAudio() } label: { Label("Import audio…", systemImage: "plus").frame(maxWidth: .infinity).padding(.vertical, 8) }
                .buttonStyle(.borderedProminent).tint(mint).foregroundStyle(.black).font(.system(size: 14, weight: .medium))
            Text("Your originals stay untouched. Still keeps its own local copies.")
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
        }
    }
    func trackRow(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? mint : .white.opacity(0.4))
                Text(title).lineLimit(1).foregroundStyle(.white)
                Spacer()
            }.font(.system(size: 14)).padding(12).frame(maxWidth: .infinity).background(selected ? .white.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(SharedPressStyle(motion: interaction)).accessibilityLabel(title + (selected ? ", selected" : ""))
    }
    var settings: some View {
        VStack(alignment:.leading,spacing:20) {
            Button {model.walkthrough.reset();showPage(6)} label: {
                HStack(spacing:12) {
                    Image(systemName:"play.rectangle").font(.system(size:24)).foregroundStyle(accent)
                    VStack(alignment:.leading,spacing:4) {
                        Text("How Still works").font(.system(size:14,weight:.semibold))
                        Text("Try the controls at your own pace").font(.system(size:11)).foregroundStyle(.secondary)
                    }
                    Spacer();Image(systemName:"chevron.right").font(.system(size:11)).foregroundStyle(.secondary)
                }.padding(16).background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:20))
            }.buttonStyle(SharedPressStyle(motion:interaction)).foregroundStyle(.white)
            IconRail(icons:["macwindow","timer","speaker.wave.2","person.crop.circle"],names:["Notch","Sessions","Sound","Profile"],selection:$model.settingsTab,color:accent)
            VStack(alignment:.leading,spacing:20) {
                if model.settingsTab == 0 {
                    Text("Notch").font(.system(size:16,weight:.semibold))
                    Picker("Notch style",selection:$model.circularNotch) {Text("Full").tag(false);Text("Circular").tag(true)}.pickerStyle(.segmented).accessibilityLabel("Notch style")
                    Toggle("Open from screen edge",isOn:$model.hoverToOpen)
                    Text("Move to the very top centre of your screen to open instantly. Clicking Still or pressing Control–Option–Space also opens it.").font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    VStack(alignment:.leading,spacing:8) {
                        Text("Glass transparency")
                        Slider(value:$model.glassTransparency,in:0...1).accessibilityLabel("Glass transparency")
                        HStack {Text("Less");Spacer();Text("More")}.font(.system(size:10)).foregroundStyle(.secondary)
                    }
                } else if model.settingsTab == 1 {
                    Text("Sessions").font(.system(size:16,weight:.semibold))
                    durationRow("Focus",value:$model.focusMinutes,range:1...180)
                    durationRow("Break",value:$model.breakMinutes,range:1...60)
                    Text("Standard rhythm: 25 minutes of focus, then a 5-minute break. Duration changes apply to the next session.").font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    Toggle("Auto-start next session",isOn:$model.autoStart)
                    Text("Ranked and Hardcore always require a seven-second Engage hold. They never start automatically.").font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                } else if model.settingsTab == 2 {
                    Text("Sound").font(.system(size:16,weight:.semibold))
                    Toggle("Tick every 5 minutes",isOn:$model.tickEnabled)
                    Toggle("Ding at completion",isOn:$model.dingEnabled)
                    Slider(value:$model.soundVolume,in:0...1).accessibilityLabel("Timer sound volume")
                    HStack {Button("Test tick") {model.previewTick()};Spacer();Button("Test ding") {model.previewDing()}}
                    Button {showPage(2)} label: {Label("Manage music & white noise",systemImage:"music.note.list")}.buttonStyle(SharedPressStyle(motion:interaction)).foregroundStyle(accent)
                    Text("During focus, tap the speaker to mute, tap the track name to choose music, or drag across the sound row to adjust its volume. Remove imported tracks in the audio library.").font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                } else {
                    Text("Profile").font(.system(size:16,weight:.semibold))
                    HStack {RankEmblem(rank:PlayerRank(xp:model.journey.spendableXP),size:56);Spacer();Text(model.journey.playerRank).font(.system(size:20,weight:.semibold,design:.rounded));Spacer()}
                    Toggle("Testing profile",isOn:Binding(get:{model.journey.testingUnlocked},set:{model.useTestingProfile($0)})).disabled(model.hasProgress || model.recoveryChecking || model.recoverySnapshot != nil)
                    Text("Testing uses separate sample progress with all badges and free consumables. Turn it off to return to your original progress. Switch between sessions.").font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    HStack {Button("Ranks & shop") {showPage(8)};Spacer();Button("My Journey") {showPage(5)}}.foregroundStyle(accent)
                }
            }.padding(20).frame(maxWidth:.infinity,alignment:.leading).background(.white.opacity(0.035),in:RoundedRectangle(cornerRadius:24))
            HStack {Text("⌃ ⌥ Space").foregroundStyle(.secondary);Spacer();Button("Quit Still") {NSApp.terminate(nil)}}.font(.system(size:11))
        }.font(.system(size:12)).buttonStyle(SharedPressStyle(motion:interaction)).toggleStyle(.switch).controlSize(.small).tint(accent)
    }
    func durationRow(_ label: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack {
            Text(label); Spacer()
            Stepper(value: value, in: range) { Text("\(value.wrappedValue) min").monospacedDigit().frame(width: 64, alignment: .trailing) }.fixedSize()
        }.font(.system(size: 14))
    }
}

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class HoverHost: NSHostingView<StillView> {
    var entered: (() -> Void)?
    var exited: (() -> Void)?
    var moved: (() -> Void)?
    private var hoverArea: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // inVisibleRect tracks animated bounds automatically. Recreating it during
        // every layout generated false exits while the notch was opening.
        guard hoverArea == nil else { return }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); hoverArea = area
    }
    override func mouseMoved(with event:NSEvent) {moved?()}
    override func mouseEntered(with event: NSEvent) { entered?() }
    override func mouseExited(with event: NSEvent) { exited?() }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = FocusModel()
    var panel: NotchPanel!
    var host: HoverHost!
    var status: NSStatusItem!
    var screen: NSScreen { NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.screens.first! }
    var notchWidth: CGFloat { if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea { return max(160, right.minX - left.maxX) }; return 120 }
    var notchHeight: CGFloat { max(30, screen.safeAreaInsets.top) }
    var hoverOpenWork: DispatchWorkItem?
    var collapseWork: DispatchWorkItem?
    var globalHover: Any?
    var globalClick: Any?
    var localClick: Any?
    var wantsExpanded = true
    var isAnimating = false
    var animationGeneration = 0
    var interactionPinned = false
    var menuTracking = false
    var hotkey: EventHotKeyRef?
    var subscriptions = Set<AnyCancellable>()
    private var layoutRefreshPending = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let mainMenu = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Still", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; mainMenu.addItem(appItem)
        let editItem = NSMenuItem(); let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: NSSelectorFromString(action), keyEquivalent: key)
        }
        editItem.submenu = editMenu; mainMenu.addItem(editItem); NSApp.mainMenu = mainMenu
        panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovable = false; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        host = HoverHost(rootView: makeView()); host.sizingOptions = [.intrinsicContentSize]; panel.contentView = host
        panel.acceptsMouseMovedEvents=true
        host.moved = { [weak self] in self?.scheduleHoverOpen() }
        globalHover=NSEvent.addGlobalMonitorForEvents(matching:.mouseMoved) { [weak self] _ in
            Task { @MainActor in self?.scheduleHoverOpen() }
        }
        host.entered = { [weak self] in self?.scheduleHoverOpen() }
        host.exited = { [weak self] in self?.hoverOpenWork?.cancel();self?.scheduleCollapse() }
        model.onChange = { [weak self] in self?.updateStatus() }
        model.onComplete = { [weak self] in
            guard let self else { return }; self.model.page = 0
            if !self.model.autoStart { self.expand(activate: false) }
        }
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.image = NSImage(systemSymbolName: "leaf", accessibilityDescription: "Still focus timer")
        status.button?.target = self; status.button?.action = #selector(statusClick)
        status.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        globalClick = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.model.importing, !self.panel.frame.contains(NSEvent.mouseLocation) else { return }
                self.collapse()
            }
        }
        localClick = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .leftMouseDown && event.window === self.panel { self.interactionPinned = true; self.collapseWork?.cancel() }
            if event.type == .keyDown && event.keyCode == 53 && !self.model.importing { self.collapse(); return nil }
            return event
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wake), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        for (publisher, page) in [(model.online.objectWillChange, 4), (model.socialPanel.objectWillChange, 4), (model.journeyPanel.objectWillChange, 5), (model.rankPanel.objectWillChange, 8), (model.walkthrough.objectWillChange, 6)] {
            publisher.debounce(for: .milliseconds(40), scheduler: RunLoop.main).sink { [weak self] _ in
                guard let self, self.model.page == page else { return }; self.refreshLayout()
            }.store(in: &subscriptions)
        }
        model.$recoverySnapshot.dropFirst().sink { [weak self] _ in self?.refreshLayout() }.store(in: &subscriptions)
        model.$recoveryChecking.dropFirst().sink { [weak self] _ in self?.refreshLayout() }.store(in: &subscriptions)
        model.$selectedTier.dropFirst().debounce(for:.milliseconds(40),scheduler:RunLoop.main).sink { [weak self] _ in self?.refreshLayout() }.store(in:&subscriptions)
        model.$selectedArchetype.dropFirst().debounce(for:.milliseconds(40),scheduler:RunLoop.main).sink { [weak self] _ in self?.refreshLayout() }.store(in:&subscriptions)
        model.$settingsTab.dropFirst().debounce(for:.milliseconds(40),scheduler:RunLoop.main).sink { [weak self] _ in self?.refreshLayout() }.store(in:&subscriptions)
        model.$page.dropFirst().sink { [weak self] _ in self?.refreshLayout() }.store(in: &subscriptions)
        model.$tracks.dropFirst().sink { [weak self] _ in self?.refreshLayout() }.store(in: &subscriptions)
        model.$clock.dropFirst().sink { [weak self] _ in guard let self, self.model.page == 0 else { return }; self.refreshLayout() }.store(in: &subscriptions)
        model.$parkedNotes.dropFirst().sink { [weak self] _ in guard let self, self.model.page == 7 else { return }; self.refreshLayout() }.store(in: &subscriptions)
        model.$awardSummary.dropFirst().sink { [weak self] _ in self?.refreshLayout() }.store(in: &subscriptions)
        model.$message.dropFirst().sink { [weak self] _ in self?.refreshLayout() }.store(in: &subscriptions)
        NotificationCenter.default.addObserver(self, selector: #selector(menuBegan), name: NSMenu.didBeginTrackingNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(menuEnded), name: NSMenu.didEndTrackingNotification, object: nil)
        registerShortcut()
        expand(activate: false, animated: false)
    }
    func refreshLayout() {
        guard wantsExpanded, !layoutRefreshPending else { return }
        layoutRefreshPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }; self.layoutRefreshPending = false
            guard self.wantsExpanded else { return }; self.resize(animated: true)
        }
    }
    func makeView() -> StillView { StillView(model: model, interaction: model.surfaceMotion, notchWidth: notchWidth, notchHeight: notchHeight, close: { [weak self] in self?.collapse() }, open: { [weak self] in self?.expand(activate: true) }) }
    func frame(expanded: Bool) -> NSRect {
        if !expanded {
            if model.circularNotch {return NSRect(x:screen.frame.midX-notchWidth/2-40,y:screen.frame.maxY-notchHeight/2-16,width:32,height:32)}
            return NSRect(x:screen.frame.midX-(notchWidth+116)/2,y:screen.frame.maxY-notchHeight-3,width:notchWidth+116,height:notchHeight+3)
        }
        let width: CGFloat = 420
        let height: CGFloat = expanded ? (model.page == 1 ? 550 : model.page == 3 ? 640 : model.page == 6 ? 660 : 560) + notchHeight : notchHeight + 14
        return NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height)
    }
    func expand(activate: Bool, animated: Bool = true) {
        hoverOpenWork?.cancel()
        collapseWork?.cancel()
        if activate { interactionPinned = true }
        if wantsExpanded && model.expanded && panel.isVisible {
            if activate { NSApp.activate(ignoringOtherApps: true); panel.makeKey() }
            return
        }
        let wasClosed = !model.expanded
        wantsExpanded = true
        if wasClosed { model.reveal = 0; model.contentVisibility = 0; model.expanded = true }
        panel.orderFrontRegardless(); resize(animated: animated)
        if activate { NSApp.activate(ignoringOtherApps: true); panel.makeKey() }
    }
    func collapse() {
        hoverOpenWork?.cancel()
        guard !model.importing, !menuTracking, wantsExpanded else { return }
        collapseWork?.cancel(); wantsExpanded = false; interactionPinned = false
        model.cancelEngage()
        model.surfaceMotion.reset()
        if model.isRecordingNote { model.finishNoteRecording() }
        panel.makeFirstResponder(nil); resize(animated: true); panel.resignKey()
    }
    func resize(animated: Bool) {
        host.layoutSubtreeIfNeeded()
        let target: NSRect
        if wantsExpanded {
            let size = host.fittingSize
            let height = max(size.height, notchHeight + 200)
            target = NSRect(x: screen.frame.midX - 210, y: screen.frame.maxY - height, width: 420, height: height)
        } else { target = frame(expanded: false) }
        // Content-only updates must not restart an opening spring or animate an identical window frame.
        if wantsExpanded && model.reveal == 1 && model.contentVisibility == 1 && panel.frame == target && !isAnimating { return }
        animationGeneration += 1
        let generation = animationGeneration
        let revealTarget = wantsExpanded ? 1.0 : 0.0
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, !panel.frame.isEmpty else {
            isAnimating = false
            panel.setFrame(target, display: true); model.reveal = revealTarget; model.contentVisibility = revealTarget
            if !wantsExpanded { model.expanded = false; model.page = 0; if !model.clock.running { model.pauseAudio() } }
            return
        }
        isAnimating = true
        let duration = wantsExpanded ? NotchMotion.openDuration : NotchMotion.closeDuration
        let ease = wantsExpanded
            ? CAMediaTimingFunction(controlPoints: 0.22, 1.08, 0.36, 1)
            : CAMediaTimingFunction(controlPoints: 0.32, 0, 0.28, 1.06)
        // The window and the view share the same curve and duration. AppKit and
        // Core Animation drive intermediate frames instead of publishing a new
        // SwiftUI model value and forcing a window resize on each display tick.
        if wantsExpanded {
            withAnimation(.timingCurve(0.22, 1.08, 0.36, 1, duration: duration)) { model.reveal = revealTarget }
            withAnimation(.easeOut(duration: 0.18).delay(0.04)) { model.contentVisibility = 1 }
        } else {
            withAnimation(.timingCurve(0.32, 0, 0.28, 1.06, duration: duration)) { model.reveal = revealTarget }
            withAnimation(.easeOut(duration: 0.12)) { model.contentVisibility = 0 }
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = ease
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(target, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.animationGeneration == generation else { return }
                self.isAnimating = false
                if !self.wantsExpanded {
                    self.model.expanded = false; self.model.page = 0
                    if !self.model.clock.running { self.model.pauseAudio() }
                }
            }
        }
    }
    func scheduleHoverOpen() {
        if wantsExpanded {return}
        hoverOpenWork?.cancel()
        guard !wantsExpanded,model.hoverToOpen,NSEvent.pressedMouseButtons == 0 else {return}
        let point=NSEvent.mouseLocation
        guard point.y >= screen.frame.maxY-3,point.y <= screen.frame.maxY,
              abs(point.x-screen.frame.midX)<=48 else {return}
        expand(activate:false)
    }
    func scheduleCollapse() {
        collapseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.interactionPinned, !self.model.importing, !self.menuTracking,
                  !self.panel.frame.contains(NSEvent.mouseLocation) else { return }
            self.collapse()
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (!isAnimating ? NotchMotion.exitGrace : NotchMotion.openDuration + NotchMotion.exitGrace), execute: work)
    }
    @objc func menuBegan() { menuTracking = true; collapseWork?.cancel() }
    @objc func menuEnded() { menuTracking = false; if !panel.frame.contains(NSEvent.mouseLocation) { scheduleCollapse() } }
    func updateStatus() { status?.button?.toolTip = "Still · \(model.modeName) · \(model.time)\nControl–Option–Space to open" }
    @objc func statusClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu(); menu.addItem(withTitle: "Open timer", action: #selector(show), keyEquivalent: "")
            menu.addItem(withTitle: "Focus Archetypes…", action: #selector(showArchetypes), keyEquivalent: "")
            menu.addItem(withTitle: "Audio library…", action: #selector(showLibrary), keyEquivalent: "")
            menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: "")
            menu.addItem(withTitle: model.clock.running ? "Pause timer" : "Start timer", action: #selector(toggleTimer), keyEquivalent: "")
            menu.addItem(.separator()); menu.addItem(withTitle: "Quit Still", action: #selector(quit), keyEquivalent: "q")
            menu.items.forEach { $0.target = self }; status.menu = menu; status.button?.performClick(nil); status.menu = nil
        } else { wantsExpanded ? collapse() : expand(activate: true) }
    }
    @objc func show() { model.page = 0; expand(activate: true) }
    @objc func showArchetypes() { model.page = 3; expand(activate: true) }
    @objc func showLibrary() { model.page = 2; expand(activate: true) }
    @objc func showSettings() { model.page = 1; expand(activate: true) }
    @objc func toggleTimer() { model.toggle() }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func wake() { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.resize(animated: false) } }
    @objc func screenChanged() { host.rootView = makeView(); resize(animated: false) }
    func registerShortcut() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            Task { @MainActor in if let delegate = NSApp.delegate as? AppDelegate { delegate.wantsExpanded ? delegate.collapse() : delegate.expand(activate: true) } }
            return noErr
        }, 1, &eventType, nil, nil)
        let id = EventHotKeyID(signature: 0x53544C4C, id: 1)
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &hotkey)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model.finishNoteRecording()
        if model.recoverySnapshot != nil {model.discardRecovery()}
        if model.hasProgress && model.mode == 0 {model.endSession()}
        model.stopPulse();model.pauseAudio()
        Task { [weak self] in
            await self?.model.flushHeartbeatClear()
            sender.reply(toApplicationShouldTerminate:true)
        }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) { model.finishNoteRecording(); animationGeneration += 1; if model.hasProgress && model.mode == 0 { model.endSession() }; model.stopPulse(); model.pauseAudio(); if let hotkey { UnregisterEventHotKey(hotkey) } }
}

func selfTest() {
    var c = SessionClock(duration: 1500, remaining: 1500)
    let start = Date(timeIntervalSince1970: 1000)
    c.start(at: start)
    precondition(c.seconds(at: start.addingTimeInterval(300)) == 1200)
    precondition(c.tickBoundary(at: start.addingTimeInterval(299.9)) == 0)
    precondition(c.tickBoundary(at: start.addingTimeInterval(300)) == 1)
    precondition(c.tickBoundary(at: start.addingTimeInterval(600)) == 2)
    c.pause(at: start.addingTimeInterval(375)); precondition(c.remaining == 1125 && !c.running)
    c.start(at: start.addingTimeInterval(500)); precondition(c.seconds(at: start.addingTimeInterval(1625)) == 0)
    c.reset(60); precondition(c.duration == 60 && c.remaining == 60 && !c.running)
    var journey = FocusJourney(); let session = UUID()
    precondition(journey.award(session: session, archetype: .systemBuilding, minutes: 99, at: start))
    precondition(journey.progress(for: .systemBuilding).level == 1)
    precondition(!journey.award(session: session, archetype: .legacy, minutes: 99, at: start))
    precondition(journey.award(session: UUID(), archetype: .systemBuilding, minutes: 1, at: start))
    precondition(journey.progress(for: .systemBuilding).level == 2)
    precondition(journey.progress(for: .systemBuilding).milestones == [true, true, false, false])
    precondition(journey.progress(for: .legacy).xp == 0)
    let restored = try! JSONDecoder().decode(FocusJourney.self, from: JSONEncoder().encode(journey))
    precondition(restored.totalXP == 100 && restored.records.count == 2)
    print("PASS: independent archetype totals, exact level boundaries, milestones, duplicate award rejection, persistence round trip.")
    var stakes = FocusJourney()
    let day = Date()
    precondition(stakes.award(session: UUID(), archetype: .systemBuilding, minutes: 100, at: day))
    precondition(stakes.award(session: UUID(), archetype: .skillMastery, minutes: 10, at: day, tier: .ranked))
    precondition(stakes.progress(for: .skillMastery).xp == 15 && stakes.streak == 1)
    stakes.endEarly(session: UUID(), archetype: .systemBuilding, tier: .ranked, at: day)
    precondition(stakes.progress(for: .systemBuilding).xp == 85 && stakes.progress(for: .skillMastery).xp == 15 && stakes.streak == 0)
    stakes.endEarly(session: UUID(), archetype: .systemBuilding, tier: .zen, at: day)
    precondition(stakes.progress(for: .systemBuilding).xp == 85)
    let failed = UUID()
    stakes.endEarly(session: failed, archetype: .systemBuilding, tier: .hardcore, at: day)
    stakes.endEarly(session: failed, archetype: .systemBuilding, tier: .hardcore, at: day)
    precondition(stakes.progress(for: .systemBuilding).xp == 43 && stakes.failures.count == 1)
    precondition(stakes.award(session: UUID(), archetype: .legacy, minutes: 10, at: day, tier: .hardcore))
    precondition(stakes.progress(for: .legacy).xp == 20 && stakes.game.trophies.isEmpty)
    for _ in 0..<4 { precondition(stakes.award(session: UUID(), archetype: .legacy, minutes: 1, at: day, tier: .ranked)) }
    precondition(stakes.game.trophies.isEmpty)
    let persisted = try! JSONDecoder().decode(FocusJourney.self, from: JSONEncoder().encode(stakes))
    precondition(persisted.failures.count == 1 && persisted.progress(for: .systemBuilding).xp == 43 && persisted.game.trophies.isEmpty)
    let old = #"{"records":[]}"#.data(using: .utf8)!
    precondition((try! JSONDecoder().decode(FocusJourney.self, from: old)).totalXP == 0)
    print("PASS: tier rewards, XP penalties, streak reset, failure deduplication, badges and legacy data migration.")
    print("PASS: countdown, five-minute ticks, pause/resume, completion and reset")
}

@MainActor func interactionTest() {
    guard Bundle.main.bundleIdentifier == "com.still.focus.tests.v13" else { fatalError("Run interaction checks from the isolated test bundle.") }
    let m = FocusModel()
    m.pulse?.invalidate(); m.autoStart = false; m.tickEnabled = false; m.dingEnabled = false
    m.clearAudioSelection(); m.journey = FocusJourney(); m.saveJourney(); m.selectArchetype(.skillMastery); m.selectedTier = .zen; m.focusMinutes = 1
    precondition(m.primaryTitle == "Start focus")
    m.toggle(engaged:true); precondition(m.primaryTitle == "Pause" && m.hasProgress)
    m.clock.start(at: Date().addingTimeInterval(-10)); m.update(); m.pause()
    let paused = m.remaining
    precondition(paused > 49 && paused < 51 && m.primaryTitle == "Resume")
    m.selectMode(1); precondition(m.mode == 0 && m.remaining == paused)
    m.selectMode(99); precondition(m.mode == 0)
    m.selectArchetype(.legacy); precondition(m.selectedArchetype == .skillMastery)
    m.focusMinutes = 2
    precondition(m.remaining == paused && m.clock.duration == 60)
    m.toggle(engaged:true); precondition(m.clock.running && m.clock.seconds(at: Date()) < 51)
    m.reset(); precondition(m.remaining == 120 && m.primaryTitle == "Start focus")
    precondition(m.journey.totalXP == 0)
    for count in 1...4 {
        m.selectMode(0); m.reset(); m.toggle(engaged:true); m.update(at: m.clock.deadline!.addingTimeInterval(1))
        precondition(m.sessions == count && m.completed)
        precondition(m.journey.progress(for: .skillMastery).xp == count * 2)
        precondition(m.journey.progress(for: .legacy).xp == 0)
        m.update(at: Date().addingTimeInterval(10000))
        precondition(m.journey.records.count == count)
        precondition(m.primaryTitle == "Start break")
        m.toggle(engaged:true); precondition(m.mode == 1 && m.clock.running)
        let xpBeforeBreak = m.journey.totalXP
        m.update(at: m.clock.deadline!.addingTimeInterval(1)); precondition(m.journey.totalXP == xpBeforeBreak)
    }
    let social = SocialPanelModel()
    let zenScores = social.demoRows().map(\.xp)
    precondition(social.demoRows().count == 8)
    social.tier = 2
    precondition(social.demoRows().map(\.xp) != zenScores)
    social.tab = 1
    precondition(!social.demoRows().contains(where: { $0.handle == "Omer" }))
    social.accepted.insert("Omer"); social.incoming.removeAll { $0 == "Omer" }
    precondition(social.demoRows().contains(where: { $0.handle == "Omer" }) && !social.incoming.contains("Omer"))
    print("PASS: sample tiers have distinct standings; pending sample friends enter Friends only after acceptance.")
    let reloaded = FocusModel(); reloaded.pulse?.invalidate()
    precondition(reloaded.journey.totalXP == 8 && reloaded.journey.records.count == 4)
    print("PASS: archetype lock, correct XP attribution, no XP for cancelled sessions or breaks, duplicate-completion protection, saved progress reload.")
    print("PASS: Start/Pause/Resume, duration changes preserve paused time, reset uses next duration, focus sessions alternate with a single configurable break.")
}

@MainActor func asyncRegressionTest() async {
    guard Bundle.main.bundleIdentifier == "com.still.focus.tests.v13" else { fatalError("Use isolated test bundle") }
    let m = FocusModel()
    m.autoStart = true; m.tickEnabled = false; m.dingEnabled = false; m.clearAudioSelection()
    m.focusMinutes = 1; m.selectMode(0); m.reset(); m.toggle()
    m.update(at: m.clock.deadline!.addingTimeInterval(1))
    m.autoStart = false
    try? await Task.sleep(for: .milliseconds(2200))
    precondition(m.completed && !m.clock.running, "Disabled auto-start still fired")
    m.autoStart = true; m.reset(); m.toggle(engaged:true); m.update(at: m.clock.deadline!.addingTimeInterval(1))
    try? await Task.sleep(for: .milliseconds(1000))
    m.reset(); m.toggle(engaged:true); m.update(at: m.clock.deadline!.addingTimeInterval(1))
    let current = m.sessionID
    try? await Task.sleep(for: .milliseconds(1200))
    precondition(m.completed && m.sessionID == current, "An old completion advanced a newer session")
    try? await Task.sleep(for: .milliseconds(1200))
    precondition(m.mode == 1 && m.clock.running, "Current auto-start did not advance")
    m.pause(); m.autoStart = false
    print("PASS: disabling auto-start cancels delayed advance; stale callbacks cannot advance a newer session; current auto-start still works.")
}

@MainActor func pauseBankTest() {
    guard Bundle.main.bundleIdentifier == "com.still.focus.tests.v13" else {fatalError("Use isolated test bundle")}
    let date=Date(timeIntervalSince1970:1000)
    var bank=PauseBank();bank.pause(at:date);bank.pause(at:date.addingTimeInterval(10))
    precondition(bank.wasPaused && bank.remaining(at:date.addingTimeInterval(60))==240)
    bank.resume(at:date.addingTimeInterval(60));bank.pause(at:date.addingTimeInterval(100))
    precondition(bank.remaining(at:date.addingTimeInterval(339.9))>0)
    precondition(bank.remaining(at:date.addingTimeInterval(340))==0)
    var journey=FocusJourney()
    for tier in [IntensityTier.ranked,.hardcore] {
        precondition(journey.award(session:UUID(),archetype:.skillMastery,minutes:10,at:date,tier:tier))
        precondition(journey.records.last?.earnedXP == (tier == .ranked ? 15 : 20))
        precondition(journey.award(session:UUID(),archetype:.skillMastery,minutes:10,at:date,tier:tier,wasPaused:true))
        precondition(journey.records.last?.earnedXP==10 && journey.records.last?.wasPaused==true)
    }
    let m=FocusModel();m.autoStart=false;m.tickEnabled=false;m.dingEnabled=false;m.reset();m.mode=0;m.focusMinutes=10;m.selectArchetype(.systemBuilding)
    for tier in [IntensityTier.ranked,.hardcore] {
        m.journey=FocusJourney();m.journey.award(session:UUID(),archetype:.systemBuilding,minutes:100,at:Date())
        m.selectTier(tier);m.toggle(engaged:true)
        let now=Date();m.pause(at:now)
        precondition(m.sessionMultiplier==1 && m.isPaused && m.pauseRemaining==300)
        m.update(at:now.addingTimeInterval(299.9));precondition(m.hasProgress)
        m.update(at:now.addingTimeInterval(300));precondition(!m.hasProgress)
        precondition(m.journey.totalXP == (tier == .ranked ? 85 : 50))
        precondition(m.journey.failures.count == (tier == .hardcore ? 1 : 0))
        m.update(at:now.addingTimeInterval(600));precondition(m.journey.totalXP == (tier == .ranked ? 85 : 50))
    }
    m.selectTier(.zen);m.toggle();let now=Date();m.pause(at:now);m.update(at:now.addingTimeInterval(1000));precondition(m.isPaused && m.sessionMultiplier==1)
    m.reset();m.focusMinutes=2
    print("PASS: cumulative five-minute allowance, immediate permanent XP tax, 2x/1x awards, exact expiry penalties once, Hardcore failure record, and unlimited Zen pauses.")
}

@MainActor func engageTest() async {
    guard Bundle.main.bundleIdentifier == "com.still.focus.tests.v13" else {fatalError("Use isolated test bundle")}
    let m=FocusModel();m.autoStart=false;m.reset();m.mode=0;m.selectedTier = .ranked;m.expanded=true
    m.toggle();precondition(!m.clock.running,"Click bypassed engagement")
    m.beginEngage(requirePointer:false)
    func releaseBeforeDeadline() { Thread.sleep(forTimeInterval:6.9); m.cancelEngage() }
    releaseBeforeDeadline();precondition(m.engageStarted == nil && !m.clock.running)
    try? await Task.sleep(for:.milliseconds(200));precondition(!m.clock.running,"Cancelled hold started later")
    print("PASS: releasing at 6.9 seconds resets hold and cannot start later.")
    m.beginEngage(requirePointer:false);try? await Task.sleep(for:.milliseconds(7200));precondition(m.clock.running)
    m.pause();m.reset();m.selectedTier = .hardcore;m.toggle();precondition(!m.clock.running)
    m.beginEngage(requirePointer:false);m.selectTier(.zen);precondition(m.engageStarted == nil && !m.clock.running)
    m.stopPulse()
    print("PASS: full seven-second hold starts Ranked; Hardcore click bypass is blocked; changing tier cancels hold.")
}

@MainActor func heartbeatTest() async throws {
    guard Bundle.main.bundleIdentifier == "com.still.focus.tests.v13" else {fatalError("Use isolated test bundle")}
    let root=FileManager.default.temporaryDirectory.appendingPathComponent("StillHeartbeatTests-"+UUID().uuidString)
    let now=Date()
    let snapshot=TimerHeartbeat(timestamp:now,elapsed:300,duration:1500,mode:0,sessionID:UUID(),archetype:.systemBuilding,tier:.ranked,running:true,pauseBank:PauseBank(),sessions:2)
    precondition(snapshot.valid && snapshot.graceRemaining(at:now.addingTimeInterval(179.9))>0 && snapshot.graceRemaining(at:now.addingTimeInterval(180))==0)
    let store=TimerHeartbeatStore(url:root.appendingPathComponent("io.json"))
    let saved=await store.save(snapshot,revision:1);precondition(saved)
    let loaded=await store.load();precondition(loaded?.sessionID==snapshot.sessionID && loaded?.elapsed==300)
    let cleared=await store.clear(revision:3);precondition(cleared)
    await store.save(snapshot,revision:2)
    let stale=await store.load();precondition(stale==nil,"Stale write resurrected cleared state")
    let payload=try JSONEncoder().encode(snapshot);precondition(payload.count<2048)
    try Data("invalid snapshot".utf8).write(to:root.appendingPathComponent("io.json"))
    let corrupt=await store.load();precondition(corrupt==nil)
    var expiredBank=PauseBank();expiredBank.pause(at:now.addingTimeInterval(-301))
    let pausedSnapshot=TimerHeartbeat(timestamp:now.addingTimeInterval(-10),elapsed:300,duration:1500,mode:0,sessionID:UUID(),archetype:.systemBuilding,tier:.ranked,running:false,pauseBank:expiredBank,sessions:0)
    precondition(pausedSnapshot.graceRemaining(at:now)==0,"Recovery refilled an expired pause bank")
    func fixture(_ snap:TimerHeartbeat,model:FocusModel,name:String) async {
        let url=root.appendingPathComponent(name)
        let writer=TimerHeartbeatStore(url:url);await writer.save(snap,revision:1)
        model.heartbeatStore=TimerHeartbeatStore(url:url)
        model.recoveryChecking=true;await model.loadRecovery(at:now)
    }
    let recovered=FocusModel(recoveryEnabled:false);recovered.journey=FocusJourney()
    await fixture(snapshot,model:recovered,name:"resume.json")
    precondition(recovered.isRecoveryGracePeriod && recovered.recoverySnapshot?.sessionID==snapshot.sessionID)
    recovered.toggle(engaged:true);precondition(!recovered.clock.running,"Pending recovery was bypassed")
    recovered.resumeRecovery(at:now.addingTimeInterval(10))
    precondition(recovered.clock.running && recovered.sessionID==snapshot.sessionID && recovered.clock.duration==1500 && recovered.remaining==1200 && recovered.sessionMultiplier==1.5)
    recovered.stopPulse();await recovered.flushHeartbeatClear()
    var bank=PauseBank();bank.pause(at:now.addingTimeInterval(-60));bank.resume(at:now)
    let taxed=TimerHeartbeat(timestamp:now,elapsed:300,duration:1500,mode:0,sessionID:UUID(),archetype:.skillMastery,tier:.hardcore,running:true,pauseBank:bank,sessions:0)
    let taxedModel=FocusModel(recoveryEnabled:false);taxedModel.journey=FocusJourney()
    await fixture(taxed,model:taxedModel,name:"tax.json");taxedModel.resumeRecovery(at:now)
    precondition(taxedModel.sessionMultiplier==1 && taxedModel.pauseRemaining==240)
    taxedModel.stopPulse();await taxedModel.flushHeartbeatClear()
    let expired=TimerHeartbeat(timestamp:now.addingTimeInterval(-181),elapsed:300,duration:1500,mode:0,sessionID:UUID(),archetype:.systemBuilding,tier:.hardcore,running:true,pauseBank:PauseBank(),sessions:0)
    let ended=FocusModel(recoveryEnabled:false);ended.journey=FocusJourney();ended.journey.award(session:UUID(),archetype:.systemBuilding,minutes:100,at:now)
    await fixture(expired,model:ended,name:"expired.json")
    precondition(ended.recoverySnapshot==nil && ended.journey.totalXP==50 && ended.journey.failures.count==1)
    let duplicate=FocusModel(recoveryEnabled:false);duplicate.journey=try JSONDecoder().decode(FocusJourney.self,from:JSONEncoder().encode(ended.journey))
    await fixture(expired,model:duplicate,name:"duplicate.json")
    precondition(duplicate.journey.totalXP==50 && duplicate.journey.failures.count==1 && duplicate.recoverySnapshot==nil)
    await ended.flushHeartbeatClear();await duplicate.flushHeartbeatClear()
    let cadence=FocusModel(recoveryEnabled:false);cadence.reset();cadence.mode=0;cadence.selectedTier = .zen;cadence.tickEnabled=false;cadence.dingEnabled=false
    cadence.heartbeatStore=TimerHeartbeatStore(url:root.appendingPathComponent("cadence.json"));cadence.toggle()
    let first=cadence.heartbeatRevision
    cadence.update();precondition(cadence.heartbeatRevision==first,"Unthrottled heartbeat write")
    try await Task.sleep(for:.milliseconds(3300))
    precondition(cadence.heartbeatRevision>first,"Missing three-second heartbeat")
    cadence.stopPulse();await cadence.flushHeartbeatClear()
    let final=await cadence.heartbeatStore?.load();precondition(final==nil)
    try FileManager.default.removeItem(at:root)
    print("PASS: \(payload.count)-byte asynchronous snapshot, three-second throttling, stale-write protection, 180-second recovery boundary, same-session resume, no downtime XP, preserved multiplier/bank, once-only failure resolution, clean shutdown clear.")
}

func pillarTest() throws {
    precondition(FocusPillar.allCases == [.ops, .master, .build])
    MainActor.assumeIsolated {
        let model = FocusModel(recoveryEnabled: false)
        precondition(model.selectedPillar == .ops && model.selectedTier == .zen)
    }
    let legacy = #"{"records":[{"id":"00000000-0000-4000-8000-000000000001","archetype":"systemBuilding","minutes":30,"completedAt":0,"earnedXP":60},{"id":"00000000-0000-4000-8000-000000000002","archetype":"selfOvercoming","minutes":20,"completedAt":0,"earnedXP":40},{"id":"00000000-0000-4000-8000-000000000003","archetype":"legacy","minutes":15,"completedAt":0,"earnedXP":15},{"id":"00000000-0000-4000-8000-000000000004","archetype":"providence","minutes":10,"completedAt":0,"earnedXP":10}],"deductions":{"selfOvercoming":10}}"#
    var journey=try JSONDecoder().decode(FocusJourney.self,from:Data(legacy.utf8))
    precondition(journey.pillarProgress(for:.build).xp==90 && journey.pillarProgress(for:.ops).xp==25 && journey.totalXP==115)
    let id=UUID();journey.award(session:id,archetype:.skillMastery,minutes:10,at:Date(),tier:.ranked)
    precondition(journey.records.last?.earnedXP==15 && journey.achievementXP(for:.skillMastery)==0)
    let total=journey.totalXP;journey.tag(session:id,track:.selfOvercoming)
    precondition(journey.totalXP==total && journey.achievementXP(for:.selfOvercoming)==55)
    journey.tag(session:id,track:.legacy)
    precondition(journey.totalXP==total && journey.achievementXP(for:.selfOvercoming)==40 && journey.achievementXP(for:.legacy)==30)
    precondition(FocusPillar.build.defaultTier == .hardcore && FocusPillar.master.defaultTier == .ranked && FocusPillar.ops.defaultTier == .zen)
    let roundTrip=try JSONDecoder().decode(FocusJourney.self,from:JSONEncoder().encode(journey));precondition(roundTrip.totalXP==total)
    print("PASS: legacy XP/deductions merge, 2x/1.5x/1x pillar defaults, optional tag attribution/retag without duplicate XP, and persistence.")
}

@MainActor func durationRewardTest() {
    let defaults=UserDefaults.standard
    let keys=["focus","rest","pomodoroDefaults.25.5.v1","focusJourney.v1"]
    let saved=keys.map {defaults.object(forKey:$0)}
    defer {for (key,value) in zip(keys,saved) {if let value {defaults.set(value,forKey:key)} else {defaults.removeObject(forKey:key)}}}
    defaults.set(15,forKey:"focus");defaults.set(10,forKey:"rest");defaults.removeObject(forKey:"pomodoroDefaults.25.5.v1")
    let m=FocusModel(recoveryEnabled:false)
    precondition(m.focusMinutes==25 && m.breakMinutes==5 && m.clock.duration==1500)
    m.autoStart=false;m.tickEnabled=false;m.dingEnabled=false;m.clearAudioSelection();m.journey=FocusJourney()
    for tier in IntensityTier.allCases {
        for minutes in [25,50] {
            m.mode=0;m.reset();m.selectTier(tier);m.setDuration(minutes)
            let expected=Int((Double(minutes)*tier.multiplier).rounded())
            precondition(m.previewXP==expected)
            m.toggle(engaged:true);m.update(at:m.clock.deadline!.addingTimeInterval(0.1))
            precondition(m.completed && m.journey.records.last?.earnedXP==expected)
        }
    }
    m.mode=1;m.reset();let before=m.journey.totalXP
    m.toggle();m.update(at:m.clock.deadline!.addingTimeInterval(0.1));precondition(m.journey.totalXP==before)
    m.mode=0;m.reset();m.focusMinutes=45;m.breakMinutes=10
    let reopened=FocusModel(recoveryEnabled:false);precondition(reopened.focusMinutes==45 && reopened.breakMinutes==10)
    m.stopPulse();reopened.stopPulse()
    print("PASS: saved defaults migrate to 25/5 once, custom durations survive relaunch, longer sessions award more XP in every tier, displayed XP matches completion payout, and breaks earn no XP.")
}

@main enum StillApplication {
 static func main() {

if CommandLine.arguments.contains("--upgrade-test") {MainActor.assumeIsolated {try! upgrade537Test()}}
else if CommandLine.arguments.contains("--testing-profile-test") {try! testingProfileTest()}
else if CommandLine.arguments.contains("--duration-test") {MainActor.assumeIsolated {durationRewardTest()}}
else if CommandLine.arguments.contains("--game-test") {MainActor.assumeIsolated {try! focusGameTest()}}
else if CommandLine.arguments.contains("--pillar-test") {try! pillarTest()}
else if CommandLine.arguments.contains("--heartbeat-test") {
    Task { @MainActor in do {try await heartbeatTest();exit(0)} catch {print(error);exit(1)} };RunLoop.main.run()
} else if CommandLine.arguments.contains("--pause-bank-test") { MainActor.assumeIsolated {pauseBankTest()} }
else if CommandLine.arguments.contains("--engage-test") {
    Task { @MainActor in await engageTest(); exit(0) }; RunLoop.main.run()
} else if CommandLine.arguments.contains("--self-test") { selfTest() } else if CommandLine.arguments.contains("--async-test") {
    Task { @MainActor in await asyncRegressionTest(); exit(0) }
    RunLoop.main.run()
} else if CommandLine.arguments.contains("--interaction-test") { MainActor.assumeIsolated { interactionTest() } } else {
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

 }
}
