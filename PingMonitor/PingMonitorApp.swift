import SwiftUI

@main
struct PingMonitorApp: App {
    @StateObject private var pingManager = PingManager()

    var body: some Scene {
        MenuBarExtra {
            ContentView(pingManager: pingManager)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: statusIcon)
                    .symbolRenderingMode(.monochrome)
                if pingManager.status != .idle {
                    if pingManager.lastPingTime < 0 {
                        Text("!")
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                    } else {
                        Text(pingTimeDisplay)
                            .font(.system(size: 10))
                    }
                }
            }
        }
        .menuBarExtraStyle(.window)
    }

    private var statusIcon: String {
        switch pingManager.status {
        case .good:
            return "checkmark.circle"
        case .warning:
            return "exclamationmark.circle"
        case .error:
            return "xmark.circle"
        case .idle:
            return "circle"
        }
    }

    private var pingTimeDisplay: String {
        if pingManager.lastPingTime < 0 {
            return "!"
        } else if pingManager.lastPingTime == 0 {
            return "-"
        } else {
            return "\(Int(pingManager.lastPingTime))"
        }
    }
}
