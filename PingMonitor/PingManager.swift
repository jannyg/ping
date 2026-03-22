import Foundation
import UserNotifications
import AppKit

enum PingStatus {
    case idle, good, warning, error
}

class PingManager: ObservableObject {
    @Published var status: PingStatus = .idle
    @Published var lastPingTime: TimeInterval = 0
    @Published var averagePingTime: TimeInterval = 0
    @Published var packetLoss: Double = 0

    @Published var host: String {
        didSet {
            if host != oldValue {
                UserDefaults.standard.set(host, forKey: "pingHost")
                restartPinging()
            }
        }
    }

    @Published var warningThreshold: Double {
        didSet {
            if warningThreshold != oldValue {
                UserDefaults.standard.set(warningThreshold, forKey: "warningThreshold")
            }
        }
    }

    @Published var errorThreshold: Double {
        didSet {
            if errorThreshold != oldValue {
                UserDefaults.standard.set(errorThreshold, forKey: "errorThreshold")
            }
        }
    }

    @Published var pingInterval: TimeInterval {
        didSet {
            if pingInterval != oldValue {
                UserDefaults.standard.set(pingInterval, forKey: "pingInterval")
                restartPinging()
            }
        }
    }

    private var timer: Timer?
    private var currentPing: SimplePing?
    private var totalPings: Int = 0
    private var failedPings: Int = 0
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var previousStatus: PingStatus = .idle

    init() {
        // Load saved settings or use defaults
        self.host = UserDefaults.standard.string(forKey: "pingHost") ?? "8.8.8.8"
        self.pingInterval = UserDefaults.standard.double(forKey: "pingInterval")
        self.warningThreshold = UserDefaults.standard.double(forKey: "warningThreshold")
        self.errorThreshold = UserDefaults.standard.double(forKey: "errorThreshold")

        // Set defaults if not previously set
        if self.pingInterval == 0 { self.pingInterval = 5 }
        if self.warningThreshold == 0 { self.warningThreshold = 100 }
        if self.errorThreshold == 0 { self.errorThreshold = 200 }

        if !UserDefaults.standard.bool(forKey: "hasRequestedNotificationPermission") {
            requestNotificationPermission()
            UserDefaults.standard.set(true, forKey: "hasRequestedNotificationPermission")
        }
        restartPinging()
        registerSleepWakeObservers()
    }

    deinit {
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }

    private func registerSleepWakeObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        sleepObserver = nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handleSleep()
        }
        wakeObserver = nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handleWake()
        }
    }

    private func handleSleep() {
        timer?.invalidate()
        timer = nil
        currentPing?.stop()
        currentPing = nil
        status = .idle
    }

    private func handleWake() {
        // Wait briefly for network to come back up before pinging
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.restartPinging()
        }
    }

    private func restartPinging() {
        timer?.invalidate()
        startPinging()
    }

    func startPinging() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: pingInterval, repeats: true) { [weak self] _ in
            self?.pingHost()
        }
        pingHost() // Start first ping immediately
    }

    private func pingHost() {
        currentPing?.stop()
        let ping = SimplePing(hostName: host)
        ping.delegate = self
        currentPing = ping
        ping.start()
    }

    private func handlePingFailure(error: Error) {
        DispatchQueue.main.async {
            self.failedPings += 1
            self.totalPings += 1
            self.lastPingTime = -1
            self.packetLoss = Double(self.failedPings) / Double(self.totalPings) * 100

            let newStatus = PingStatus.error
            if self.previousStatus != newStatus {
                self.sendNotification(title: "Ping Failed", body: error.localizedDescription)
            }
            self.status = newStatus
            self.previousStatus = newStatus
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if granted {
                print("Notification permission granted")
            } else if let error = error {
                print("Error requesting notification permission: \(error)")
            }
        }
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func updateStatus(pingTime: TimeInterval) {
        lastPingTime = pingTime
        totalPings += 1

        let newStatus: PingStatus
        if pingTime >= errorThreshold {
            newStatus = .error
        } else if pingTime >= warningThreshold {
            newStatus = .warning
        } else {
            newStatus = .good
        }

        if newStatus != previousStatus {
            if newStatus == .error {
                sendNotification(title: "High Latency", body: "Ping time: \(Int(pingTime))ms")
            } else if newStatus == .warning && previousStatus != .error {
                sendNotification(title: "Elevated Latency", body: "Ping time: \(Int(pingTime))ms")
            }
        }
        status = newStatus
        previousStatus = newStatus

        packetLoss = Double(failedPings) / Double(totalPings) * 100
        averagePingTime = (averagePingTime * Double(totalPings - 1) + pingTime) / Double(totalPings)
    }

    func resetStats() {
        DispatchQueue.main.async {
            self.totalPings = 0
            self.failedPings = 0
            self.lastPingTime = 0
            self.averagePingTime = 0
            self.packetLoss = 0
            self.status = .idle
            self.previousStatus = .idle
        }
    }
}

extension PingManager: SimplePingDelegate {
    func simplePing(_ pinger: SimplePing, didReceiveReplyWithTime time: TimeInterval) {
        DispatchQueue.main.async {
            self.updateStatus(pingTime: time)
        }
    }

    func simplePing(_ pinger: SimplePing, didFailWithError error: Error) {
        handlePingFailure(error: error)
    }
}
