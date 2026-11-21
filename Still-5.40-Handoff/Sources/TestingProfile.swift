import Foundation

extension FocusJourney {
    static func testingProfile(at now: Date = Date()) -> FocusJourney {
        var profile = FocusJourney()
        profile.testingUnlocked = true
        let calendar = Calendar.current
        var index = 0
        for age in (0...23).reversed() where age != 10 && age != 11 {
            let day = calendar.date(byAdding:.day,value:-age,to:calendar.startOfDay(for:now))!
            for block in 0..<2 {
                let finish = calendar.date(byAdding:.minute,value:9*60+35+block*275+(age%3)*7,to:day)!
                guard finish < now else {continue}
                let pillar = FocusPillar.allCases[index%3]
                let minutes = [25,45,35,50,25,45,60][index%7]
                let id = UUID()
                profile.award(session:id,archetype:pillar.representative,minutes:minutes,at:finish,tier:pillar.defaultTier,wasPaused:index%13 == 0)
                profile.tag(session:id,track:pillar.tracks[(index/3)%pillar.tracks.count])
                index += 1
            }
        }
        profile.game.spent = 450
        profile.game.inventory = [FocusItem.shield.rawValue:3, FocusItem.overclock.rawValue:2]
        profile.game.equipped = []
        profile.game.trophies = Set(FocusGame.trophyNames)
        profile.game.cleanDays = (0..<7).reversed().compactMap { calendar.date(byAdding:.day,value:-$0,to:calendar.startOfDay(for:now)) }
        profile.failures = [FailureRecord(id:UUID(),archetype:.systemBuilding,date:now.addingTimeInterval(-20*86400))]
        return profile
    }
    var storageKey: String { testingUnlocked ? "focusJourney.testing.v1" : "focusJourney.v1" }
}
@MainActor extension FocusModel {
    func loadTestingProfileIfEnabled() {
        guard Bundle.main.bundleIdentifier == "com.still.focus" else {return}
        let defaults = UserDefaults.standard
        if defaults.object(forKey:"testingProfile.enabled") == nil { defaults.set(true,forKey:"testingProfile.enabled") }
        guard defaults.bool(forKey:"testingProfile.enabled") else {return}
        if let data=defaults.data(forKey:"focusJourney.testing.v1"), let saved=try? JSONDecoder().decode(FocusJourney.self,from:data) {journey=saved;journey.testingUnlocked=true}
        else {journey=FocusJourney.testingProfile()}
        journey.game.trophies.formUnion(FocusGame.trophyNames)
        saveJourney()
    }
    func useTestingProfile(_ enabled: Bool) {
        guard !hasProgress, !recoveryChecking, recoverySnapshot == nil else {return}
        saveJourney();clearHeartbeat()
        UserDefaults.standard.set(enabled,forKey:"testingProfile.enabled")
        let key=enabled ? "focusJourney.testing.v1" : "focusJourney.v1"
        if let data=UserDefaults.standard.data(forKey:key),let saved=try? JSONDecoder().decode(FocusJourney.self,from:data) {journey=saved}
        else {journey=enabled ? FocusJourney.testingProfile() : FocusJourney()}
        journey.testingUnlocked=enabled;if enabled {journey.game.trophies.formUnion(FocusGame.trophyNames)};saveJourney()
        if heartbeatStore != nil {
            let bundle=Bundle.main.bundleIdentifier ?? "com.still.focus"
            let url=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
                .appendingPathComponent("Still/Recovery/"+bundle+(enabled ? "/testing-heartbeat.json" : "/heartbeat.json"))
            heartbeatStore=TimerHeartbeatStore(url:url)
        }
        selectedArchetype=FocusPillar.ops.representative;selectedTier = .zen;reset()
    }
}

func testingProfileTest() throws {
    var profile=FocusJourney.testingProfile(at:Date(timeIntervalSince1970:1_800_000_000))
    precondition(profile.playerRank == "Big bro" && profile.testingUnlocked)
    precondition(profile.records.count > 30 && profile.game.trophies.count == FocusGame.trophyNames.count)
    for pillar in FocusPillar.allCases {
        let progress=profile.pillarProgress(for:pillar)
        precondition(progress.level > 1 && progress.xp % 100 > 0)
    }
    let wallet=profile.spendableXP
    for item in FocusItem.allCases {precondition(profile.purchase(item));precondition(profile.spendableXP == wallet)}
    precondition(profile.game.count(.shield)>0 && profile.game.count(.overclock)>0)
    let restored=try JSONDecoder().decode(FocusJourney.self,from:JSONEncoder().encode(profile))
    precondition(restored.testingUnlocked && restored.spendableXP == wallet && restored.game.trophies.count == FocusGame.trophyNames.count)
    let normal=try JSONDecoder().decode(FocusJourney.self,from:Data(#"{"records":[]}"#.utf8))
    precondition(!normal.testingUnlocked && normal.storageKey != profile.storageKey)
    print("PASS: believable Big bro profile, partial progress in all pillars, unlocked badges, free items without wallet loss, separate persistence, and normal-profile migration. Wallet: \(wallet) XP.")
}
