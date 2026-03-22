# Packet Inter-Network Groper

![Build](https://github.com/jannyg/ping/actions/workflows/build.yml/badge.svg)

A macOS menu bar app that continuously monitors network connectivity by pinging a specified host. Instant visual feedback and live statistics — always visible in your menu bar.

## Features

- Real-time latency monitoring with configurable ping interval
- Visual status indicator in the menu bar (green / yellow / red)
- Live statistics: current ping, rolling average, and packet loss
- Configurable warning and error thresholds
- System notifications on high latency or ping failures
- Handles sleep/wake cycles gracefully — no stale stats after waking up

## Requirements

- macOS 13.0 (Ventura) or later

## Getting Started

1. Clone the repo and open `PingMonitor.xcodeproj` in Xcode
2. Select the `PingMonitor` scheme and run (`⌘R`)
3. The app appears in your menu bar — click the icon to open the stats panel
4. Click the gear icon to configure host, thresholds, and ping interval

## Use Cases

- **Commuting**: track connection stability on trains or buses
- **Remote work**: monitor quality when working from cafés or co-working spaces
- **Troubleshooting**: gather latency and packet loss data to share with IT support
- **Public WiFi**: assess reliability before starting important calls or transfers

## License

MIT
