import SwiftUI
import UniformTypeIdentifiers
import WebKit
import CryptoKit
import AVKit

struct FullScreenViewer: View {
    var elements: [PageElement]
    @Binding var isPresented: Bool
    var initialIndex: Int

    @State private var currentIndex: Int = 0

    var body: some View {
        TabView(selection: $currentIndex) {
            ForEach(elements.indices, id: \.self) { index in
                let element = elements[index]
                Group {
                    if let base64 = element.imageBase64,
                       let data = Data(base64Encoded: base64),
                       let uiImage = UIImage(data: data) {
                        ZoomableImageView(image: Image(uiImage: uiImage))
                    } else if let videoName = element.videoFileName {
                        let url = FileManager.default
                            .urls(for: .documentDirectory, in: .userDomainMask)[0]
                            .appendingPathComponent("Videos")
                            .appendingPathComponent(videoName)
                        VideoPlayer(player: AVPlayer(url: url))
                            .edgesIgnoringSafeArea(.all)
                    }
                }
                .tag(index)
                .background(Color.black)
            }
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
        .background(Color.black)
        .ignoresSafeArea()
        .onAppear {
            currentIndex = initialIndex
        }
        .overlay(
            Button(action: {
                isPresented = false
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.white)
                    .padding()
            }, alignment: .topTrailing
        )
    }
}
