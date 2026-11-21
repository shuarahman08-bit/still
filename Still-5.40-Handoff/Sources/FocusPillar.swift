import SwiftUI

enum FocusPillar: String, CaseIterable, Identifiable {
    case ops, master, build
    var id:String {rawValue}
    var title:String {rawValue.capitalized}
    var symbol:String {self == .build ? "hammer.fill" : self == .master ? "book.fill" : "briefcase.fill"}
    var defaultTier:IntensityTier {self == .build ? .hardcore : self == .master ? .ranked : .zen}
    var representative:FocusArchetype {self == .build ? .systemBuilding : self == .master ? .skillMastery : .providence}
    var tracks:[FocusArchetype] {self == .build ? [.systemBuilding,.selfOvercoming] : self == .master ? [.skillMastery] : [.providence,.legacy]}
    var scope:String {self == .build ? "Code, design, writing and deep structural work." : self == .master ? "Documentation, tutorials and deliberate practice." : "Email, meetings, finance and operational documentation."}
    static func containing(_ track:FocusArchetype)->FocusPillar {allCases.first{$0.tracks.contains(track)}!}
}
extension FocusJourney {
    func pillarProgress(for pillar:FocusPillar)->ArchetypeProgress {
        let records=records.filter{pillar.tracks.contains($0.archetype)}
        let gross=records.reduce(0){$0+($1.earnedXP ?? $1.minutes)}
        let lost=pillar.tracks.reduce(0){$0+(deductions[$1.rawValue] ?? 0)}
        return ArchetypeProgress(xp:max(0,gross-lost),sessions:records.count)
    }
    func achievementXP(for tag:FocusArchetype)->Int {
        records.filter{($0.achievementTag ?? ($0.pillarSchema == nil ? $0.archetype : nil))==tag}.reduce(0){$0+($1.earnedXP ?? $1.minutes)}
    }
}
