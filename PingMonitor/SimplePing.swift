import Foundation
import os.log

protocol SimplePingDelegate: AnyObject {
    func simplePing(_ pinger: SimplePing, didReceiveReplyWithTime time: TimeInterval)
    func simplePing(_ pinger: SimplePing, didFailWithError error: Error)
}

class SimplePing {
    weak var delegate: SimplePingDelegate?
    private let hostName: String
    private let process = Process()
    private var isCompleted = false
    private let logger = Logger(subsystem: "dev.jannyg.pingmonitor", category: "SimplePing")

    init(hostName: String) {
        self.hostName = hostName
    }

    func start() {
        let timeout: TimeInterval = 10 // seconds

        // Verify ping executable exists and is accessible
        let pingPath = "/sbin/ping"
        guard FileManager.default.fileExists(atPath: pingPath) else {
            logger.error("Ping executable not found at \(pingPath)")
            complete(withError: NSError(domain: "SimplePing", code: -1, userInfo: [NSLocalizedDescriptionKey: "Ping executable not found"]))
            return
        }

        process.executableURL = URL(fileURLWithPath: pingPath)
        process.arguments = ["-c", "3", hostName]

        #if DEBUG
        logger.debug("Executing command: /sbin/ping -c 3 \(self.hostName)")
        #endif

        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            logger.error("Failed to start ping: \(error.localizedDescription)")
            complete(withError: error)
            return
        }

        #if DEBUG
        logger.debug("Starting ping to host: \(self.hostName)")
        #endif

        // All delegate callbacks are dispatched to the main thread below.

        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self = self else { return }
            if self.process.isRunning {
                #if DEBUG
                self.logger.debug("Ping process is still running after timeout. Terminating...")
                #endif
                self.process.terminate()
                DispatchQueue.main.async {
                    self.complete(withError: NSError(domain: "SimplePing", code: -1, userInfo: [NSLocalizedDescriptionKey: "Ping process timed out"]))
                }
            }
        }

        DispatchQueue.global().async { [weak self] in
            guard let self = self else { return }
            #if DEBUG
            self.logger.debug("Ping process is running: \(self.process.isRunning)")
            #endif
            self.process.waitUntilExit()
            DispatchQueue.main.async {
                self.handleProcessTermination()
            }
        }
    }

    func stop() {
        if process.isRunning {
            process.terminate()
        }
    }

    private func complete(withTime time: TimeInterval) {
        guard !isCompleted else { return }
        isCompleted = true
        delegate?.simplePing(self, didReceiveReplyWithTime: time)
    }

    private func complete(withError error: Error) {
        guard !isCompleted else { return }
        isCompleted = true
        delegate?.simplePing(self, didFailWithError: error)
    }

    private func handleProcessTermination() {
        let outputPipe = process.standardOutput as? Pipe
        let errorPipe = process.standardError as? Pipe

        let outputData = outputPipe?.fileHandleForReading.readDataToEndOfFile() ?? Data()
        let errorData = errorPipe?.fileHandleForReading.readDataToEndOfFile() ?? Data()

        #if DEBUG
        logger.debug("Raw stdout data: \(outputData)")
        logger.debug("Raw stderr data: \(errorData)")
        #endif

        let output = String(data: outputData, encoding: .utf8) ?? ""
        let error = String(data: errorData, encoding: .utf8) ?? ""

        #if DEBUG
        logger.debug("Stdout: \(output)")
        logger.debug("Stderr: \(error)")
        #endif

        // Combine stdout and stderr for processing
        let combinedOutput = output + "\n" + error

        #if DEBUG
        logger.debug("Combined output: \(combinedOutput)")
        #endif

        let status = process.terminationStatus
        logger.info("Process terminated with status: \(status)")

        if !combinedOutput.isEmpty {
            self.processPingOutput(combinedOutput)
        } else {
            complete(withError: NSError(domain: "SimplePing", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "No output received"]))
        }
    }

    private func processPingOutput(_ output: String) {
        #if DEBUG
        logger.debug("Processing ping output: \(output)")
        #endif

        // Check for "No route to host" error
        if output.contains("sendto: No route to host") || output.contains("No route to host") {
            complete(withError: NSError(domain: "SimplePing", code: -1, userInfo: [NSLocalizedDescriptionKey: "No route to host"]))
            return
        }

        // Check for "Request timeout" error
        if output.contains("Request timeout for icmp_seq") {
            complete(withError: NSError(domain: "SimplePing", code: -1, userInfo: [NSLocalizedDescriptionKey: "Request timeout"]))
            return
        }

        // Check for 100% packet loss
        if output.contains("100% packet loss") {
            complete(withError: NSError(domain: "SimplePing", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response from host"]))
            return
        }

        // Parse average from summary line: "round-trip min/avg/max/stddev = X/Y/Z/W ms"
        if let summaryLine = output.components(separatedBy: "\n").first(where: { $0.contains("min/avg/max") }),
           let statsStr = summaryLine.components(separatedBy: " = ").last,
           let avgStr = statsStr.components(separatedBy: "/").dropFirst().first,
           let avg = Double(avgStr) {
            complete(withTime: avg)
            return
        }

        // Fall back to last individual time= value
        if output.contains("time="),
           let timeStr = output.components(separatedBy: "time=").last?
               .components(separatedBy: " ").first?
               .trimmingCharacters(in: .whitespaces),
           let time = Double(timeStr) {
            complete(withTime: time)
            return
        }

        // Handle unexpected or empty output
        if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            complete(withError: NSError(domain: "SimplePing", code: -1, userInfo: [NSLocalizedDescriptionKey: "No output received or unexpected output format"]))
            return
        }

        // Default case: unknown error
        complete(withError: NSError(domain: "SimplePing", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown error occurred"]))
    }
}
