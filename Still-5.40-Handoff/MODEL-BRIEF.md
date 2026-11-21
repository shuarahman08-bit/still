# Still 5.40 model handoff

Continue work on Still, a native SwiftUI and AppKit notch timer for Apple silicon Macs. Use the supplied Swift files as the implementation baseline. Open the bundled HTML and PNGs for design context. The HTML is a browser reference. The Swift app is the source of truth for behavior and macOS visuals.

Build on macOS with Xcode Command Line Tools using `./build.sh`. Open `build/Still.app`. The build uses a separate bundle identifier to isolate preferences. Use your own Supabase project if explicitly adding online functionality. This package uses placeholder connection settings and retains sample leaderboard data.

## Product and design

- Keep the full notch default, optional circular notch, screen edge hover, and click to hold open.
- Keep the large countdown first. On setup, click it to cycle focus durations of 15, 25, 45, and 60 minutes. Keep Focus and Break separate.
- During a session, keep Pause compact, the music row small, and Parking Lot easy to see and use. Preserve typed capture, the mic, mute, track selection, and drag volume.
- Focus Archetypes uses Ops, Master, and Build with Zen, Ranked, and Hardcore intensity. Keep the short spin on pillar selection and the temporary tier glow.
- Ranks uses distinct crest chambers for NPC, Big bro, and Big Man, selectable rank previews, segmented XP, and matching badge and shop treatments. Keep the Global and Friends podium and standings.
- Preserve session, XP, pause bank, badge, and recovery rules already in the code. Keep decorative effects static or triggered by interaction and respect Reduce Motion.

## Where to work

- Still.swift handles app lifecycle, notch, timer, audio, and Parking Lot.
- RankPanel.swift, RankChamber.swift, and EmblemArtwork.swift define rank and badge presentation.
- ProgressPanels.swift contains leaderboard and journey views.
- FocusPillar.swift, FocusGame.swift, PauseBank.swift, and TimerHeartbeat.swift contain progression and session logic.

Before handing back a change, build it and verify the affected screens and controls. Use fixture data for active-session previews.
