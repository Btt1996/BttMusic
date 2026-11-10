import SwiftData
import SwiftUI

@main
struct BttMusicApp: App {
    let container: ModelContainer

    @State private var audio = AudioEngine()
    @State private var library = LibraryStore()
    @State private var telegram = TelegramService()
    @State private var x1 = X1SpotifyService()
    @State private var x2 = X2AcquisitionService()
    @State private var updates = UpdateService()
    @State private var showSplash = true

    init() {
        do {
            container = try ModelContainer(for: Track.self, Playlist.self)
        } catch {
            fatalError("Could not create model container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environment(audio)
                    .environment(library)
                    .environment(telegram)
                    .environment(x1)
                    .environment(x2)
                    .environment(updates)
                    .modelContainer(container)
                    .onAppear {
                        library.bind(context: ModelContext(container))
                        audio.restoreQueue(tracks: library.tracks)
                    }
                    .preferredColorScheme(.dark)

                if showSplash {
                    SplashView()
                        .transition(.opacity)
                        .zIndex(10)
                        .task {
                            try? await Task.sleep(for: .seconds(2.0))
                            withAnimation(.easeOut(duration: 0.5)) {
                                showSplash = false
                            }
                        }
                }
            }
        }
    }
}

struct SplashView: View {
    @State private var logoIn = false
    @State private var titleIn = false
    @State private var creditIn = false
    @State private var ruleIn = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            // Ambient glow behind the logo
            Circle()
                .fill(BT.gradient)
                .frame(width: 340, height: 340)
                .blur(radius: 110)
                .opacity(logoIn ? 0.30 : 0)
            VStack(spacing: 0) {
                Image("BTLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 158, height: 158)
                    .clipShape(RoundedRectangle(cornerRadius: 38))
                    .shadow(color: BT.magenta.opacity(0.45), radius: 36, y: 10)
                    .scaleEffect(logoIn ? 1 : 0.78)
                    .opacity(logoIn ? 1 : 0)
                Text("Btt Music")
                    .font(.system(size: 40, weight: .semibold, design: .serif))
                    .foregroundStyle(.white)
                    .padding(.top, 28)
                    .opacity(titleIn ? 1 : 0)
                    .offset(y: titleIn ? 0 : 14)
                // Gradient rule line that draws outward
                Rectangle()
                    .fill(BT.horizontalGradient)
                    .frame(width: ruleIn ? 132 : 0, height: 2)
                    .clipShape(Capsule())
                    .padding(.top, 14)
                Text("By Taboubi Ahmed")
                    .font(.system(size: 14, weight: .medium))
                    .tracking(2.5)
                    .textCase(.uppercase)
                    .foregroundStyle(BT.textSecondary)
                    .padding(.top, 16)
                    .opacity(creditIn ? 1 : 0)
            }
        }
        .task {
            withAnimation(.spring(response: 0.75, dampingFraction: 0.7)) { logoIn = true }
            try? await Task.sleep(for: .seconds(0.5))
            withAnimation(.easeOut(duration: 0.45)) { titleIn = true }
            withAnimation(.easeOut(duration: 0.5).delay(0.1)) { ruleIn = true }
            try? await Task.sleep(for: .seconds(0.35))
            withAnimation(.easeOut(duration: 0.5)) { creditIn = true }
        }
    }
}
