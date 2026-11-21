import SwiftUI
import AppKit

struct IconRail: View {
    let icons: [String]
    let names: [String]
    @Binding var selection: Int
    let color: Color
    var badges: [Int] = []
    @Namespace private var marker
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 4) {
            ForEach(icons.indices, id: \.self) { index in
                Button {withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.8)) {selection=index}} label: {
                    Image(systemName: icons[index]).font(.system(size: 17, weight: .medium))
                        .foregroundStyle(selection == index ? color : .white.opacity(0.45))
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .overlay(alignment: .topTrailing) {
                            if index < badges.count, badges[index] > 0 {
                                Text("\(badges[index])").font(.system(size:10,weight:.semibold)).foregroundStyle(.black)
                                    .frame(width:16,height:16).background(color,in:Circle()).padding(4)
                            }
                        }
                        .background {
                            if selection == index {
                                Capsule().fill(.white.opacity(0.12))
                                    .overlay {Capsule().strokeBorder(.white.opacity(0.28),lineWidth:0.7)}
                                    .matchedGeometryEffect(id:"selection",in:marker)
                            }
                        }.contentShape(Capsule())
                }.help(names[index]).accessibilityLabel(names[index]).accessibilityValue(selection == index ? "Selected" : "")
            }
        }.padding(4).background(.white.opacity(0.045),in:Capsule())
    }
}

@MainActor final class SocialPanelModel: ObservableObject {
    @Published var tab = 0
    @Published var tier = 0
    @Published var preview = true
    @Published var addName = ""
    @Published var accepted: Set<String> = []
    @Published var incoming = ["Omer", "Frederick"]
    @Published var outgoing = ["Layla"]
    @Published var editingAccount = false
    var requests: Int {incoming.count + outgoing.count}
    func demoRows() -> [DemoPlayer] {
        let names = tab == 1 ? ["Harry", "Yusuf"] + accepted.sorted() : ["Mark", "Harry", "Omer", "Frederick", "Yusuf", "Layla", "Adam", "Daniel"]
        let unique = Array(Set(names)).sorted()
        return unique.enumerated().map {i,name in
            let score = [840, 3215, 5960, 1725, 7480, 625, 2980, 540][i % 8] + tier * (i + 1) * 73
            return DemoPlayer(handle:name,xp:score)
        }.sorted { $0.xp == $1.xp ? $0.handle < $1.handle : $0.xp > $1.xp }
    }
}
struct DemoPlayer: Identifiable {
    let handle:String
    let xp:Int
    var id:String {handle}
    var trophies:Set<String> {
        switch handle {
        case "Mark", "Frederick": return Set(FocusGame.trophyNames)
        case "Harry", "Omer": return ["big man ting"]
        case "Yusuf", "Layla": return ["redemption arc"]
        default: return []
        }
    }
}

struct SocialPanel: View {
    @ObservedObject var state: SocialPanelModel
    @ObservedObject var online: OnlineStore
    let motion: SurfaceMotion
    let journey: FocusJourney
    let openRanks: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var color: Color {IntensityTier.allCases[state.tier].color}
    var body: some View {
        VStack(spacing:16) {
            HStack {
                Label(state.preview ? "Preview" : "Online",systemImage:state.preview ? "eye" : "network")
                    .font(.system(size:11,weight:.medium)).foregroundStyle(.secondary)
                Spacer()
                Button {state.preview.toggle()} label:{Image(systemName:state.preview ? "network" : "eye")}
                    .help(state.preview ? "Open real leaderboard" : "Show sample players").accessibilityLabel(state.preview ? "Open real leaderboard" : "Show sample players")
                if !state.preview && online.signedIn {
                    Button {state.editingAccount.toggle()} label:{Image(systemName:"person.crop.circle")}.help("Account").accessibilityLabel("Account")
                }
            }
            if !state.preview && !online.signedIn {
                OnlineJoinView(online:online,accent:color,motion:motion)
            } else {
                IconRail(icons:["globe.americas.fill","person.2.fill","tray.full.fill"],names:["Global","Friends","Requests"],selection:$state.tab,color:color,badges:[0,0,state.preview ? state.requests : online.friends.filter{!$0.accepted}.count])
                if state.tab != 2 {
                    if state.preview {
                        IconRail(icons:["leaf.fill","chevron.up.2","flame.fill"],names:["Zen","Ranked","Hardcore"],selection:$state.tier,color:color)
                    } else {
                        HStack {Label("All tiers",systemImage:"square.stack.3d.up");Spacer();Button {Task {await online.reload()}} label:{Image(systemName:"arrow.clockwise")}.help("Refresh scores").accessibilityLabel("Refresh scores")}.font(.system(size:11)).foregroundStyle(.secondary)
                    }
                    standings
                } else {requests}
                if state.editingAccount && !state.preview {
                    HStack {
                        TextField("Player name",text:$online.handle).textFieldStyle(.roundedBorder)
                        Button {online.saveProfile()} label:{Image(systemName:"checkmark")}.help("Save player name")
                        Button {online.confirmSignOut=true} label:{Image(systemName:"rectangle.portrait.and.arrow.right")}.help("Sign out")
                    }
                }
                if !state.preview, let status=online.status {Text(status).font(.system(size:11)).foregroundStyle(.secondary)}
            }
        }.buttonStyle(SharedPressStyle(motion:motion)).tint(color)
            .animation(reduceMotion ? nil : .spring(response:0.4,dampingFraction:0.82),value:state.tab)
            .animation(reduceMotion ? nil : .spring(response:0.4,dampingFraction:0.82),value:state.tier)
            .onChange(of:state.tab) {_,tab in
                guard !state.preview else {return}; online.friendScope=tab == 1; Task {await online.reload()}
            }
            .onChange(of:state.preview) {_,preview in
                guard !preview else {return}; online.friendScope=state.tab == 1; Task {await online.reload()}
            }
            .alert("Leave this account?",isPresented:$online.confirmSignOut) {
                Button("Cancel",role:.cancel) {}
                Button("Sign out",role:.destructive) {online.signOut()}
            } message:{Text("Guest accounts cannot be recovered after signing out. Your local history stays on this Mac.")}
    }
    var standings: some View {
        VStack(spacing:16) {
            competitionPodium
            HStack {Text("Standings");Spacer();Text("XP")}.font(.system(size:10,weight:.medium)).foregroundStyle(.secondary).padding(.horizontal,12)
            ScrollView {
                VStack(spacing:8) {
                    if state.preview {
                        ForEach(Array(state.demoRows().enumerated()),id:\.element.id) {rank,player in
                            row(rank:rank+1,name:player.handle,xp:player.xp,isMe:false,trophies:player.trophies)
                        }
                    } else {
                        ForEach(online.players) {player in row(rank:player.rank,name:player.handle,xp:player.xp,isMe:player.id == online.userID,trophies:player.id == online.userID ? journey.game.trophies : [])}
                        if online.players.isEmpty {Image(systemName:"flag.checkered").font(.system(size:32)).foregroundStyle(.secondary).padding(24);Text("Your first session starts the climb.").font(.system(size:12)).foregroundStyle(.secondary)}
                    }
                }.background(ScrollChrome())
            }.frame(height:180).scrollIndicators(.hidden)
            localProfile
        }
    }
    var podiumPlayers:[DemoPlayer] {
        state.preview ? Array(state.demoRows().prefix(3)) : online.players.prefix(3).map {DemoPlayer(handle:$0.handle,xp:$0.xp)}
    }
    var competitionPodium:some View {
        VStack(spacing:12) {
            HStack {
                Text(state.preview ? IntensityTier.allCases[state.tier].title : "Leaderboard").font(.system(size:16,weight:.semibold,design:.rounded))
                Spacer()
                Text(state.tab == 0 ? "Global" : "Friends").font(.system(size:11)).foregroundStyle(.secondary)
            }
            HStack(alignment:.bottom,spacing:6) {
                ForEach([1,0,2],id:\.self) {index in
                    if index < podiumPlayers.count {podiumSlot(podiumPlayers[index],place:index+1)}
                    else {Color.clear.frame(maxWidth:.infinity).frame(height:110).accessibilityHidden(true)}
                }
            }
            HStack(spacing:10) {
                Rectangle().fill(color.opacity(0.12)).frame(height:0.5)
                Image(systemName:"trophy").font(.system(size:11)).foregroundStyle(color.opacity(0.65))
                Rectangle().fill(color.opacity(0.12)).frame(height:0.5)
            }
        }.padding(16).background(.white.opacity(0.025),in:RoundedRectangle(cornerRadius:24))
            .overlay {RoundedRectangle(cornerRadius:24).strokeBorder(color.opacity(0.2),lineWidth:0.7)}
    }
    func podiumSlot(_ player:DemoPlayer,place:Int)->some View {
        VStack(spacing:5) {
            Group {
                if place == 1 {Image(systemName:"crown.fill").foregroundStyle(color)}
                else {Text(String(format:"%02d",place)).foregroundStyle(.secondary)}
            }.font(.system(size:10,weight:.semibold)).frame(height:16)
            RankEmblem(rank:PlayerRank(xp:player.xp),size:place == 1 ? 58 : 46)
            Text(player.handle).font(.system(size:12,weight:.semibold)).lineLimit(1)
            Text(PlayerRank(xp:player.xp).title).font(.system(size:9)).foregroundStyle(.secondary)
            Text(player.xp.formatted()).font(.system(size:14,weight:.semibold,design:.rounded)).monospacedDigit().padding(.top,3)
        }.frame(maxWidth:.infinity).padding(.vertical,8)
            .background(color.opacity(place == 1 ? 0.055 : 0),in:RoundedRectangle(cornerRadius:20))
    }
    func row(rank:Int,name:String,xp:Int,isMe:Bool,trophies:Set<String>)->some View {
        let badge=PlayerRank(xp:isMe ? journey.spendableXP : xp)
        return HStack(spacing:12) {
            Text(String(format:"%02d",rank)).font(.system(size:12,weight:.medium,design:.rounded)).monospacedDigit().foregroundStyle(.secondary).frame(width:20)
            RankEmblem(rank:badge,size:40)
            VStack(alignment:.leading,spacing:4) {
                HStack(spacing:4) {Text(name).font(.system(size:14,weight:.semibold)).lineLimit(1);if isMe {Image(systemName:"person.fill.checkmark").font(.system(size:9)).accessibilityLabel("You")}}
                HStack(spacing:6) {
                    Text(badge.title).font(.system(size:10,weight:.medium)).foregroundStyle(badge.color)
                    ForEach(Array(FocusGame.trophyNames.enumerated()).filter{trophies.contains($0.element)}.prefix(3),id:\.offset) {index,name in
                        Image(systemName:FocusGame.trophySymbols[index]).font(.system(size:10)).foregroundStyle(IntensityTier.hardcore.color).help(name).accessibilityLabel(name)
                    }
                }
            }
            Spacer(minLength:4)
            VStack(alignment:.trailing,spacing:2) {
                Text(xp.formatted()).font(.system(size:14,weight:.semibold,design:.rounded)).monospacedDigit()
                Text("XP").font(.system(size:9,weight:.medium)).foregroundStyle(.secondary)
            }
        }.padding(12).background(isMe ? color.opacity(0.08) : .white.opacity(0.025),in:RoundedRectangle(cornerRadius:16))
    }
    var localProfile:some View {
        Button(action:openRanks) {
            HStack(spacing:12) {
                RankEmblem(rank:PlayerRank(xp:journey.spendableXP),size:48)
                VStack(alignment:.leading,spacing:4) {
                    Text("You · \(journey.playerRank)").font(.system(size:14,weight:.semibold))
                    HStack(spacing:6) {
                        Text("On this Mac").font(.system(size:10)).foregroundStyle(.secondary)
                        ForEach(Array(FocusGame.trophyNames.enumerated()).filter{journey.game.trophies.contains($0.element)}.prefix(3),id:\.offset) {index,name in
                            Image(systemName:FocusGame.trophySymbols[index]).font(.system(size:10)).foregroundStyle(IntensityTier.hardcore.color).accessibilityLabel(name)
                        }
                    }
                }
                Spacer()
                VStack(alignment:.trailing,spacing:4) {Text("\(journey.spendableXP.formatted()) XP").font(.system(size:13,weight:.semibold,design:.rounded));Label("\(journey.game.trophies.count) / \(FocusGame.trophyNames.count)",systemImage:"rosette").font(.system(size:10)).foregroundStyle(.secondary)}
                Image(systemName:"chevron.right").font(.system(size:10)).foregroundStyle(.secondary)
            }.padding(16).background(.white.opacity(0.07),in:RoundedRectangle(cornerRadius:24))
                .overlay {RoundedRectangle(cornerRadius:24).strokeBorder(.white.opacity(0.18),lineWidth:0.7)}
        }.accessibilityLabel("Your rank, \(journey.playerRank), \(journey.spendableXP) XP, \(journey.game.trophies.count) badges. Open Ranks.")
    }
    var requests: some View {
        VStack(spacing:16) {
            HStack {
                Image(systemName:"person.badge.plus").foregroundStyle(color)
                TextField("Player name",text:state.preview ? $state.addName : $online.friendHandle).textFieldStyle(.plain)
                Button {
                    if state.preview {
                        let name=state.addName.trimmingCharacters(in:.whitespacesAndNewlines)
                        guard !name.isEmpty else {return}
                        if !state.outgoing.contains(name) {state.outgoing.append(name)};state.addName=""
                    } else {online.friend(online.friendHandle,action:"request")}
                } label:{Image(systemName:"arrow.up.circle.fill").font(.system(size:24))}.help("Send friend request").accessibilityLabel("Send friend request")
            }.padding(12).background(.white.opacity(0.06),in:RoundedRectangle(cornerRadius:16))
            ScrollView {
                VStack(spacing:12) {
                    if state.preview {
                        ForEach(state.incoming,id:\.self) {name in requestRow(name:name,incoming:true) {state.accepted.insert(name);state.incoming.removeAll{$0==name}} remove:{state.incoming.removeAll{$0==name}}}
                        ForEach(state.outgoing,id:\.self) {name in requestRow(name:name,incoming:false) {} remove:{state.outgoing.removeAll{$0==name}}}
                        if state.requests == 0 {emptyInbox}
                    } else {
                        ForEach(online.friends.filter{!$0.accepted}) {friend in requestRow(name:friend.handle,incoming:friend.incoming) {online.friend(friend.handle,action:"accept")} remove:{online.friend(friend.handle,action:"remove")}}
                        if online.friends.filter({!$0.accepted}).isEmpty {emptyInbox}
                    }
                }.background(ScrollChrome())
            }.frame(height:300).scrollIndicators(.hidden)
        }
    }
    var emptyInbox:some View {VStack(spacing:12) {Image(systemName:"tray").font(.system(size:32));Text("All caught up").font(.system(size:12))}.foregroundStyle(.secondary).padding(24)}
    func requestRow(name:String,incoming:Bool,accept:@escaping()->Void,remove:@escaping()->Void)->some View {
        HStack(spacing:12) {
            Image(systemName:incoming ? "arrow.down.left" : "arrow.up.right").foregroundStyle(color).accessibilityLabel(incoming ? "Incoming request" : "Sent request")
            Text(name).font(.system(size:14,weight:.medium));Spacer()
            if incoming {Button(action:accept) {Image(systemName:"checkmark.circle.fill").font(.system(size:24)).foregroundStyle(color)}.help("Accept \(name)").accessibilityLabel("Accept \(name)")}
            Button(action:remove) {Image(systemName:"xmark.circle").font(.system(size:20)).foregroundStyle(.secondary)}.help(incoming ? "Decline \(name)" : "Cancel request to \(name)").accessibilityLabel(incoming ? "Decline \(name)" : "Cancel request to \(name)")
        }.padding(16).background(.white.opacity(0.04),in:RoundedRectangle(cornerRadius:16))
    }
}

@MainActor final class JourneyPanelModel: ObservableObject {
    @Published var tab=0
    @Published var path=0
    @Published var historyPage=0
    @Published var taggingSession: UUID?
}
struct JourneyPanel: View {
    @ObservedObject var state:JourneyPanelModel
    let journey:FocusJourney
    let tagSession:(UUID,FocusArchetype)->Void
    let motion:SurfaceMotion
    let color:Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var days:[Date] {(0..<7).reversed().compactMap {Calendar.current.date(byAdding:.day,value:-$0,to:Calendar.current.startOfDay(for:Date()))}}
    var daily:[Int] {days.map {day in journey.records.filter{Calendar.current.isDate($0.completedAt,inSameDayAs:day)}.reduce(0){$0+$1.minutes}}}
    var body:some View {
        VStack(spacing:16) {
            IconRail(icons:["chart.bar.xaxis","clock.arrow.circlepath"],names:["Overview","Sessions"],selection:$state.tab,color:color)
            if state.tab == 0 {overview} else {sessions}
        }.buttonStyle(SharedPressStyle(motion:motion)).tint(color)
            .animation(reduceMotion ? nil : .spring(response:0.4,dampingFraction:0.82),value:state.tab)
            .animation(reduceMotion ? nil : .spring(response:0.4,dampingFraction:0.82),value:state.path)
    }
    var overview:some View {
        let totals=daily
        let dates=days
        return VStack(spacing:16) {
            HStack(alignment:.center) {
                VStack(alignment:.leading,spacing:4) {
                    Label("Today",systemImage:"sun.max").font(.system(size:11)).foregroundStyle(.secondary)
                    HStack(alignment:.firstTextBaseline,spacing:4) {Text("\(totals.last ?? 0)").font(.system(size:40,weight:.light,design:.rounded)).monospacedDigit();Text("min").font(.system(size:12)).foregroundStyle(.secondary)}
                }
                Spacer()
                VStack(alignment:.trailing,spacing:12) {
                    Label("\(journey.currentStreak)",systemImage:"flame.fill").foregroundStyle(color).accessibilityLabel("\(journey.currentStreak) day streak")
                    Label("\(journey.totalXP.formatted())",systemImage:"sparkles").foregroundStyle(color).accessibilityLabel("\(journey.totalXP) total XP")
                }.font(.system(size:14,weight:.semibold,design:.rounded))
            }.padding(16).background(.white.opacity(0.05),in:RoundedRectangle(cornerRadius:24))
            HStack(alignment:.bottom,spacing:12) {
                ForEach(Array(dates.enumerated()),id:\.offset) {i,day in
                    VStack(spacing:8) {
                        RoundedRectangle(cornerRadius:4).fill(color.opacity(totals[i] == 0 ? 0.12 : 0.8))
                            .frame(height:max(4,64*CGFloat(totals[i])/CGFloat(max(1,totals.max() ?? 1))))
                        Text(day.formatted(.dateTime.weekday(.narrow))).font(.system(size:10)).foregroundStyle(.secondary)
                    }.frame(maxWidth:.infinity).help("\(day.formatted(date:.abbreviated,time:.omitted)): \(totals[i]) minutes")
                        .accessibilityLabel("\(day.formatted(date:.abbreviated,time:.omitted)), \(totals[i]) minutes")
                }
            }.frame(height:88,alignment:.bottom).padding(.horizontal,8)
            IconRail(icons:FocusPillar.allCases.map(\.symbol),names:FocusPillar.allCases.map(\.title),selection:$state.path,color:color)
            let path=FocusPillar.allCases[state.path]
            let progress=journey.pillarProgress(for:path)
            HStack(spacing:16) {
                ZStack {
                    Circle().stroke(.white.opacity(0.08),lineWidth:4)
                    Circle().trim(from:0,to:CGFloat(progress.xp % 100)/100).stroke(color,style:StrokeStyle(lineWidth:4,lineCap:.round)).rotationEffect(.degrees(-90))
                    VStack(spacing:2) {Text("\(progress.level)").font(.system(size:24,weight:.medium,design:.rounded));Text("LEVEL").font(.system(size:8,weight:.semibold)).foregroundStyle(.secondary)}
                }.frame(width:72,height:72)
                VStack(alignment:.leading,spacing:8) {
                    Text(path.title).font(.system(size:14,weight:.semibold)).fixedSize(horizontal:false,vertical:true)
                    Text(journey.playerRank).font(.system(size:11)).foregroundStyle(color)
                    Text("\(progress.xp % 100) / 100 XP").font(.system(size:11)).monospacedDigit().foregroundStyle(.secondary)
                }
                Spacer(minLength:0)
            }.padding(16).background(.white.opacity(0.04),in:RoundedRectangle(cornerRadius:24))
        }
    }
    var sessions:some View {
        let history=Array(journey.records.reversed())
        let pages=max(1,(history.count+3)/4)
        let page=min(state.historyPage,pages-1)
        return VStack(spacing:12) {
            if history.isEmpty {
                VStack(spacing:16) {Image(systemName:"clock.badge.checkmark").font(.system(size:40)).foregroundStyle(color);Text("Your first session starts here.").font(.system(size:14))}.frame(height:260)
            }
            ForEach(Array(history.dropFirst(page*4).prefix(4))) {record in
                VStack(spacing:12) {
                    HStack(spacing:12) {
                        Image(systemName:FocusPillar.containing(record.archetype).symbol).font(.system(size:20)).foregroundStyle(color).frame(width:32)
                        VStack(alignment:.leading,spacing:4) {
                            Text(FocusPillar.containing(record.archetype).title).font(.system(size:12,weight:.medium)).lineLimit(1)
                            Text(record.completedAt.formatted(date:.abbreviated,time:.shortened)).font(.system(size:10)).foregroundStyle(.secondary)
                            if let tag=record.achievementTag {Text(tag.title).font(.system(size:10)).foregroundStyle(color).lineLimit(1)}
                        }
                        Spacer(minLength:4)
                        VStack(alignment:.trailing,spacing:4) {
                            Text("+\(record.earnedXP ?? record.minutes)").font(.system(size:16,weight:.medium,design:.rounded)).foregroundStyle(color)
                            Text("\(record.minutes) min").font(.system(size:10)).foregroundStyle(.secondary)
                        }
                        Button {
                            withAnimation(reduceMotion ? nil : .spring(response:0.4,dampingFraction:0.82)) {state.taggingSession = state.taggingSession == record.id ? nil : record.id}
                        } label: {
                            Image(systemName:record.achievementTag == nil ? "tag" : "tag.fill").font(.system(size:14)).foregroundStyle(record.achievementTag == nil ? .white.opacity(0.45) : color).frame(width:28,height:32)
                        }.help("Achievement tag").accessibilityLabel("Edit achievement tag for \(FocusPillar.containing(record.archetype).title) session, \(record.completedAt.formatted(date:.abbreviated,time:.shortened))")
                    }
                    if state.taggingSession == record.id {
                        VStack(spacing:8) {
                            HStack(spacing:8) {
                                ForEach(FocusArchetype.allCases) {tag in
                                    Button {tagSession(record.id,tag)} label: {
                                        Image(systemName:tag.symbol).font(.system(size:16)).foregroundStyle(record.achievementTag == tag ? color : .white.opacity(0.4)).frame(maxWidth:.infinity).frame(height:32)
                                            .background(record.achievementTag == tag ? color.opacity(0.12) : .clear,in:RoundedRectangle(cornerRadius:10))
                                    }.help(tag.title).accessibilityLabel("Tag completed session: \(tag.title)").accessibilityValue(record.achievementTag == tag ? "Selected" : "")
                                }
                            }
                            Text(record.achievementTag?.title ?? "Achievement tag · optional").font(.system(size:10)).foregroundStyle(.secondary)
                        }.transition(.opacity.combined(with:.scale(scale:0.98,anchor:.top)))
                    }
                }.padding(16).background(.white.opacity(0.04),in:RoundedRectangle(cornerRadius:16))
            }
            if pages > 1 {
                HStack {
                    Button {state.historyPage=max(0,page-1)} label:{Image(systemName:"chevron.left")}.disabled(page==0).accessibilityLabel("Newer sessions")
                    Spacer();Text("\(page+1) / \(pages)").font(.system(size:11)).foregroundStyle(.secondary);Spacer()
                    Button {state.historyPage=min(pages-1,page+1)} label:{Image(systemName:"chevron.right")}.disabled(page==pages-1).accessibilityLabel("Older sessions")
                }.padding(12)
            }
        }
    }

}

// Keep trackpad/wheel scrolling without a persistent native scroll rail.
private struct ScrollChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { [weak view] in
            guard let scroll = view?.enclosingScrollView else { return }
            scroll.hasVerticalScroller = false
            scroll.hasHorizontalScroller = false
        }
    }
}
