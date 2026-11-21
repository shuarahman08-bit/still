import SwiftUI

enum PlayerRank: Int, CaseIterable, Identifiable {
    case npc, bigBro, bigMan
    var id: Int { rawValue }
    init(xp: Int) { self = xp >= 5000 ? .bigMan : xp >= 1000 ? .bigBro : .npc }
    var title: String { ["NPC", "Big bro", "Big Man"][rawValue] }
    var threshold: Int { [0, 1000, 5000][rawValue] }
    var symbol: String { ["minus", "chevron.up.2", "crown.fill"][rawValue] }
    var color: Color { self == .npc ? .white.opacity(0.8) : self == .bigBro ? IntensityTier.ranked.color : IntensityTier.hardcore.color }
    var next: PlayerRank? { PlayerRank(rawValue: rawValue + 1) }
}

struct CrestShape: Shape {
    func path(in rect: CGRect) -> Path {
        let points: [CGPoint] = [CGPoint(x:0.5,y:0.02),CGPoint(x:0.9,y:0.23),CGPoint(x:0.87,y:0.7),CGPoint(x:0.5,y:0.98),CGPoint(x:0.13,y:0.7),CGPoint(x:0.1,y:0.23)]
        return Path { path in
            for (i,p) in points.enumerated() { let point=CGPoint(x:rect.minX+p.x*rect.width,y:rect.minY+p.y*rect.height); if i==0 {path.move(to:point)} else {path.addLine(to:point)} }
            path.closeSubpath()
        }
    }
}
struct RankEmblem:View {
    let rank:PlayerRank
    var size:CGFloat=72
    var metal:LinearGradient {LinearGradient(stops:[.init(color:.white.opacity(0.72),location:0),.init(color:rank.color.opacity(0.32),location:0.28),.init(color:.black.opacity(0.7),location:0.65),.init(color:rank.color.opacity(0.6),location:1)],startPoint:.topLeading,endPoint:.bottomTrailing)}
    var body:some View {
        ZStack {
            RankPlate(rank:rank).fill(LinearGradient(colors:[.white.opacity(0.16),rank.color.opacity(0.06),.black.opacity(0.55)],startPoint:.topLeading,endPoint:.bottomTrailing))
            RankPlate(rank:rank).stroke(metal,lineWidth:1.4)
            RankPlate(rank:rank).stroke(rank.color.opacity(0.2),lineWidth:size*0.035).scaleEffect(0.88)
            RankPlate(rank:rank).fill(.black.opacity(0.22)).scaleEffect(0.79)
            RankPlate(rank:rank).stroke(LinearGradient(colors:[.black.opacity(0.6),.white.opacity(0.18)],startPoint:.top,endPoint:.bottom),lineWidth:0.7).scaleEffect(0.79)
            if rank == .bigMan {Laurel().fill(rank.color.opacity(0.45))}
            VStack(spacing:size*0.08) {
                Group {
                    if rank == .npc {
                        VStack(spacing:size*0.035) {ForEach(0..<3) {i in Capsule().frame(width:size*(i == 2 ? 0.14 : 0.22),height:max(1,size*0.025))}}
                    } else if rank == .bigBro {RankChevron().frame(width:size*0.39,height:size*0.29)}
                    else {Image(systemName:"crown.fill").font(.system(size:size*0.28,weight:.medium))}
                }.frame(height:size*0.3)
                    .foregroundStyle(LinearGradient(colors:[.white.opacity(0.9),rank.color.opacity(0.9)],startPoint:.top,endPoint:.bottom))
                HStack(spacing:size*0.04) {ForEach(0...rank.rawValue,id:\.self) {_ in Circle().fill(rank.color.opacity(0.75)).frame(width:size*0.025,height:size*0.025)}}
            }.offset(y:size*0.02)
        }.frame(width:size,height:size).shadow(color:.black.opacity(0.3),radius:3,y:2).accessibilityLabel(rank.title)
    }
}
struct TrophyEmblem:View {
    let index:Int
    var unlocked:Bool
    var size:CGFloat=64
    var tint:Color {FocusGame.trophyColors[index].opacity(unlocked ? 1 : 0.4)}
    var body:some View {
        ZStack {
            AchievementPlate(index:index).fill(LinearGradient(colors:[.white.opacity(0.13),tint.opacity(0.06),.black.opacity(0.45)],startPoint:.topLeading,endPoint:.bottomTrailing))
            AchievementPlate(index:index).stroke(LinearGradient(colors:[.white.opacity(0.65),tint.opacity(0.2),tint.opacity(0.7)],startPoint:.topLeading,endPoint:.bottomTrailing),lineWidth:1.1)
            AchievementPlate(index:index).stroke(tint.opacity(0.25),lineWidth:size*0.025).scaleEffect(0.87)
            AchievementPlate(index:index).fill(.black.opacity(0.2)).scaleEffect(0.77)
            Image(systemName:FocusGame.trophySymbols[index]).font(.system(size:size*0.32,weight:.medium))
                .foregroundStyle(LinearGradient(colors:[.white.opacity(unlocked ? 0.9 : 0.25),tint],startPoint:.top,endPoint:.bottom))
                .shadow(color:.black.opacity(0.4),radius:0,y:1)
        }.frame(width:size,height:size)
            .overlay(alignment:.bottomTrailing) {
                Image(systemName:unlocked ? "checkmark" : "lock.fill").font(.system(size:size*0.1,weight:.bold)).foregroundStyle(tint)
                    .frame(width:size*0.22,height:size*0.22).background(Color.black.opacity(0.8),in:Circle())
                    .overlay {Circle().strokeBorder(tint.opacity(0.3),lineWidth:0.5)}.offset(x:-size*0.03,y:-size*0.03)
            }.accessibilityLabel(FocusGame.trophyNames[index])
    }
}
@MainActor final class RankPanelModel: ObservableObject {
    @Published var inspectedRank: PlayerRank?
    @Published var tab = 0
    @Published var item: FocusItem = .shield
    @Published var trophy = 0
}
struct RankPanel: View {
    @ObservedObject var state: RankPanelModel
    let journey: FocusJourney
    let enabled: Bool
    let buy: (FocusItem) -> Void
    let equip: (FocusItem) -> Void
    let motion: SurfaceMotion
    let openJourney: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var rank: PlayerRank {PlayerRank(xp:journey.spendableXP)}
    var body: some View {
        VStack(spacing:16) {
            HStack {
                Label("\(journey.spendableXP.formatted()) XP",systemImage:"sparkles").font(.system(size:14,weight:.semibold,design:.rounded)).foregroundStyle(rank.color)
                Spacer()
                Button(action:openJourney) {Image(systemName:"chart.bar.xaxis").frame(width:32,height:32)}.help("My Journey").accessibilityLabel("My Journey")
            }
            IconRail(icons:["shield.lefthalf.filled","rosette","bag"],names:["Ranks","Badges","XP Shop"],selection:$state.tab,color:rank.color)
            if state.tab == 0 {ranks} else if state.tab == 1 {badges} else {shop}
        }.buttonStyle(SharedPressStyle(motion:motion)).tint(rank.color)
            .animation(reduceMotion ? nil : .spring(response:0.4,dampingFraction:0.8),value:state.tab)
            .animation(reduceMotion ? nil : .spring(response:0.4,dampingFraction:0.8),value:state.item)
            .animation(reduceMotion ? nil : .spring(response:0.4,dampingFraction:0.8),value:state.trophy)
    }
    var ranks: some View {
        let inspected=state.inspectedRank ?? rank
        return VStack(spacing:16) {
            RankHeroCard(inspected:inspected,current:rank,xp:journey.spendableXP)
            HStack(spacing:8) {
                ForEach(PlayerRank.allCases) {tier in
                    Button {state.inspectedRank=tier} label: {
                        VStack(spacing:7) {
                            HStack {Text(["I","II","III"][tier.rawValue]).font(.system(size:8,weight:.semibold)).tracking(1);Spacer();if tier == inspected {Circle().frame(width:4,height:4)}}.foregroundStyle(tier.color.opacity(0.7))
                            RankEmblem(rank:tier,size:58)
                            Text(tier.title).font(.system(size:11,weight:.semibold)).foregroundStyle(.white.opacity(0.85))
                        }.frame(maxWidth:.infinity).padding(12)
                            .background(LinearGradient(colors:[tier.color.opacity(tier == inspected ? 0.12 : 0.025),.black.opacity(0.24)],startPoint:.top,endPoint:.bottom),in:RoundedRectangle(cornerRadius:18))
                            .overlay {RoundedRectangle(cornerRadius:18).strokeBorder(tier == inspected ? tier.color.opacity(0.6) : .white.opacity(0.065),lineWidth:0.7)}
                            .overlay(alignment:.bottom) {Capsule().fill(tier.color.opacity(tier == inspected ? 0.8 : 0.12)).frame(height:2).padding(.horizontal,22).padding(.bottom,1)}
                    }.accessibilityLabel("Inspect \(tier.title)").accessibilityAddTraits(tier == inspected ? .isSelected : [])
                }
            }
            HStack {Label("\(journey.game.trophies.count) / \(FocusGame.trophyNames.count)",systemImage:"rosette");Spacer();Label("\(journey.game.inventory.values.reduce(0,+))",systemImage:"bag")}.font(.system(size:12,weight:.medium)).foregroundStyle(.secondary).padding(.horizontal,8)
        }.animation(reduceMotion ? nil : .spring(response:0.4,dampingFraction:0.82),value:state.inspectedRank)
    }
    var badges: some View {
        VStack(spacing:16) {
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:8),count:3),spacing:8) {
                ForEach(FocusGame.trophyNames.indices,id:\.self) {index in
                    Button {state.trophy=index} label: {
                        VStack(spacing:8) {
                            TrophyEmblem(index:index,unlocked:journey.game.trophies.contains(FocusGame.trophyNames[index]),size:56)
                            Text(FocusGame.trophyNames[index]).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.85)
                        }.frame(maxWidth:.infinity).padding(.vertical,12)
                            .background(FocusGame.trophyColors[index].opacity(state.trophy == index ? 0.06 : 0.02),in:RoundedRectangle(cornerRadius:20))
                            .overlay {RoundedRectangle(cornerRadius:20).strokeBorder(state.trophy == index ? FocusGame.trophyColors[index].opacity(0.4) : .clear,lineWidth:0.7)}
                    }.accessibilityLabel(FocusGame.trophyNames[index]).help(FocusGame.trophyNames[index])
                }
            }
            VStack(spacing:16) {
                let unlocked=journey.game.trophies.contains(FocusGame.trophyNames[state.trophy])
                TrophyEmblem(index:state.trophy,unlocked:unlocked,size:88)
                Text(FocusGame.trophyNames[state.trophy]).font(.system(size:22,weight:.semibold,design:.rounded))
                Text(FocusGame.trophyDetails[state.trophy]).font(.system(size:12)).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
                Label(unlocked ? "Earned" : badgeProgress,systemImage:unlocked ? "checkmark.seal.fill" : "lock.fill").font(.system(size:12,weight:.medium)).foregroundStyle(unlocked ? FocusGame.trophyColors[state.trophy] : .white.opacity(0.5))
            }.padding(24).frame(maxWidth:.infinity).background {RankChamberSurface(tint:FocusGame.trophyColors[state.trophy])}
            if !journey.failures.isEmpty {Label("\(journey.failures.count) failure records",systemImage:"flame").font(.system(size:11)).foregroundStyle(.secondary)}
        }
    }
    var badgeProgress:String {
        switch state.trophy {
        case 0:return "Recover after a Hardcore failure"
        case 1:return "\(journey.game.strictChain) / 3 unbroken blocks"
        case 2:return "\(journey.game.cleanDays.count) / 7 clean focus days"
        case 3:return "60 minutes, no pauses"
        case 4:return "Complete an Overclock"
        default:return "Park 3 thoughts, finish without pausing"
        }
    }
    var shop: some View {
        VStack(spacing:16) {
            HStack(spacing:8) {
                ForEach(FocusItem.allCases) {item in
                    Button {state.item=item} label: {
                        VStack(spacing:8) {
                            itemArt(item,size:48)
                            Text(item == .shield ? "Shield" : item == .overclock ? "Overclock" : "Alibi").font(.system(size:11,weight:.medium))
                            Text(journey.testingUnlocked ? (item == .alibi ? "Ready" : "\(journey.game.count(item)) ready") : "\(item.cost.formatted()) XP").font(.system(size:10)).foregroundStyle(.secondary)
                        }.frame(maxWidth:.infinity).padding(.vertical,16)
                            .background(.white.opacity(state.item == item ? 0.09 : 0.025),in:RoundedRectangle(cornerRadius:24))
                            .overlay {RoundedRectangle(cornerRadius:24).strokeBorder(state.item == item ? item.displayColor.opacity(0.4) : .clear,lineWidth:0.7)}
                    }.accessibilityLabel(item.title).help(item.title)
                }
            }
            selectedItem
            Text(enabled ? "Buy equips your next eligible session. Tap the checkmark to unequip." : "Shop opens between sessions.").font(.system(size:11)).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
        }
    }
    var selectedItem: some View {
        let item=state.item
        let activeAlibi=item == .alibi && journey.game.alibis.contains{$0.end > Date()}
        let shortfall=journey.testingUnlocked ? 0 : max(0,item.cost-journey.spendableXP)
        return VStack(spacing:16) {
            itemArt(item,size:88)
            HStack {
                Text(item.title).font(.system(size:20,weight:.semibold,design:.rounded))
                Spacer()
                if item != .alibi, journey.game.count(item)>0 {
                    Button {equip(item)} label: {Label("\(journey.game.count(item))",systemImage:journey.game.equipped.contains(item) ? "checkmark.circle.fill" : "circle")}.disabled(!enabled).accessibilityLabel("Toggle \(item.title) equipped, \(journey.game.count(item)) owned")
                }
            }
            Text(item.detail).font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            if activeAlibi, let until=journey.game.alibis.last?.end {Label("Protected until \(until.formatted(date:.abbreviated,time:.shortened))",systemImage:"checkmark.shield").font(.system(size:11))}
            Button {buy(item)} label: {
                HStack {Image(systemName:activeAlibi ? "checkmark.shield.fill" : shortfall > 0 ? "lock.fill" : "plus");Text(activeAlibi ? "Alibi active" : journey.testingUnlocked ? (item == .alibi ? "Use Alibi" : "Equip") : "\(item.cost.formatted()) XP");Spacer();if shortfall>0 {Text("\(shortfall.formatted()) to go").font(.system(size:11))}}
                    .font(.system(size:14,weight:.semibold)).padding(16).frame(maxWidth:.infinity)
                    .foregroundStyle(item.displayColor)
                    .background(item.displayColor.opacity(shortfall>0 ? 0.08 : 0.2),in:RoundedRectangle(cornerRadius:16))
            }.disabled(!enabled || shortfall>0 || activeAlibi).accessibilityLabel(journey.testingUnlocked ? "Equip \(item.title)" : "Buy \(item.title) for \(item.cost) XP")
        }.padding(24).background {RankChamberSurface(tint:item.displayColor)}
    }
    func itemArt(_ item:FocusItem,size:CGFloat)->some View {
        ItemEmblem(item:item,size:size)
    }
}

extension FocusItem {
    var displayColor: Color {self == .shield ? IntensityTier.ranked.color : self == .overclock ? IntensityTier.hardcore.color : Color(red:0.73,green:0.8,blue:0.95)}
}
struct ItemEmblem: View {
    let item: FocusItem
    let size: CGFloat
    var metal: LinearGradient {LinearGradient(colors:[.white.opacity(0.85),item.displayColor.opacity(0.15),item.displayColor.opacity(0.9)],startPoint:.topLeading,endPoint:.bottomTrailing)}
    var body: some View {
        ZStack {
            if item == .shield {
                CrestShape().fill(item.displayColor.opacity(0.12))
                CrestShape().stroke(metal,lineWidth:1.5)
                CrestShape().stroke(item.displayColor.opacity(0.3),lineWidth:1).padding(size*0.1)
                Image(systemName:"shield.lefthalf.filled").font(.system(size:size*0.36,weight:.medium)).foregroundStyle(item.displayColor)
            } else if item == .overclock {
                ZStack {
                    RoundedRectangle(cornerRadius:size*0.12).fill(.black.opacity(0.25))
                    RoundedRectangle(cornerRadius:size*0.12).fill(item.displayColor.opacity(0.3)).frame(height:size*0.4).frame(maxHeight:.infinity,alignment:.bottom)
                    RoundedRectangle(cornerRadius:size*0.12).stroke(metal,lineWidth:1.5)
                    Image(systemName:"bolt.fill").font(.system(size:size*0.32,weight:.semibold)).foregroundStyle(item.displayColor)
                    Capsule().fill(metal).frame(width:size*0.32,height:size*0.09).offset(y:-size*0.39)
                    HStack(spacing:size*0.04) {ForEach(0..<3) {_ in Capsule().fill(item.displayColor.opacity(0.7)).frame(width:size*0.035,height:size*0.1)}}.offset(y:size*0.24)
                }.frame(width:size*0.48,height:size*0.74).rotationEffect(.degrees(12))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius:size*0.1).fill(item.displayColor.opacity(0.1))
                    RoundedRectangle(cornerRadius:size*0.1).stroke(metal,lineWidth:1.5)
                    HStack(spacing:size*0.12) {
                        Image(systemName:"moon.zzz.fill").font(.system(size:size*0.24,weight:.medium))
                        Rectangle().fill(item.displayColor.opacity(0.3)).frame(width:1,height:size*0.3)
                        Text("24h").font(.system(size:size*0.15,weight:.semibold,design:.rounded))
                    }.foregroundStyle(item.displayColor)
                }.frame(width:size*0.9,height:size*0.6).rotationEffect(.degrees(-8))
            }
        }.frame(width:size,height:size).shadow(color:item.displayColor.opacity(0.15),radius:8,y:4).accessibilityHidden(true)
    }
}
