import SwiftUI
import AVFoundation

let accent = Color(red: 0.95, green: 0.78, blue: 0.63)

// MARK: - pin ボタン

struct PinButton: View {
    var size: CGFloat = 64
    var recording = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(recording ? "stop" : "pin")
                .font(.system(size: size * 0.2, weight: .bold))
                .tracking(1)
                .foregroundStyle(Color(red: 0.1, green: 0.06, blue: 0.03))
                .frame(width: size, height: size)
                .background(accent)
                .clipShape(Circle())
        }
    }
}

// MARK: - 起動画面

struct StartView: View {
    var onPin: () -> Void
    var error: String?
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 24) {
                HStack(spacing: 18) {
                    Text("Safari cam").font(.system(size: 30, weight: .semibold)).foregroundStyle(.white)
                    PinButton(action: onPin)
                }
                if let e = error {
                    Text(e).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center).padding(.horizontal, 32)
                }
            }
        }
    }
}

// MARK: - カメラ

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        return v
    }
    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

struct GridOverlay: View {
    var body: some View {
        GeometryReader { g in
            Path { p in
                for i in 1...2 {
                    let x = g.size.width * CGFloat(i) / 3, y = g.size.height * CGFloat(i) / 3
                    p.move(to: .init(x: x, y: 0)); p.addLine(to: .init(x: x, y: g.size.height))
                    p.move(to: .init(x: 0, y: y)); p.addLine(to: .init(x: g.size.width, y: y))
                }
            }
            .stroke(Color.white.opacity(0.35), lineWidth: 1)
        }
    }
}

struct IconButton: View {
    let system: String
    var on = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(on ? .black : .white)
                .frame(width: 40, height: 40)
                .background(on ? Color.white : Color.black.opacity(0.45))
                .clipShape(Circle())
        }
    }
}

struct CameraScreen: View {
    @ObservedObject var cam: CameraManager
    @State private var grid = true
    @State private var flash = false

    var body: some View {
        ZStack {
            CameraPreview(session: cam.session).ignoresSafeArea()
            Color.white.opacity(cam.beauty * 0.22).ignoresSafeArea().allowsHitTesting(false)
            if grid { GridOverlay().ignoresSafeArea().allowsHitTesting(false) }
            if flash { Color.white.ignoresSafeArea().allowsHitTesting(false) }

            VStack {
                HStack(spacing: 8) {
                    Spacer()
                    IconButton(system: "grid", on: grid) { grid.toggle() }
                    IconButton(system: "arrow.triangle.2.circlepath") { cam.flip() }
                }
                .padding(.horizontal, 12).padding(.top, 10)

                Spacer()

                HStack(spacing: 12) {
                    Text("美白").font(.caption).foregroundStyle(.white.opacity(0.7))
                    Slider(value: $cam.beauty, in: 0...1).tint(accent)
                    Text("\(Int(cam.beauty * 100))").font(.caption).monospacedDigit().foregroundStyle(.white.opacity(0.7)).frame(width: 28, alignment: .trailing)
                }
                .padding(.horizontal, 20).padding(.bottom, 26)

                ZStack {
                    Button {
                        cam.capturePhoto()
                        flash = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { withAnimation(.easeOut(duration: 0.2)) { flash = false } }
                    } label: {
                        ZStack {
                            Circle().stroke(.white, lineWidth: 4).frame(width: 78, height: 78)
                            Circle().fill(.white).frame(width: 62, height: 62)
                        }
                    }
                    HStack {
                        Spacer()
                        Button { cam.toggleRecording() } label: {
                            Text(cam.isRecording ? "■" : "●")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 48, height: 48)
                                .background(Color.black.opacity(0.45))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    .padding(.trailing, 16)
                }
                .padding(.bottom, 18)
            }
        }
        .background(Color.black)
    }
}

// MARK: - ブラウザ（トップ画面）

struct BrowserScreen: View {
    @ObservedObject var web: WebModel
    @ObservedObject var cam: CameraManager
    @State private var text = ""
    @State private var showPicker = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Spacer().frame(width: 40)
                Button { web.webView.goBack() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold)).frame(width: 32, height: 38)
                }
                .disabled(!web.canGoBack).opacity(web.canGoBack ? 1 : 0.3)

                TextField("検索 / URL", text: $text)
                    .focused($focused)
                    .keyboardType(.webSearch)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit { web.go(text); focused = false }
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(Color(white: 0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                Button { web.hasPDF ? web.openSavedPDF() : (showPicker = true) } label: {
                    Image(systemName: "doc.text").frame(width: 32, height: 38)
                }
                .simultaneousGesture(LongPressGesture().onEnded { _ in showPicker = true })
                Button { web.openMap() } label: { Image(systemName: "map").frame(width: 32, height: 38) }

                PinButton(size: 38, recording: cam.isRecording) { cam.toggleRecording() }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color(white: 0.11))

            WebView(webView: web.webView).ignoresSafeArea(edges: .bottom)
        }
        .background(Color(white: 0.11).ignoresSafeArea())
        .onReceive(web.$address) { if !focused { text = $0 } }
        .sheet(isPresented: $showPicker) { DocumentPicker { web.importPDF($0) } }
    }
}
