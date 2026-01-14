import SwiftUI
import ApplicationServices
import Combine
import UniformTypeIdentifiers
import ServiceManagement
import CoreGraphics
import Network

// MARK: - 1. MAIN ENTRY & DELEGATE
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
    var settingsWindow: NSWindow?
    var aboutWindow: NSWindow?
    var windowWatcher: WindowWatcher?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMenuBar()
        
        // Start Core System
        windowWatcher = WindowWatcher(appState: appState)
        windowWatcher?.startWatching()
        
        // Auto-check for updates
        UpdateManager.shared.checkForUpdates(isManual: false)
    }
    
    // MARK: - Menu Bar Setup
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
        
        // Section 1: Settings
        menu.addItem(NSMenuItem(title: appState.localize("menu_open"), action: #selector(openSettings), keyEquivalent: "s"))
        menu.addItem(NSMenuItem.separator())
        
        // Section 2: Language
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
        
        // Section 3: System
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: appState.localize("menu_about"), action: #selector(openAbout), keyEquivalent: "a"))
        menu.addItem(NSMenuItem(title: appState.localize("menu_quit"), action: #selector(quitApp), keyEquivalent: "q"))
        
        statusBarItem.menu = menu
        statusBarItem.button?.performClick(nil)
    }
    
    func menuDidClose(_ menu: NSMenu) {
        statusBarItem.menu = nil
    }
    
    // MARK: - Window Management
    @objc func openSettings() {
        bringWindowToFront(
            window: &settingsWindow,
            view: ContentView().environmentObject(appState),
            title: appState.localize("title"),
            size: NSSize(width: 500, height: 450)
        )
    }
    
    @objc func openAbout() {
        bringWindowToFront(
            window: &aboutWindow,
            view: AboutView().environmentObject(appState),
            title: "",
            size: NSSize(width: 350, height: 450)
        )
    }
    
    func bringWindowToFront<V: View>(window: inout NSWindow?, view: V, title: String, size: NSSize) {
        if window != nil {
            window?.level = .floating
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let hostingController = NSHostingController(rootView: view)
        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = title
        newWindow.setContentSize(size)
        newWindow.styleMask = [.titled, .closable, .fullSizeContentView]
        if title == appState.localize("title") { newWindow.styleMask.insert(.miniaturizable) }
        
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        newWindow.level = .floating
        
        window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func setLangEng() { appState.setLanguage(.english) }
    @objc func setLangThai() { appState.setLanguage(.thai) }
    @objc func quitApp() { NSApp.terminate(nil) }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            if window == settingsWindow { settingsWindow = nil }
            if window == aboutWindow { aboutWindow = nil }
        }
    }
}

// MARK: - 2. CORE LOGIC (WINDOW WATCHER)
struct TargetDatabase {
    /// Apps that require specific monitoring (Watchlist Trap)
    static let specialApps: Set<String> = [
        "com.apple.Safari", "com.apple.TextEdit", "com.apple.Preview", "com.apple.Terminal",
        "com.apple.QuickTimePlayerX", "com.apple.iWork.Pages", "com.apple.iWork.Numbers", "com.apple.iWork.Keynote",
        "com.apple.mail", "com.apple.MobileSMS", "com.apple.iCal", "com.apple.AddressBook",
        "com.apple.reminders", "com.apple.Notes", "com.apple.FaceTime", "com.apple.Music",
        "com.apple.TV", "com.apple.podcasts", "com.apple.Photos", "com.apple.iBooksX",
        "com.apple.Maps", "com.apple.findmy", "com.apple.Home", "com.apple.news",
        "com.apple.stocks", "com.apple.weather", "com.apple.AppStore", "com.apple.Automator"
    ]
}

class ObserverContext {
    weak var watcher: WindowWatcher?
    let pid: pid_t
    init(watcher: WindowWatcher, pid: pid_t) {
        self.watcher = watcher
        self.pid = pid
    }
}

class WindowWatcher {
    var appState: AppState
    var watchedPIDs: Set<pid_t> = []
    var activeObservers: [pid_t: (axObserver: AXObserver, context: UnsafeMutableRawPointer)] = [:]
    
    init(appState: AppState) {
        self.appState = appState
    }
    
    // --- Lifecycle Monitoring ---
    func startWatching() {
        let workspace = NSWorkspace.shared
        
        // 1. Initial Scan
        for app in workspace.runningApplications { handleAppLaunch(app) }
        
        // 2. Launch Listener
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.handleAppLaunch(app)
            }
        }
        
        // 3. Deactivate Listener (The Trap)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didDeactivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.handleAppDeactivate(app)
            }
        }
        
        // 4. Terminate Listener
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.handleAppTerminate(app)
            }
        }
    }
    
    // --- Handlers ---
    func handleAppLaunch(_ app: NSRunningApplication) {
        guard let bundleId = app.bundleIdentifier else { return }
        
        if TargetDatabase.specialApps.contains(bundleId) {
            // Add to Watchlist (No AX Observer needed initially)
            watchedPIDs.insert(app.processIdentifier)
        } else {
            // Standard Observer
            _ = registerObserver(for: app)
        }
    }
    
    func handleAppTerminate(_ app: NSRunningApplication) {
        watchedPIDs.remove(app.processIdentifier)
        unregisterObserver(for: app)
    }
    
    func handleAppDeactivate(_ app: NSRunningApplication) {
        guard appState.isMonitoringEnabled else { return }
        
        if watchedPIDs.contains(app.processIdentifier) {
            // Trigger Hard Check immediately
            performHardCheck(app)
        }
    }
    
    // --- Checking Logic ---
    func performHardCheck(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        let appName = app.localizedName ?? "Unknown"
        
        // Wait for window animations (0.5s)
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            guard let runningApp = NSRunningApplication(processIdentifier: pid), !runningApp.isTerminated else { return }
            
            // Check User Permissions
            if !self.shouldCheckApp(runningApp) { return }
            
            // CoreGraphics Scan (No Accessibility needed)
            let windowCount = self.countWindowsViaCoreGraphics(pid: pid)
            
            if windowCount == 0 {
                print("Watchlist Kill: \(appName)")
                self.terminateApp(runningApp, name: appName)
            }
        }
    }
    
    func shouldCheckApp(_ app: NSRunningApplication) -> Bool {
        var shouldCheck = false
        DispatchQueue.main.sync {
            let name = app.localizedName ?? ""
            let bundle = app.bundleIdentifier ?? ""
            
            if self.appState.listMode == .exclude {
                let isWhitelisted = self.appState.whitelistApps.contains(name) || self.appState.whitelistApps.contains(bundle)
                let isSystem = self.appState.systemApps.contains(name)
                shouldCheck = !isWhitelisted && !isSystem
            } else {
                shouldCheck = self.appState.blacklistApps.contains(name) || self.appState.blacklistApps.contains(bundle)
            }
        }
        return shouldCheck
    }
    
    func countWindowsViaCoreGraphics(pid: pid_t) -> Int {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        
        var validCount = 0
        for info in infoList {
            if let ownerPID = info[kCGWindowOwnerPID as String] as? Int, ownerPID == pid {
                // Filter: Layer 0, Visible, Reasonable Size
                if let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                   let alpha = info[kCGWindowAlpha as String] as? Double, alpha > 0 {
                    
                    if let bounds = info[kCGWindowBounds as String] as? [String: Any],
                       let w = bounds["Width"] as? Double, w > 50,
                       let h = bounds["Height"] as? Double, h > 50 {
                        validCount += 1
                    }
                }
            }
        }
        return validCount
    }
    
    // --- Legacy Observer (For Standard Apps) ---
    func registerObserver(for app: NSRunningApplication) -> Bool {
        guard app.activationPolicy == .regular, let bundleId = app.bundleIdentifier, !bundleId.contains("BYEREDX") else { return false }
        
        let pid = app.processIdentifier
        if activeObservers[pid] != nil { return true }
        
        let context = ObserverContext(watcher: self, pid: pid)
        let contextPtr = Unmanaged.passRetained(context).toOpaque()
        var observer: AXObserver?
        
        let err = AXObserverCreate(pid, { (observer, element, notification, refcon) in
            guard let refcon = refcon else { return }
            let ctx = Unmanaged<ObserverContext>.fromOpaque(refcon).takeUnretainedValue()
            if let app = NSRunningApplication(processIdentifier: ctx.pid) {
                ctx.watcher?.performHardCheck(app)
            }
        }, &observer)
        
        if err == .success, let axObserver = observer {
            let appElement = AXUIElementCreateApplication(pid)
            AXObserverAddNotification(axObserver, appElement, kAXUIElementDestroyedNotification as CFString, contextPtr)
            AXObserverAddNotification(axObserver, appElement, kAXMainWindowChangedNotification as CFString, contextPtr)
            
            CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(axObserver), .defaultMode)
            activeObservers[pid] = (axObserver, contextPtr)
            return true
        } else {
            Unmanaged<ObserverContext>.fromOpaque(contextPtr).release()
            return false
        }
    }
    
    func unregisterObserver(for app: NSRunningApplication) {
        let pid = app.processIdentifier
        if let (axObserver, contextPtr) = activeObservers[pid] {
            let appElement = AXUIElementCreateApplication(pid)
            AXObserverRemoveNotification(axObserver, appElement, kAXUIElementDestroyedNotification as CFString)
            AXObserverRemoveNotification(axObserver, appElement, kAXMainWindowChangedNotification as CFString)
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(axObserver), .defaultMode)
            
            Unmanaged<ObserverContext>.fromOpaque(contextPtr).release()
            activeObservers.removeValue(forKey: pid)
        }
    }
    
    func terminateApp(_ app: NSRunningApplication, name: String) {
        app.terminate()
        DispatchQueue.main.async { self.appState.lastLog = "Closed: \(name)" }
    }
}

// MARK: - 3. REPORT SYSTEM (VIEW MODEL)
class ReportViewModel: ObservableObject {
    @Published var name: String = ""
    @Published var email: String = ""
    @Published var subject: String = ""
    @Published var details: String = ""
    @Published var selectedImage: NSImage?
    @Published var imageFileName: String = ""
    
    @Published var isSending: Bool = false
    @Published var showAlert: Bool = false
    @Published var alertMessage: String = ""
    @Published var alertTitle: String = ""
    
    var appState: AppState
    
    init(appState: AppState) {
        self.appState = appState
    }
    
    // Unique ID for rate limiting
    private var deviceID: String {
        let key = "device_report_uuid"
        if let storedID = UserDefaults.standard.string(forKey: key) { return storedID }
        let newID = UUID().uuidString
        UserDefaults.standard.set(newID, forKey: key)
        return newID
    }
    
    func selectImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        
        if panel.runModal() == .OK, let url = panel.url {
            // Check file size (5MB Limit)
            if let resources = try? url.resourceValues(forKeys: [.fileSizeKey]),
               let fileSize = resources.fileSize, fileSize > 5 * 1024 * 1024 {
                self.alertTitle = appState.localize("report_upload_fail")
                self.alertMessage = appState.localize("report_size_limit")
                self.showAlert = true
                return
            }
            if let image = NSImage(contentsOf: url) {
                self.selectedImage = image
                self.imageFileName = url.lastPathComponent
            }
        }
    }
    
    func sendReport() {
        // 1. Internet Check
        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "InternetMonitor")
        monitor.start(queue: queue)
        Thread.sleep(forTimeInterval: 0.1)
        
        if monitor.currentPath.status == .unsatisfied {
            DispatchQueue.main.async {
                self.alertTitle = self.appState.localize("report_send_fail")
                self.alertMessage = self.appState.localize("report_no_internet")
                self.showAlert = true
            }
            monitor.cancel()
            return
        }
        monitor.cancel()
        
        // 2. Validate
        if name.isEmpty || email.isEmpty || subject.isEmpty || details.isEmpty {
            self.alertTitle = appState.localize("report_incomplete")
            self.alertMessage = appState.localize("report_fill_all")
            self.showAlert = true
            return
        }
        
        self.isSending = true
        
        // 3. Prepare URL (Using Secrets)
        guard let url = URL(string: Secrets.reportUrl) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var json: [String: Any] = [
            "userID": deviceID,
            "name": name,
            "email": email,
            "subject": subject,
            "details": details
        ]
        
        if let img = selectedImage,
           let tiff = img.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) {
            json["image"] = jpegData.base64EncodedString()
            json["imageName"] = imageFileName
            json["imageType"] = "image/jpeg"
        }
        
        do { request.httpBody = try JSONSerialization.data(withJSONObject: json) } catch { self.isSending = false; return }
        
        // 4. Send
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isSending = false
                
                if error != nil {
                    self.alertTitle = self.appState.localize("report_send_fail")
                    self.alertMessage = self.appState.localize("report_net_error")
                    self.showAlert = true
                    return
                }
                
                if let data = data, let responseStr = String(data: data, encoding: .utf8) {
                    if responseStr.contains("success") {
                        self.alertTitle = self.appState.localize("report_send_success")
                        self.alertMessage = self.appState.localize("report_thank_you")
                        self.clearForm()
                    } else if responseStr.contains("User daily limit reached") {
                        self.alertTitle = self.appState.localize("report_send_fail")
                        self.alertMessage = self.appState.localize("report_limit_user")
                    } else if responseStr.contains("System daily limit reached") {
                        self.alertTitle = self.appState.localize("report_send_fail")
                        self.alertMessage = self.appState.localize("report_limit_system")
                    } else {
                        self.alertTitle = self.appState.localize("report_send_fail")
                        self.alertMessage = self.appState.localize("report_server_error")
                    }
                } else {
                    self.alertTitle = self.appState.localize("report_send_fail")
                    self.alertMessage = self.appState.localize("report_server_error")
                }
                self.showAlert = true
            }
        }.resume()
    }
    
    func clearForm() {
        name = ""; email = ""; subject = ""; details = ""; selectedImage = nil; imageFileName = ""
    }
}

// MARK: - 4. REPORT VIEW (UI)
struct ReportView: View {
    @EnvironmentObject var appState: AppState
    @StateObject var viewModel: ReportViewModel
    @Environment(\.presentationMode) var presentationMode
    
    init(appState: AppState) {
        _viewModel = StateObject(wrappedValue: ReportViewModel(appState: appState))
    }
    
    var body: some View {
        VStack(spacing: 15) {
            // Header
            ZStack {
                Text(appState.localize("report_header"))
                    .font(.title2)
                    .fontWeight(.bold)
                
                HStack {
                    Spacer()
                    Button(action: { presentationMode.wrappedValue.dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                    .help("Close")
                }
            }
            .padding([.top, .horizontal])
            
            // Form
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Group {
                        Text(appState.localize("report_name")).font(.caption).foregroundColor(.secondary)
                        TextField("", text: $viewModel.name).textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        Text(appState.localize("report_email")).font(.caption).foregroundColor(.secondary)
                        TextField("", text: $viewModel.email).textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        Text(appState.localize("report_subject")).font(.caption).foregroundColor(.secondary)
                        TextField("", text: $viewModel.subject).textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        Text(appState.localize("report_details")).font(.caption).foregroundColor(.secondary)
                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $viewModel.details)
                                .font(.body)
                                .frame(height: 100)
                                .padding(4)
                                .background(Color(NSColor.textBackgroundColor))
                                .cornerRadius(4)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.4), lineWidth: 1))
                            
                            if viewModel.details.isEmpty {
                                Text(appState.localize("report_placeholder"))
                                    .foregroundColor(.gray)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 8)
                                    .allowsHitTesting(false)
                                    .font(.caption)
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Image Upload
                    HStack {
                        Button(action: { viewModel.selectImage() }) {
                            Label(appState.localize("report_upload_btn"), systemImage: "photo")
                        }
                        
                        if let _ = viewModel.selectedImage {
                            Text(viewModel.imageFileName).foregroundColor(.green).lineLimit(1).truncationMode(.middle)
                            Button(action: { viewModel.selectedImage = nil; viewModel.imageFileName = "" }) {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                            }.buttonStyle(.plain)
                        } else {
                            Text(appState.localize("report_optional")).font(.caption).foregroundColor(.gray)
                        }
                    }
                    
                    // Submit Button
                    if viewModel.isSending {
                        HStack { Spacer(); ProgressView(appState.localize("report_sending")); Spacer() }
                    } else {
                        Button(action: { viewModel.sendReport() }) {
                            Text(appState.localize("report_submit_btn"))
                                .frame(maxWidth: .infinity)
                                .padding(5)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .padding(.top, 5)
                    }
                }
                .padding()
            }
        }
        .frame(width: 400, height: 600)
        .alert(isPresented: $viewModel.showAlert) {
            Alert(
                title: Text(viewModel.alertTitle),
                message: Text(viewModel.alertMessage),
                dismissButton: .default(Text("OK"), action: {
                    if viewModel.alertTitle == appState.localize("report_send_success") {
                        presentationMode.wrappedValue.dismiss()
                    }
                })
            )
        }
    }
}

// MARK: - 5. APP STATE & LOCALIZATION
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
    
    enum Language: String, CaseIterable { case english = "English"; case thai = "Thai" }
    enum ListMode: String, CaseIterable { case exclude = "exclude"; case target = "target" }
    
    init() {
        if let langString = defaults.string(forKey: "appLanguage"), let lang = Language(rawValue: langString) { self.currentLanguage = lang }
        if let modeString = defaults.string(forKey: "listMode"), let mode = ListMode(rawValue: modeString) { self.listMode = mode }
        
        if let savedWhitelist = defaults.stringArray(forKey: "whitelistAppsStore") {
            self.whitelistApps = savedWhitelist
        } else {
            self.whitelistApps = defaults.stringArray(forKey: "exclusionList") ?? systemApps
        }
        
        self.blacklistApps = defaults.stringArray(forKey: "blacklistAppsStore") ?? []
        if !whitelistApps.contains("BYEREDX") { whitelistApps.append("BYEREDX") }
        
        saveLists()
        self.isAccessibilityTrusted = AXIsProcessTrusted()
        self.checkLaunchAtLoginStatus()
    }
    
    func saveLists() {
        defaults.set(whitelistApps, forKey: "whitelistAppsStore")
        defaults.set(blacklistApps, forKey: "blacklistAppsStore")
    }
    
    func checkLaunchAtLoginStatus() { self.isLaunchAtLoginEnabled = (SMAppService.mainApp.status == .enabled) }
    
    func toggleLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            self.isLaunchAtLoginEnabled = enabled
        } catch { self.checkLaunchAtLoginStatus() }
    }
    
    func setLanguage(_ lang: Language) { currentLanguage = lang; defaults.set(lang.rawValue, forKey: "appLanguage"); objectWillChange.send() }
    func setListMode(_ mode: ListMode) { listMode = mode; defaults.set(mode.rawValue, forKey: "listMode"); objectWillChange.send() }
    
    func addAppToCurrentList(_ name: String) {
        guard !name.isEmpty else { return }
        if listMode == .exclude { if !whitelistApps.contains(name) { whitelistApps.append(name) } }
        else { if !blacklistApps.contains(name) { blacklistApps.append(name) } }
        saveLists(); objectWillChange.send()
    }
    
    func removeAppFromCurrentList(_ name: String) {
        if listMode == .exclude { if systemApps.contains(name) { return }; whitelistApps.removeAll { $0 == name } }
        else { blacklistApps.removeAll { $0 == name } }
        saveLists(); objectWillChange.send()
    }
    
    var currentDisplayList: [String] { return listMode == .exclude ? whitelistApps : blacklistApps }
    
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
            "mode_target": [.english: "Mode: Close Only Listed Apps (Target)", .thai: "โหมด: ปิดเฉพาะแอปที่เลือกไว้เท่านั้น"],
            
            // REPORT SYSTEM LOCALIZATION
            "report_header": [.english: "Report a Problem", .thai: "แจ้งปัญหาการใช้งาน"],
            "report_name": [.english: "Name", .thai: "ชื่อ"],
            "report_email": [.english: "Email", .thai: "อีเมล"],
            "report_subject": [.english: "Subject", .thai: "หัวข้อปัญหา"],
            "report_details": [.english: "Details", .thai: "รายละเอียด"],
            "report_placeholder": [.english: "You can report which apps are not closing correctly or any other issues here. We will fix it in the next update.", .thai: "ผู้ใช้งานสามารถแจ้งว่าโปรแกรมนี้ ไม่ตอบสนองกับแอปไหน คุณสามารถแจ้งได้ เราจะทำการแก้ไขให้ในการอัพเดตครั้งถัดไป"],
            "report_upload_btn": [.english: "Upload Image", .thai: "อัปโหลดรูปภาพ"],
            "report_optional": [.english: "(.jpeg, .png) Optional", .thai: "(.jpeg, .png) ไม่บังคับ"],
            "report_submit_btn": [.english: "Submit Report", .thai: "ส่งแจ้งปัญหา"],
            "report_sending": [.english: "Sending...", .thai: "กำลังส่งข้อมูล..."],
            "report_upload_fail": [.english: "Upload Failed", .thai: "อัปโหลดไม่สำเร็จ"],
            "report_size_limit": [.english: "Image size is too large (Max 5MB).", .thai: "ขนาดไฟล์รูปภาพใหญ่เกินไป (ต้องไม่เกิน 5MB)"],
            "report_send_fail": [.english: "Send Failed", .thai: "ส่งไม่สำเร็จ"],
            "report_no_internet": [.english: "Please connect to the internet.", .thai: "กรุณาเชื่อมต่ออินเทอร์เน็ต"],
            "report_incomplete": [.english: "Incomplete Data", .thai: "ข้อมูลไม่ครบ"],
            "report_fill_all": [.english: "Please fill in all text fields.", .thai: "กรุณากรอกข้อมูลที่เป็นตัวอักษรให้ครบถ้วน"],
            "report_net_error": [.english: "Network error. Please try again.", .thai: "ส่งข้อมูลไม่สำเร็จ กรุณาลองใหม่อีกครั้ง"],
            "report_send_success": [.english: "Success", .thai: "ส่งสำเร็จ"],
            "report_thank_you": [.english: "Thank you for your report.", .thai: "ส่งสำเร็จแล้ว ขอบคุณสำหรับการแจ้งปัญหา"],
            "report_server_error": [.english: "Server error.", .thai: "ส่งข้อมูลไม่สำเร็จ"],
            "report_limit_user": [.english: "Daily limit reached (3 reports/day).", .thai: "คุณส่งรายงานครบโควต้าประจำวันแล้ว (3 ครั้ง/วัน)"],
            "report_limit_system": [.english: "System daily limit reached. Please try again tomorrow.", .thai: "ระบบรับรายงานครบโควต้าประจำวันแล้ว กรุณาลองใหม่พรุ่งนี้"]
        ]
        return dict[key]?[currentLanguage] ?? key
    }
}

extension AppState { func refreshPermissionStatus() { self.isAccessibilityTrusted = AXIsProcessTrusted() } }

// MARK: - 6. SETTINGS VIEW
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("hideRecentDock") private var hideRecentDock = false
    let uiTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
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
                // TAB 1: General
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
                
                // TAB 2: List Manager
                VStack {
                    HStack {
                        Picker("", selection: $appState.listMode) {
                            Text(appState.localize("mode_exclude")).tag(AppState.ListMode.exclude)
                            Text(appState.localize("mode_target")).tag(AppState.ListMode.target)
                        }
                        .pickerStyle(.menu).frame(width: 320)
                        .onChange(of: appState.listMode) { oldValue, newValue in appState.setListMode(newValue) }
                    }.padding(.top, 10)
                    
                    Button(action: openFilePicker) {
                        Label(appState.localize("select_app_btn"), systemImage: "plus.magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large).buttonStyle(.borderedProminent).padding(.top, 5)
                    
                    List {
                        ForEach(appState.currentDisplayList, id: \.self) { appName in
                            HStack {
                                Image(systemName: appState.listMode == .exclude ? "shield.fill" : "target")
                                    .foregroundColor(getIconColor(appName: appName))
                                Text(appName).fontWeight(isSystemApp(appName) ? .medium : .regular)
                                Spacer()
                                if appState.listMode == .exclude && isSystemApp(appName) {
                                    Text(appState.localize("system_tag"))
                                        .font(.caption2).foregroundColor(.secondary)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color.gray.opacity(0.1)).cornerRadius(4)
                                } else {
                                    Button(action: { appState.removeAppFromCurrentList(appName) }) {
                                        Image(systemName: "xmark.circle.fill").foregroundColor(.gray).font(.title3)
                                    }.buttonStyle(.plain)
                                }
                            }.padding(.vertical, 4)
                        }
                    }.listStyle(.inset)
                }.padding().tabItem { Label(appState.localize("tab_whitelist"), systemImage: "list.bullet.rectangle") }
            }
        }
        .frame(width: 500, height: 450)
        .onReceive(uiTimer) { _ in appState.refreshPermissionStatus() }
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

// MARK: - 7. ABOUT & UPDATES
struct AboutData {
    static let version = "1.0.5"
    static let developer = "BYEREDX Team"
    static let githubUser = "trondarkmode"
    static let githubRepo = "BYEREDX"
    
    static func getUpdateNote(language: AppState.Language) -> String {
        switch language {
        case .english:
            return "Version 1.0.5: Added 'Report a Problem' feature."
        case .thai:
            return "เวอร์ชัน 1.0.5: เพิ่มระบบแจ้งปัญหาการใช้งาน"
        }
    }
}

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
                            self.showNoInternetAlert = true; self.updateStatus = "Error"
                        } else { self.updateStatus = "Error" }
                    }
                    return
                }
                if let data = data, let release = try? JSONDecoder().decode(GithubRelease.self, from: data) {
                    let serverVer = release.tagName.replacingOccurrences(of: "v", with: "")
                    let localVer = AboutData.version
                    if serverVer.compare(localVer, options: .numeric) == .orderedDescending {
                        self.latestVersion = serverVer; self.newVersionURL = URL(string: release.htmlUrl); self.updateStatus = ""
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
        alert.addButton(withTitle: "Download"); alert.addButton(withTitle: "Later")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn { if let url = self.newVersionURL { NSWorkspace.shared.open(url) } }
    }
}

struct AboutView: View {
    @EnvironmentObject var appState: AppState
    @StateObject var updater = UpdateManager.shared
    @State private var showReportWindow = false
    
    var body: some View {
        VStack(spacing: 15) {
            ZStack(alignment: .topTrailing) {
                HStack {
                    Spacer()
                    Button(action: { showReportWindow = true }) {
                        Image(systemName: "exclamationmark.bubble.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(appState.localize("report_header"))
                    .padding([.top, .trailing], 15)
                }
                .frame(maxWidth: .infinity)
                
                VStack {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .frame(width: 70, height: 70)
                        .padding(.top, 20)
                    
                    Text("BYEREDX")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("\(appState.localize("version_label")) \(AboutData.version)")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("by \(AboutData.developer)")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity)
            }
            
            if updater.updateStatus == "checking" {
                ProgressView(appState.localize("checking")).scaleEffect(0.8)
            } else if updater.updateStatus == "uptodate" {
                Text(appState.localize("uptodate")).foregroundColor(.green).font(.caption)
            } else {
                Button(action: { updater.checkForUpdates(isManual: true) }) {
                    Label(appState.localize("check_update"), systemImage: "arrow.triangle.2.circlepath")
                }.controlSize(.small)
            }
            
            Divider()
            
            ScrollView {
                Text(AboutData.getUpdateNote(language: appState.currentLanguage))
                    .font(.body)
                    .multilineTextAlignment(.leading)
                    .padding()
            }
            .frame(maxHeight: .infinity)
            
            Spacer()
        }
        .frame(width: 350, height: 450)
        .background(Color(NSColor.windowBackgroundColor))
        .alert(isPresented: $updater.showManualUpdateAlert) {
            Alert(title: Text(appState.localize("update_avail")),
                  message: Text("v\(AboutData.version) -> v\(updater.latestVersion)"),
                  primaryButton: .default(Text(appState.localize("download_btn")), action: { if let url = updater.newVersionURL { NSWorkspace.shared.open(url) } }),
                  secondaryButton: .cancel(Text(appState.localize("later_btn"))))
        }
        .overlay(EmptyView().alert(isPresented: $updater.showNoInternetAlert) { Alert(title: Text(appState.localize("no_internet_title")), message: Text(appState.localize("no_internet_msg")), dismissButton: .default(Text("OK"))) })
        .sheet(isPresented: $showReportWindow) {
            ReportView(appState: appState)
        }
    }
}
