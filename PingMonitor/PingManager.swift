import Foundation
import UserNotifications
import AppKit

enum PingStatus {
    case idle, good, warning, error
}

struct HostnameValidator {
    static func isValid(_ host: String) -> Bool {
        guard !host.isEmpty, host.count <= 253 else { return false }
        let ipv4 = /^((25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)\.){3}(25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)$/
        let ipv6 = /^\[?([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}\]?$/
        let fqdn = /^(?:[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)*[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?$/
        return (try? ipv4.firstMatch(in: host)) != nil
            || (try? ipv6.firstMatch(in: host)) != nil
            || (try? fqdn.firstMatch(in: host)) != nil
    }
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
            let clamped = max(1.0, min(3600.0, pingInterval))
            if pingInterval != clamped {
                pingInterval = clamped
                return
            }
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

    init() {
        let savedHost = UserDefaults.standard.string(forKey: "pingHost") ?? "8.8.8.8"
        self.host = HostnameValidator.isValid(savedHost) ? savedHost : "8.8.8.8"

        let savedInterval = UserDefaults.standard.double(forKey: "pingInterval")
        self.pingInterval = savedInterval == 0 ? 5 : max(1.0, min(3600.0, savedInterval))

        let savedWarning = UserDefaults.standard.double(forKey: "warningThreshold")
        self.warningThreshold = savedWarning == 0 ? 100 : max(1.0, min(30000.0, savedWarning))

        let savedError = UserDefaults.standard.double(forKey: "errorThreshold")
        self.errorThreshold = savedError == 0 ? 200 : max(1.0, min(30000.0, savedError))

        requestNotificationPermission()
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
            self.status = .error
            self.lastPingTime = -1  // Set to -1 to indicate failure
            self.packetLoss = Double(self.failedPings) / Double(self.totalPings) * 100

            self.sendNotification(title: "Ping Failed", body: error.localizedDescription)
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

        if pingTime >= errorThreshold {
            status = .error
            sendNotification(title: "High Latency", body: "Ping time: \(Int(pingTime))ms")
        } else if pingTime >= warningThreshold {
            status = .warning
        } else {
            status = .good
        }

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
