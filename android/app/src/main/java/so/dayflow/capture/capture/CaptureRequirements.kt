package so.dayflow.capture.capture

import android.app.AppOpsManager
import android.app.NotificationManager
import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat

object CaptureRequirements {
  fun hasUsageAccess(context: Context): Boolean {
    val manager = context.getSystemService(AppOpsManager::class.java)
    return manager.unsafeCheckOpNoThrow(
      AppOpsManager.OPSTR_GET_USAGE_STATS,
      android.os.Process.myUid(),
      context.packageName
    ) == AppOpsManager.MODE_ALLOWED
  }

  fun hasNotificationAccess(context: Context): Boolean =
    ContextCompat.checkSelfPermission(
      context,
      Manifest.permission.POST_NOTIFICATIONS
    ) == PackageManager.PERMISSION_GRANTED &&
      context.getSystemService(NotificationManager::class.java).areNotificationsEnabled()
}
