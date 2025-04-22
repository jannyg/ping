import Foundation
import Network
import UserNotifications

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
            UserDefaults.standard.set(host, forKey: "pingHost")
            restartPinging()
        }
    }

    @Published var warningThreshold: Double {
        didSet {
            UserDefaults.standard.set(warningThreshold, forKey: "warningThreshold")
        }
    }

    @Published var errorThreshold: Double {
        didSet {
            UserDefaults.standard.set(errorThreshold, forKey: "errorThreshold")
        }
    }

    @Published var pingInterval: TimeInterval {
        didSet {
            UserDefaults.standard.set(pingInterval, forKey: "pingInterval")
            restartPinging()
        }
    }

    private var timer: Timer?
    private var currentPing: SimplePing?
    private var totalPings: Int = 0
    private var failedPings: Int = 0

    init() {
        // Load saved settings or use defaults
        self.host = UserDefaults.standard.string(forKey: "pingHost") ?? "8.8.8.8"
        self.warningThreshold = UserDefaults.standard.double(forKey: "warningThreshold")
        self.errorThreshold = UserDefaults.standard.double(forKey: "errorThreshold")
        self.pingInterval = UserDefaults.standard.double(forKey: "pingInterval")

        // Set defaults if not previously set
        if self.warningThreshold == 0 { self.warningThreshold = 100 }
        if self.errorThreshold == 0 { self.errorThreshold = 200 }
        if self.pingInterval == 0 { self.pingInterval = 5 }

        requestNotificationPermission()
        startPinging()
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

        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self, weak ping] in
            if ping === self?.currentPing {
                self?.currentPing?.stop()
                self?.handlePingFailure(error: NSError(domain: "PingMonitor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Timeout"]))
            }
        }
    }

    private func handlePingFailure(error: Error) {
        DispatchQueue.main.async {
            self.failedPings += 1
            self.totalPings += 1
            self.status = .error
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
            failedPings += 1
            sendNotification(title: "High Latency", body: "Ping time: \(Int(pingTime))ms")
        } else if pingTime >= warningThreshold {
            status = .warning
        } else {
            status = .good
        }

        packetLoss = Double(failedPings) / Double(totalPings) * 100
        averagePingTime = (averagePingTime * Double(totalPings - 1) + pingTime) / Double(totalPings)
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
