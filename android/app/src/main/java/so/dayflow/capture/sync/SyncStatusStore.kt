package so.dayflow.capture.sync

import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

enum class SyncPhase {
  IDLE,
  WAITING_FOR_MAC,
  CONNECTING,
  SYNCING,
  ERROR
}

data class SyncStatus(
  val phase: SyncPhase = SyncPhase.IDLE,
  val completed: Int = 0,
  val total: Int = 0,
  val lastSuccessAtUTCMS: Long? = null,
  val error: String? = null
)

object SyncStatusStore {
  private const val PREFERENCES = "dayflow-sync-health"
  private const val PHASE = "phase"
  private const val COMPLETED = "completed"
  private const val TOTAL = "total"
  private const val LAST_SUCCESS_AT = "last-success-at"
  private const val ERROR = "error"

  private var preferences: SharedPreferences? = null
  private val _status = MutableStateFlow(SyncStatus())
  val status: StateFlow<SyncStatus> = _status

  fun initialize(context: Context) {
    val applicationContext = context.applicationContext
    val stored = applicationContext.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
    preferences = stored
    val storedPhase = runCatching {
      SyncPhase.valueOf(stored.getString(PHASE, null).orEmpty())
    }.getOrDefault(SyncPhase.IDLE)
    val wasInterrupted = storedPhase == SyncPhase.CONNECTING || storedPhase == SyncPhase.SYNCING
    _status.value = SyncStatus(
      phase = if (wasInterrupted) SyncPhase.ERROR else storedPhase,
      completed = stored.getInt(COMPLETED, 0),
      total = stored.getInt(TOTAL, 0),
      lastSuccessAtUTCMS = stored.getLong(LAST_SUCCESS_AT, 0L).takeIf { it > 0L },
      error = if (wasInterrupted) {
        "上次同步被中断，Dayflow 将自动重试"
      } else {
        stored.getString(ERROR, null)
      }
    )
    if (wasInterrupted) persist(_status.value)
  }

  fun update(
    phase: SyncPhase,
    completed: Int = 0,
    total: Int = 0,
    error: String? = null,
    markSuccess: Boolean = false
  ) {
    val lastSuccess = if (markSuccess) System.currentTimeMillis() else _status.value.lastSuccessAtUTCMS
    val value = SyncStatus(phase, completed, total, lastSuccess, error)
    _status.value = value
    persist(value)
  }

  private fun persist(value: SyncStatus) {
    preferences?.edit()
      ?.putString(PHASE, value.phase.name)
      ?.putInt(COMPLETED, value.completed)
      ?.putInt(TOTAL, value.total)
      ?.putLong(LAST_SUCCESS_AT, value.lastSuccessAtUTCMS ?: 0L)
      ?.apply {
        if (value.error == null) remove(ERROR) else putString(ERROR, value.error)
      }
      ?.apply()
  }
}
