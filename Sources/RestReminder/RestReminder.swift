import AppKit
import SwiftUI
import Foundation
import QuartzCore

// 图片缓存管理类
class ImageCacheManager: ObservableObject {
    static let shared = ImageCacheManager()
    @Published var cachedImage: NSImage?
    private let highResImageUrl = URL(string: "https://picsum.photos/3840/2160")!
    private var isLoading = false
    
    // 本地缓存文件路径
    private var cacheFilePath: URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsDirectory.appendingPathComponent("desktop_background_cache.jpg")
    }
    
    private init() {
        // 应用启动时先加载本地缓存
        loadCachedImageFromDisk()
        // 然后开始预加载新图片
        preloadImage()
    }
    
    // 从本地磁盘加载缓存图片
    private func loadCachedImageFromDisk() {
        if FileManager.default.fileExists(atPath: cacheFilePath.path) {
            if let image = NSImage(contentsOf: cacheFilePath) {
                cachedImage = image
            }
        }
    }
    
    // 保存图片到本地磁盘
    private func saveImageToDisk(_ image: NSImage) {
        if let tiffData = image.tiffRepresentation, let bitmapImage = NSBitmapImageRep(data: tiffData) {
            if let jpegData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
                do {
                    try jpegData.write(to: cacheFilePath, options: .atomic)
                } catch {
                    // 保存失败不影响应用运行
                }
            }
        }
    }
    
    // 预加载高清图片并缓存
    func preloadImage() {
        guard !isLoading else { return }
        isLoading = true
        
        let task = URLSession.shared.dataTask(with: highResImageUrl) { [weak self] data, response, error in            
            defer { self?.isLoading = false }
            
            guard let data = data, let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return
            }
            
            guard let image = NSImage(data: data) else { return }
            
            DispatchQueue.main.async {
                self?.cachedImage = image
                // 保存到本地磁盘，实现持久化缓存
                self?.saveImageToDisk(image)
            }
        }
        
        task.resume()
    }
    
    // 获取缓存图片，如果没有则返回nil
    func getCachedImage() -> NSImage? {
        return cachedImage
    }
}

// 全局状态管理
class AppState: ObservableObject, @unchecked Sendable {
    @Published var isRunning = true
    @Published var isPaused = false
    @Published var remainingTime: TimeInterval = 30.0 * 60.0
    @Published var showingReminder = false
    @Published var remainingReminderTime: TimeInterval = 0 // 提醒剩余时间倒计时
    @Published var inspirationalQuote: String = "来财来财来财～～" // 励志短语
    @Published var settings = Settings() {
        didSet {
            saveSettings()
            remainingTime = TimeInterval(settings.reminderInterval) * 60.0
        }
    }
    
    private var lastQuoteUpdateDate: Date = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date.distantPast // 上次更新励志短语的日期（设置为昨天，确保首次运行会更新）

    private var timer: DispatchSourceTimer?
    private var reminderTimeoutTimer: DispatchSourceTimer?
    private var reminderTimeout: TimeInterval = 300 // 5分钟后自动关闭提醒

    init() {
        loadSettings()
        startTimer()
        // 应用启动时就检查并更新励志短语
        // checkAndUpdateQuote()
    }

    func startTimer() {
        // 取消现有的定时器
        timer?.cancel()
        
        // 创建新的DispatchSourceTimer
        timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer?.schedule(deadline: .now(), repeating: .seconds(1))
        timer?.setEventHandler { [weak self] in
            guard let self = self, !self.isPaused else { return }

            if self.remainingTime > 0 {
                self.remainingTime -= 1
            } else {
                self.showReminder()
            }
        }
        
        // 启动定时器
        timer?.resume()
    }

    func resetTimer() {
        remainingTime = TimeInterval(settings.reminderInterval) * 60.0
        isPaused = false
        startTimer()
    }

    func pauseTimer() {
        isPaused.toggle()
    }

    func stopTimer() {
        isRunning = false
        timer?.cancel()
        timer = nil
    }

    func showReminder() {
        print("AppState.showReminder开始")
        // 检查是否需要跳过提醒
        if shouldSkipReminder() {
            print("AppState.showReminder: 跳过提醒")
            // 跳过提醒时应该重置计时器
            resetTimer()
            return
        }
        
        // 检查是否已经在显示提醒，如果是则跳过
        if showingReminder {
            print("AppState.showReminder: 已经在显示提醒，跳过")
            // 已经在显示提醒时，不应该重置计时器，避免冲突
            return
        }

        // 触发图片刷新
        ImageCacheManager.shared.preloadImage()
        
        print("AppState.showReminder: 设置showingReminder为true")
        showingReminder = true
        
        // 显示当前励志短语状态
        print("AppState.showReminder: 当前励志短语 = \(inspirationalQuote)")
        
        // 检查并更新励志短语
        // checkAndUpdateQuote()
        
        // 停止当前计时器，不再更新状态栏
        print("AppState.showReminder: 停止当前计时器")
        timer?.cancel()
        timer = nil
        
        // 设置超时自动关闭
        print("AppState.showReminder: 设置超时自动关闭")
        setupReminderTimeout()
        print("AppState.showReminder结束")
    }
    
    func dismissReminder() {
        showingReminder = false
        
        // 清除超时计时器
        clearReminderTimeout()
        
        print("AppState.dismissReminder: 全屏提醒已关闭")
        
        // 倒计时结束后重新开始新的一轮
        resetTimer()
    }
    
    // 停止计时 - 完全停止计时器
    func stopTimerCompletely() {
        print("AppState.stopTimerCompletely: 完全停止计时")
        timer?.cancel()
        timer = nil
        remainingTime = 0
        showingReminder = false
        clearReminderTimeout()
    }
    
    // 继续计时 - 由用户手动触发
    func continueTimer() {
        print("AppState.continueTimer: 继续计时")
        // 先退出全屏提醒
        showingReminder = false
        clearReminderTimeout()
        // 然后重置计时器
        resetTimer()
    }
    
    // 设置提醒超时
    private func setupReminderTimeout() {
        // 清除之前的计时器
        clearReminderTimeout()
        
        // 初始化剩余时间
        remainingReminderTime = reminderTimeout
        
        // 创建重复定时器，每秒更新倒计时
        reminderTimeoutTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        reminderTimeoutTimer?.schedule(deadline: .now(), repeating: .seconds(1))
        reminderTimeoutTimer?.setEventHandler { [weak self] in
            guard let self = self else { return }
            
            if self.remainingReminderTime > 0 {
                self.remainingReminderTime -= 1
            } else {
                print("提醒超时，自动关闭")
                self.dismissReminder()
            }
        }
        reminderTimeoutTimer?.resume()
    }
    
    // 清除提醒超时
    private func clearReminderTimeout() {
        reminderTimeoutTimer?.cancel()
        reminderTimeoutTimer = nil
        remainingReminderTime = 0
    }

    private func shouldSkipReminder() -> Bool {
        // 如果屏蔽功能未启用，不跳过提醒
        guard settings.isBlockingEnabled else {
            return false
        }
        
        // 检查当前前台应用是否在屏蔽列表中
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return settings.blockedApps.contains(frontmostApp)
    }

    func saveSettings() {
        // 使用UserDefaults保存设置
        UserDefaults.standard.set(settings.reminderInterval, forKey: "reminderInterval")
        UserDefaults.standard.set(settings.isBlockingEnabled, forKey: "isBlockingEnabled")
        UserDefaults.standard.set(settings.blockedApps, forKey: "blockedApps")
    }

    func loadSettings() {
        // 从UserDefaults加载设置
        var loadedSettings = Settings()
        
        if let isBlockingEnabled = UserDefaults.standard.object(forKey: "isBlockingEnabled") as? Bool {
            loadedSettings.isBlockingEnabled = isBlockingEnabled
        }
        if let blockedApps = UserDefaults.standard.object(forKey: "blockedApps") as? [String] {
            loadedSettings.blockedApps = blockedApps
        }
        if let reminderInterval = UserDefaults.standard.object(forKey: "reminderInterval") as? Int {
            loadedSettings.reminderInterval = reminderInterval
        }
        
        // 替换整个settings对象，触发didSet观察者
        settings = loadedSettings
        
        // 调试使用，这会覆盖didSet中设置的值
        #if DEBUG
        remainingTime = 3.0 // 调试模式下启用
        #endif
        
        // 恢复正常配置：5分钟后自动关闭提醒
        reminderTimeout = 300 // 5分钟后自动关闭提醒
    }
    
    func addBlockedApp(_ bundleIdentifier: String) {
        if !settings.blockedApps.contains(bundleIdentifier) {
            settings.blockedApps.append(bundleIdentifier)
        }
    }
    
    func removeBlockedApp(_ bundleIdentifier: String) {
        settings.blockedApps.removeAll { $0 == bundleIdentifier }
    }
    
    func isAppBlocked(_ bundleIdentifier: String) -> Bool {
        return settings.blockedApps.contains(bundleIdentifier)
    }
    
    // 检查是否需要更新励志短语（每天更新一次）
    private func shouldUpdateQuote() -> Bool {
        let currentDate = Date()
        let calendar = Calendar.current
        let needsUpdate = !calendar.isDate(lastQuoteUpdateDate, inSameDayAs: currentDate)
        print("励志短语更新检查: 当前日期 = \(currentDate), 上次更新日期 = \(lastQuoteUpdateDate), 是否需要更新 = \(needsUpdate)")
        return needsUpdate
    }
    
    // 本地备份励志短语列表（当API不可用时使用）
    private let backupQuotes = [
        "行动是成功的阶梯，行动越多，登得越高 —— 陈安之",
        "成功的秘诀在于坚持目标 —— 迪斯雷利",
        "每一次努力都是最优的亲近，每一滴汗水都是机遇的滋润 —— 佚名",
        "今天的付出，明天的收获 —— 佚名",
        "不为失败找理由，要为成功找方法 —— 佚名",
        "命运掌握在自己手中 —— 佚名",
        "只有想不到，没有做不到 —— 佚名",
        "成功来自坚持，执着创造奇迹 —— 佚名",
        "每天进步一点点，成功离你近一点 —— 佚名",
        "梦想不抛弃苦心追求的人，只要不停止追求，你们会沐浴在梦想的光辉之中 —— 佚名"
    ]
    
    // 异步获取新的励志短语
    private func fetchInspirationalQuote() async {
        print("开始获取新的励志短语...")
        // 使用hitokoto.cn中文一言API获取励志名言
        let apiUrl = "https://v1.hitokoto.cn/"
        guard let url = URL(string: apiUrl) else {
            print("无效的API URL: \(apiUrl)")
            useBackupQuote()
            return
        }
        
        print("正在发送API请求: \(url)")
        
        // 创建带有超时配置的URLSession
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10 // 10秒超时
        config.timeoutIntervalForResource = 15 // 15秒资源超时
        let session = URLSession(configuration: config)
        
        do {
            let (data, response) = try await session.data(from: url)
            print("API请求成功，响应数据大小: \(data.count) bytes")
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("API响应格式错误")
                useBackupQuote()
                return
            }
            
            print("API响应状态码: \(httpResponse.statusCode)")
            guard httpResponse.statusCode == 200 else {
                print("API请求失败，状态码: \(httpResponse.statusCode)")
                useBackupQuote()
                return
            }
            
            // 解析JSON响应 (hitokoto.cn格式)
            struct HitokotoResponse: Codable {
                let hitokoto: String // 名言内容
                let from: String? // 出处
                let from_who: String? // 作者
            }
            
            print("开始解析JSON响应...")
            let quoteResponse = try JSONDecoder().decode(HitokotoResponse.self, from: data)
            print("JSON解析成功: 内容 = \(quoteResponse.hitokoto), 出处/作者 = \(quoteResponse.from ?? quoteResponse.from_who ?? "未知")")
            
            // 组合新励志短语
            var newQuote = quoteResponse.hitokoto
            if let source = quoteResponse.from, !source.isEmpty {
                newQuote += " —— \(source)"
            } else if let author = quoteResponse.from_who, !author.isEmpty {
                newQuote += " —— \(author)"
            }
            print("生成新励志短语: \(newQuote)")
            
            // 更新励志短语和日期
            DispatchQueue.main.async {
                print("更新励志短语，旧值: \(self.inspirationalQuote), 新值: \(newQuote)")
                self.inspirationalQuote = newQuote
                self.lastQuoteUpdateDate = Date()
                print("励志短语更新完成，新的更新日期: \(self.lastQuoteUpdateDate)")
            }
        } catch let error as URLError {
            print("获取励志短语网络错误: \(error.localizedDescription), 错误代码: \(error.code)")
            useBackupQuote()
        } catch let error as DecodingError {
            print("获取励志短语解析错误: \(error.localizedDescription)")
            // 尝试打印响应数据
            do {
                let (debugData, _) = try await session.data(from: url)
                let responseString = String(data: debugData, encoding: .utf8) ?? "无法解析响应数据"
                print("原始响应数据: \(responseString)")
            } catch {
                print("调试数据获取失败: \(error.localizedDescription)")
            }
            useBackupQuote()
        } catch {
            print("获取励志短语失败: \(error.localizedDescription)")
            useBackupQuote()
        }
    }
    
    // 使用本地备份励志短语
    private func useBackupQuote() {
        print("使用本地备份励志短语...")
        let randomIndex = Int.random(in: 0..<backupQuotes.count)
        let backupQuote = backupQuotes[randomIndex]
        print("选择备份短语: \(backupQuote)")
        
        DispatchQueue.main.async {
            self.inspirationalQuote = backupQuote
            self.lastQuoteUpdateDate = Date()
            print("励志短语已更新为备份短语，新的更新日期: \(self.lastQuoteUpdateDate)")
        }
    }
    
    // 检查并更新励志短语（如果需要）
    func checkAndUpdateQuote() {
        print("开始检查励志短语更新...")
        if shouldUpdateQuote() {
            print("正在更新励志短语...")
            Task {
                await fetchInspirationalQuote()
            }
        } else {
            print("励志短语无需更新，当前短语: \(inspirationalQuote)")
        }
    }
}

// 设置结构
struct Settings {
    var reminderInterval: Int = 1 // 分钟
    var isBlockingEnabled: Bool = true // 是否启用应用屏蔽
    var blockedApps: [String] = [] // 空默认列表，由用户手动添加
}

// 主应用
@main
class RestReminderMain {
    static func main() {
        // 启动应用
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate

        // 运行应用
        app.run()
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!

    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("RestReminder 应用已启动")

        // 创建状态栏项
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // 创建菜单
        createMenu()

        // 初始化状态栏显示
        updateStatusBar(time: appState.remainingTime)

        // 监听提醒状态变化
        appState.$showingReminder
            .sink {[weak self] showing in
                print("提醒状态变化: \(showing)")
                if showing {
                    self?.showFullScreenReminder()
                } else {
                    self?.dismissFullScreenReminder()
                }
            }
            .store(in: &cancellables)

        // 监听时间变化，更新状态栏
        appState.$remainingTime
            .sink {[weak self] time in
                self?.updateStatusBar(time: time)
            }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    @MainActor
    private func createMenu() {
        menu = NSMenu()

        // 添加菜单项
        let resetItem = NSMenuItem(title: "重新计时", action: #selector(resetTimer), keyEquivalent: "")
        resetItem.target = self
        menu.addItem(resetItem)

        let pauseTitle = appState.isPaused ? "继续计时" : "暂停计时"
        let pauseItem = NSMenuItem(title: pauseTitle, action: #selector(pauseTimer), keyEquivalent: "")
        pauseItem.target = self
        menu.addItem(pauseItem)

        let startRestItem = NSMenuItem(title: "开始休息", action: #selector(startRest), keyEquivalent: "")
        startRestItem.target = self
        menu.addItem(startRestItem)

        // 添加提醒间隔子菜单
        let intervalMenu = NSMenu(title: "提醒间隔")

        // 常用时间选项
        let timeOptions = [5, 10, 15, 20, 25, 30, 45, 60]
        for minutes in timeOptions {
            let item = NSMenuItem(
                title: "\(minutes) 分钟",
                action: #selector(setReminderInterval(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = minutes
            // 添加勾选标记
            if minutes == appState.settings.reminderInterval {
                item.state = .on
            }
            intervalMenu.addItem(item)
        }

        // 添加自定义时间选项
        let customItem = NSMenuItem(title: "自定义...", action: #selector(showCustomIntervalDialog), keyEquivalent: "")
        customItem.target = self
        intervalMenu.addItem(NSMenuItem.separator())
        intervalMenu.addItem(customItem)

        // 将子菜单添加到主菜单
        let intervalMenuItem = NSMenuItem(title: "提醒间隔", action: nil, keyEquivalent: "")
        intervalMenuItem.submenu = intervalMenu
        menu.addItem(intervalMenuItem)

        // 添加设置菜单项
        let settingsItem = NSMenuItem(title: "设置", action: #selector(showSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        // 设置状态栏按钮
        if let button = statusItem.button {
            // 设置标题（只显示时间，不显示emoji）
            
            // 使用等宽字体，避免宽度变化
            let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            button.font = font
            
            // 微调垂直位置的偏移量（正数向下，负数向上）
            let verticalOffset: CGFloat = -5.0
            
            // 创建带有基线偏移的富文本
            let attributedString = NSMutableAttributedString(string: "--:--")
            attributedString.addAttribute(.font, value: font, range: NSRange(location: 0, length: attributedString.length))
            attributedString.addAttribute(.baselineOffset, value: verticalOffset, range: NSRange(location: 0, length: attributedString.length))
            button.attributedTitle = attributedString
            
            // 简化图标配置，使用与文字匹配的大小
            let symbolConfig = NSImage.SymbolConfiguration(
                pointSize: 18, 
                weight: .regular
            )
            
            let image = NSImage(systemSymbolName: "hourglass", accessibilityDescription: "Rest Reminder")
            button.image = image?.withSymbolConfiguration(symbolConfig)
            button.imagePosition = .imageLeft

            // 使用默认的缩放和对齐，让系统处理垂直居中
            button.alignment = .center

            // 确保按钮可见
            button.isHidden = false

            // 设置目标和动作
            button.target = self
        }

        // 设置状态栏项的菜单
        statusItem.menu = menu

        print("菜单创建完成")
    }

    // 设置提醒间隔
    @objc @MainActor private func setReminderInterval(_ sender: NSMenuItem) {
        if let minutes = sender.representedObject as? Int {
            appState.settings.reminderInterval = minutes
            // 更新菜单勾选状态
            createMenu()
        }
    }

    // 显示自定义时间对话框
    @objc @MainActor private func showCustomIntervalDialog() {
        let alert = NSAlert()
        alert.messageText = "设置自定义提醒间隔"
        alert.informativeText = "请输入分钟数："

        // 添加输入框
        let inputTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        inputTextField.stringValue = "\(appState.settings.reminderInterval)"
        inputTextField.placeholderString = "输入分钟数"
        inputTextField.bezelStyle = .roundedBezel
        alert.accessoryView = inputTextField

        // 添加按钮
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")

        // 运行对话框
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // 处理输入
            if let minutes = Int(inputTextField.stringValue), minutes > 0 {
                appState.settings.reminderInterval = minutes
                // 更新菜单
                createMenu()
            }
        }
    }
    
    // 显示设置窗口
    @objc @MainActor private func showSettings() {
        // 创建SwiftUI视图
        let settingsView = SettingsView(appState: appState)
        
        // 设置窗口尺寸
        let windowWidth: CGFloat = 400
        let windowHeight: CGFloat = 360
        
        // 创建窗口
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        // 设置窗口属性
        window.title = "休息提醒设置"
        window.isReleasedWhenClosed = false
        window.level = .floating
        
        // 创建宿主控制器
        let hostingController = NSHostingController(rootView: settingsView)
        window.contentViewController = hostingController
        
        // 在当前屏幕中央显示窗口
        centerWindowOnCurrentScreen(window)
        
        // 显示窗口并确保它在最前面
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // 将窗口居中显示在当前屏幕（鼠标所在屏幕）
    private func centerWindowOnCurrentScreen(_ window: NSWindow) {
        // 获取当前鼠标位置
        let mouseLocation = NSEvent.mouseLocation
        
        // 查找包含鼠标位置的屏幕
        var currentScreen: NSScreen?
        for screen in NSScreen.screens {
            if screen.frame.contains(mouseLocation) {
                currentScreen = screen
                break
            }
        }
        
        // 如果找不到，使用主屏幕
        guard let screen = currentScreen ?? NSScreen.main else {
            window.center()
            return
        }
        
        // 计算屏幕中央位置
        let screenCenter = NSPoint(
            x: screen.frame.midX,
            y: screen.frame.midY
        )
        
        // 设置窗口位置（窗口中心对准屏幕中心）
        let windowFrame = window.frame
        let windowOrigin = NSPoint(
            x: screenCenter.x - windowFrame.width / 2,
            y: screenCenter.y - windowFrame.height / 2
        )
        
        window.setFrameOrigin(windowOrigin)
    }
    
    // 获取当前运行的应用列表
    private func getRunningApps() -> [(name: String, bundleId: String)] {
        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications
        
        return runningApps.compactMap { app in
            guard let bundleId = app.bundleIdentifier, let name = app.localizedName else {
                return nil
            }
            return (name: name, bundleId: bundleId)
        }.sorted { $0.name < $1.name }
    }
    
    // 切换应用屏蔽状态
    @objc @MainActor private func toggleAppBlock(_ sender: NSMenuItem) {
        if let bundleId = sender.representedObject as? String {
            if appState.isAppBlocked(bundleId) {
                appState.removeBlockedApp(bundleId)
                sender.state = .off
            } else {
                appState.addBlockedApp(bundleId)
                sender.state = .on
            }
        }
    }

    @objc func stopTimer() {
        appState.stopTimer()
    }

    @MainActor
    private func updateStatusBar(time: TimeInterval) {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let timeString = String(format: "%02d:%02d", minutes, seconds)

        if let button = statusItem.button {
            // 使用等宽字体，避免宽度变化
            let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            
            // 微调垂直位置的偏移量（正数向下，负数向上）
            let verticalOffset: CGFloat = -1.0
            
            // 创建带有基线偏移的富文本
            let attributedString = NSMutableAttributedString(string: timeString)
            attributedString.addAttribute(.font, value: font, range: NSRange(location: 0, length: attributedString.length))
            attributedString.addAttribute(.baselineOffset, value: verticalOffset, range: NSRange(location: 0, length: attributedString.length))
            button.attributedTitle = attributedString
            
            // 确保按钮可见
            button.isHidden = false
        }

        print("状态栏更新: \(timeString)")
    }
    
    @MainActor
    private func showFullScreenReminder() {
        // 检查是否已经有提醒窗口，避免重复创建
        if !reminderWindows.isEmpty {
            print("提醒窗口已存在，跳过创建")
            return
        }
        
        print("开始显示全屏提醒")
        
        // 为每个屏幕创建全屏窗口
        for (index, screen) in NSScreen.screens.enumerated() {
            print("为屏幕 \(index+1) 创建窗口，尺寸：\(screen.frame)")

            // 使用更简单的方式创建窗口
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: true,
                screen: screen
            )

            // 设置窗口属性
            window.level = .screenSaver
            window.backgroundColor = NSColor.clear
            window.isOpaque = false
            window.isMovable = false
            window.isReleasedWhenClosed = false  // 避免窗口被过早释放
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenPrimary]
            window.ignoresMouseEvents = false

            // 创建SwiftUI视图控制器
            let contentView = ReminderView(
                appState: self.appState,
                continueAction: {
                    Task {
                        @MainActor in
                        self.appState.continueTimer()
                    }
                },
                stopAction: {
                    Task {
                        @MainActor in
                        self.appState.stopTimerCompletely()
                    }
                }
            )
            let hostingController = NSHostingController(rootView: contentView)
            window.contentViewController = hostingController

            // 设置窗口显示
            window.makeKeyAndOrderFront(nil)
            window.setFrame(screen.frame, display: true, animate: false)

            // 存储窗口
            reminderWindows.append(window)
            print("窗口 \(index+1) 创建完成")
        }
        print("全屏提醒显示完成")
    }
    
    private var reminderWindows = [NSWindow]()
    
    @MainActor
    private func dismissFullScreenReminder() {
        print("开始关闭全屏提醒")
        // 遍历窗口数组，关闭每个窗口
        for window in reminderWindows {
            // 移除窗口的内容视图控制器，确保资源释放
            window.contentViewController = nil
            // 关闭窗口
            window.close()
            // 释放窗口资源
            window.orderOut(nil)
        }
        // 清空窗口数组，确保所有窗口引用都被释放
        reminderWindows.removeAll(keepingCapacity: false)
        print("全屏提醒关闭完成")
        // 强制垃圾回收，释放所有不再引用的对象
        autoreleasepool {
            // 空的自动释放池，强制释放所有自动释放的对象
        }
    }
    
    // 菜单操作
    @objc func resetTimer() {
        appState.resetTimer()
    }

    @objc func pauseTimer() {
        appState.pauseTimer()
    }

    @objc func startRest() {
        appState.showReminder()
    }

    @objc @MainActor
    func quit() {
        print("收到退出请求，开始清理资源")
        
        // 强制关闭任何可能存在的提醒
        appState.showingReminder = false
        
        // 停止计时器
        appState.stopTimer()
        
        // 关闭所有窗口
        dismissFullScreenReminder()
        
        // 立即退出，不等待异步操作
        print("资源清理完成，退出应用")
        NSApplication.shared.terminate(nil)
    }
}

// 标签页类型
enum SettingsTab {
    case general
    case blocking
}

// 设置视图
struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            // 标签页导航
            HStack(spacing: 0) {
                Button(action: { selectedTab = .general }) {
                    HStack(spacing: 8) {
                        Image(systemName: "gear")
                        Text("通用")
                    }
                    .padding()
                    .frame(height: 44)
                    .frame(maxWidth: .infinity)
                    .background(selectedTab == .general ? Color.blue : Color.clear)
                    .foregroundColor(selectedTab == .general ? Color.white : Color.primary)
                }
                .buttonStyle(.borderless)
                .contentShape(Rectangle())

                Button(action: { selectedTab = .blocking }) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock")
                        Text("屏蔽")
                    }
                    .padding()
                    .frame(height: 44)
                    .frame(maxWidth: .infinity)
                    .background(selectedTab == .blocking ? Color.blue : Color.clear)
                    .foregroundColor(selectedTab == .blocking ? Color.white : Color.primary)
                }
                .buttonStyle(.borderless)
                .contentShape(Rectangle())
            }

            // 标签页内容 - 使用条件渲染替代TabView，移除默认指示器
            if selectedTab == .general {
                GeneralSettingsView(appState: appState)
            } else {
                BlockingSettingsView(appState: appState)
            }
        }
        .frame(width: 400, height: 360)
    }
}

// 通用设置视图
struct GeneralSettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("休息提醒设置")
                .font(.title2)
                .fontWeight(.bold)

            HStack {
                Text("提醒间隔：")
                    .frame(width: 80, alignment: .trailing)
                TextField("分钟", value: $appState.settings.reminderInterval, formatter: NumberFormatter())
                    .frame(width: 120)
                    .textFieldStyle(.roundedBorder)
                Text("分钟")
            }
            .padding(.leading, 20)

            Spacer()

            HStack(spacing: 16) {
                Button("重置计时") {
                    appState.resetTimer()
                }
                .buttonStyle(.bordered)

                Button(appState.isPaused ? "继续" : "暂停") {
                    appState.pauseTimer()
                }
                .buttonStyle(.bordered)

                Button("退出") {
                    Task {
                        @MainActor in
                        NSApplication.shared.terminate(nil)
                    }
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding()
    }
}

// 屏蔽设置视图
struct BlockingSettingsView: View {
    @ObservedObject var appState: AppState
    @State private var runningApps: [(name: String, bundleId: String)] = []
    @State private var showingAddAppDialog = false

    var body: some View {
        VStack(spacing: 0) {
            // 屏蔽开关
            HStack {
                Text("应用屏蔽")
                    .font(.headline)
                Spacer()
                Toggle("", isOn: $appState.settings.isBlockingEnabled)
                    .toggleStyle(SwitchToggleStyle())
            }
            .padding()

            // 已配置的屏蔽应用列表
            VStack {
                if appState.settings.blockedApps.isEmpty {
                    Text("暂无屏蔽应用，请点击添加按钮添加")
                        .font(.caption)
                        .foregroundColor(.gray)
                } else {
                    List(appState.settings.blockedApps, id: \.self) { bundleId in
                        HStack {
                            // 尝试获取应用图标和名称
                            if let appInfo = getAppInfo(from: bundleId) {
                                Image(nsImage: appInfo.icon)
                                    .resizable()
                                    .frame(width: 24, height: 24)
                                Text("\(appInfo.name)(\(bundleId))")
                                    .lineLimit(1)
                            } else {
                                Text(bundleId)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button(action: { removeBlockedApp(bundleId) }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                    .frame(width: 20, height: 20)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal)

            // 按钮栏
            HStack {
                Button(action: { 
                    refreshRunningApps()
                    showingAddAppDialog = true
                }) {
                    Image(systemName: "plus")
                    Text("添加应用")
                }
                .buttonStyle(.bordered)
                .sheet(isPresented: $showingAddAppDialog) {
                    AddAppSheet(
                        runningApps: runningApps,
                        blockedApps: $appState.settings.blockedApps,
                        onDismiss: { showingAddAppDialog = false }
                    )
                }

                Spacer()

                Button(action: { refreshRunningApps() }) {
                    Image(systemName: "arrow.clockwise")
                    Text("刷新")
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .onAppear {
            refreshRunningApps()
        }
    }

    // 获取应用信息
    private func getAppInfo(from bundleId: String) -> (name: String, icon: NSImage)? {
        // 尝试从已运行的应用中获取信息
        let workspace = NSWorkspace.shared
        if let app = workspace.runningApplications.first(where: { $0.bundleIdentifier == bundleId }) {
            if let name = app.localizedName, let icon = app.icon {
                return (name: name, icon: icon)
            }
        }
        
        // 尝试从已安装的应用中获取信息
        if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleId) {
            let name = appURL.lastPathComponent.replacingOccurrences(of: ".app", with: "")
            let icon = workspace.icon(forFile: appURL.path)
            return (name: name, icon: icon)
        }
        
        return nil
    }

    // 刷新运行中的应用列表
    private func refreshRunningApps() {
        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications
        
        self.runningApps = runningApps.compactMap { app in
            guard let bundleId = app.bundleIdentifier, let name = app.localizedName else {
                return nil
            }
            return (name: name, bundleId: bundleId)
        }.sorted { $0.name < $1.name }
    }

    // 移除屏蔽应用
    private func removeBlockedApp(_ bundleId: String) {
        appState.settings.blockedApps.removeAll { $0 == bundleId }
    }
}

// 添加应用弹窗
struct AddAppSheet: View {
    let runningApps: [(name: String, bundleId: String)]
    @Binding var blockedApps: [String]
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 弹窗标题
            HStack {
                Text("添加屏蔽应用")
                    .font(.headline)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color.gray.opacity(0.1))

            // 应用列表
            List(runningApps, id: \.bundleId) { app in
                HStack {
                    // 正确获取应用图标 - 使用应用URL或默认图标
                    Image(nsImage: {
                        let workspace = NSWorkspace.shared
                        if let appURL = workspace.urlForApplication(withBundleIdentifier: app.bundleId) {
                            return workspace.icon(forFile: appURL.path)
                        } else {
                            // 默认图标
                            return NSImage(named: NSImage.applicationIconName) ?? NSImage()
                        }
                    }())
                        .resizable()
                        .frame(width: 24, height: 24)
                    Text("\(app.name)(\(app.bundleId))")
                        .lineLimit(1)
                    Spacer()
                    if !blockedApps.contains(app.bundleId) {
                        Button(action: { addBlockedApp(app.bundleId) }) {
                            Text("添加")
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Text("已添加")
                            .foregroundColor(.gray)
                    }
                }
            }
            .listStyle(.plain)
        }
        .frame(width: 400, height: 360)
    }

    // 添加到屏蔽列表
    private func addBlockedApp(_ bundleId: String) {
        if !blockedApps.contains(bundleId) {
            blockedApps.append(bundleId)
        }
    }
}

// 桌面背景视图
struct DesktopBackgroundView: NSViewRepresentable {
    @ObservedObject private var imageCache = ImageCacheManager.shared
    
    class Coordinator {
        // 用于存储Combine订阅
        var cancellables = Set<AnyCancellable>()
        // 不需要weak修饰符，因为Coordinator的生命周期与NSView一致
        var view: NSView?
        
        // 观察缓存图片变化
        func observeCacheChanges(imageCache: ImageCacheManager) {
            imageCache.$cachedImage
                .sink { [weak self] newImage in
                    guard let self = self, let view = self.view, let image = newImage else { return }
                    DispatchQueue.main.async {
                        // 添加过渡动画
                        let transition = CATransition()
                        transition.type = .fade
                        transition.duration = 0.5
                        transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                        view.layer?.add(transition, forKey: "contentsTransition")
                        
                        // 只有在4K图片成功加载后，才替换桌面背景
                        view.layer?.contents = image
                        view.layer?.contentsGravity = .resizeAspectFill
                        view.layer?.backgroundColor = nil // 移除背景色，使用图片
                    }
                }
                .store(in: &self.cancellables)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator()
    }
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        
        // 首先始终使用桌面背景作为初始背景
        useLocalBackupBackground(view: view)
        
        // 如果已经有缓存的4K图片，立即替换
        if let cachedImage = imageCache.getCachedImage() {
            view.layer?.contents = cachedImage
            view.layer?.contentsGravity = .resizeAspectFill
            view.layer?.backgroundColor = nil // 移除背景色，使用图片
        } else {
            // 在后台继续预加载4K图片，以便下次使用
            imageCache.preloadImage()
        }
        
        // 更新Coordinator的view引用并设置缓存图片变化监听
        context.coordinator.view = view
        context.coordinator.observeCacheChanges(imageCache: imageCache)
        
        return view
    }
    
    // 使用本地备份方案（AppleScript获取桌面背景）作为备选
    private func useLocalBackupBackground(view: NSView) {
        // 直接使用桌面背景作为默认背景
        var desktopImage: NSImage?
        
        // 使用AppleScript获取桌面背景
        let script = "tell application \"System Events\" to get picture of desktop 1"
        var error: NSDictionary?
        
        if let scriptObject = NSAppleScript(source: script) {
            let output = scriptObject.executeAndReturnError(&error)
            
            if error == nil, let filePath = output.stringValue, filePath != "" {
                // 尝试加载桌面背景图片
                desktopImage = NSImage(contentsOfFile: filePath)
            }
        }
        
        // 如果成功获取到桌面背景图片，使用它
        if let image = desktopImage {
            view.layer?.contents = image
            view.layer?.contentsGravity = .resizeAspectFill
            view.layer?.backgroundColor = nil // 移除背景色，使用图片
        } else {
            // 最后的备选：黑色背景
            view.layer?.backgroundColor = NSColor.black.cgColor
            view.layer?.contents = nil
        }
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // 不需要更新逻辑
    }
}

// 自定义透明按钮 - 显示手指鼠标指针和悬停效果
struct HandCursorButton: NSViewRepresentable {
    let title: String
    let systemImage: String
    let action: () -> Void
    
    func makeNSView(context: Context) -> CustomButton {
        CustomButton(title: title, systemImage: systemImage, action: action)
    }
    
    func updateNSView(_ nsView: CustomButton, context: Context) {
        // 不需要更新
    }
}

// 自定义按钮内容视图 - 精确控制图标和文字布局
class ButtonContentView: NSView {
    private let imageView: NSImageView
    private let label: NSTextField
    
    init(title: String, systemImage: String) {
        // 创建图标视图
        imageView = NSImageView()
        
        // 使用 NSImageSymbolConfiguration 来正确设置系统图标的大小
        if let image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title) {
            let config = NSImage.SymbolConfiguration(pointSize: 32, weight: .regular)
            let largeImage = image.withSymbolConfiguration(config)
            imageView.image = largeImage
        }
        imageView.contentTintColor = .white
        imageView.imageScaling = .scaleNone
        
        // 创建文字标签 - 保持原来的大小
        label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 14) 
        label.textColor = .white
        label.alignment = .center
        
        super.init(frame: .zero)
        
        // 添加子视图
        addSubview(imageView)
        addSubview(label)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // 重写布局方法，确保图标和文字在按钮内垂直居中
    override func layout() {
        super.layout()
        
        // 确保按钮内容视图的尺寸与按钮一致
        self.frame = bounds
        
        let imageHeight = imageView.intrinsicContentSize.height
        let labelHeight = label.intrinsicContentSize.height
        
        // 如果标题为空，只显示图标并居中
        if label.stringValue.isEmpty {
            // 设置图标位置（水平和垂直居中）
            imageView.frame = NSRect(
                x: (frame.width - imageView.intrinsicContentSize.width) / 2, // 水平居中
                y: (55 - imageHeight) / 2, // 垂直居中
                width: imageView.intrinsicContentSize.width,
                height: imageHeight
            )
            
            // 隐藏文字
            label.isHidden = true
        } else {
            // 同时显示图标和文字的情况
            let spacing: CGFloat = 8 // 图标和文字之间的间距
            let totalHeight = imageHeight + labelHeight + spacing
            
            // 计算垂直居中的起始位置（按钮高度60px，居中对齐）
            let startY = (55 - totalHeight) / 2
            
            // 设置图标位置（水平居中，垂直居中对齐）
            imageView.frame = NSRect(
                x: (frame.width - imageView.intrinsicContentSize.width) / 2, // 水平居中
                y: startY + labelHeight + spacing, // 文字上方
                width: imageView.intrinsicContentSize.width,
                height: imageHeight
            )
            
            // 设置文字位置（水平居中，垂直居中对齐）
            label.frame = NSRect(
                x: 0,
                y: startY, // 从起始位置开始
                width: frame.width,
                height: labelHeight
            )
            
            // 显示文字
            label.isHidden = false
        }
    }
}

// 自定义 NSButton 子类，实现手指指针和透明背景
class CustomButton: NSButton {
    private let buttonAction: () -> Void // 重命名为 buttonAction，避免与 NSButton.action 冲突
    private let originalBackgroundColor: NSColor = .clear
    private let hoverBackgroundColor: NSColor = .clear // 去除悬停背景色
    private let contentView: ButtonContentView // 存储内容视图引用
    
    init(title: String, systemImage: String, action: @escaping () -> Void) {
        self.buttonAction = action
        
        // 创建自定义内容视图
        contentView = ButtonContentView(title: title, systemImage: systemImage)
        
        super.init(frame: NSRect(x: 0, y: 0, width: 60, height: 60))
        
        // 基本配置
        self.setButtonType(.momentaryPushIn)
        self.isBordered = false // 无边框，透明背景
        self.wantsLayer = true
        self.layer?.backgroundColor = originalBackgroundColor.cgColor
        self.layer?.cornerRadius = 8 // 添加圆角
        
        // 确保不显示默认的"Button"文本
        self.title = "" // 设置为空字符串
        if let cell = self.cell as? NSButtonCell {
            cell.title = "" // 同时设置cell的标题为空
        }
        
        // 使用自定义视图来精确控制图标和文字布局
        addSubview(contentView)
        
        // 设置目标和动作
        self.target = self
        self.action = #selector(buttonClicked)
        
        // 立即添加鼠标跟踪区域
        setupTrackingArea()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // 按钮点击事件
    @objc private func buttonClicked() {
        buttonAction()
    }
    
    // 设置鼠标跟踪区域
    private func setupTrackingArea() {
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }
    
    // 重写 mouseEntered 方法，显示手指指针和背景变化
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        NSCursor.pointingHand.set() // 显示手指指针
        self.layer?.backgroundColor = hoverBackgroundColor.cgColor // 背景变化
    }
    
    // 重写 mouseExited 方法，恢复默认状态
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        NSCursor.arrow.set() // 恢复默认指针
        self.layer?.backgroundColor = originalBackgroundColor.cgColor // 恢复背景
    }
    
    // 重写 mouseDown 方法，不添加点击效果
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        // 不改变背景色
    }
    
    // 重写 mouseUp 方法，不改变背景状态
    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        // 不改变背景色
    }
    
    // 确保按钮能接收鼠标事件
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(self.bounds, cursor: NSCursor.pointingHand) // 直接添加指针矩形
    }
    
    // 确保按钮能接收鼠标进入/退出事件
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // 重新添加跟踪区域
        setupTrackingArea()
    }
    
    // 重写此方法确保按钮能接收鼠标事件
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
    
    // 重写布局方法，确保内容视图也被正确布局
    override func layout() {
        super.layout()
        self.contentView.frame = bounds
    }
}

// 全屏提醒视图 - 简化实现，避免内存管理问题
struct ReminderView: View {
    @ObservedObject var appState: AppState
    let continueAction: () -> Void
    let stopAction: () -> Void
    
    // 控制二级菜单显示
    @State private var showingMenu = false
    // 呼吸灯动画透明度
    @State private var buttonOpacity = 0.3
    // 控制呼吸动画的计时器
    @State private var timer: Timer? = nil
    // 控制呼吸动画的方向（true: 淡入, false: 淡出）
    @State private var isFadingIn = true
    // 控制是否启用呼吸动画
    @State private var isBreathingEnabled = true
    
    // 计算阴影效果：根据透明度动态计算白色光晕强度
    private var buttonShadow: (color: Color, radius: CGFloat) {
        // 当透明度越高时，白色光晕越强
        let shadowOpacity = buttonOpacity * 0.5 // 光晕透明度范围：0.1到0.5
        let shadowRadius = buttonOpacity * 8.0 // 光晕半径范围：1.6到8.0
        return (color: Color.white.opacity(shadowOpacity), radius: shadowRadius)
    }
    
    // 将秒转换为分:秒格式
    var formattedTime: String {
        let minutes = Int(appState.remainingReminderTime) / 60
        let seconds = Int(appState.remainingReminderTime) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    // 启动呼吸动画
    private func startBreathingAnimation() {
        isBreathingEnabled = true
        isFadingIn = true
        buttonOpacity = 0.3 // 设置初始透明度
        
        // 清除现有的计时器
        timer?.invalidate()
        
        // 创建新的计时器，每50毫秒更新一次透明度
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            if self.isBreathingEnabled {
                if self.isFadingIn {
                    // 淡入效果
                    self.buttonOpacity += 0.02
                    if self.buttonOpacity >= 1.0 {
                        self.buttonOpacity = 1.0
                        self.isFadingIn = false
                    }
                } else {
                    // 淡出效果
                    self.buttonOpacity -= 0.02
                    if self.buttonOpacity <= 0.2 { // 降低初始透明度，增强呼吸效果
                        self.buttonOpacity = 0.2
                        self.isFadingIn = true
                    }
                }
            }
        }
    }
    
    // 停止呼吸动画
    private func stopBreathingAnimation() {
        isBreathingEnabled = false
        // 立即将透明度设置为1.0
        buttonOpacity = 1.0
        // 清除计时器
        timer?.invalidate()
    }
    
    var body: some View {
        ZStack {
            // 使用桌面背景
            DesktopBackgroundView()
                .opacity(1) 

            // 半透明遮罩 
            Color.black.opacity(0.2)
                // 添加透明背景来捕获所有点击事件，避免崩溃
                .contentShape(Rectangle())
                .onTapGesture {
                    // 点击非菜单区域关闭二级菜单
                    showingMenu = false
                }

            ZStack {
                // 主要内容居中显示
                VStack(spacing: 10) {

                    // 主标题 - 只保留阴影效果提高可读性
                    Text("☕ 喝口水～活动一下～")
                        .font(.system(size: 66, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .shadow(color: .black, radius: 8, x: 0, y: 0)

                    // 倒计时显示 - 只保留阴影效果
                    Text(formattedTime)
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.top, 100)
                        .padding(.bottom, 0)
                        .shadow(color: .black, radius: 6, x: 0, y: 0)

                    // 按钮组 - 居中分布
                    HStack(spacing: 40) {
                        // 停止按钮 - 使用圆圈+X图标
                        HandCursorButton(
                            title: "", // 空标题，只显示图标
                            systemImage: "xmark.circle",
                            action: {
                                // 显示二级菜单
                                showingMenu.toggle()
                            }
                        )
                        .frame(width: 55, height: 55) 
                        .padding(.top, 0)
                        .opacity(buttonOpacity)
                        .shadow(color: buttonShadow.color, radius: buttonShadow.radius, x: 0, y: 0) // 添加动态白色光晕效果
                        .shadow(color: .black, radius: 6, x: 0, y: 0) // 添加黑色阴影，效果同文字
                        .onAppear {
                            // 启动呼吸动画
                            startBreathingAnimation()
                        }
                        .onHover {
                            if $0 {
                                // 鼠标进入时，停止呼吸动画
                                stopBreathingAnimation()
                            } else {
                                // 鼠标离开时，重新开始呼吸动画
                                startBreathingAnimation()
                            }
                        }
                        .onDisappear {
                            // 视图消失时，清除计时器
                            timer?.invalidate()
                        }
                    }
                }
                
                // 二级菜单 - 精确定位在停止按钮下方
                if showingMenu {
                    // 使用GeometryReader和定位将菜单准确放置在停止按钮下方
                    GeometryReader {geometry in
                        ZStack {
                            // 将菜单定位在屏幕中心下方，正好是停止按钮的位置
                            VStack(spacing: 0) {
                                // 三角形指示器
                                Triangle()
                                    .fill(Color.gray)
                                    .frame(width: 20, height: 10)
                                    .offset(y: 5) // 调整三角形位置，使其与菜单顶部对齐
                                
                                // 菜单项 - 固定宽度200px
                                VStack(spacing: 0) {
                                    MenuItem(title: "适时休息，重获专注")
                                        .foregroundColor(.white)
                                        .background(Color.gray)
                                        .disabled(true)
                                    
                                    Divider()
                                    
                                    MenuItem(title: "重新开始")
                                        .onTapGesture {
                                            showingMenu = false
                                            // 执行开始番茄钟的操作
                                            continueAction()
                                        }
                                    
                                    Divider()
                                    
                                    MenuItem(title: "停止休息")
                                        .onTapGesture {
                                            showingMenu = false
                                            // 执行停止休息的操作
                                            stopAction()
                                        }
                                    
                                    Divider()
                                    
                                    MenuItem(title: "取消")
                                        .onTapGesture {
                                            showingMenu = false
                                            // 取消操作，不执行任何动作
                                        }
                                }
                                .frame(width: 300) // 设置固定宽度300px
                                .background(Color(NSColor.controlBackgroundColor).opacity(0.9))
                                .cornerRadius(8)
                            }
                            .position(
                                x: geometry.size.width / 2, // 水平居中
                                y: geometry.size.height / 2 + 238 // 垂直位置：屏幕中心偏下238px，确保显示在停止按钮下方
                            )
                        }
                    }
                }
            }
            
            .padding()
        }
        .ignoresSafeArea()
    }
    
    // 自定义三角形视图
    struct Triangle: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
            return path
        }
    }
    
    // 自定义菜单项视图
    struct MenuItem: View {
        let title: String
        @State private var isHovered = false
        
        var body: some View {
            Text(title)
                .font(.system(size: 14))
                .padding(.vertical, 12)
                .padding(.horizontal, 30)
                .frame(maxWidth: .infinity, alignment: .center)
                .foregroundColor(.white) // 始终保持白色
                .background(isHovered ? Color.white.opacity(0.3) : Color.clear) // 降低背景透明度
                .onHover {
                    isHovered = $0
                }
        }
    }
}

// 扩展，添加Combine支持
import Combine
