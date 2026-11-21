import SwiftUI

// Distinct silhouettes and inset bevels stay crisp at row and profile sizes.
struct RankPlate:Shape {
    let rank:PlayerRank
    func path(in rect:CGRect)->Path {
        let pts:[CGPoint]
        switch rank {
        case .npc:pts=[.init(x:0.3,y:0.07),.init(x:0.7,y:0.07),.init(x:0.82,y:0.2),.init(x:0.82,y:0.76),.init(x:0.5,y:0.94),.init(x:0.18,y:0.76),.init(x:0.18,y:0.2)]
        case .bigBro:pts=[.init(x:0.5,y:0.03),.init(x:0.87,y:0.22),.init(x:0.84,y:0.67),.init(x:0.5,y:0.97),.init(x:0.16,y:0.67),.init(x:0.13,y:0.22)]
        case .bigMan:pts=[.init(x:0.5,y:0.01),.init(x:0.7,y:0.14),.init(x:0.89,y:0.17),.init(x:0.86,y:0.67),.init(x:0.7,y:0.82),.init(x:0.5,y:0.99),.init(x:0.3,y:0.82),.init(x:0.14,y:0.67),.init(x:0.11,y:0.17),.init(x:0.3,y:0.14)]
        }
        return Path {p in
            p.move(to:.init(x:pts[0].x*rect.width,y:pts[0].y*rect.height))
            for q in pts.dropFirst(){p.addLine(to:.init(x:q.x*rect.width,y:q.y*rect.height))};p.closeSubpath()
        }
    }
}
struct RankChevron:Shape {
    func path(in r:CGRect)->Path {
        Path {p in
            for y in [0.0,0.43] {
                p.move(to:.init(x:r.width*0.08,y:r.height*(y+0.25)))
                p.addLine(to:.init(x:r.width*0.5,y:r.height*y))
                p.addLine(to:.init(x:r.width*0.92,y:r.height*(y+0.25)))
                p.addLine(to:.init(x:r.width*0.92,y:r.height*(y+0.42)))
                p.addLine(to:.init(x:r.width*0.5,y:r.height*(y+0.17)))
                p.addLine(to:.init(x:r.width*0.08,y:r.height*(y+0.42)));p.closeSubpath()
            }
        }
    }
}
struct Laurel:Shape {
    func path(in r:CGRect)->Path {
        Path {p in
            for side in [-1.0,1.0] {
                func point(_ x:Double,_ y:Double)->CGPoint {.init(x:r.width*(0.5+side*x),y:r.height*y)}
                for i in 0..<4 {
                    let x=0.37-Double(i)*0.025,y=0.38+Double(i)*0.105
                    p.move(to:point(x-0.02,y+0.07))
                    p.addQuadCurve(to:point(x+0.075,y-0.045),control:point(x+0.08,y+0.045))
                    p.addQuadCurve(to:point(x-0.02,y+0.07),control:point(x-0.04,y-0.05));p.closeSubpath()
                }
            }
        }
    }
}
struct AchievementPlate:Shape {
    let index:Int
    func path(in r:CGRect)->Path {
        if index == 0 {return Path(ellipseIn:r.insetBy(dx:r.width*0.04,dy:r.height*0.04))}
        let n=index == 1 ? 6 : index == 2 ? 12 : index == 3 ? 8 : index == 4 ? 6 : 10
        return Path {p in
            for i in 0..<n {
                let a=Double(i)*2*Double.pi/Double(n)-Double.pi/2
                let radius=index == 2 && i%2 != 0 ? 0.39 : 0.47
                let q=CGPoint(x:r.width*(0.5+radius*cos(a)),y:r.height*(0.5+radius*sin(a)))
                if i==0 {p.move(to:q)} else {p.addLine(to:q)}
            };p.closeSubpath()
        }
    }
}
