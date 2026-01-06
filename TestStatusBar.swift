import AppKit

class TestAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 创建状态栏项
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.title = "⏰ Test"
            button.action = #selector(showMenu)
        }
        
        print("Test app launched with status bar item")
    }
    
    @objc func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "测试", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        
        statusItem.popUpMenu(menu)
    }
}

// 运行应用
let app = NSApplication.shared
let delegate = TestAppDelegate()
app.delegate = delegate
app.run()
