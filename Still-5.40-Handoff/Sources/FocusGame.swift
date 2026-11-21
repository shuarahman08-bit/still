import SwiftUI

enum FocusItem: String, Codable, CaseIterable, Identifiable {
    case shield, overclock, alibi
    var id: String { rawValue }
    var title: String { self == .shield ? "Combo Shield" : self == .overclock ? "Overclock Stim" : "The Alibi" }
    var symbol: String { self == .shield ? "shield.lefthalf.filled" : self == .overclock ? "bolt.fill" : "moon.zzz.fill" }
    var cost: Int { self == .shield ? 500 : self == .overclock ? 1000 : 2000 }
    var detail: String {
        switch self {
        case .shield: return "Next strict session: the first pause keeps your multiplier. The shield shatters; pause time still counts."
        case .overclock: return "Next focus: 60 minutes, Hardcore, 3× XP. No pauses, including sleep. Ending early uses Hardcore penalties."
        case .alibi: return "Protect a 24-hour absence from breaking your daily streak. Starts now. Does not forgive failed sessions or count as a focus day."
        }
    }
}
struct GameSession: Codable {
    var id: UUID
    var startedAt: Date
    var overclock: Bool
    var shield: Bool
    var shieldShattered = false
    var paused = false
    var parkedThoughts: Int?
}
struct AlibiWindow: Codable {
    var start: Date
    var end: Date
}
struct FocusGame: Codable {
    var spent = 0
    var inventory: [String: Int] = [:]
    var equipped: Set<FocusItem> = []
    var active: GameSession?
    var alibis: [AlibiWindow] = []
    var lastHardcoreFailure: Date?
    var lastFailure: Date?
    var strictChain = 0
    var lastStrictEnd: Date?
    var cleanDays: [Date] = []
    var trophies: Set<String> = []
    var lastIntegrityEvent: Date?
    static let trophyNames = ["redemption arc", "big man ting", "immaculate Aura", "locked in", "built different", "side quest denied"]
    static let trophySymbols = ["arrow.uturn.up", "flame.fill", "sparkles", "lock.shield.fill", "bolt.shield.fill", "square.and.pencil"]
    static let trophyColors: [Color] = [IntensityTier.ranked.color,IntensityTier.hardcore.color,Color(red:0.73,green:0.8,blue:0.95),Color(red:0.46,green:0.84,blue:0.87),Color(red:0.94,green:0.69,blue:0.38),Color(red:0.73,green:0.64,blue:0.93)]
    static let trophyDetails = [
        "After a Hardcore failure, start a new 45-minute focus within 60 seconds and successfully finish it.",
        "Finish three consecutive Hardcore blocks of at least 25 minutes. Use no pause time; begin each within five minutes of the last.",
        "Complete focus on seven consecutive calendar days with no failed strict sessions, shattered shields or clock integrity triggers. Alibis do not count as focus days.",
        "Finish a Ranked or Hardcore block of at least 60 minutes without using the pause bank.",
        "Complete an Overclock: a 60-minute Hardcore block with no pauses or early exit.",
        "Park three thoughts during one focus block of at least 25 minutes. Finish without pausing."
    ]
    func count(_ item: FocusItem) -> Int { inventory[item.rawValue, default: 0] }
    func coversAbsence(from last: Date, to now: Date) -> Bool {
        let covered = alibis.reduce(0.0) { total, window in
            total + max(0, min(now, window.end).timeIntervalSince(max(last, window.start)))
        }
        let shifted = last.addingTimeInterval(covered)
        let cal = Calendar.current
        let yesterday = cal.date(byAdding: .day, value: -1, to: now)!
        return cal.isDate(shifted, inSameDayAs: now) || cal.isDate(shifted, inSameDayAs: yesterday)
    }

    mutating func begin(id: UUID, tier: IntensityTier, at now: Date) {
        guard active?.id != id else { return }
        let stim = equipped.contains(.overclock) && count(.overclock) > 0
        let shield = !stim && tier != .zen && equipped.contains(.shield) && count(.shield) > 0
        for item in [FocusItem.overclock, .shield] where (item == .overclock ? stim : shield) {
            inventory[item.rawValue, default: 0] -= 1; equipped.remove(item)
        }
        active = GameSession(id: id, startedAt: now, overclock: stim, shield: shield)
    }
    mutating func fail(tier: IntensityTier, at now: Date) {
        strictChain = 0; lastStrictEnd = nil; cleanDays = []; lastFailure = now
        if tier == .hardcore { lastHardcoreFailure = now }
        active = nil
    }
    mutating func finish(id: UUID, minutes: Int, tier: IntensityTier, wasPaused: Bool, at now: Date) {
        let context = active?.id == id ? active : nil
        let clean = !wasPaused && context?.paused != true
        if let context, let failed = lastHardcoreFailure,
           context.startedAt >= failed, context.startedAt.timeIntervalSince(failed) <= 60,
           minutes == 45 { trophies.insert("redemption arc") }
        if tier == .hardcore && minutes >= 25 && clean {
            let gap = context.flatMap { session in lastStrictEnd.map { session.startedAt.timeIntervalSince($0) } }
            strictChain = gap.map { (0...300).contains($0) ? strictChain + 1 : 1 } ?? 1
            lastStrictEnd = now
            if strictChain >= 3 { trophies.insert("big man ting") }
        } else { strictChain = 0; lastStrictEnd = nil }
        let cal = Calendar.current
        let day = cal.startOfDay(for: now)
        let spoiledToday = [lastFailure, lastIntegrityEvent].compactMap { $0 }.contains { cal.isDate($0, inSameDayAs: now) }
        if !spoiledToday {
            if let last = cleanDays.last, !cal.isDate(last, inSameDayAs: day), cal.date(byAdding: .day, value: 1, to: last) != day { cleanDays = [] }
            if cleanDays.last != day { cleanDays.append(day) }
            cleanDays = Array(cleanDays.suffix(7))
            if cleanDays.count == 7 { trophies.insert("immaculate Aura") }
        }
        if tier != .zen && minutes >= 60 && clean {trophies.insert("locked in")}
        if context?.overclock == true && minutes >= 60 && clean {trophies.insert("built different")}
        if (context?.parkedThoughts ?? 0) >= 3 && minutes >= 25 && clean {trophies.insert("side quest denied")}
        active = nil
    }
}
extension FocusJourney {
    var spendableXP: Int { max(0, totalXP - game.spent) }
    var playerRank: String { PlayerRank(xp:spendableXP).title }
    var rankSymbol: String { PlayerRank(xp:spendableXP).symbol }
    @discardableResult mutating func purchase(_ item: FocusItem, at now: Date = Date()) -> Bool {
        guard testingUnlocked || spendableXP >= item.cost, item != .alibi || !game.alibis.contains(where: { $0.end > now }) else { return false }
        if !testingUnlocked {game.spent += item.cost}
        if item == .alibi { game.alibis.append(AlibiWindow(start: now, end: now.addingTimeInterval(86400))) }
        else { game.inventory[item.rawValue, default: 0] += 1; game.equipped.insert(item) }
        return true
    }
}
@MainActor extension FocusModel {
    var overclockPending: Bool { journey.game.equipped.contains(.overclock) && journey.game.count(.overclock) > 0 }
    var isOverclock: Bool { journey.game.active?.id == sessionID && journey.game.active?.overclock == true }
    func buyItem(_ item: FocusItem) {
        guard !hasProgress, recoverySnapshot == nil, !recoveryChecking else { message = "Visit the shop between sessions."; return }
        if journey.purchase(item) { if overclockPending { selectedTier = .hardcore }; saveJourney(); resetIfIdle(); message = item == .alibi ? "Alibi active for 24 hours." : "\(item.title) ready for your next eligible session." }
        else { message = "Not enough XP, or an Alibi is already active." }
    }
    func equipItem(_ item: FocusItem) {
        guard !hasProgress, recoverySnapshot == nil, journey.game.count(item) > 0 else { return }
        if journey.game.equipped.contains(item) { journey.game.equipped.remove(item) } else { journey.game.equipped.insert(item) }
        if overclockPending { selectedTier = .hardcore }
        saveJourney(); resetIfIdle()
    }
}

@MainActor func focusGameTest() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var journey = FocusJourney()
    journey.award(session: UUID(), archetype: .providence, minutes: 6000, at: now)
    precondition(journey.playerRank == "Big Man")
    precondition(journey.purchase(.shield, at: now) && journey.spendableXP == 5500)
    precondition(journey.purchase(.overclock, at: now) && journey.spendableXP == 4500 && journey.playerRank == "Big bro")
    precondition(journey.purchase(.alibi, at: now) && !journey.purchase(.alibi, at: now))
    precondition(journey.totalXP == 6000 && journey.spendableXP == 2500)
    let saved = try JSONDecoder().decode(FocusJourney.self, from: JSONEncoder().encode(journey))
    precondition(saved.game.spent == 3500 && saved.game.count(.shield) == 1 && saved.game.equipped.contains(.overclock))
    var poor = FocusJourney(); precondition(!poor.purchase(.shield))
    var game = FocusGame()
    game.alibis = [AlibiWindow(start: now, end: now.addingTimeInterval(86400))]
    precondition(game.coversAbsence(from: now, to: now.addingTimeInterval(2*86400)))
    precondition(!game.coversAbsence(from: now, to: now.addingTimeInterval(3*86400)))
    var rebound = FocusJourney()
    rebound.endEarly(session: UUID(), archetype: .systemBuilding, tier: .hardcore, at: now)
    let id = UUID(); rebound.game.begin(id: id, tier: .hardcore, at: now.addingTimeInterval(60))
    rebound.award(session: id, archetype: .systemBuilding, minutes: 45, at: now.addingTimeInterval(2760), tier: .hardcore)
    precondition(rebound.game.trophies.contains("redemption arc"))
    var late = FocusJourney()
    late.endEarly(session: UUID(), archetype: .systemBuilding, tier: .hardcore, at: now)
    let lateID = UUID(); late.game.begin(id: lateID, tier: .hardcore, at: now.addingTimeInterval(60.1))
    late.award(session: lateID, archetype: .systemBuilding, minutes: 45, at: now.addingTimeInterval(2761), tier: .hardcore)
    precondition(!late.game.trophies.contains("redemption arc"))
    var chain = FocusJourney()
    for i in 0..<3 {
        let id = UUID(), start = now.addingTimeInterval(Double(i)*1600)
        chain.game.begin(id: id, tier: .hardcore, at: start)
        chain.award(session: id, archetype: .systemBuilding, minutes: 25, at: start.addingTimeInterval(1500), tier: .hardcore)
    }
    precondition(chain.game.trophies.contains("big man ting"))
    var aura = FocusJourney()
    for i in 0..<7 { aura.award(session: UUID(), archetype: .providence, minutes: 25, at: Calendar.current.date(byAdding: .day, value: i, to: now)!) }
    precondition(aura.game.trophies.contains("immaculate Aura"))
    var broken = FocusJourney()
    for i in 0..<7 {
        let day = Calendar.current.date(byAdding: .day, value: i, to: now)!
        if i == 3 { broken.endEarly(session: UUID(), archetype: .systemBuilding, tier: .ranked, at: day) }
        broken.award(session: UUID(), archetype: .providence, minutes: 25, at: day)
    }
    precondition(!broken.game.trophies.contains("immaculate Aura"))
    let model = FocusModel(recoveryEnabled: false)
    model.autoStart = false; model.tickEnabled = false; model.dingEnabled = false
    model.journey = FocusJourney(); model.journey.award(session: UUID(), archetype: .systemBuilding, minutes: 6000, at: Date())
    model.focusMinutes = 25; model.selectTier(.hardcore); model.mode = 0; model.reset()
    precondition(model.journey.purchase(.shield))
    model.toggle(engaged: true)
    precondition(model.journey.game.count(.shield) == 0)
    model.pause(); precondition(model.sessionMultiplier == 2 && !model.pauseBank.wasPaused && model.journey.game.active?.shieldShattered == true)
    model.toggle(); model.pause(); precondition(model.sessionMultiplier == 1 && model.pauseBank.wasPaused)
    model.endSession()
    precondition(model.journey.purchase(.overclock))
    model.toggle(engaged: true)
    precondition(model.isOverclock && model.clock.duration == 3600 && model.sessionMultiplier == 3 && model.journey.game.count(.overclock) == 0)
    let earnedBefore = model.journey.totalXP
    model.update(at: model.clock.deadline!.addingTimeInterval(1))
    precondition(model.journey.totalXP == earnedBefore + 180)
    let count = model.journey.records.count
    model.update(); precondition(model.journey.records.count == count)
    model.reset(); model.mode = 0; model.journey.game.inventory[FocusItem.overclock.rawValue] = 1; model.journey.game.equipped.insert(.overclock)
    model.toggle(engaged: true); let failures = model.journey.failures.count
    model.pause(); precondition(!model.hasProgress && model.journey.failures.count == failures+1 && model.journey.game.count(.overclock) == 0)
    let old = try JSONDecoder().decode(FocusJourney.self, from: Data(#"{"records":[]}"#.utf8))
    precondition(old.game.spent == 0 && old.game.trophies.isEmpty)
    print("PASS: wallet charges, rank thresholds/drop, insufficient funds, Alibi boundaries, inventory persistence, redemption 60s boundary, strict chain, seven clean days, shield first/second pauses, Overclock 60min/3x/no-pause failure, duplicate awards and migration.")
}
