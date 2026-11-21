import SwiftUI

struct ChamberLines:Shape {
    func path(in r:CGRect)->Path {
        Path {p in
            for x in [-0.5,0.0,0.25,0.5,0.75,1.0,1.5] {
                p.move(to:.init(x:r.width*0.5,y:r.height*0.51))
                p.addLine(to:.init(x:r.width*x,y:r.height))
            }
            for y in [0.64,0.77,0.94] {
                p.move(to:.init(x:0,y:r.height*y));p.addLine(to:.init(x:r.width,y:r.height*y))
            }
        }
    }
}
struct ChamberCorners:Shape {
    func path(in r:CGRect)->Path {
        Path {p in
            for (x,y,sx,sy) in [(10.0,10.0,1.0,1.0),(Double(r.width)-10,10.0,-1.0,1.0),(10.0,Double(r.height)-10,1.0,-1.0),(Double(r.width)-10,Double(r.height)-10,-1.0,-1.0)] {
                p.move(to:.init(x:x,y:y+sy*12));p.addLine(to:.init(x:x,y:y));p.addLine(to:.init(x:x+sx*12,y:y))
            }
        }
    }
}
struct RankChamberSurface:View {
    let tint:Color
    var body:some View {
        GeometryReader {g in
            ZStack {
                Color(white:0.035)
                RadialGradient(colors:[tint.opacity(0.26),tint.opacity(0.075),tint.opacity(0)],center:UnitPoint(x:0.5,y:0.37),startRadius:0,endRadius:g.size.width*0.65)
                Path {p in
                    p.move(to:.init(x:g.size.width*0.39,y:0));p.addLine(to:.init(x:g.size.width*0.61,y:0))
                    p.addLine(to:.init(x:g.size.width*0.87,y:g.size.height*0.64));p.addLine(to:.init(x:g.size.width*0.13,y:g.size.height*0.64));p.closeSubpath()
                }.fill(LinearGradient(colors:[.white.opacity(0.05),tint.opacity(0.035),.clear],startPoint:.top,endPoint:.bottom))
                ChamberLines().stroke(tint.opacity(0.1),lineWidth:0.6)
                    .mask(LinearGradient(colors:[.clear,.clear,.white.opacity(0.5)],startPoint:.top,endPoint:.bottom))
                ChamberCorners().stroke(tint.opacity(0.4),style:StrokeStyle(lineWidth:0.8,lineCap:.round))
            }
        }.clipShape(RoundedRectangle(cornerRadius:24))
            .overlay {RoundedRectangle(cornerRadius:24).strokeBorder(LinearGradient(colors:[.white.opacity(0.25),tint.opacity(0.1),tint.opacity(0.45)],startPoint:.topLeading,endPoint:.bottomTrailing),lineWidth:0.8)}
            .overlay(alignment:.top) {LinearGradient(colors:[.clear,tint.opacity(0.65),.clear],startPoint:.leading,endPoint:.trailing).frame(width:130,height:1).padding(.top,1)}
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}
struct RankHeroCard:View {
    let inspected:PlayerRank
    let current:PlayerRank
    let xp:Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var fraction:Double {
        guard let next=inspected.next else {return min(1,max(0,Double(xp)/Double(max(1,inspected.threshold))))}
        return min(1,max(0,Double(xp-inspected.threshold)/Double(next.threshold-inspected.threshold)))
    }
    var body:some View {
        VStack(spacing:12) {
            HStack(spacing:6) {
                HStack(spacing:2) {ForEach(0...inspected.rawValue,id:\.self) {_ in Capsule().fill(inspected.color).frame(width:3,height:8)}}
                Text("RANK \(["I","II","III"][inspected.rawValue])").tracking(1.3)
                Spacer()
                Text(inspected == current ? "CURRENT" : "PREVIEW").tracking(1)
            }.font(.system(size:9,weight:.semibold)).foregroundStyle(inspected.color.opacity(0.85))
            ZStack {
                Ellipse().fill(inspected.color.opacity(0.075)).frame(width:170,height:27).offset(y:68)
                Ellipse().stroke(inspected.color.opacity(0.25),lineWidth:0.7).frame(width:170,height:27).offset(y:68)
                RankEmblem(rank:inspected,size:136)
                    .shadow(color:inspected.color.opacity(0.18),radius:16,y:1)
                    .phaseAnimator([false,true,false],trigger:inspected.rawValue) {view,phase in
                        view.scaleEffect(phase && !reduceMotion ? 1.055 : 1)
                    } animation: {_ in reduceMotion ? nil : .spring(response:0.32,dampingFraction:0.75)}
            }.frame(height:156)
            Text(inspected.title).font(.system(size:32,weight:.semibold,design:.rounded)).foregroundStyle(.white.opacity(0.95))
                .shadow(color:inspected.color.opacity(0.3),radius:12)
            VStack(spacing:8) {
                HStack(spacing:3) {
                    ForEach(0..<24,id:\.self) {i in
                        RoundedRectangle(cornerRadius:1).fill(Double(i)/24 < fraction ? inspected.color.opacity(0.85) : .white.opacity(0.08)).frame(height:5)
                    }
                }.accessibilityLabel("Rank progress").accessibilityValue("\(Int(fraction*100)) percent")
                HStack {
                    if inspected == current,let next=inspected.next {
                        Text("\(xp.formatted()) / \(next.threshold.formatted()) XP").foregroundStyle(inspected.color)
                        Spacer()
                        Text("Next · \(next.title)").foregroundStyle(.white.opacity(0.45))
                    } else {
                        Text("\(inspected.threshold.formatted()) XP").foregroundStyle(inspected.color)
                        Spacer()
                        Image(systemName:xp >= inspected.threshold ? "checkmark.seal.fill" : "lock.fill").foregroundStyle(inspected.color.opacity(0.7))
                    }
                }.font(.system(size:10,weight:.medium)).monospacedDigit()
            }.padding(.top,3)
        }.padding(20).frame(maxWidth:.infinity)
            .background {RankChamberSurface(tint:inspected.color)}
    }
}
