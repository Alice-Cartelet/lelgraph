import SwiftUI
import UniformTypeIdentifiers
import WebKit
import CryptoKit
import AVKit


// MARK: - 内存图片缓存（按屏幕尺寸缩放 + 按字节计费）
class ImageCache {
    static let shared = ImageCache()
    private init() {
        cache.totalCostLimit = 80 * 1024 * 1024 // 80MB 上限
        cache.countLimit = 40
    }
    private var cache = NSCache<NSString, UIImage>()

    /// 解码并缩放到屏幕宽度，减少内存占用
    func image(for base64: String) -> UIImage? {
        if let cached = cache.object(forKey: base64 as NSString) {
            return cached
        }
        guard let data = Data(base64Encoded: base64) else { return nil }

        // ✅ 按屏幕宽度缩放，不存原始尺寸
        let screenWidth = UIScreen.main.bounds.width * UIScreen.main.scale
        let image = downsampledImage(from: data, maxPixelSize: screenWidth) ?? UIImage(data: data)
        guard let finalImage = image else { return nil }

        // ✅ 按实际字节数计费，让 NSCache 能精准驱逐
        let cost = Int(finalImage.size.width * finalImage.size.height * finalImage.scale * 4)
        cache.setObject(finalImage, forKey: base64 as NSString, cost: cost)
        return finalImage
    }

    /// 从指定 key 移除单张图片
    func removeImage(for base64: String) {
        cache.removeObject(forKey: base64 as NSString)
    }

    /// 清空全部缓存
    func clearAll() {
        cache.removeAllObjects()
    }

    // MARK: - ImageIO 降采样（不全量解码）
    private func downsampledImage(from data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,       // 先不缓存原图
            kCGImageSourceShouldAllowFloat: true
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
            return nil
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,    // 缩略图才缓存
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - 懒加载图片视图（可见时加载，不可见时释放）
struct LazyImageView: View {
    let base64: String
    let onTap: () -> Void

    @State private var image: UIImage? = nil

    var body: some View {
        Group {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(12)
                    .shadow(radius: 5)
                    .onTapGesture { onTap() }
            } else {
                // 占位符
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray5))
                    .frame(height: 160)
                    .overlay(ProgressView())
            }
        }
        .onAppear {
            // ✅ 进入视口才解码
            if image == nil {
                DispatchQueue.global(qos: .userInitiated).async {
                    let loaded = ImageCache.shared.image(for: base64)
                    DispatchQueue.main.async { image = loaded }
                }
            }
        }
        .onDisappear {
            // ✅ 离开视口释放引用，缓存由 NSCache 自动管理
            image = nil
        }
    }
}

// MARK: - 编辑状态
struct EditorState {
    var index: Int? = nil
    var editingText: String = ""
    var newText: String = ""
    var selectedImage: UIImage?

    mutating func reset() {
        index = nil
        editingText = ""
        newText = ""
        selectedImage = nil
    }
}

// MARK: - 插入文字弹窗状态
struct InsertTextDialogState {
    var isVisible: Bool = false
    var text: String = ""
    var position: Int? = nil

    mutating func show(at pos: Int) {
        position = pos
        text = ""
        isVisible = true
    }

    mutating func hide() {
        isVisible = false
        text = ""
        position = nil
    }
}

// MARK: - ViewerView
struct ViewerView: View {
    let fileURL: URL
    let baseURL: URL
    var fileName: String
    var forceEdit: Bool = false

    @State private var content: [PageElement] = []
    @State private var editMode = false
    @State private var editor = EditorState()
    @State private var insertDialog = InsertTextDialogState()

    @State private var showVideoPicker = false
    @State private var showImagePicker = false
    @State private var showFullScreenViewer = false
    @State private var selectedIndex = 0
    @State private var showSaveSuccess = false
    @State private var showActionSheet = false
    @State private var actionSheetImage: UIImage? = nil

    private var videosBaseURL: URL {
        baseURL.appendingPathComponent("Videos")
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(content.indices, id: \.self) { idx in
                        ElementView(
                            element: content[idx],
                            videosBaseURL: videosBaseURL,
                            isEditing: editMode,
                            isEditingThis: editor.index == idx,
                            editingText: $editor.editingText,
                            onSaveText: { saveEditedText(at: idx) },
                            onTapText: { startEditingText(at: idx) },
                            onDelete: { content.remove(at: idx) },
                            onTapElement: {
                                selectedIndex = idx
                                showFullScreenViewer = true
                            },
                            onLongPressImage: { image in
                                actionSheetImage = image
                                showActionSheet = true
                            }
                        )

                        if editMode {
                            InsertControlsView(
                                onInsertImage: {
                                    selectedIndex = idx + 1
                                    showImagePicker = true
                                },
                                onInsertText: {
                                    insertDialog.show(at: idx + 1)
                                }
                            )
                        }
                    }

                    if editMode {
                        NewElementPanel(
                            newText: $editor.newText,
                            selectedImage: $editor.selectedImage,
                            onAddText: { insertText(editor.newText, at: nil) },
                            onPickImage: {
                                selectedIndex = content.count
                                showImagePicker = true
                            },
                            onPickVideo: { showVideoPicker = true }
                        )
                    }
                }
                .padding()
            }

            if insertDialog.isVisible {
                InsertTextDialog(
                    state: $insertDialog,
                    onInsert: { insertText($0, at: insertDialog.position) }
                )
            }
        }
        .navigationTitle(fileName)
        .toolbar {
            Button(editMode ? "保存" : "编辑") {
                if editMode { save() }
                withAnimation {
                    editMode.toggle()
                    editor.reset()
                }
            }
        }
        .onAppear {
            ImageCache.shared.clearAll()
            load()
            if forceEdit { editMode = true }
        }
        .onDisappear {
            ImageCache.shared.clearAll()
            content = []
            editor.reset()
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: $editor.selectedImage)
        }
        .sheet(isPresented: $showVideoPicker) {
            VideoPicker { url in
                if let url = url { importVideo(url: url) }
                showVideoPicker = false
            }
        }
        .fullScreenCover(isPresented: $showFullScreenViewer) {
            if content.indices.contains(selectedIndex) {
                let images = content.compactMap { elem -> UIImage? in
                    guard let base64 = elem.imageBase64 else { return nil }
                    return ImageCache.shared.image(for: base64)
                }
                if !images.isEmpty {
                    FullScreenPagerView(
                        images: images,
                        currentIndex: $selectedIndex,
                        isPresented: $showFullScreenViewer,
                        showSaveSuccess: $showSaveSuccess
                    )
                } else {
                    VStack {
                        Text("无法预览此元素").foregroundColor(.white).padding()
                        Button("关闭") { showFullScreenViewer = false }.foregroundColor(.blue)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.ignoresSafeArea())
                }
            }
        }
        .confirmationDialog("保存图片", isPresented: $showActionSheet, titleVisibility: .visible) {
            Button("保存到相册") {
                if let img = actionSheetImage {
                    UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    showSaveSuccess = true
                }
            }
            Button("取消", role: .cancel) { }
        }
        .overlay(
            Group {
                if showSaveSuccess {
                    Text("保存成功")
                        .font(.system(size: 16, weight: .semibold))
                        .padding(.vertical, 12)
                        .padding(.horizontal, 24)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.black.opacity(0.8))
                                .blur(radius: 2)
                        )
                        .foregroundColor(.white)
                        .shadow(radius: 5)
                        .scaleEffect(showSaveSuccess ? 1.0 : 0.8)
                        .opacity(showSaveSuccess ? 1 : 0)
                        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: showSaveSuccess)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation { showSaveSuccess = false }
                            }
                        }
                        .padding(.top, 60)
                        .zIndex(1)
                }
            }
        )
        .onChange(of: editor.selectedImage) { _ in
            if let img = editor.selectedImage { insertImage(img, at: selectedIndex) }
        }
        .onTapGesture { hideKeyboard() }
    }

    // MARK: - 加载 / 保存
    func load() {
        DispatchQueue.global(qos: .userInitiated).async {
            var loaded: [PageElement] = []
            if let enc = try? Data(contentsOf: fileURL),
               let dec = try? CryptoHelper.decrypt(enc),
               let decoded = try? JSONDecoder().decode([PageElement].self, from: dec) {
                loaded = decoded
            }
            DispatchQueue.main.async { self.content = loaded }
        }
    }

    func save() {
        let snapshot = content
        DispatchQueue.global(qos: .utility).async {
            if let json = try? JSONEncoder().encode(snapshot),
               let enc = try? CryptoHelper.encrypt(json) {
                try? enc.write(to: fileURL)
            }
        }
    }

    // MARK: - 插入 / 修改元素
    func insertText(_ text: String, at pos: Int?) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if let p = pos, p <= content.count { content.insert(PageElement(text: t), at: p) }
        else { content.append(PageElement(text: t)) }
        editor.newText = ""
        insertDialog.hide()
        hideKeyboard()
    }

    func insertImage(_ image: UIImage?, at pos: Int?) {
        guard let img = image,
              let data = img.pngData() ?? img.jpegData(compressionQuality: 0.8) else { return }
        let base64 = data.base64EncodedString()
        let isGIF = data.starts(with: [0x47, 0x49, 0x46])
        let elem = PageElement(imageBase64: base64, isGIF: isGIF)
        if let p = pos, p <= content.count { content.insert(elem, at: p) }
        else { content.append(elem) }
        editor.selectedImage = nil
        hideKeyboard()
    }

    func saveEditedText(at idx: Int) {
        let t = editor.editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { content.remove(at: idx) } else { content[idx].text = t }
        editor.index = nil
        editor.editingText = ""
    }

    func startEditingText(at idx: Int) {
        editor.index = idx
        editor.editingText = content[idx].text ?? ""
    }

    // MARK: - 视频导入
    func importVideo(url: URL) {
        let dir = videosBaseURL
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encName = url.deletingPathExtension().lastPathComponent + ".alv"
        let dest = dir.appendingPathComponent(encName)
        do {
            if !FileManager.default.fileExists(atPath: dest.path) {
                var data = try Data(contentsOf: url)
                data.insert(contentsOf: "ALV!".data(using: .utf8)!, at: 0)
                try data.write(to: dest, options: .atomic)
            }
            content.append(PageElement(videoFileName: encName))
        } catch { print("视频导入失败: \(error)") }
    }

    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}

// MARK: - ElementView
struct ElementView: View {
    var element: PageElement
    var videosBaseURL: URL
    var isEditing: Bool
    var isEditingThis: Bool
    @Binding var editingText: String
    var onSaveText: () -> Void
    var onTapText: () -> Void
    var onDelete: () -> Void
    var onTapElement: () -> Void
    var onLongPressImage: (UIImage) -> Void  // ✅ 长按回调移到这里

    var body: some View {
        Group {
            if let videoName = element.videoFileName {
                let url = videosBaseURL.appendingPathComponent(videoName)
                if FileManager.default.fileExists(atPath: url.path) {
                    VideoAutoPlayerView(url: url)
                        .frame(height: 200)
                        .cornerRadius(12)
                        .shadow(radius: 5)
                        .onTapGesture { onTapElement() }
                } else {
                    Text("视频文件丢失").foregroundColor(.red)
                }
            } else if let base64 = element.imageBase64 {
                // ✅ 改用懒加载视图
                LazyImageView(base64: base64, onTap: onTapElement)
                    .gesture(
                        LongPressGesture(minimumDuration: 0.6).onEnded { _ in
                            if let img = ImageCache.shared.image(for: base64) {
                                onLongPressImage(img)
                            }
                        }
                    )
            } else if let text = element.text {
                if isEditing && isEditingThis {
                    VStack {
                        TextEditor(text: $editingText)
                            .font(.body)
                            .frame(minHeight: 80)
                            .padding(8)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        HStack {
                            Spacer()
                            Button("完成") { onSaveText() }
                                .padding(.horizontal)
                                .padding(.vertical, 6)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }
                } else {
                    Text(text.isEmpty ? " " : text)
                        .font(.body)
                        .frame(minHeight: 40, alignment: .leading)
                        .background(text.isEmpty ? Color(.systemGray5).opacity(0.3) : Color.clear)
                        .onTapGesture { if isEditing { onTapText() } }
                }
            }
        }
        .contextMenu {
            if isEditing {
                Button(role: .destructive, action: onDelete) {
                    Label("删除", systemImage: "trash")
                }
            }
        }
    }
}

// MARK: - InsertControlsView
struct InsertControlsView: View {
    var onInsertImage: () -> Void
    var onInsertText: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onInsertImage) {
                Label("插入图片", systemImage: "photo.on.rectangle.angled").font(.footnote)
            }
            .frame(maxWidth: .infinity).padding()
            .background(Color.accentColor.opacity(0.1)).cornerRadius(10)

            Button(action: onInsertText) {
                Label("插入文字", systemImage: "text.cursor").font(.footnote)
            }
            .frame(maxWidth: .infinity).padding()
            .background(Color.accentColor.opacity(0.1)).cornerRadius(10)
        }
    }
}

// MARK: - NewElementPanel
struct NewElementPanel: View {
    @Binding var newText: String
    @Binding var selectedImage: UIImage?
    var onAddText: () -> Void
    var onPickImage: () -> Void
    var onPickVideo: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            TextField("输入文字", text: $newText)
                .padding(12).background(Color(.systemGray5)).cornerRadius(10)
                .submitLabel(.done).onSubmit { onAddText() }

            Button("添加文字", action: onAddText)
                .frame(maxWidth: .infinity).padding()
                .background(newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.green)
                .foregroundColor(.white).cornerRadius(12)
                .disabled(newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            HStack(spacing: 16) {
                Button(action: onPickImage) {
                    Label("选择图片", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity)
                }
                .padding().background(Color.blue.opacity(0.8)).foregroundColor(.white).cornerRadius(12)

                Button(action: onPickVideo) {
                    Label("选择视频", systemImage: "video").frame(maxWidth: .infinity)
                }
                .padding().background(Color.orange).foregroundColor(.white).cornerRadius(12)
            }

            if let img = selectedImage {
                Image(uiImage: img).resizable().scaledToFit()
                    .frame(maxHeight: 200).cornerRadius(12).shadow(radius: 5).padding(.vertical)
            }
        }
        .padding().background(Color(.systemGray6)).cornerRadius(15).padding(.top)
    }
}

// MARK: - InsertTextDialog
struct InsertTextDialog: View {
    @Binding var state: InsertTextDialogState
    var onInsert: (String) -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea().onTapGesture { state.hide() }
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .frame(width: 300, height: 200)
                .overlay(
                    VStack(spacing: 20) {
                        Text("插入文字").font(.headline)
                        TextField("请输入文字", text: $state.text)
                            .textFieldStyle(RoundedBorderTextFieldStyle()).padding(.horizontal)
                        HStack {
                            Button("取消") { state.hide() }
                            Spacer()
                            Button("插入") { onInsert(state.text); state.hide() }
                                .disabled(state.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .padding(.horizontal)
                        Spacer()
                    }
                    .padding(.top, 20)
                )
        }
    }
}

// MARK: - FullScreenPagerView
struct FullScreenPagerView: View {
    var images: [UIImage]
    @Binding var currentIndex: Int
    @Binding var isPresented: Bool
    @Binding var showSaveSuccess: Bool

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        TabView(selection: $currentIndex) {
            ForEach(images.indices, id: \.self) { idx in
                ZoomablePageImage(
                    image: images[idx],
                    scale: $scale, lastScale: $lastScale,
                    offset: $offset, lastOffset: $lastOffset
                )
                .tag(idx)
            }
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
        .background(Color.black.ignoresSafeArea())
        .overlay(
            VStack {
                HStack {
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28)).foregroundColor(.white).padding()
                    }
                    Spacer()
                    Button(action: {
                        if images.indices.contains(currentIndex) {
                            UIImageWriteToSavedPhotosAlbum(images[currentIndex], nil, nil, nil)
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            showSaveSuccess = true
                        }
                    }) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 24)).foregroundColor(.white).padding()
                    }
                }
                Spacer()
            }
        )
    }
}

// MARK: - ZoomablePageImage
struct ZoomablePageImage: View {
    let image: UIImage
    @Binding var scale: CGFloat
    @Binding var lastScale: CGFloat
    @Binding var offset: CGSize
    @Binding var lastOffset: CGSize

    var body: some View {
        Image(uiImage: image)
            .resizable().scaledToFit()
            .scaleEffect(scale).offset(offset)
            .gesture(
                scale > 1.0
                    ? DragGesture()
                        .onChanged { value in
                            offset = CGSize(width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height)
                        }
                        .onEnded { _ in lastOffset = offset }
                    : nil
            )
            .gesture(
                MagnificationGesture()
                    .onChanged { value in scale = lastScale * value }
                    .onEnded { _ in lastScale = scale }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
    }
}
