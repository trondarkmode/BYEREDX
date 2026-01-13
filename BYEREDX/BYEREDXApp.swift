import SwiftUI
import ApplicationServices
import Combine
import UniformTypeIdentifiers
import ServiceManagement

// =========================================================================
//                  ZONE: MAIN ENTRY & APP DELEGATE
// =========================================================================

@main
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
    
    var statusBarItem: NSStatusItem!
    var appState = AppState()
    var timer: Timer?
    var settingsWindow: NSWindow?
    var aboutWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMenuBar()
        startMonitoring()
        UpdateManager.shared.checkForUpdates(isManual: false)
    }
    
    func setupMenuBar() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusBarItem.button {
            button.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "BYEREDX")
            button.action = #selector(menuButtonAction(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }
    
    @objc func menuButtonAction(_ sender: NSStatusBarButton) {
        appState.refreshPermissionStatus()
        
        let menu = NSMenu()
        menu.delegate = self
        
        menu.addItem(NSMenuItem(title: appState.localize("menu_open"), action: #selector(openSettings), keyEquivalent: "s"))
        menu.addItem(NSMenuItem.separator())
        
        let langMenu = NSMenu()
        let engItem = NSMenuItem(title: "English", action: #selector(setLangEng), keyEquivalent: "")
        engItem.target = self
        engItem.state = appState.currentLanguage == .english ? .on : .off
        let thaiItem = NSMenuItem(title: "ไทย", action: #selector(setLangThai), keyEquivalent: "")
        thaiItem.target = self
        thaiItem.state = appState.currentLanguage == .thai ? .on : .off
        langMenu.addItem(engItem)
        langMenu.addItem(thaiItem)
        
        let langMenuItem = NSMenuItem(title: appState.localize("menu_lang"), action: nil, keyEquivalent: "")
        menu.setSubmenu(langMenu, for: langMenuItem)
        menu.addItem(langMenuItem)
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(title: appState.localize("menu_about"), action: #selector(openAbout), keyEquivalent: "a"))
        menu.addItem(NSMenuItem(title: appState.localize("menu_quit"), action: #selector(quitApp), keyEquivalent: "q"))
        
        statusBarItem.menu = menu
        statusBarItem.button?.performClick(nil)
    }
    
    func menuDidClose(_ menu: NSMenu) {
        statusBarItem.menu = nil
    }
    
    @objc func openSettings() {
        if settingsWindow != nil {
            settingsWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        appState.refreshPermissionStatus()
        appState.checkLaunchAtLoginStatus()
        
        let hostingController = NSHostingController(rootView: ContentView().environmentObject(appState))
        let window = NSWindow(contentViewController: hostingController)
        window.title = appState.localize("title")
        window.setContentSize(NSSize(width: 500, height: 450))
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func openAbout() {
        if aboutWindow != nil {
            aboutWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let hostingController = NSHostingController(rootView: AboutView().environmentObject(appState))
        let window = NSWindow(contentViewController: hostingController)
        window.title = ""
        window.setContentSize(NSSize(width: 350, height: 450))
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.aboutWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func setLangEng() { appState.setLanguage(.english) }
    @objc func setLangThai() { appState.setLanguage(.thai) }
    @objc func quitApp() { NSApp.terminate(nil) }
    
    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkAndQuitApps()
        }
    }
    
    func checkAndQuitApps() {
        let isTrusted = AXIsProcessTrusted()
        DispatchQueue.main.async {
            if self.appState.isAccessibilityTrusted != isTrusted {
                self.appState.isAccessibilityTrusted = isTrusted
            }
        }
        guard appState.isMonitoringEnabled && isTrusted else { return }
        
        let workspace = NSWorkspace.shared
        let allRunningApps = workspace.runningApplications
        let regularApps = allRunningApps.filter { $0.activationPolicy == .regular }
        
        for app in regularApps {
            guard let bundleId = app.bundleIdentifier, let appName = app.localizedName else { continue }
            
            if bundleId.contains("BYEREDX") { continue }
            
            var shouldClose = false
            
            if appState.listMode == .exclude {
                let isInWhitelist = appState.whitelistApps.contains(appName) || appState.whitelistApps.contains(bundleId)
                if isInWhitelist { continue }
                if appState.systemApps.contains(appName) { continue }
                
                if bundleId == "com.google.Chrome" {
                    let chromeAppsRunning = allRunningApps.filter {
                        ($0.bundleIdentifier?.hasPrefix("com.google.Chrome.app") ?? false)
                    }
                    let isImportantRunning = chromeAppsRunning.contains { cApp in
                        guard let cName = cApp.localizedName else { return false }
                        return appState.whitelistApps.contains(cName)
                    }
                    if isImportantRunning { continue }
                }
                shouldClose = true
            } else {
                let isInBlacklist = appState.blacklistApps.contains(appName) || appState.blacklistApps.contains(bundleId)
                if isInBlacklist { shouldClose = true }
            }
            
            if shouldClose {
                if !app.isFinishedLaunching { continue }
                let appRef = AXUIElementCreateApplication(app.processIdentifier)
                var windowsRef: CFTypeRef?
                let result = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef)
                
                if result == .success, let windowList = windowsRef as? [AXUIElement], windowList.isEmpty {
                    print("Closing \(appName)")
                    app.terminate()
                    DispatchQueue.main.async { self.appState.lastLog = "Closed: \(appName)" }
                }
            }
        }
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            if window == settingsWindow { settingsWindow = nil }
            if window == aboutWindow { aboutWindow = nil }
        }
    }
}

// =========================================================================
//                  ZONE: APP STATE & DATA MANAGEMENT
// =========================================================================

class AppState: ObservableObject {
    @Published var isMonitoringEnabled: Bool = true
    @Published var currentLanguage: Language = .english
    @Published var isAccessibilityTrusted: Bool = false
    @Published var lastLog: String = "Waiting..."
    @Published var isLaunchAtLoginEnabled: Bool = false
    @Published var listMode: ListMode = .exclude
    
    @Published var whitelistApps: [String] = []
    @Published var blacklistApps: [String] = []
    
    private let defaults = UserDefaults.standard
    let systemApps = ["Finder", "BYEREDX", "Spotlight", "Dock", "System Settings"]
    
    enum Language: String, CaseIterable {
        case english = "English"
        case thai = "Thai"
    }
    
    enum ListMode: String, CaseIterable {
        case exclude = "exclude"
        case target = "target"
    }
    
    init() {
        if let langString = defaults.string(forKey: "appLanguage"), let lang = Language(rawValue: langString) {
            self.currentLanguage = lang
        }
        if let modeString = defaults.string(forKey: "listMode"), let mode = ListMode(rawValue: modeString) {
            self.listMode = mode
        }
        
        if let savedWhitelist = defaults.stringArray(forKey: "whitelistAppsStore") {
            self.whitelistApps = savedWhitelist
        } else {
            if let oldList = defaults.stringArray(forKey: "exclusionList") {
                self.whitelistApps = oldList
            } else {
                self.whitelistApps = systemApps
            }
        }
        
        if let savedBlacklist = defaults.stringArray(forKey: "blacklistAppsStore") {
            self.blacklistApps = savedBlacklist
        } else {
            self.blacklistApps = []
        }
        
        // Cleanup & Force Add BYEREDX
        if whitelistApps.contains("RealClose") { whitelistApps.removeAll { $0 == "RealClose" } }
        if whitelistApps.contains("BYEX") { whitelistApps.removeAll { $0 == "BYEX" } }
        if !whitelistApps.contains("BYEREDX") { whitelistApps.append("BYEREDX") }
        
        saveLists()
        self.isAccessibilityTrusted = AXIsProcessTrusted()
        self.checkLaunchAtLoginStatus()
    }
    
    func saveLists() {
        defaults.set(whitelistApps, forKey: "whitelistAppsStore")
        defaults.set(blacklistApps, forKey: "blacklistAppsStore")
    }
    
    func checkLaunchAtLoginStatus() {
        if SMAppService.mainApp.status == .enabled { self.isLaunchAtLoginEnabled = true } else { self.isLaunchAtLoginEnabled = false }
    }
    
    func toggleLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            self.isLaunchAtLoginEnabled = enabled
        } catch {
            print("Failed: \(error)")
            self.checkLaunchAtLoginStatus()
        }
    }
    
    func setLanguage(_ lang: Language) {
        currentLanguage = lang
        defaults.set(lang.rawValue, forKey: "appLanguage")
        objectWillChange.send()
    }
    
    func setListMode(_ mode: ListMode) {
        listMode = mode
        defaults.set(mode.rawValue, forKey: "listMode")
        objectWillChange.send()
    }
    
    func addAppToCurrentList(_ name: String) {
        if name.isEmpty { return }
        if listMode == .exclude {
            if !whitelistApps.contains(name) { whitelistApps.append(name); saveLists() }
        } else {
            if !blacklistApps.contains(name) { blacklistApps.append(name); saveLists() }
        }
        objectWillChange.send()
    }
    
    func removeAppFromCurrentList(_ name: String) {
        if listMode == .exclude {
            if systemApps.contains(name) { return }
            whitelistApps.removeAll { $0 == name }
        } else {
            blacklistApps.removeAll { $0 == name }
        }
        saveLists()
        objectWillChange.send()
    }
    
    var currentDisplayList: [String] {
        return listMode == .exclude ? whitelistApps : blacklistApps
    }
    
    func localize(_ key: String) -> String {
        let dict: [String: [Language: String]] = [
            "title": [.english: "BYEREDX Settings", .thai: "ตั้งค่า BYEREDX"],
            "tab_general": [.english: "General", .thai: "ทั่วไป"],
            "tab_whitelist": [.english: "List Manager", .thai: "จัดการรายชื่อ"],
            "auto_quit": [.english: "Enable Auto Quit", .thai: "เปิดใช้งานปิดอัตโนมัติ"],
            "auto_quit_desc": [.english: "Quit apps when red X is clicked (0 windows).", .thai: "ปิดแอปทันทีเมื่อกดกากบาทสีแดง"],
            "launch_login": [.english: "Start at Login", .thai: "เริ่มทำงานเมื่อเปิดเครื่อง"],
            "launch_login_desc": [.english: "Automatically start BYEREDX in background.", .thai: "เปิดโปรแกรม BYEREDX อัตโนมัติเมื่อเข้าสู่ระบบ"],
            "hide_recent": [.english: "Hide Recent Apps on Dock", .thai: "ซ่อนแอป Recent บน Dock"],
            "hide_recent_desc": [.english: "Removes recent apps section (Dock restarts).", .thai: "ลบช่องแอปล่าสุด (Dock จะรีสตาร์ท)"],
            "status_on": [.english: "System Active", .thai: "ระบบกำลังทำงาน"],
            "status_off": [.english: "System Paused", .thai: "ระบบหยุดทำงาน"],
            "perm_error": [.english: "Permission Required. Click to Fix.", .thai: "ต้องการสิทธิ์การเข้าถึง คลิกเพื่อแก้ไข"],
            "select_app_btn": [.english: "Select Application...", .thai: "เลือกโปรแกรม..."],
            "menu_open": [.english: "Open Settings", .thai: "เปิดหน้าต่างตั้งค่า"],
            "menu_about": [.english: "About BYEREDX", .thai: "เกี่ยวกับ BYEREDX"],
            "menu_quit": [.english: "Quit BYEREDX", .thai: "ปิดโปรแกรม BYEREDX"],
            "menu_lang": [.english: "Language / ภาษา", .thai: "Language / ภาษา"],
            "system_tag": [.english: "System", .thai: "ระบบ"],
            "version_label": [.english: "Version", .thai: "เวอร์ชัน"],
            "check_update": [.english: "Check for Updates", .thai: "ตรวจสอบเวอร์ชันใหม่"],
            "checking": [.english: "Checking...", .thai: "กำลังตรวจสอบ..."],
            "uptodate": [.english: "You are up to date!", .thai: "เป็นเวอร์ชันล่าสุดแล้ว!"],
            "update_avail": [.english: "New version available!", .thai: "มีเวอร์ชันใหม่!"],
            "download_btn": [.english: "Download", .thai: "ดาวน์โหลด"],
            "later_btn": [.english: "Later", .thai: "ไว้ทีหลัง"],
            "no_internet_title": [.english: "No Internet Connection", .thai: "ไม่มีการเชื่อมต่ออินเทอร์เน็ต"],
            "no_internet_msg": [.english: "Please connect to the internet to check for updates.", .thai: "กรุณาเชื่อมต่ออินเทอร์เน็ตเพื่อตรวจสอบการอัปเดต"],
            "mode_exclude": [.english: "Mode: Close All Apps (Except Whitelist)", .thai: "โหมด: ปิดทุกแอป (ยกเว้นที่เลือกไว้)"],
            "mode_target": [.english: "Mode: Close Only Listed Apps (Target)", .thai: "โหมด: ปิดเฉพาะแอปที่เลือกไว้เท่านั้น"]
        ]
        return dict[key]?[currentLanguage] ?? key
    }
}

extension AppState { func refreshPermissionStatus() { self.isAccessibilityTrusted = AXIsProcessTrusted() } }

// =========================================================================
//                  ZONE: UI LAYOUT (SETTINGS)
// =========================================================================

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("hideRecentDock") private var hideRecentDock = false
    
    var body: some View {
        VStack {
            Text(appState.localize("title")).font(.title2).fontWeight(.bold).padding(.top)
            if !appState.isAccessibilityTrusted {
                Button(action: {
                    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                    AXIsProcessTrustedWithOptions(options as CFDictionary)
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
                }) {
                    Text(appState.localize("perm_error")).padding(8).frame(maxWidth: .infinity).background(Color.red).foregroundColor(.white).cornerRadius(8)
                }.buttonStyle(.plain).padding(.horizontal)
            }
            TabView {
                VStack(spacing: 20) {
                    Toggle(isOn: $appState.isMonitoringEnabled) {
                        VStack(alignment: .leading) {
                            Text(appState.localize("auto_quit")).font(.headline)
                            Text(appState.localize("auto_quit_desc")).font(.caption).foregroundColor(.secondary)
                        }
                    }.toggleStyle(SwitchToggleStyle(tint: .green))
                    Divider()
                    Toggle(isOn: Binding(get: { appState.isLaunchAtLoginEnabled }, set: { appState.toggleLaunchAtLogin($0) })) {
                        VStack(alignment: .leading) {
                            Text(appState.localize("launch_login")).font(.headline)
                            Text(appState.localize("launch_login_desc")).font(.caption).foregroundColor(.blue)
                        }
                    }.toggleStyle(SwitchToggleStyle(tint: .blue))
                    Divider()
                    Toggle(isOn: Binding(get: { self.hideRecentDock }, set: { self.hideRecentDock = $0; toggleDockRecents(hide: $0) })) {
                        VStack(alignment: .leading) {
                            Text(appState.localize("hide_recent")).font(.headline)
                            Text(appState.localize("hide_recent_desc")).font(.caption).foregroundColor(.orange)
                        }
                    }.toggleStyle(SwitchToggleStyle(tint: .orange))
                    Spacer()
                    HStack {
                        Text("Last Activity:").font(.caption).bold()
                        Text(appState.lastLog).font(.caption).foregroundColor(.gray)
                    }.padding(5).background(Color.black.opacity(0.05)).cornerRadius(5)
                }.padding().tabItem { Label(appState.localize("tab_general"), systemImage: "gear") }
                
                VStack {
                    HStack {
                        Picker("", selection: $appState.listMode) {
                            Text(appState.localize("mode_exclude")).tag(AppState.ListMode.exclude)
                            Text(appState.localize("mode_target")).tag(AppState.ListMode.target)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 320)
                        .onChange(of: appState.listMode) { _, newValue in
                            appState.setListMode(newValue)
                        }
                    }.padding(.top, 10)
                    
                    Button(action: openFilePicker) { Label(appState.localize("select_app_btn"), systemImage: "plus.magnifyingglass").frame(maxWidth: .infinity) }.controlSize(.large).buttonStyle(.borderedProminent).padding(.top, 5)
                    
                    List {
                        ForEach(appState.currentDisplayList, id: \.self) { appName in
                            HStack {
                                Image(systemName: appState.listMode == .exclude ? "shield.fill" : "target")
                                    .foregroundColor(getIconColor(appName: appName))
                                Text(appName).fontWeight(isSystemApp(appName) ? .medium : .regular)
                                Spacer()
                                if appState.listMode == .exclude && isSystemApp(appName) {
                                    Text(appState.localize("system_tag")).font(.caption2).foregroundColor(.secondary).padding(.horizontal, 6).padding(.vertical, 2).background(Color.gray.opacity(0.1)).cornerRadius(4)
                                } else {
                                    Button(action: { appState.removeAppFromCurrentList(appName) }) { Image(systemName: "xmark.circle.fill").foregroundColor(.gray).font(.title3) }.buttonStyle(.plain)
                                }
                            }.padding(.vertical, 4)
                        }
                    }.listStyle(.inset)
                }.padding().tabItem { Label(appState.localize("tab_whitelist"), systemImage: "list.bullet.rectangle") }
            }
        }.frame(width: 500, height: 450)
    }
    
    func isSystemApp(_ name: String) -> Bool { return appState.systemApps.contains(name) }
    func getIconColor(appName: String) -> Color {
        if appState.listMode == .exclude && isSystemApp(appName) { return .blue }
        return appState.listMode == .exclude ? .green : .red
    }
    func openFilePicker() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.application]; panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        if panel.runModal() == .OK { for url in panel.urls { appState.addAppToCurrentList(url.deletingPathExtension().lastPathComponent) } }
    }
    func toggleDockRecents(hide: Bool) {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/defaults"); p.arguments = ["write", "com.apple.dock", "show-recents", "-bool", hide ? "false" : "true"]; try? p.run(); p.waitUntilExit()
        let k = Process(); k.executableURL = URL(fileURLWithPath: "/usr/bin/killall"); k.arguments = ["Dock"]; try? k.run()
    }
}

// =========================================================================
//                  ZONE: ABOUT & UPDATE MANAGER
// =========================================================================

struct AboutData {
    static let version = "1.0.3"
    static let developer = "BYEREDX Team"
    static let githubUser = "trondarkmode"
    static let githubRepo = "BYEREDX"
    
    static func getUpdateNote(language: AppState.Language) -> String {
        switch language {
        case .english:
            return """
            Welcome to BYEREDX
            
            This application automatically quits apps when you click the red 'x' button.
            
            Version 1.0.3 Update Highlights:
            
            Adjust stability.
            
            Version 1.0.2 Update Highlights:
            
            • Dual Operation Modes:
              - Exclude Mode (Standard): Closes all applications automatically, except for those specified in the Whitelist.
              - Target Mode (New): Only closes specific applications designated in the Target List.
            
            • Integrated Update System:
              - Added a "Check for Updates" button to verify and download the latest version directly from GitHub.
              - Automatic update checking upon application launch.
            
            • System Improvements:
              - Independent list management for each mode.
              - Enhanced Start at Login functionality.
            """
        case .thai:
            return """
            ยินดีต้อนรับสู่ BYEREDX
            
            โปรแกรมนี้จะช่วยปิดแอปพลิเคชั่นที่เรากดด้วยปุ่มกากบาทสีแดงที่แอปพลิเคชั่นเหล่านั้นให้อัตโนมัติ
            
            สิ่งที่อัปเดตใหม่ในเวอร์ชัน 1.0.3:
            
            ปรับความเสถียรของโปรแกรม
            
            สิ่งที่อัปเดตใหม่ในเวอร์ชัน 1.0.2:
            
            • โหมดการทำงานแบบคู่ (Dual Operation Modes):
              - โหมดยกเว้น (Exclude Mode): ปิดทุกโปรแกรมอัตโนมัติ ยกเว้นโปรแกรมที่ระบุไว้ในรายการ (ค่าเริ่มต้น)
              - โหมดเจาะจง (Target Mode): ปิดเฉพาะโปรแกรมที่ระบุไว้ในรายการเท่านั้น (เหมาะสำหรับเลือกปิดบางแอป)
            
            • ระบบอัปเดตโปรแกรม (Integrated Update System):
              - เพิ่มปุ่ม "ตรวจสอบเวอร์ชันใหม่" เพื่อตรวจสอบและดาวน์โหลดเวอร์ชันล่าสุดจาก GitHub
              - ระบบตรวจสอบการอัปเดตอัตโนมัติเมื่อเปิดใช้งานโปรแกรม
            
            • การปรับปรุงระบบ:
              - แยกฐานข้อมูลรายชื่อโปรแกรมของแต่ละโหมดออกจากกันอย่างอิสระ
              - ปรับปรุงเสถียรภาพของฟังก์ชันเริ่มทำงานเมื่อเปิดเครื่อง
            """
        }
    }
}

// --- Update Logic ---
struct GithubRelease: Codable {
    let tagName: String
    let htmlUrl: String
    enum CodingKeys: String, CodingKey { case tagName = "tag_name"; case htmlUrl = "html_url" }
}

class UpdateManager: ObservableObject {
    static let shared = UpdateManager()
    @Published var updateStatus: String = ""
    @Published var showManualUpdateAlert: Bool = false
    @Published var showNoInternetAlert: Bool = false
    @Published var newVersionURL: URL? = nil
    @Published var latestVersion: String = ""
    
    func checkForUpdates(isManual: Bool) {
        let urlString = "https://api.github.com/repos/\(AboutData.githubUser)/\(AboutData.githubRepo)/releases/latest"
        guard let url = URL(string: urlString) else { return }
        
        if isManual { self.updateStatus = "checking" }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    if isManual {
                        let nsError = error as NSError
                        if nsError.domain == NSURLErrorDomain && (nsError.code == NSURLErrorNotConnectedToInternet || nsError.code == NSURLErrorCannotFindHost) {
                            self.showNoInternetAlert = true
                            self.updateStatus = "Error"
                        } else { self.updateStatus = "Error" }
                    }
                    return
                }
                if let data = data, let release = try? JSONDecoder().decode(GithubRelease.self, from: data) {
                    let serverVer = release.tagName.replacingOccurrences(of: "v", with: "")
                    let localVer = AboutData.version
                    if serverVer.compare(localVer, options: .numeric) == .orderedDescending {
                        self.latestVersion = serverVer
                        self.newVersionURL = URL(string: release.htmlUrl)
                        self.updateStatus = ""
                        if isManual { self.showManualUpdateAlert = true } else { self.showNativeUpdateAlert() }
                    } else { if isManual { self.updateStatus = "uptodate" } }
                } else { if isManual { self.updateStatus = "Error" } }
            }
        }.resume()
    }
    
    func showNativeUpdateAlert() {
        let alert = NSAlert()
        alert.messageText = "New version available!"
        alert.informativeText = "Version \(latestVersion) is available. Would you like to download it now?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn { if let url = self.newVersionURL { NSWorkspace.shared.open(url) } }
    }
}

struct AboutView: View {
    @EnvironmentObject var appState: AppState
    @StateObject var updater = UpdateManager.shared
    var body: some View {
        VStack(spacing: 15) {
            Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 70, height: 70).padding(.top, 20)
            Text("BYEREDX").font(.largeTitle).fontWeight(.bold)
            Text("\(appState.localize("version_label")) \(AboutData.version)").font(.headline).foregroundColor(.secondary)
            Text("by \(AboutData.developer)").font(.caption).foregroundColor(.gray)
            if updater.updateStatus == "checking" { ProgressView(appState.localize("checking")).scaleEffect(0.8) }
            else if updater.updateStatus == "uptodate" { Text(appState.localize("uptodate")).foregroundColor(.green).font(.caption) }
            else { Button(action: { updater.checkForUpdates(isManual: true) }) { Label(appState.localize("check_update"), systemImage: "arrow.triangle.2.circlepath") }.controlSize(.small) }
            Divider()
            ScrollView { Text(AboutData.getUpdateNote(language: appState.currentLanguage)).font(.body).multilineTextAlignment(.leading).padding() }.frame(maxHeight: .infinity)
            Spacer()
        }
        .frame(width: 350, height: 450).background(Color(NSColor.windowBackgroundColor))
        .alert(isPresented: $updater.showManualUpdateAlert) {
            Alert(title: Text(appState.localize("update_avail")), message: Text("v\(AboutData.version) -> v\(updater.latestVersion)"), primaryButton: .default(Text(appState.localize("download_btn")), action: { if let url = updater.newVersionURL { NSWorkspace.shared.open(url) } }), secondaryButton: .cancel(Text(appState.localize("later_btn"))))
        }
        .overlay(EmptyView().alert(isPresented: $updater.showNoInternetAlert) { Alert(title: Text(appState.localize("no_internet_title")), message: Text(appState.localize("no_internet_msg")), dismissButton: .default(Text("OK"))) })
    }
}
