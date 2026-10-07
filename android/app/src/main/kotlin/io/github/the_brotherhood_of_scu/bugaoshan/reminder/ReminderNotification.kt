package io.github.the_brotherhood_of_scu.bugaoshan.reminder

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import io.github.the_brotherhood_of_scu.bugaoshan.MainActivity
import io.github.the_brotherhood_of_scu.bugaoshan.R

/**
 * 本地提醒的通知构建与通知渠道管理。
 *
 * 与既有 [io.github.the_brotherhood_of_scu.bugaoshan.update.DownloadNotificationService] 分离：
 * - 下载通知为低优先级（IMPORTANCE_LOW）常驻进度条，静音且不震动。
 * - 课程提醒为高优先级（IMPORTANCE_HIGH）横幅通知，支持声音、震动与锁屏唤醒。
 *
 * 渠道 ID 默认为 [DEFAULT_CHANNEL_ID]（与 Dart 侧 `channel: bugaoshan_reminder` 严格对应）。
 */
object ReminderNotification {

    private const val TAG = "ReminderNotification"
    const val DEFAULT_CHANNEL_ID = "bugaoshan_reminder"

    /**
     * 创建课程提醒专用的通知渠道（API 26+）。
     *
     * 设为 IMPORTANCE_HIGH 保证在锁屏和使用其他应用时能弹出横幅并发出提示音。
     */
    fun createChannel(context: Context, channelId: String = DEFAULT_CHANNEL_ID) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                    ?: return

            // 若渠道已存在，系统不会重复创建也不会覆盖用户已修改的设置
            val existing = notificationManager.getNotificationChannel(channelId)
            if (existing != null) return

            val name = try {
                context.getString(R.string.reminder_notification_channel_name)
            } catch (e: Exception) {
                "课程提醒"
            }
            val descriptionText = try {
                context.getString(R.string.reminder_notification_channel_desc)
            } catch (e: Exception) {
                "上课前的课前提醒通知"
            }

            val channel = NotificationChannel(
                channelId,
                name,
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = descriptionText
                enableLights(true)
                enableVibration(true)
                setShowBadge(true)
            }

            notificationManager.createNotificationChannel(channel)
            Log.d(TAG, "Notification channel created: $channelId")
        }
    }

    /**
     * 投递单条提醒通知。
     *
     * @param context 上下文
     * @param item 提醒条目数据
     * @param channelId 通知渠道 ID
     */
    fun showReminder(
        context: Context,
        item: ReminderItemData,
        channelId: String = DEFAULT_CHANNEL_ID,
    ) {
        createChannel(context, channelId)

        // 检查通知权限是否可用，被拒则不发
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) {
            Log.w(TAG, "Notification is disabled by user, skipping reminder: ${item.id}")
            return
        }

        // 点击通知拉起 MainActivity
        val contentIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("reminder_id", item.id)
        }

        val pendingIntent = PendingIntent.getActivity(
            context,
            item.stableNotificationId,
            contentIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(item.title)
            .setContentText(item.body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(item.body))
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setWhen(item.fireAtMillis)
            .setShowWhen(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)

        // 若有折叠分组键，利用 setGroup 归入同一通知组（折叠展示）
        if (!item.collapseKey.isNullOrEmpty()) {
            builder.setGroup(item.collapseKey)
        }

        val notificationManager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
        if (notificationManager != null) {
            notificationManager.notify(item.stableNotificationId, builder.build())
            Log.d(TAG, "Reminder notification posted: id=${item.id}, notifId=${item.stableNotificationId}")
        } else {
            Log.e(TAG, "NotificationManager not available")
        }
    }
}
