import Foundation

protocol SimplePingDelegate: AnyObject {
    func simplePing(_ pinger: SimplePing, didReceiveReplyWithTime time: TimeInterval)
    func simplePing(_ pinger: SimplePing, didFailWithError error: Error)
}

class SimplePing {
    weak var delegate: SimplePingDelegate?
    private let hostName: String
    private let process = Process()
    private let startTime: Date

    init(hostName: String) {
        self.hostName = hostName
        self.startTime = Date()
    }

    func start() {
        process.executableURL = URL(fileURLWithPath: "/sbin/ping")
        process.arguments = ["-c", "1", hostName]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()

            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                guard let self = self else { return }
                let data = handle.availableData
                if !data.isEmpty {
                    let output = String(data: data, encoding: .utf8) ?? ""
                    self.processPingOutput(output)
                }
            }
        } catch {
            delegate?.simplePing(self, didFailWithError: error)
        }
    }

    func stop() {
        if process.isRunning {
            process.terminate()
        }
    }

    private func processPingOutput(_ output: String) {
        if output.contains("time=") {
            if let timeStr = output.components(separatedBy: "time=").last?
                .components(separatedBy: " ").first?
                .trimmingCharacters(in: .whitespaces),
               let time = Double(timeStr) {
                delegate?.simplePing(self, didReceiveReplyWithTime: time)
            }
        } else if output.contains("Request timeout") || output.contains("100.0% packet loss") {
            delegate?.simplePing(self, didFailWithError: NSError(domain: "SimplePing", code: -1, userInfo: [NSLocalizedDescriptionKey: "Timeout"]))
        } else if !output.contains("PING") && !output.isEmpty {
            delegate?.simplePing(self, didFailWithError: NSError(domain: "SimplePing", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to ping host"]))
        }
    }
}
