import SwiftUI

struct ContentView: View {
    @ObservedObject var pingManager: PingManager
    @State private var showingSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Packet Inter-Network Groper")
                    .font(.headline)
                Spacer()
                Button(action: { showingSettings.toggle() }) {
                    Image(systemName: "gear")
                }
            }

            Divider()

            Group {
                StatusRow(title: "Status", value: statusText)
                StatusRow(title: "Host", value: pingManager.host)
                StatusRow(title: "Last Ping", value: pingManager.lastPingTime < 0 ? "Failed" : "\(Int(pingManager.lastPingTime))ms")
                StatusRow(title: "Average", value: "\(Int(pingManager.averagePingTime))ms")
                StatusRow(title: "Packet Loss", value: String(format: "%.1f%%", pingManager.packetLoss))
            }

            if showingSettings {
                Divider()

                Group {
                    SettingsRow(title: "Host", text: $pingManager.host)
                    SettingsRow(title: "Warning at", text: Binding(
                        get: { String(Int(pingManager.warningThreshold)) },
                        set: { pingManager.warningThreshold = Double($0) ?? 100 }
                    ))
                    .suffix(text: "ms")

                    SettingsRow(title: "Error at", text: Binding(
                        get: { String(Int(pingManager.errorThreshold)) },
                        set: { pingManager.errorThreshold = Double($0) ?? 200 }
                    ))
                    .suffix(text: "ms")

                    SettingsRow(title: "Interval", text: Binding(
                        get: { String(Int(pingManager.pingInterval)) },
                        set: { pingManager.pingInterval = Double($0) ?? 5 }
                    ))
                    .suffix(text: "sec")
                }
            }

            Divider()

            HStack {
                Button("Reset Stats") {
                    pingManager.resetStats()
                }
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .frame(width: 250)
    }

    private var statusText: String {
        switch pingManager.status {
        case .good:
            return "Good"
        case .warning:
            return "Warning"
        case .error:
            return "Error"
        case .idle:
            return "Idle"
        }
    }
}

public struct StatusRow: View {
    let title: String
    let value: String

    public var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .bold()
        }
    }
}

public struct SettingsRow: View {
    let title: String
    @Binding var text: String
    private var suffixText: String = ""

    public init(title: String, text: Binding<String>) {
        self.title = title
        self._text = text
    }

    public var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
            if !suffixText.isEmpty {
                Text(suffixText)
                    .foregroundColor(.secondary)
            }
        }
    }

    public func suffix(text: String) -> SettingsRow {
        var view = self
        view.suffixText = text
        return view
    }
}
