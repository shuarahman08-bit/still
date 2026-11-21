import SwiftUI

@MainActor final class WalkthroughModel: ObservableObject {
    @Published var step = 0
    @Published var breakSelected = false
    @Published var playing = false
    @Published var path: FocusArchetype = .providence
    @Published var tier: IntensityTier = .zen
    @Published var thought = ""
    @Published var captured = false
    @Published var friends = false
    @Published var volume = 0.45
    @Published var muted = false
    @Published var edgeOpen = false
    @Published var rankXP = 2150
    func reset() {step=0;breakSelected=false;playing=false;path = .providence;tier = .zen;thought="";captured=false;friends=false;volume=0.45;muted=false;edgeOpen=false;rankXP=2150}
    let titles = ["Make room for focus", "Choose your work", "Choose your stakes", "Park it. Keep going.", "Make progress visible", "Sound, your way", "Open with intention", "Focus with friends"]
    var explanation: String {
        switch step {
        case 0: return "Start with 25 minutes of focus and a 5-minute break. Choose a duration beneath the countdown. During a session, Pause is the main action; End appears after pausing. These controls are practice only."
        case 1: return FocusPillar.containing(path).scope + " Ops defaults to Zen, Master to Ranked, and Build to Hardcore. Optional achievement tags belong in My Journey → Sessions after completion."
        case 2: return tier.detail + (tier == .zen ? ". Zen pauses freely." : ". Hold Engage for seven full seconds; releasing early resets the hold. A Combo Shield protects the first pause’s multiplier, but pause time still counts.")
        case 3: return "While focusing, type a thought and tap the save arrow, or tap the mic to record in place. Tap stop to save your voice note. Open Parking Lot to revisit notes. This practice thought stays in the guide."
        case 4: return "Completed focus minutes earn XP, with your mode’s multiplier. Each pillar levels separately. Your XP wallet determines NPC, Big bro (1,000), or Big Man (5,000). Ranks holds behavioral badges and consumables: Shield protects one pause, Overclock is 60 minutes at 3× with no pauses, and Alibi protects a 24-hour absence."
        case 5: return "The quiet home shortcut opens your music library. During focus, tap the speaker to mute, tap the name for a picker, and drag across the row for volume. Import or remove music in Manage audio. This sample slider makes no sound."
        case 6: return "Move to the very top edge at the centre of your screen to open Still. Hovering over the rest of the notch won’t trigger it. Click to keep it open; click outside or press Escape to dismiss. Full and Circular styles are in Settings. This example does not change your settings."
        default: return "The leaderboard has Global, Friends and Requests, plus sample players for previewing the interface. Your local profile opens Ranks. Testing progress stays on this Mac and is separate from your original profile; switch profiles in Settings."

        }
    }
}

struct WalkthroughView: View {
    @ObservedObject var demo: WalkthroughModel
    let accent: Color
    let motion: SurfaceMotion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 8) {
                ForEach(demo.titles.indices, id: \.self) { step in
                    Button { demo.step = step } label: {
                        Capsule().fill(step <= demo.step ? accent : .white.opacity(0.12)).frame(height: 4)
                            .frame(maxWidth: .infinity).padding(.vertical, 8).contentShape(Rectangle())
                    }.buttonStyle(SharedPressStyle(motion: motion)).accessibilityLabel("Guide step \(step + 1)")
                }
            }
            Text(demo.titles[demo.step]).font(.system(size: 24, weight: .semibold, design: .rounded))
            demoContent.frame(maxWidth: .infinity).frame(height: 180)
                .padding(16).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 24))
            Text(demo.explanation).font(.system(size: 14)).foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true).frame(minHeight: 96, alignment: .top)
            HStack {
                Button { demo.step = max(0, demo.step - 1) } label: {Image(systemName: "arrow.left").frame(width: 40, height: 40)}
                    .disabled(demo.step == 0).accessibilityLabel("Previous guide step")
                Spacer()
                Text("\(demo.step + 1) / \(demo.titles.count)").font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                Button { demo.step = demo.step == demo.titles.count-1 ? 0 : demo.step + 1 } label: {
                    Label(demo.step == demo.titles.count-1 ? "Replay" : "Next", systemImage: demo.step == demo.titles.count-1 ? "arrow.counterclockwise" : "arrow.right")
                        .font(.system(size: 14, weight: .semibold)).padding(12)
                        .foregroundStyle(.black).background(accent, in: Capsule())
                }
            }.buttonStyle(SharedPressStyle(motion: motion))
        }.tint(accent).buttonStyle(SharedPressStyle(motion:motion))
            .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8), value: demo.step)
    }
    @ViewBuilder var demoContent: some View {
        switch demo.step {
        case 0:
            VStack(spacing: 16) {
                Picker("Practice mode", selection: $demo.breakSelected) {Text("Focus").tag(false); Text("Break").tag(true)}.pickerStyle(.segmented)
                Text(demo.breakSelected ? "05:00" : demo.playing ? "24:59" : "25:00")
                    .font(.system(size: 48, weight: .medium, design: .rounded)).monospacedDigit()
                Button {demo.playing.toggle()} label: {Label(demo.playing ? "Pause practice" : "Try play", systemImage: demo.playing ? "pause.fill" : "play.fill")}.tint(accent)
            }
        case 1:
            VStack(spacing: 24) {
                HStack {ForEach(FocusPillar.allCases) {pillar in
                    let path=pillar.representative
                    Button {demo.path=path} label: {PillarGlyph(pillar:pillar,color:demo.path == path ? accent : .white.opacity(0.4),size:32).foregroundStyle(demo.path == path ? accent : .white.opacity(0.4)).frame(maxWidth:.infinity).frame(height:48)}.buttonStyle(SharedPressStyle(motion: motion)).accessibilityLabel(pillar.title)
                }}
                Text(FocusPillar.containing(demo.path).title).font(.system(size:16,weight:.semibold)).multilineTextAlignment(.center)
                ProgressView(value:25,total:100).tint(accent).accessibilityLabel("Example: 25 of 100 XP")
            }
        case 2:
            VStack(spacing:24) {
                HStack {ForEach(IntensityTier.allCases) {tier in
                    Button {demo.tier=tier} label: {VStack(spacing:8) {Image(systemName:tier == .zen ? "leaf.fill" : tier == .ranked ? "chevron.up.2" : "flame.fill").font(.system(size:24)); Text(tier.title).font(.system(size:12,weight:.semibold))}.frame(maxWidth:.infinity).padding(.vertical,16).foregroundStyle(demo.tier == tier ? tier.color : .white.opacity(0.4))}.buttonStyle(SharedPressStyle(motion: motion))
                }}
                Text(demo.tier == .hardcore ? "2× XP · 50% at stake" : demo.tier == .ranked ? "1.5× XP · 15% at stake" : "1× XP · No early-end penalty").font(.system(size:16,weight:.semibold)).foregroundStyle(demo.tier.color)
            }
        case 3:
            VStack(alignment:.leading,spacing:16) {
                Label("Parking Lot",systemImage:"square.and.pencil").font(.system(size:16,weight:.semibold))
                HStack {TextField("Try parking a thought…",text:$demo.thought).textFieldStyle(.roundedBorder); Button {demo.captured=true} label:{Image(systemName:"arrow.up.circle.fill").font(.system(size:24))}.disabled(demo.thought.trimmingCharacters(in:.whitespaces).isEmpty).accessibilityLabel("Save practice thought")}
                if demo.captured {Label("Parked. You can return to it later.",systemImage:"checkmark.circle.fill").font(.system(size:12)).foregroundStyle(accent)}
            }
        case 4:
            VStack(spacing:12) {
                RankEmblem(rank:PlayerRank(xp:demo.rankXP),size:80)
                Picker("Practice rank",selection:$demo.rankXP) {Text("NPC").tag(250);Text("Big bro").tag(2150);Text("Big Man").tag(5400)}.pickerStyle(.segmented)
                Text("\(demo.rankXP.formatted()) XP").font(.system(size:14,weight:.semibold,design:.rounded))
            }
        case 5:
            VStack(spacing:20) {
                HStack {
                    Button {demo.muted.toggle()} label: {Image(systemName:demo.muted ? "speaker.slash.fill" : "speaker.wave.2.fill").font(.system(size:24))}.accessibilityLabel("Toggle practice sound")
                    Text("Rain on the window").font(.system(size:14));Spacer()
                }
                Slider(value:$demo.volume,in:0...1).tint(accent).accessibilityLabel("Practice music volume")
                Text("\(Int(demo.volume*100))% · \(demo.muted ? "Muted" : "Sound on")").font(.system(size:12)).foregroundStyle(.secondary)
            }
        case 6:
            VStack(spacing:16) {
                Button {demo.edgeOpen.toggle()} label: {Capsule().fill(accent).frame(height:5).frame(maxWidth:.infinity).padding(.vertical,12).contentShape(Rectangle())}.accessibilityLabel("Try the top screen edge")
                Image(systemName:demo.edgeOpen ? "rectangle.expand.vertical" : "leaf.fill").font(.system(size:36)).foregroundStyle(accent)
                Text(demo.edgeOpen ? "Open · Escape or click outside to close" : "Tap the thin edge above to try").font(.system(size:12)).foregroundStyle(.secondary)
            }
        default:
            VStack(spacing:24) {
                Picker("Example leaderboard",selection:$demo.friends) {Text("Global").tag(false);Text("Friends").tag(true)}.pickerStyle(.segmented)
                Image(systemName:demo.friends ? "person.2.fill" : "trophy.fill").font(.system(size:48)).foregroundStyle(accent)
                Text("Complete → Earn XP → Climb").font(.system(size:14,weight:.semibold))
            }
        }
    }
}
