import SwiftUI

struct kp: View {
    @State private var isActive = false
    @State private var showUpdateAlert = false
    @State private var updateMessage = "加载更新内容中..."
    @State private var isFirstLaunch: Bool = !UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
    @State private var shouldExitOnDismiss = false
    @State private var launchStartTime = Date()
    
    @State private var backgroundImages: [String] = []
    @State private var selectedBackground: UIImage? = nil
    
    // 本地保存的图片版本号
    @State private var localImageVersion: String = UserDefaults.standard.string(forKey: "localImageVersion") ?? "0"
    
    // Loading 控制
    @State private var isLoading = false
    
    private let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("img")
    private let imgBaseUrl = "https://nuist.com.cn/"
    
    var body: some View {
        ZStack {
            if isActive {
                ContentView()
                    .background(
                        Group {
                            if let bg = selectedBackground {
                                Image(uiImage: bg)
                                    .resizable()
                                    .scaledToFill()
                                    .ignoresSafeArea()
                            } else {
                                Color.white
                            }
                        }
                    )
            } else {
                // 开屏界面
                ZStack {
                    // 背景
                    if let bg = selectedBackground {
                        Image(uiImage: bg)
                            .resizable()
                            .scaledToFill()
                            .ignoresSafeArea()
                    } else {
                        Color.white.ignoresSafeArea()
                    }
                    
                    // 前景内容（不会被背景挡住）
                    VStack {
                        Spacer()
                        
                        Text("lelegraph")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundColor(.black)
                            .shadow(radius: 10)
                            .padding(.bottom, 80)
                        
                        Spacer()
                        
                        VStack(spacing: 8) {
                            Button(action: {
                                if let url = URL(string: "https://github.com/Alice-Cartelet") {
                                    UIApplication.shared.open(url)
                                }
                            }) {
                                Text("Powered by Alice-Cartelet")
                                    .foregroundColor(.black)
                                    .font(.title3)
                            }
                        }
                        .padding()
                        .background(Color.white.opacity(0.7))
                        .cornerRadius(16)
                        .shadow(radius: 4)
                        .padding(.bottom, 20)
                    }
                }
            }
            
            // Loading覆盖层
            if isLoading {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                ProgressView("背景图片更新中，请稍候...")
                    .padding(24)
                    .background(Color.white)
                    .cornerRadius(12)
                    .shadow(radius: 10)
            }
        }
        .alert(isPresented: $showUpdateAlert) {
            Alert(
                title: Text("本软件有新版本"),
                message: Text(updateMessage),
                dismissButton: .default(Text("确定"), action: {
                    if shouldExitOnDismiss {
                        exit(0)
                    } else {
                        withAnimation {
                            isActive = true
                        }
                    }
                })
            )
        }
        .onAppear {
            launchStartTime = Date()
            createCacheDirIfNeeded()
            loadLocalBackgroundImages()
            selectRandomBackground()
            
            checkImageVersionAndUpdate {
                // 无论是否更新，更新完成后都进入主页面
                withAnimation {
                    isActive = true
                }
                
                if isFirstLaunch {
                    delayThenShowAlertOrMain(content: "本软件已更新3.4.1\n- 优化了内存加载方式，防止内存溢出。\n-改进了图片加载方式，保证图片加载的稳定性。\n")
                    UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
                    isFirstLaunch = false
                } else {
                    checkUpdate()
                }
            }
        }
    }
    
    func createCacheDirIfNeeded() {
        if !FileManager.default.fileExists(atPath: cacheDir.path) {
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }
    }
    
    func loadLocalBackgroundImages() {
        do {
            let files = try FileManager.default.contentsOfDirectory(atPath: cacheDir.path)
            backgroundImages = files.filter { $0.hasSuffix(".png") || $0.hasSuffix(".jpg") || $0.hasSuffix(".jpeg") }
        } catch {
            backgroundImages = []
        }
    }
    
    func selectRandomBackground() {
        guard !backgroundImages.isEmpty else { return }
        let randomName = backgroundImages.randomElement()!
        let fileUrl = cacheDir.appendingPathComponent(randomName)
        if let data = try? Data(contentsOf: fileUrl),
           let image = UIImage(data: data) {
            selectedBackground = image
        }
    }
    
    func checkImageVersionAndUpdate(completion: @escaping () -> Void) {
        guard let url = URL(string: imgBaseUrl + "in") else {
            completion()
            return
        }
        let task = URLSession.shared.dataTask(with: url) { data, _, error in
            guard error == nil,
                  let data = data,
                  let versionString = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                DispatchQueue.main.async { completion() }
                return
            }
            
            if versionString == "0" || versionString == localImageVersion {
                // 版本相同或0，不更新
                DispatchQueue.main.async { completion() }
            } else {
                DispatchQueue.main.async {
                    isLoading = true
                }
                fetchImageNamesAndDownload {
                    UserDefaults.standard.set(versionString, forKey: "localImageVersion")
                    localImageVersion = versionString
                    
                    DispatchQueue.main.async {
                        isLoading = false
                        completion()
                    }
                }
            }
        }
        task.resume()
    }
    
    func fetchImageNamesAndDownload(completion: @escaping () -> Void) {
        guard let url = URL(string: imgBaseUrl + "img") else {
            completion()
            return
        }
        let task = URLSession.shared.dataTask(with: url) { data, _, error in
            guard error == nil,
                  let data = data,
                  let imageNames = try? JSONDecoder().decode([String].self, from: data),
                  !imageNames.isEmpty else {
                completion()
                return
            }
            downloadAndCacheImages(named: imageNames, completion: completion)
        }
        task.resume()
    }
    
    func downloadAndCacheImages(named imageNames: [String], completion: @escaping () -> Void) {
        for oldFile in backgroundImages {
            let fileUrl = cacheDir.appendingPathComponent(oldFile)
            try? FileManager.default.removeItem(at: fileUrl)
        }
        
        let group = DispatchGroup()
        var downloadedImages = [String]()
        
        for imageName in imageNames {
            group.enter()
            let imageUrlString = imgBaseUrl + imageName
            guard let imageUrl = URL(string: imageUrlString) else {
                group.leave()
                continue
            }
            let destinationUrl = cacheDir.appendingPathComponent(imageName)
            let task = URLSession.shared.downloadTask(with: imageUrl) { localUrl, _, error in
                defer { group.leave() }
                guard error == nil, let localUrl = localUrl else { return }
                do {
                    try FileManager.default.moveItem(at: localUrl, to: destinationUrl)
                    downloadedImages.append(imageName)
                } catch {
                    try? FileManager.default.removeItem(at: destinationUrl)
                }
            }
            task.resume()
        }
        
        group.notify(queue: .main) {
            self.backgroundImages = downloadedImages
            if let first = downloadedImages.first {
                let fileUrl = cacheDir.appendingPathComponent(first)
                if let data = try? Data(contentsOf: fileUrl),
                   let img = UIImage(data: data) {
                    self.selectedBackground = img
                }
            }
            completion()
        }
    }
    
    func delayThenShowAlertOrMain(content: String) {
        let elapsed = Date().timeIntervalSince(launchStartTime)
        let delay = max(1.0 - elapsed, 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if content.isEmpty {
                withAnimation {
                    isActive = true
                }
            } else {
                updateMessage = content
                showUpdateAlert = true
            }
        }
    }
    
    func checkUpdate() {
        guard let url = URL(string: "https://nuist.com.cn/up") else {
            delayThenShowAlertOrMain(content: "")
            return
        }
        let task = URLSession.shared.dataTask(with: url) { data, _, error in
            guard error == nil, let data = data,
                  let responseString = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) else {
                DispatchQueue.main.async {
                    delayThenShowAlertOrMain(content: "")
                }
                return
            }
            if responseString == "1" {
                fetchUpdateText(forceExit: false)
            } else if responseString == "2" {
                fetchUpdateText(forceExit: true)
            } else {
                DispatchQueue.main.async {
                    delayThenShowAlertOrMain(content: "")
                }
            }
        }
        task.resume()
    }
    
    func fetchUpdateText(forceExit: Bool) {
        guard let url = URL(string: "https://nuist.com.cn/txt") else {
            DispatchQueue.main.async {
                delayThenShowAlertOrMain(content: "")
            }
            return
        }
        let task = URLSession.shared.dataTask(with: url) { data, _, error in
            var text = ""
            if let data = data, let fetchedText = String(data: data, encoding: .utf8) {
                text = fetchedText
            }
            DispatchQueue.main.async {
                shouldExitOnDismiss = forceExit
                delayThenShowAlertOrMain(content: text)
            }
        }
        task.resume()
    }
}
