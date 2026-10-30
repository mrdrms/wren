import SwiftUI

/// A vermilion hanko: the artist's seal, stamped a little crooked, its letter carved out.
struct Seal: View {
    var text = "W"
    var size: CGFloat = 64
    var color = Color(red: 0.78, green: 0.25, blue: 0.17)

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.14)
            .fill(color)
            .overlay {
                Text(text)
                    .font(.system(size: size * 0.66, weight: .bold, design: .serif))
                    .foregroundStyle(Color(red: 0.99, green: 0.95, blue: 0.9))
            }
            .frame(width: size, height: size)
            .rotationEffect(.degrees(-4))
    }
}

/// The first few seconds of every session: an ensō brushed onto washi, the seal pressed
/// beside it, the name, then the page. A click skips it.
struct LaunchRitual: View {
    let theme: Theme
    let finish: () -> Void
    @State private var stamped = false
    @State private var named = false

    var body: some View {
        ZStack {
            Rectangle().fill(Color(red: 0.97, green: 0.95, blue: 0.9))
            PaperGrain(dark: false)
            VStack(spacing: 26) {
                ZStack(alignment: .bottomTrailing) {
                    Enso(color: Color(red: 0.11, green: 0.1, blue: 0.09))
                        .frame(width: 230, height: 230)
                    Seal(size: 46)
                        .scaleEffect(stamped ? 1 : 2.4)
                        .opacity(stamped ? 1 : 0)
                        .offset(x: 6, y: -8)
                }
                VStack(spacing: 10) {
                    Text("Wren")
                        .font(.system(size: 46, weight: .regular, design: .serif))
                        .tracking(2)
                    Text("A quiet place to write")
                        .font(.system(size: 11, weight: .semibold))
                        .textCase(.uppercase)
                        .tracking(3)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(Color(red: 0.11, green: 0.1, blue: 0.09))
                .opacity(named ? 1 : 0)
                .offset(y: named ? 0 : 8)
            }
        }
        .environment(\.colorScheme, .light)
        .ignoresSafeArea()
        .contentShape(.rect)
        .onTapGesture(perform: finish)
        .task {
            try? await Task.sleep(for: .milliseconds(1250))
            withAnimation(.spring(duration: 0.32, bounce: 0.25)) { stamped = true }
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.easeOut(duration: 0.6)) { named = true }
            try? await Task.sleep(for: .milliseconds(1300))
            finish()
        }
    }
}
