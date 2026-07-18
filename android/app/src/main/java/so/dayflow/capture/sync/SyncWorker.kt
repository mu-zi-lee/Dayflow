package so.dayflow.capture.sync

import android.content.Context
import android.os.Build
import android.util.Base64
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import java.io.File
import java.net.ConnectException
import java.net.SocketTimeoutException
import java.util.UUID
import javax.crypto.AEADBadTagException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import so.dayflow.capture.DayflowCaptureApp
import so.dayflow.capture.data.CaptureDeviceWire
import so.dayflow.capture.data.DeviceIdentity
import so.dayflow.capture.data.SyncRequest
import so.dayflow.capture.data.toWire

class SyncWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
  override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
    val app = applicationContext as DayflowCaptureApp
    app.repository.withSyncMutation { performSync(app) }
  }

  private suspend fun performSync(app: DayflowCaptureApp): Result {
    app.repository.cleanup()
    val pairing = app.pairingStore.pairing.value ?: run {
      SyncStatusStore.update(SyncPhase.IDLE)
      return Result.success()
    }
    val pending = app.database.captureDao().pending()

    Log.i(TAG, "Starting sync for ${pending.size} pending captures")
    SyncStatusStore.update(SyncPhase.CONNECTING, total = pending.size)
    val endpoint = MacDiscovery(applicationContext).find(pairing)
      ?: run {
        Log.w(TAG, "Paired Mac could not be discovered")
        SyncStatusStore.update(
          SyncPhase.WAITING_FOR_MAC,
          total = pending.size,
          error = "未找到已配对的 Mac，请确认两台设备位于同一局域网且 Mac 版 Dayflow 正在运行"
        )
        return Result.retry()
      }

    try {
      EncryptedSyncClient(endpoint, pairing).use { client ->
        val deviceId = DeviceIdentity.id(applicationContext)
        client.send(
          SyncRequest(
            kind = "register",
            requestId = UUID.randomUUID().toString(),
            device = CaptureDeviceWire(
              id = deviceId,
              displayName = Build.MODEL,
              model = Build.PRODUCT,
              osVersion = "Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})"
            )
          )
        ).requireSuccess()
        app.pairingStore.markVerified()

        if (pending.isEmpty()) {
          SyncStatusStore.update(SyncPhase.IDLE, markSuccess = true)
          return Result.success()
        }

        val manifest = client.send(
          SyncRequest(
            kind = "manifest",
            requestId = UUID.randomUUID().toString(),
            deviceId = deviceId,
            captureIds = pending.map { it.captureId }
          )
        ).also { it.requireSuccess() }
        val missing = manifest.missingCaptureIds.orEmpty().toSet()
        val existing = pending.filterNot { missing.contains(it.captureId) }
        existing.forEach {
          app.repository.acknowledgeAndCleanup(it)
        }

        val uploads = pending.filter { missing.contains(it.captureId) }
        var completed = existing.size
        SyncStatusStore.update(SyncPhase.SYNCING, completed, pending.size)
        if (uploads.isNotEmpty()) app.database.captureDao().markUploading(uploads.map { it.captureId })
        try {
          for (capture in uploads) {
            val file = File(capture.filePath)
            val imageBase64 = if (capture.filePath.isBlank() && capture.captureKind == "redacted") {
              null
            } else {
              require(file.isFile) { "Missing capture ${capture.captureId}" }
              Base64.encodeToString(file.readBytes(), Base64.NO_WRAP)
            }
            val response = client.send(
              SyncRequest(
                kind = "upload",
                requestId = UUID.randomUUID().toString(),
                metadata = capture.toWire(),
                imageBase64 = imageBase64
              )
            )
            response.requireSuccess()
            check(response.acceptedCaptureId == capture.captureId) {
              "Mac 未确认当前截图"
            }
            app.repository.acknowledgeAndCleanup(capture)
            completed += 1
            SyncStatusStore.update(SyncPhase.SYNCING, completed, pending.size)
          }
        } catch (error: Throwable) {
          withContext(NonCancellable) {
            app.database.captureDao().markPending(uploads.map { it.captureId })
          }
          throw error
        }
      }
      app.repository.cleanup()
      val remaining = app.repository.pendingCountNow()
      if (remaining > 0) {
        SyncStatusStore.update(SyncPhase.SYNCING, completed = 0, total = remaining)
        return Result.retry()
      }
      SyncStatusStore.update(
        SyncPhase.IDLE,
        completed = pending.size,
        total = pending.size,
        markSuccess = true
      )
      return Result.success()
    } catch (error: CancellationException) {
      throw error
    } catch (error: Throwable) {
      Log.e(TAG, "Sync failed", error)
      val message = when (error) {
        is AEADBadTagException -> "配对验证失败，请重新配对 Mac"
        is ConnectException, is SocketTimeoutException ->
          "暂时无法连接 Mac，请保持两台设备连接同一 Wi-Fi 并打开 Mac 版 Dayflow"
        else -> error.message ?: "同步失败，Dayflow 将自动重试"
      }
      SyncStatusStore.update(SyncPhase.ERROR, total = pending.size, error = message)
      return if (error is AEADBadTagException) {
        Result.failure()
      } else {
        Result.retry()
      }
    }
  }

  private fun so.dayflow.capture.data.SyncResponse.requireSuccess() {
    check(ok) { error ?: "Dayflow sync failed" }
  }

  private companion object {
    const val TAG = "DayflowSync"
  }
}
