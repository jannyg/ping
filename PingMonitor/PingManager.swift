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
        let ipv6 = /^(\[)?((([0-9a-fA-F]{1,4}:){7}([0-9a-fA-F]{1,4}|:))|(([0-9a-fA-F]{1,4}:){6}(:[0-9a-fA-F]{1,4}|((25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)){3})|:))|(([0-9a-fA-F]{1,4}:){5}(((:[0-9a-fA-F]{1,4}){1,2})|:((25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)){3})|:))|(([0-9a-fA-F]{1,4}:){4}(((:[0-9a-fA-F]{1,4}){1,3})|((:[0-9a-fA-F]{1,4})?:((25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)){3}))|:))|(([0-9a-fA-F]{1,4}:){3}(((:[0-9a-fA-F]{1,4}){1,4})|((:[0-9a-fA-F]{1,4}){0,2}:((25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)){3}))|:))|(([0-9a-fA-F]{1,4}:){2}(((:[0-9a-fA-F]{1,4}){1,5})|((:[0-9a-fA-F]{1,4}){0,3}:((25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)){3}))|:))|(([0-9a-fA-F]{1,4}:){1}(((:[0-9a-fA-F]{1,4}){1,6})|((:[0-9a-fA-F]{1,4}){0,4}:((25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)){3}))|:))|(:(((:[0-9a-fA-F]{1,4}){1,7})|((:[0-9a-fA-F]{1,4}){0,5}:((25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)){3}))|:)))(\])?$/
        let fqdn = /^(?:[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)*[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.?$/
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
                persistence.set(host, forKey: "pingHost")
                restartPinging()
            }
        }
    }

    @Published var warningThreshold: Double {
        didSet {
            if warningThreshold != oldValue {
                persistence.set(warningThreshold, forKey: "warningThreshold")
            }
        }
    }

    @Published var errorThreshold: Double {
        didSet {
            if errorThreshold != oldValue {
                persistence.set(errorThreshold, forKey: "errorThreshold")
            }
        }
    }

    @Published var pingInterval: TimeInterval {
        didSet {
            // Clamp to valid range. Re-assigning here re-fires didSet once more,
            // but the guard below will pass on that second call, so no recursion.
            guard pingInterval >= 1.0, pingInterval <= 3600.0 else {
                pingInterval = max(1.0, min(3600.0, pingInterval))
                return
            }
            if pingInterval != oldValue {
                persistence.set(pingInterval, forKey: "pingInterval")
                restartPinging()
            }
        }
    }

    private var timer: Timer?
    private var currentPing: PingExecutorProtocol?
    private var totalPings: Int = 0
    private var failedPings: Int = 0
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    private let pingExecutorFactory: PingExecutorFactory
    private let notifications: NotificationServiceProtocol
    private let persistence: PersistenceProtocol

    init(
        pingExecutorFactory: @escaping PingExecutorFactory = { SimplePing(hostName: $0) },
        notifications: NotificationServiceProtocol = UNUserNotificationCenter.current(),
        persistence: PersistenceProtocol = UserDefaults.standard
    ) {
        self.pingExecutorFactory = pingExecutorFactory
        self.notifications = notifications
        self.persistence = persistence

        let savedHost = persistence.string(forKey: "pingHost") ?? "8.8.8.8"
        self.host = HostnameValidator.isValid(savedHost) ? savedHost : "8.8.8.8"

        let savedInterval = persistence.double(forKey: "pingInterval")
        self.pingInterval = savedInterval == 0 ? 5 : max(1.0, min(3600.0, savedInterval))

        let savedWarning = persistence.double(forKey: "warningThreshold")
        self.warningThreshold = savedWarning == 0 ? 100 : max(1.0, min(30000.0, savedWarning))

        let savedError = persistence.double(forKey: "errorThreshold")
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
        let ping = pingExecutorFactory(host)
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
        notifications.requestAuthorization(options: [.alert, .sound]) { granted, error in
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
        notifications.add(request, withCompletionHandler: nil)
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
