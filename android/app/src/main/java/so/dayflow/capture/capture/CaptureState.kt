package so.dayflow.capture.capture

import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

enum class RecordingState { STOPPED, RECORDING, PAUSED, ERROR }

object CaptureState {
  private const val PREFERENCES = "dayflow-capture-health"
  private const val STATE = "state"
  private const val MESSAGE = "message"
  private const val LAST_CAPTURE_AT = "last-capture-at"

  private var preferences: SharedPreferences? = null
  private val _state = MutableStateFlow(RecordingState.STOPPED)
  val state: StateFlow<RecordingState> = _state
  private val _message = MutableStateFlow<String?>(null)
  val message: StateFlow<String?> = _message
  private val _lastCaptureAtUTCMS = MutableStateFlow<Long?>(null)
  val lastCaptureAtUTCMS: StateFlow<Long?> = _lastCaptureAtUTCMS

  fun initialize(context: Context) {
    val applicationContext = context.applicationContext
    val stored = applicationContext.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
    preferences = stored
    _state.value = runCatching {
      RecordingState.valueOf(stored.getString(STATE, null).orEmpty())
    }.getOrDefault(RecordingState.STOPPED)
    _message.value = stored.getString(MESSAGE, null)
    _lastCaptureAtUTCMS.value = stored.getLong(LAST_CAPTURE_AT, 0L).takeIf { it > 0L }
  }

  fun update(state: RecordingState, message: String? = null) {
    _state.value = state
    _message.value = message
    preferences?.edit()
      ?.putString(STATE, state.name)
      ?.apply {
        if (message == null) remove(MESSAGE) else putString(MESSAGE, message)
      }
      ?.apply()
  }

  fun markCaptureSuccess(capturedAtUTCMS: Long = System.currentTimeMillis()) {
    _lastCaptureAtUTCMS.value = capturedAtUTCMS
    preferences?.edit()
      ?.putLong(LAST_CAPTURE_AT, capturedAtUTCMS)
      ?.apply()
  }
}

object CaptureActions {
  const val START = "so.dayflow.capture.START"
  const val PAUSE = "so.dayflow.capture.PAUSE"
  const val RESUME = "so.dayflow.capture.RESUME"
  const val STOP = "so.dayflow.capture.STOP"
}
