import SwiftUI

// One interaction transaction drives the rim, foreground and controls together.
// SwiftUI interpolates transforms; no display-link, polling or continuous shader.
@MainActor final class SurfaceMotion: ObservableObject {
    @Published var pressure: CGFloat = 0
    @Published var point = CGPoint(x: 0.5, y: 0.5)
    func press(_ pressed: Bool, at point: CGPoint, reduceMotion: Bool) {
        if pressed {
            withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82)) {
                self.point = CGPoint(x: min(1, max(0, point.x / 420)), y: min(1, max(0, point.y / 650)))
                pressure = reduceMotion ? 0 : 1
            }
        } else {
            withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.68)) { pressure = 0 }
        }
    }
    func reset() { pressure = 0 }
    var horizontal: CGFloat { (point.x - 0.5) * 2 }
}

struct SharedPressStyle: ButtonStyle {
    let motion: SurfaceMotion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // The label's geometry supplies a stable position; it is not read every frame.
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .brightness(configuration.isPressed && !reduceMotion ? 0.04 : 0)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
            .background {
                GeometryReader { proxy in
                    Color.clear.onChange(of: configuration.isPressed) { _, pressed in
                        let frame = proxy.frame(in: .named("stillSurface"))
                        motion.press(pressed, at: CGPoint(x: frame.midX, y: frame.midY), reduceMotion: reduceMotion)
                    }.onDisappear { if configuration.isPressed { motion.reset() } }
                }.allowsHitTesting(false)
            }
    }
}
