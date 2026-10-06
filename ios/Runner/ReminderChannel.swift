import Foundation
import UserNotifications

/// 本地提醒的原生投递端。
///
/// 与 Dart 侧的契约（见 `lib/services/reminder/`）：原生层不持有任何业务规则，
/// 只保证「在 `fireAtMillis` 附近投递一次」。
///
/// - 收到 `syncPlan`：先撤销上一批（按标识前缀），再登记这一批。计划里没有的
///   条目因此自然消失，无需 Dart 侧做增量 diff。
/// - 收到 `cancelAll`：撤销全部并清掉落盘的计划。
///
/// 计划本身落盘到 App Group，供排查与「已排期 N 条」的展示；它**不是**投递的
/// 依据——投递由系统按已登记的 UNNotificationRequest 完成。iOS 没有
/// `BOOT_COMPLETED` 的等价物，重启后系统会保留已登记的通知，因此不需要
/// Android 那样的重建链路。
final class ReminderChannel: NSObject {
  static let channelName = "bugaoshan/reminder"

  /// 通知标识前缀。撤销时按前缀筛选，避免误删应用内其它来源的通知。
  private static let identifierPrefix = "bugaoshan.reminder."
  private static let appGroupId = "group.io.github.thebrotherhoodofscu.bugaoshan"
  private static let storedPlanKey = "bugaoshan.reminder.plan"

  /// 与 Dart 侧 `ReminderPlan.schema` 对齐；不认识的版本直接拒绝。
  private static let supportedSchema = 1

  private let center = UNUserNotificationCenter.current()

  func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "RELEASED", message: "ReminderChannel released", details: nil))
        return
      }
      switch call.method {
      case "syncPlan":
        guard let arguments = call.arguments as? [String: Any] else {
          result(FlutterError(code: "INVALID_ARGUMENT", message: "Plan is required", details: nil))
          return
        }
        self.syncPlan(arguments, result: result)
      case "cancelAll":
        self.cancelAll(result: result)
      case "requestAuthorization":
        let provisional = (call.arguments as? [String: Any])?["provisional"] as? Bool ?? false
        self.requestAuthorization(provisional: provisional, result: result)
      case "getPermissionStatus":
        self.getPermissionStatus(result: result)
      case "getPendingCount":
        // 暴露系统实际登记数：Dart 侧只知道「我下发了 N 条」，不知道系统收下了几条
        // （超上限、时刻已过、未授权都会被系统丢弃）。排期类问题几乎都出在这个差值上。
        self.getPendingCount(result: result)
      case "openNotificationSettings":
        self.openNotificationSettings(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: - 排期

  private func syncPlan(_ payload: [String: Any], result: @escaping FlutterResult) {
    guard let schema = payload["schema"] as? Int, schema == Self.supportedSchema else {
      result(FlutterError(
        code: "UNSUPPORTED_SCHEMA",
        message: "Unsupported reminder plan schema",
        details: payload["schema"]
      ))
      return
    }

    let reminders = payload["reminders"] as? [[String: Any]] ?? []

    center.getNotificationSettings { [weak self] settings in
      guard let self else { return }
      guard settings.authorizationStatus == .authorized ||
        settings.authorizationStatus == .provisional ||
        settings.authorizationStatus == .ephemeral
      else {
        // 未授权时不登记：登记了也不会显示，反而让「已排期 N 条」误导用户。
        result(FlutterError(
          code: "NOT_AUTHORIZED",
          message: "Notification authorization not granted",
          details: nil
        ))
        return
      }

      // 全量替换：先撤销上一批，再登记新的一批。
      self.center.getPendingNotificationRequests { pending in
        let stale = pending
          .map(\.identifier)
          .filter { $0.hasPrefix(Self.identifierPrefix) }
        if !stale.isEmpty {
          self.center.removePendingNotificationRequests(withIdentifiers: stale)
        }

        self.addRequests(reminders) { added in
          self.persistPlan(payload, scheduledCount: added)
          result(added)
        }
      }
    }
  }

  private func addRequests(_ reminders: [[String: Any]], completion: @escaping (Int) -> Void) {
    var remaining = reminders.count
    if remaining == 0 {
      completion(0)
      return
    }

    // 计数用闭包，避免 DispatchGroup 里对可变状态的竞态。
    var added = 0
    let lock = NSLock()

    for reminder in reminders {
      guard
        let id = reminder["id"] as? String, !id.isEmpty,
        let fireAtMillis = reminder["fireAtMillis"] as? NSNumber
      else {
        lock.lock()
        remaining -= 1
        let done = remaining == 0
        lock.unlock()
        if done { completion(added) }
        continue
      }

      // 已过去的时刻不再登记（Dart 侧已过滤，这里再兜一层防止时钟漂移）。
      let fireDate = Date(timeIntervalSince1970: fireAtMillis.doubleValue / 1000.0)
      guard fireDate.timeIntervalSinceNow > 0 else {
        lock.lock()
        remaining -= 1
        let done = remaining == 0
        lock.unlock()
        if done { completion(added) }
        continue
      }

      let content = UNMutableNotificationContent()
      content.title = (reminder["title"] as? String) ?? ""
      content.body = (reminder["body"] as? String) ?? ""
      // 同一天同一门课的多条提前量提醒归入同一线程，锁屏上折叠展示。
      let collapseKey = reminder["collapseKey"] as? String
      if let collapseKey, !collapseKey.isEmpty {
        content.threadIdentifier = collapseKey
      }

      var components = Calendar.current.dateComponents(
        [.year, .month, .day, .hour, .minute, .second],
        from: fireDate
      )
      components.timeZone = TimeZone.current

      let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
      let request = UNNotificationRequest(
        identifier: Self.identifierPrefix + id,
        content: content,
        trigger: trigger
      )

      center.add(request) { error in
        lock.lock()
        if error == nil { added += 1 }
        remaining -= 1
        let done = remaining == 0
        lock.unlock()
        if done { completion(added) }
      }
    }
  }

  private func cancelAll(result: @escaping FlutterResult) {
    center.getPendingNotificationRequests { [weak self] pending in
      guard let self else { return }
      let stale = pending
        .map(\.identifier)
        .filter { $0.hasPrefix(Self.identifierPrefix) }
      if !stale.isEmpty {
        self.center.removePendingNotificationRequests(withIdentifiers: stale)
      }
      self.clearStoredPlan()
      result(nil)
    }
  }

  // MARK: - 授权

  private func requestAuthorization(provisional: Bool, result: @escaping FlutterResult) {
    // provisional 选项不弹授权框，直接把通知投递到通知中心（安静投递）。
    // 只有明确要「先静默试用」时才用；默认仍走标准弹窗。
    let options: UNAuthorizationOptions = provisional
      ? [.alert, .sound, .badge, .provisional]
      : [.alert, .sound, .badge]
    center.requestAuthorization(options: options) { granted, error in
      DispatchQueue.main.async {
        if let error {
          result(FlutterError(
            code: "AUTHORIZATION_FAILED",
            message: error.localizedDescription,
            details: nil
          ))
          return
        }
        result(granted)
      }
    }
  }

  private func getPermissionStatus(result: @escaping FlutterResult) {
    center.getNotificationSettings { settings in
      let status: String
      switch settings.authorizationStatus {
      case .authorized: status = "authorized"
      case .provisional: status = "provisional"
      case .ephemeral: status = "ephemeral"
      case .denied: status = "denied"
      case .notDetermined: status = "notDetermined"
      @unknown default: status = "unknown"
      }
      DispatchQueue.main.async { result(status) }
    }
  }

  // MARK: - 落盘（仅供排查与展示）

  /// 系统当前实际登记的本应用提醒条数。
  ///
  /// 与 Dart 侧的 `plan.reminders.length` 之差即「被系统丢弃的条数」——
  /// 未授权、超过 64 条上限、时刻已过都会体现为这个差值。
  private func getPendingCount(result: @escaping FlutterResult) {
    center.getPendingNotificationRequests { pending in
      let count = pending
        .map(\.identifier)
        .filter { $0.hasPrefix(Self.identifierPrefix) }
        .count
      DispatchQueue.main.async { result(count) }
    }
  }

  // MARK: - 设置跳转

  /// 打开本应用的系统设置页。
  ///
  /// iOS 没有「直接跳到通知子页」的公开 API，`openSettingsURLString` 落在应用
  /// 自己的设置页，通知开关就在首屏，是实际可用的最短路径。
  private func openNotificationSettings(result: @escaping FlutterResult) {
    guard let url = URL(string: UIApplication.openSettingsURLString) else {
      result(false)
      return
    }
    DispatchQueue.main.async {
      UIApplication.shared.open(url, options: [:]) { opened in
        result(opened)
      }
    }
  }

  private var sharedDefaults: UserDefaults? {
    UserDefaults(suiteName: Self.appGroupId)
  }

  private func persistPlan(_ payload: [String: Any], scheduledCount: Int) {
    guard let defaults = sharedDefaults else { return }
    var summary: [String: Any] = [
      "planId": (payload["planId"] as? String) ?? "",
      "scheduledCount": scheduledCount,
      "requestedCount": (payload["reminders"] as? [[String: Any]])?.count ?? 0,
    ]
    if let windowEnd = payload["windowEndMillis"] as? NSNumber {
      summary["windowEndMillis"] = windowEnd
    }
    defaults.set(summary, forKey: Self.storedPlanKey)
  }

  private func clearStoredPlan() {
    sharedDefaults?.removeObject(forKey: Self.storedPlanKey)
  }
}
