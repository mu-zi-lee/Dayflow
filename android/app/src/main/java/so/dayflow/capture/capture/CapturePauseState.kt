package so.dayflow.capture.capture

enum class CapturePauseReason {
  USER,
  SCREEN_OFF,
  QUEUE_FULL,
  PAIRING_MISSING,
  USAGE_ACCESS_MISSING,
  NOTIFICATION_PERMISSION_MISSING,
  FOREGROUND_APP_UNKNOWN
}

class CapturePauseState {
  private val reasons = mutableSetOf<CapturePauseReason>()

  @get:Synchronized
  val isPaused: Boolean
    get() = reasons.isNotEmpty()

  @Synchronized
  fun set(reason: CapturePauseReason, active: Boolean): Boolean {
    val changed = if (active) reasons.add(reason) else reasons.remove(reason)
    return changed
  }

  @Synchronized
  fun contains(reason: CapturePauseReason): Boolean = reasons.contains(reason)

  @Synchronized
  fun primaryReason(): CapturePauseReason? = when {
    reasons.contains(CapturePauseReason.USAGE_ACCESS_MISSING) -> CapturePauseReason.USAGE_ACCESS_MISSING
    reasons.contains(CapturePauseReason.NOTIFICATION_PERMISSION_MISSING) -> CapturePauseReason.NOTIFICATION_PERMISSION_MISSING
    reasons.contains(CapturePauseReason.FOREGROUND_APP_UNKNOWN) -> CapturePauseReason.FOREGROUND_APP_UNKNOWN
    reasons.contains(CapturePauseReason.PAIRING_MISSING) -> CapturePauseReason.PAIRING_MISSING
    reasons.contains(CapturePauseReason.QUEUE_FULL) -> CapturePauseReason.QUEUE_FULL
    reasons.contains(CapturePauseReason.USER) -> CapturePauseReason.USER
    reasons.contains(CapturePauseReason.SCREEN_OFF) -> CapturePauseReason.SCREEN_OFF
    else -> null
  }
}
