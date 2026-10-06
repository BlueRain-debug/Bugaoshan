import ActivityKit
import Flutter
import Foundation
import UIKit

/// 灵动岛 / Live Activity 的原生通信通道。
///
/// 与 Dart 侧的契约（见 `lib/services/reminder/live_activity_service.dart`）：
/// - Live Activity 依托 iOS 16.1+ 的 ActivityKit 框架；
/// - 系统硬约束：必须在应用处于前台活跃状态（`UIApplication.shared.applicationState == .active`）时调用 `start`；
/// - 倒计时在小组件侧通过 `Text(timerInterval:countsDown:)` 自更新，无需原生轮询或频繁 `update`；
/// - 课程切换或下课时通过 `update` / `end` 进行生命周期管理。
final class LiveActivityChannel: NSObject {
  static let channelName = "bugaoshan/live_activity"

  func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(
          FlutterError(
            code: "RELEASED",
            message: "LiveActivityChannel released",
            details: nil
          )
        )
        return
      }

      if #available(iOS 16.1, *) {
        self.handleCall(call, result: result)
      } else {
        if call.method == "isSupported" {
          result(false)
        } else {
          result(
            FlutterError(
              code: "UNSUPPORTED_PLATFORM",
              message: "Live Activities require iOS 16.1 or later",
              details: nil
            )
          )
        }
      }
    }
  }

  // MARK: - 方法分发（iOS 16.1+）

  @available(iOS 16.1, *)
  private func handleCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isSupported":
      isSupported(result: result)
    case "start":
      guard let arguments = call.arguments as? [String: Any] else {
        result(
          FlutterError(
            code: "INVALID_ARGUMENT",
            message: "Arguments are required for start",
            details: nil
          )
        )
        return
      }
      start(arguments: arguments, result: result)
    case "update":
      guard let arguments = call.arguments as? [String: Any] else {
        result(
          FlutterError(
            code: "INVALID_ARGUMENT",
            message: "Arguments are required for update",
            details: nil
          )
        )
        return
      }
      update(arguments: arguments, result: result)
    case "end":
      end(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - 能力检测与授权

  @available(iOS 16.1, *)
  private func isSupported(result: @escaping FlutterResult) {
    // ActivityAuthorizationInfo 反映系统全局开关及用户是否在设置中为本应用开启了实时活动。
    let areActivitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
    result(areActivitiesEnabled)
  }

  // MARK: - 启动实时活动

  @available(iOS 16.1, *)
  private func start(arguments: [String: Any], result: @escaping FlutterResult) {
    // 硬约束校验：iOS 要求 Live Activity 只能由处于前台活跃状态的应用启动。
    // 在后台调用会直接被系统底层拒绝，因此提早给出明确错误码以便 Dart 侧感知。
    guard UIApplication.shared.applicationState == .active else {
      result(
        FlutterError(
          code: "NOT_IN_FOREGROUND",
          message: "Live Activity can only be started while the application is in foreground",
          details: nil
        )
      )
      return
    }

    // 检查用户是否在系统设置中允许了实时活动。
    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      result(
        FlutterError(
          code: "NOT_AUTHORIZED",
          message: "Live Activities are disabled in system settings",
          details: nil
        )
      )
      return
    }

    guard
      let courseName = arguments["courseName"] as? String, !courseName.isEmpty,
      let location = arguments["location"] as? String,
      let endAtMillis = arguments["endAtMillis"] as? NSNumber
    else {
      result(
        FlutterError(
          code: "INVALID_ARGUMENT",
          message: "courseName, location and endAtMillis are required",
          details: nil
        )
      )
      return
    }

    let startAtMillis = arguments["startAtMillis"] as? NSNumber
    let startDate: Date
    if let startAtMillis {
      startDate = Date(timeIntervalSince1970: startAtMillis.doubleValue / 1000.0)
    } else {
      startDate = Date()
    }
    let endDate = Date(timeIntervalSince1970: endAtMillis.doubleValue / 1000.0)

    let nextCourseName = arguments["nextCourseName"] as? String
    let nextLocation = arguments["nextLocation"] as? String

    // 单活动策略：清理之前遗留的课程实时活动，避免灵动岛或锁屏同时出现多个课程卡片。
    cleanExistingActivities()

    let attributes = CourseLiveActivityAttributes(sessionId: "current_course")
    let contentState = CourseLiveActivityAttributes.ContentState(
      courseName: courseName,
      location: location,
      startAt: startDate,
      endAt: endDate,
      nextCourseName: nextCourseName,
      nextLocation: nextLocation
    )

    do {
      if #available(iOS 16.2, *) {
        let content = ActivityContent(state: contentState, staleDate: endDate)
        let activity = try Activity<CourseLiveActivityAttributes>.request(
          attributes: attributes,
          content: content
        )
        result(activity.id)
      } else {
        let activity = try Activity<CourseLiveActivityAttributes>.request(
          attributes: attributes,
          contentState: contentState
        )
        result(activity.id)
      }
    } catch {
      result(
        FlutterError(
          code: "ACTIVITY_START_FAILED",
          message: error.localizedDescription,
          details: nil
        )
      )
    }
  }

  // MARK: - 更新实时活动

  @available(iOS 16.1, *)
  private func update(arguments: [String: Any], result: @escaping FlutterResult) {
    guard let activity = Activity<CourseLiveActivityAttributes>.activities.first else {
      result(
        FlutterError(
          code: "NO_ACTIVE_ACTIVITY",
          message: "No active Live Activity found to update",
          details: nil
        )
      )
      return
    }

    // 局部更新：以已有状态为基准合并新入参。
    let currentState: CourseLiveActivityAttributes.ContentState
    if #available(iOS 16.2, *) {
      currentState = activity.content.state
    } else {
      currentState = activity.contentState
    }

    let courseName = (arguments["courseName"] as? String) ?? currentState.courseName
    let location = (arguments["location"] as? String) ?? currentState.location

    let startDate: Date
    if let startAtMillis = arguments["startAtMillis"] as? NSNumber {
      startDate = Date(timeIntervalSince1970: startAtMillis.doubleValue / 1000.0)
    } else {
      startDate = currentState.startAt
    }

    let endDate: Date
    if let endAtMillis = arguments["endAtMillis"] as? NSNumber {
      endDate = Date(timeIntervalSince1970: endAtMillis.doubleValue / 1000.0)
    } else {
      endDate = currentState.endAt
    }

    let nextCourseName = (arguments["nextCourseName"] as? String) ?? currentState.nextCourseName
    let nextLocation = (arguments["nextLocation"] as? String) ?? currentState.nextLocation

    let newState = CourseLiveActivityAttributes.ContentState(
      courseName: courseName,
      location: location,
      startAt: startDate,
      endAt: endDate,
      nextCourseName: nextCourseName,
      nextLocation: nextLocation
    )

    Task {
      if #available(iOS 16.2, *) {
        let content = ActivityContent(state: newState, staleDate: endDate)
        await activity.update(content)
      } else {
        await activity.update(using: newState)
      }
      DispatchQueue.main.async {
        result(nil)
      }
    }
  }

  // MARK: - 结束实时活动

  @available(iOS 16.1, *)
  private func end(result: @escaping FlutterResult) {
    let activities = Activity<CourseLiveActivityAttributes>.activities
    guard !activities.isEmpty else {
      result(nil)
      return
    }

    Task {
      for activity in activities {
        if #available(iOS 16.2, *) {
          await activity.end(nil, dismissalPolicy: .immediate)
        } else {
          await activity.end(dismissalPolicy: .immediate)
        }
      }
      DispatchQueue.main.async {
        result(nil)
      }
    }
  }

  // MARK: - 内部清理

  @available(iOS 16.1, *)
  private func cleanExistingActivities() {
    let activities = Activity<CourseLiveActivityAttributes>.activities
    for activity in activities {
      Task {
        if #available(iOS 16.2, *) {
          await activity.end(nil, dismissalPolicy: .immediate)
        } else {
          await activity.end(dismissalPolicy: .immediate)
        }
      }
    }
  }
}
