import AVKit
import SwiftUI

struct VideoWindow: View {
    @Environment(AppModel.self) private var appModel
    var sourceID: String

    @State private var player: AVPlayer?
    @State private var pinned = false
    @State private var scale = 1.0
    @State private var muted = true

    private var source: ContentSourceItem? {
        appModel.sourceDetails[sourceID] ?? appModel.sources.first(where: { $0.id == sourceID }) ?? appModel.selectedSource
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(source?.name ?? "视频窗口")
                    .font(.headline)
                Spacer()
                Button("重载") {
                    loadPlayer()
                }
                .buttonStyle(.bordered)
                Toggle("静音", isOn: $muted)
                    .toggleStyle(.button)
                    .onChange(of: muted) { _, value in
                        player?.isMuted = value
                    }
                Toggle(isOn: $pinned) {
                    Image(systemName: pinned ? "pin.fill" : "pin")
                }
                .toggleStyle(.button)
                Slider(value: $scale, in: 0.7...1.4)
                    .frame(width: 100)
            }
            .padding(12)
            .background(.thinMaterial)

            ZStack {
                if let player {
                    VideoPlayer(player: player)
                        .scaleEffect(scale)
                } else {
                    ProgressView("等待视频内容")
                }
            }
            .background(Color.black)
        }
        .onAppear {
            let pref = appModel.windowPreference(sourceID: sourceID)
            pinned = pref.pinned
            scale = pref.scale
            muted = source?.muted ?? true
            loadPlayer()
        }
        .onChange(of: pinned) { _, value in
            appModel.setWindowPreference(sourceID: sourceID, pinned: value, scale: scale)
        }
        .onChange(of: scale) { _, value in
            appModel.setWindowPreference(sourceID: sourceID, pinned: pinned, scale: value)
        }
        .onDisappear {
            player?.pause()
        }
    }

    private func loadPlayer() {
        guard let source, let url = appModel.sourceURLWithAuth(source) else {
            player = nil
            return
        }
        let next = AVPlayer(url: url)
        next.isMuted = muted
        next.play()
        player = next
    }
}
