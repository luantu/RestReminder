import AppKit
import SwiftUI

// 全局状态管理
class AppState: ObservableObject, @unchecked Sendable {
    @Published var isRunning = true
    @Published var isPaused = false
    @Published var remainingTime: TimeInterval = 30.0 * 60.0
    @Published var showingReminder = false
    @Published var settings = Settings() {
        didSet {
            saveSettings()
            remainingTime = TimeInterval(settings.reminderInterval) * 60.0
        }
    }

    private var timer: Timer?
    private var reminderTimeoutTimer: Timer?
    private let reminderTimeout: TimeInterval = 300 // 5分钟后自动关闭提醒

    init() {
        loadSettings()
        startTimer()
    }

    func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self, !self.isPaused else { return }

            if self.remainingTime > 0 {
                self.remainingTime -= 1
            } else {
                self.showReminder()
            }
        }
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
        timer?.invalidate()
    }

    func showReminder() {
        // 检查是否需要跳过提醒
        if shouldSkipReminder() {
            resetTimer()
            return
        }

        showingReminder = true
        
        // 设置超时自动关闭
        setupReminderTimeout()
    }
    
    func dismissReminder() {
        showingReminder = false
        resetTimer()
        
        // 清除超时计时器
        clearReminderTimeout()
    }
    
    // 设置提醒超时
    private func setupReminderTimeout() {
        // 清除之前的计时器
        clearReminderTimeout()
        
        // 创建新的超时计时器
        reminderTimeoutTimer = Timer.scheduledTimer(withTimeInterval: reminderTimeout, repeats: false) { [weak self] _ in
            print("提醒超时，自动关闭")
            self?.dismissReminder()
        }
    }
    
    // 清除提醒超时
    private func clearReminderTimeout() {
        reminderTimeoutTimer?.invalidate()
        reminderTimeoutTimer = nil
    }

    private func shouldSkipReminder() -> Bool {
        // 如果屏蔽功能未启用，不跳过提醒
        guard settings.isBlockingEnabled else {
            return false
        }
        
        // 检查当前前台应用是否在屏蔽列表中
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }

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
        
        if let interval = UserDefaults.standard.object(forKey: "reminderInterval") as? Int {
            loadedSettings.reminderInterval = interval
            remainingTime = TimeInterval(interval) * 60.0
        }
        if let isBlockingEnabled = UserDefaults.standard.object(forKey: "isBlockingEnabled") as? Bool {
            loadedSettings.isBlockingEnabled = isBlockingEnabled
        }
        if let blockedApps = UserDefaults.standard.object(forKey: "blockedApps") as? [String] {
            loadedSettings.blockedApps = blockedApps
        }
        
        // 替换整个settings对象，触发didSet观察者
        settings = loadedSettings
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
}

// 设置结构
struct Settings {
    var reminderInterval: Int = 30 // 分钟
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
        print("开始显示全屏提醒")
        
        // 先关闭任何可能存在的旧窗口，避免窗口堆积
        dismissFullScreenReminder()
        
        // 为每个屏幕创建全屏窗口
        for (index, screen) in NSScreen.screens.enumerated() {
            print("为屏幕 \(index+1) 创建窗口，尺寸：\(screen.frame)")

            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )

            // 确保窗口在最顶层
            window.level = .screenSaver
            // 设置窗口属性
            window.backgroundColor = NSColor.clear
            window.isOpaque = false
            window.isMovable = false
            window.isReleasedWhenClosed = true
            // 确保窗口能接收鼠标事件
            window.isMovableByWindowBackground = false
            window.acceptsMouseMovedEvents = true
            window.ignoresMouseEvents = false
            // 确保窗口显示在所有空间
            window.collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenPrimary,
                .stationary,
                .ignoresCycle
            ]

            // 创建SwiftUI视图控制器
            let contentView = ReminderView(appState: appState, screen: screen)
            let hostingController = NSHostingController(rootView: contentView)

            window.contentViewController = hostingController
            window.contentView?.wantsLayer = true

            // 确保窗口覆盖整个屏幕
            window.setFrame(screen.frame, display: true, animate: false)
            window.makeKeyAndOrderFront(nil)

            // 存储窗口控制器
            reminderWindowControllers.append(window)
            print("窗口 \(index+1) 创建完成")
        }
        print("全屏提醒显示完成")
        
        // 添加全局事件监听，作为备用关闭机制
        setupGlobalEventMonitor()
    }

    private var reminderWindowControllers = [NSWindow]()
    private var globalEventMonitor: Any?

    @MainActor
    private func dismissFullScreenReminder() {
        print("开始关闭全屏提醒")
        for window in reminderWindowControllers {
            window.close()
        }
        reminderWindowControllers.removeAll()
        
        // 移除全局事件监听
        removeGlobalEventMonitor()
        print("全屏提醒关闭完成")
    }
    
    // 设置全局事件监听，作为备用关闭机制
    private func setupGlobalEventMonitor() {
        // 移除之前的监听
        removeGlobalEventMonitor()
        
        // 监听按键事件和鼠标点击事件
        let mask: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown, .rightMouseDown]
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            // 任何按键或鼠标点击都关闭提醒
            Task {
                @MainActor in
                print("全局事件监听触发，关闭提醒")
                self?.appState.dismissReminder()
            }
        }
        print("全局事件监听已设置")
    }
    
    // 移除全局事件监听
    private func removeGlobalEventMonitor() {
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
            print("全局事件监听已移除")
        }
    }

    // 菜单操作
    @objc func resetTimer() {
        appState.resetTimer()
    }

    @objc func pauseTimer() {
        appState.pauseTimer()
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

// 全屏提醒视图
struct ReminderView: View {
    @ObservedObject var appState: AppState
    let screen: NSScreen

    var body: some View {
        ZStack {
            // 使用桌面背景
            DesktopBackgroundView()

            // 半透明遮罩
            Color.black.opacity(0.5)

            // 提醒内容
            VStack(spacing: 48) {
                Text("该休息了！")
                    .font(.system(size: 64, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(radius: 10)

                Text("站起来活动一下，保护眼睛和身体健康")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .shadow(radius: 10)

                VStack(spacing: 8) {
                    Button(action: { appState.dismissReminder() }) {
                        ZStack {
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                                .frame(width: 32, height: 32)
                            Image(systemName: "xmark")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                                .shadow(radius: 10)
                        }
                    }
                    .buttonStyle(.plain)

                    Text("停止")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .shadow(radius: 10)
                }
            }
            .padding()
        }
        .ignoresSafeArea()
        .onTapGesture {
            appState.dismissReminder()
        }
    }
}

// 桌面背景视图 - 优化版，减少资源消耗
struct DesktopBackgroundView: NSViewRepresentable {
    // 静态缓存，避免重复获取
    static var cachedDesktopImage: NSImage?
    static var lastCacheTime: Date = .distantPast
    static let cacheDuration: TimeInterval = 300 // 5分钟缓存
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        
        // 设置半透明黑色背景，不再使用复杂的桌面背景获取
        // 简化实现，避免AppleScript可能带来的性能问题和卡死
        view.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.7).cgColor
        
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // 不再需要更新逻辑，简化实现
    }
}

// 扩展，添加Combine支持
import Combine
