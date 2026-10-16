import SwiftUI

@main
struct SafariCamApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    enum Screen { case start, browser, camera }
    @StateObject private var cam = CameraManager()
    @StateObject private var web = WebModel()
    @State private var screen: Screen = .start
    @State private var error: String?

    var body: some View {
        ZStack {
            if screen == .start {
                StartView(onPin: start, error: error)
            } else {
                CameraScreen(cam: cam)
                if screen == .browser { BrowserScreen(web: web, cam: cam) }
                // 左上マーク：どの画面でも同じ位置、タップで切替
                VStack {
                    HStack {
                        Image(systemName: "megaphone.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.black.opacity(0.4))
                            .clipShape(Circle())
                            .opacity(0.6)
                            .contentShape(Circle())
                            .onLongPressGesture(minimumDuration: 0.4) {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.easeOut(duration: 0.15)) { screen = (screen == .browser) ? .camera : .browser }
                            }
                        Spacer()
                    }
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.top, 8)
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(screen == .camera)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
    }

    private func start() {
        cam.requestAndStart { ok in
            if ok {
                cam.startRecording()
                withAnimation(.easeOut(duration: 0.2)) { screen = .browser }
            } else {
                error = "カメラを使えません。設定 → Safari cam でカメラとマイクを許可してください。"
            }
        }
    }
}
