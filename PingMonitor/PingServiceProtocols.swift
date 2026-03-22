import Foundation
import UserNotifications

// MARK: - Ping executor

protocol PingExecutorProtocol: AnyObject {
    var delegate: SimplePingDelegate? { get set }
    func start()
    func stop()
}

typealias PingExecutorFactory = (String) -> PingExecutorProtocol

extension SimplePing: PingExecutorProtocol {}

// MARK: - Notifications

protocol NotificationServiceProtocol {
    func requestAuthorization(options: UNAuthorizationOptions, completionHandler: @escaping (Bool, Error?) -> Void)
    func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: ((Error?) -> Void)?)
}

extension UNUserNotificationCenter: NotificationServiceProtocol {}

// MARK: - Persistence

protocol PersistenceProtocol {
    func string(forKey key: String) -> String?
    func double(forKey key: String) -> Double
    func bool(forKey key: String) -> Bool
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: PersistenceProtocol {}
