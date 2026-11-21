import Foundation
@MainActor func upgrade537Test() throws {
    let now=Date(timeIntervalSince1970:1_800_000_000)
    func completed(_ tier:IntensityTier,_ minutes:Int,_ paused:Bool=false,_ thoughts:Int=0,_ overclock:Bool=false)->FocusGame {
        var g=FocusGame();let id=UUID()
        if overclock {g.inventory[FocusItem.overclock.rawValue]=1;g.equipped.insert(.overclock)}
        g.begin(id:id,tier:tier,at:now);g.active?.parkedThoughts=thoughts
        g.finish(id:id,minutes:minutes,tier:tier,wasPaused:paused,at:now.addingTimeInterval(Double(minutes*60)))
        return g
    }
    precondition(completed(.ranked,60).trophies.contains("locked in"))
    precondition(!completed(.zen,60).trophies.contains("locked in"))
    precondition(!completed(.ranked,59).trophies.contains("locked in"))
    precondition(!completed(.hardcore,60,true).trophies.contains("locked in"))
    precondition(completed(.hardcore,60,false,0,true).trophies.contains("built different"))
    precondition(!completed(.hardcore,60).trophies.contains("built different"))
    precondition(completed(.zen,25,false,3).trophies.contains("side quest denied"))
    precondition(!completed(.zen,25,false,2).trophies.contains("side quest denied"))
    precondition(!completed(.zen,25,true,3).trophies.contains("side quest denied"))
    var legacy=GameSession(id:UUID(),startedAt:now,overclock:false,shield:false)
    let encoded=try JSONEncoder().encode(legacy)
    var object=try JSONSerialization.jsonObject(with:encoded) as! [String:Any];object.removeValue(forKey:"parkedThoughts")
    legacy=try JSONDecoder().decode(GameSession.self,from:JSONSerialization.data(withJSONObject:object))
    precondition(legacy.parkedThoughts == nil)
    let m=FocusModel(recoveryEnabled:false);m.stopPulse();m.autoStart=false;m.clearAudioSelection();m.selectedTier = .zen;m.mode=0;m.reset();m.setDuration(25)
    for expected in [45,60,15,25] {m.cycleDuration();precondition(Int(m.clock.duration/60)==expected)}
    m.clock.start(at:now);let duration=m.clock.duration;m.cycleDuration();precondition(m.clock.duration==duration)
    m.clock.deadline=nil;m.reset();m.selectPillar(.ops);let spin=m.pillarSpin;m.selectPillar(.master);precondition(m.pillarSpin==spin+360);m.selectPillar(.master);precondition(m.pillarSpin==spin+360)
    m.stopPulse()
    precondition(FocusGame.trophyNames.count == FocusGame.trophySymbols.count && FocusGame.trophyNames.count == FocusGame.trophyDetails.count && FocusGame.trophyNames.count == FocusGame.trophyColors.count)
    print("PASS: duration cycling/active guard; one spin per pillar change; all three new badge success and exclusion cases; old active-session JSON decoding; badge artwork counts.")
}
