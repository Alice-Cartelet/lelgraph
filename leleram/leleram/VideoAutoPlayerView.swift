import SwiftUI
import UniformTypeIdentifiers
import WebKit
import CryptoKit
import AVKit
struct VideoAutoPlayerView: View {
    let url: URL   // 指向 .alv 文件
    @State private var player: AVPlayer? = nil
    @State private var tempFileURL: URL? = nil

    var body: some View {
        Group {
            if let player = player {
                VideoPlayer(player: player)
                    .onAppear { player.play() }
                    .onDisappear { player.pause() }
            } else {
                ProgressView("加载中...").onAppear { prepare() }
            }
        }
        .onDisappear { cleanup() }
    }

    private func prepare() {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                var data = try Data(contentsOf: url)
                if data.count > 4 {
                    data.removeSubrange(0..<4) // 去掉干扰字节 "ALV!"
                }
                let tmpURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("mp4")
                try data.write(to: tmpURL, options: .atomic)
                DispatchQueue.main.async {
                    self.tempFileURL = tmpURL
                    let newPlayer = AVPlayer(url: tmpURL)
                    self.player = newPlayer

                    // 循环播放
                    NotificationCenter.default.addObserver(
                        forName: .AVPlayerItemDidPlayToEndTime,
                        object: newPlayer.currentItem,
                        queue: .main
                    ) { _ in
                        newPlayer.seek(to: .zero)
                        newPlayer.play()
                    }
                }
            } catch {
                print("准备视频失败: \(error)")
            }
        }
    }

    private func cleanup() {
        if let tmp = tempFileURL {
            try? FileManager.default.removeItem(at: tmp)
            tempFileURL = nil
        }
        player = nil
    }
}
