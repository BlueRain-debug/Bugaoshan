package io.github.the_brotherhood_of_scu.bugaoshan.reminder

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 本地提醒的 MethodChannel 处理入口。
 *
 * 与 Dart 侧的契约（见 `lib/services/reminder/reminder_transport.dart`）：
 * - Channel 名称: `bugaoshan/reminder`
 * - 六个暴露方法:
 *   1. `syncPlan(payload)`: 全量替换排期计划。未授权返回 NOT_AUTHORIZED；不支持的 schema 返回 UNSUPPORTED_SCHEMA。
 *   2. `cancelAll()`: 撤销全部排期并清空持久化存储。
 *   3. `requestAuthorization(provisional)`: 请求通知权限，返回是否已获得。
 *   4. `getPermissionStatus()`: 查询当前授权状态（authorized / provisional / denied / notDetermined / unknown）。
 *   5. `getPendingCount()`: 查询当前系统中有效待触发的提醒条数。
 *   6. `openNotificationSettings()`: 跳转到系统通知设置页面。
 */
class ReminderChannel(private val activity: Activity) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "ReminderChannel"
        const val CHANNEL_NAME = "bugaoshan/reminder"
        private const val SUPPORTED_SCHEMA = 1

        /**
         * 独立权限请求码，与 NotificationPermissionHandler (1001) 互不重叠。
         */
        const val REQUEST_CODE_REMINDER_POST_NOTIFICATIONS = 1002

        private const val PREFS_NAME = "bugaoshan_reminder_channel_prefs"
        private const val KEY_HAS_REQUESTED_PERMISSION = "has_requested_notification_permission"
    }

    private var pendingAuthResult: MethodChannel.Result? = null

    /**
     * 注册 MethodChannel。
     */
    fun register(messenger: BinaryMessenger) {
        val channel = MethodChannel(messenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "syncPlan" -> {
                val arguments = call.arguments as? Map<String, Any?>
                if (arguments == null) {
                    result.error("INVALID_ARGUMENT", "Plan is required", null)
                    return
                }
                syncPlan(arguments, result)
            }
            "cancelAll" -> {
                cancelAll(result)
            }
            "requestAuthorization" -> {
                requestAuthorization(result)
            }
            "getPermissionStatus" -> {
                getPermissionStatus(result)
            }
            "getPendingCount" -> {
                getPendingCount(result)
            }
            "openNotificationSettings" -> {
                openNotificationSettings(result)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    /**
     * Activity 处理运行时权限结果的回调钩子。
     */
    fun consumePermissionResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != REQUEST_CODE_REMINDER_POST_NOTIFICATIONS) return false
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingAuthResult?.success(granted)
        pendingAuthResult = null
        return true
    }

    // MARK: - 业务逻辑实现

    private fun syncPlan(payload: Map<String, Any?>, result: MethodChannel.Result) {
        val schema = (payload["schema"] as? Number)?.toInt()
        if (schema != SUPPORTED_SCHEMA) {
            result.error(
                "UNSUPPORTED_SCHEMA",
                "Unsupported reminder plan schema",
                payload["schema"],
            )
            return
        }

        // 检查通知授权状态，未授权时绝不登记
        if (!isNotificationAuthorized(activity)) {
            result.error(
                "NOT_AUTHORIZED",
                "Notification authorization not granted",
                null,
            )
            return
        }

        val planData = ReminderPlanData.fromChannelMap(payload)
        if (planData == null) {
            result.error("INVALID_ARGUMENT", "Malformed reminder plan payload", null)
            return
        }

        val scheduledCount = ReminderScheduler.syncPlan(activity, planData)
        // 契约返回 void，传 null 或 scheduledCount 均可
        result.success(scheduledCount)
    }

    private fun cancelAll(result: MethodChannel.Result) {
        ReminderScheduler.cancelAll(activity)
        result.success(null)
    }

    private fun requestAuthorization(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            // Android 13 之前，通知权限在安装时默认开启，检查是否在系统设置中被关闭
            val enabled = NotificationManagerCompat.from(activity).areNotificationsEnabled()
            result.success(enabled)
            return
        }

        if (ContextCompat.checkSelfPermission(
                activity,
                android.Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }

        // 记录曾经发起过权限请求，供 getPermissionStatus 区分 notDetermined 与 denied
        markPermissionRequested()
        pendingAuthResult = result

        try {
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                REQUEST_CODE_REMINDER_POST_NOTIFICATIONS,
            )
        } catch (e: Exception) {
            Log.e(TAG, "Failed to request POST_NOTIFICATIONS", e)
            pendingAuthResult = null
            result.success(false)
        }
    }

    private fun getPermissionStatus(result: MethodChannel.Result) {
        val areEnabled = NotificationManagerCompat.from(activity).areNotificationsEnabled()
        if (!areEnabled) {
            // 无论是全局关闭还是被撤销，均视为 denied
            result.success("denied")
            return
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success("authorized")
            return
        }

        val granted = ContextCompat.checkSelfPermission(
            activity,
            android.Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED

        if (granted) {
            result.success("authorized")
        } else {
            val hasRequested = hasRequestedPermission()
            if (!hasRequested) {
                // 尚未向用户申请过
                result.success("notDetermined")
            } else {
                result.success("denied")
            }
        }
    }

    private fun getPendingCount(result: MethodChannel.Result) {
        val count = ReminderScheduler.getPendingCount(activity)
        result.success(count)
    }

    private fun openNotificationSettings(result: MethodChannel.Result) {
        try {
            val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                    putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
                }
            } else {
                Intent("android.settings.APP_NOTIFICATION_SETTINGS").apply {
                    putExtra("app_package", activity.packageName)
                    putExtra("app_uid", activity.applicationInfo.uid)
                }
            }
            activity.startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to open notification settings directly, falling back to app details", e)
            try {
                val fallback = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.fromParts("package", activity.packageName, null)
                }
                activity.startActivity(fallback)
                result.success(true)
            } catch (e2: Exception) {
                Log.e(TAG, "Failed to open any settings page", e2)
                result.success(false)
            }
        }
    }

    // MARK: - 辅助检查

    private fun isNotificationAuthorized(context: Context): Boolean {
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) {
            return false
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            return ContextCompat.checkSelfPermission(
                context,
                android.Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED
        }
        return true
    }

    private fun markPermissionRequested() {
        val prefs = activity.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().putBoolean(KEY_HAS_REQUESTED_PERMISSION, true).apply()
    }

    private fun hasRequestedPermission(): Boolean {
        val prefs = activity.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getBoolean(KEY_HAS_REQUESTED_PERMISSION, false)
    }
}
