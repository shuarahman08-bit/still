import SwiftUI

struct PillarGlyph: View {
    let pillar: FocusPillar
    let color: Color
    var size: CGFloat = 48
    var phase: Double = 0
    var body: some View {
        ZStack {
            switch pillar {
            case .ops:
                RoundedRectangle(cornerRadius:size*0.09).fill(color.opacity(0.12)).frame(width:size*0.75,height:size*0.52).offset(y:size*0.08)
                RoundedRectangle(cornerRadius:size*0.09).stroke(color,lineWidth:1.5).frame(width:size*0.75,height:size*0.52).offset(y:size*0.08)
                RoundedRectangle(cornerRadius:size*0.05).stroke(color.opacity(0.8),lineWidth:1.5).frame(width:size*0.27,height:size*0.14).offset(y:-size*0.25)
                Rectangle().fill(color.opacity(0.35)).frame(width:size*0.74,height:1).offset(y:size*0.03)
                RoundedRectangle(cornerRadius:1).fill(color).frame(width:size*0.08,height:size*0.12).offset(y:size*0.06)
                Image(systemName:"checkmark.circle.fill").font(.system(size:size*0.28,weight:.semibold)).background(.black.opacity(0.5),in:Circle()).offset(x:size*0.32,y:size*0.29)
                    .scaleEffect(phase == 0 ? 1 : 1 + 0.04*sin(phase*2))
            case .master:
                BookPages().fill(color.opacity(0.06)).frame(width:size*0.8,height:size*0.58).offset(y:size*0.06)
                BookPages().stroke(color,lineWidth:1.5).frame(width:size*0.8,height:size*0.58).offset(y:size*0.06)
                Path {p in p.move(to:CGPoint(x:size*0.5,y:size*0.328));p.addLine(to:CGPoint(x:size*0.5,y:size*0.85))}
                    .stroke(color.opacity(0.8),lineWidth:1).frame(width:size,height:size)
                ForEach(0..<3) {index in
                    HStack(spacing:size*0.18) {
                        Capsule().fill(color.opacity(0.6)).frame(width:size*0.17,height:1.2)
                        Capsule().fill(color.opacity(0.6)).frame(width:size*0.17,height:1.2)
                    }.offset(y:CGFloat(index)*size*0.1-size*0.04)
                }
                Image(systemName:"sparkle").font(.system(size:size*0.18,weight:.medium)).offset(x:size*0.3,y:-size*0.34)
                    .scaleEffect(phase == 0 ? 1 : 1+0.08*sin(phase*2))
            case .build:
                Image(systemName:"gearshape.fill").font(.system(size:size*0.58,weight:.medium)).rotationEffect(.degrees(phase*18)).offset(x:-size*0.15,y:-size*0.1)
                Image(systemName:"gearshape.fill").font(.system(size:size*0.4,weight:.medium)).rotationEffect(.degrees(-phase*26)).offset(x:size*0.24,y:size*0.22)
                Circle().fill(.black.opacity(0.6)).frame(width:size*0.14,height:size*0.14).offset(x:-size*0.15,y:-size*0.1)
                Circle().fill(.black.opacity(0.6)).frame(width:size*0.09,height:size*0.09).offset(x:size*0.24,y:size*0.22)
            }
        }.foregroundStyle(color).frame(width:size,height:size).accessibilityHidden(true)
    }
}
struct BookPages: Shape {
    func path(in rect:CGRect)->Path {
        Path { p in
            let w=rect.width,h=rect.height
            p.move(to:CGPoint(x:w*0.5,y:h*0.1))
            p.addQuadCurve(to:CGPoint(x:0,y:h*0.03),control:CGPoint(x:w*0.24,y:-h*0.1))
            p.addLine(to:CGPoint(x:0,y:h*0.83))
            p.addQuadCurve(to:CGPoint(x:w*0.5,y:h),control:CGPoint(x:w*0.25,y:h*0.72))
            p.addQuadCurve(to:CGPoint(x:w,y:h*0.83),control:CGPoint(x:w*0.75,y:h*0.72))
            p.addLine(to:CGPoint(x:w,y:h*0.03))
            p.addQuadCurve(to:CGPoint(x:w*0.5,y:h*0.1),control:CGPoint(x:w*0.76,y:-h*0.1))
            p.closeSubpath()
        }
    }
}
struct PillarMedallion: View {
    let pillar: FocusPillar
    let color: Color
    let animate: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors:[.white.opacity(0.045),.black.opacity(0.15)],startPoint:.topLeading,endPoint:.bottomTrailing))
            Circle().strokeBorder(LinearGradient(colors:[.white.opacity(0.5),color.opacity(0.12),color.opacity(0.5)],startPoint:.topLeading,endPoint:.bottomTrailing),lineWidth:1.2)
            Circle().strokeBorder(color.opacity(0.17),lineWidth:0.7).padding(7)
            Circle().trim(from:0.07,to:0.3).stroke(color.opacity(0.55),style:StrokeStyle(lineWidth:1.5,lineCap:.round)).rotationEffect(.degrees(-90)).padding(3)
            if animate && !reduceMotion {
                TimelineView(.animation(minimumInterval:1.0/24)) {timeline in
                    PillarGlyph(pillar:pillar,color:color,size:64,phase:timeline.date.timeIntervalSinceReferenceDate)
                }
            } else {PillarGlyph(pillar:pillar,color:color,size:64)}
        }.frame(width:104,height:104).shadow(color:color.opacity(0.07),radius:10,y:4)
    }
}
struct IntensityEmblem: View {
    let tier: IntensityTier
    var selected: Bool
    var body: some View {
        ZStack {
            if tier == .hardcore {
                CrestShape().fill(tier.color.opacity(selected ? 0.16 : 0.04))
                CrestShape().stroke(tier.color.opacity(selected ? 0.8 : 0.4),lineWidth:1)
            } else {
                Circle().fill(tier.color.opacity(selected ? 0.14 : 0.04))
                Circle().strokeBorder(tier.color.opacity(selected ? 0.65 : 0.25),lineWidth:1)
            }
            Image(systemName:tier == .zen ? "leaf.fill" : tier == .ranked ? "chevron.up.2" : "flame.fill")
                .font(.system(size:18,weight:.semibold)).foregroundStyle(tier.color.opacity(selected ? 1 : 0.5))
        }.frame(width:38,height:38).accessibilityHidden(true)
    }
}
extension FocusPillar {
    var shortScope: String {self == .ops ? "Email · Meetings · Admin" : self == .master ? "Learn · Practice · Refine" : "Code · Design · Create"}
}
