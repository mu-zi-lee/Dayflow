package so.dayflow.capture

import android.app.Activity
import android.app.Application
import android.os.Bundle
import androidx.room.Room
import androidx.work.Configuration
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import so.dayflow.capture.capture.CaptureState
import so.dayflow.capture.data.CaptureDatabase
import so.dayflow.capture.data.CaptureRepository
import so.dayflow.capture.sync.PairingStore
import so.dayflow.capture.sync.SyncStatusStore

class DayflowCaptureApp : Application(), Configuration.Provider {
  private val visibleActivityCount = AtomicInteger(0)
  private val applicationScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

  val hasVisibleActivity: Boolean
    get() = visibleActivityCount.get() > 0

  lateinit var database: CaptureDatabase
    private set
  lateinit var repository: CaptureRepository
    private set
  lateinit var pairingStore: PairingStore
    private set

  override fun onCreate() {
    super.onCreate()
    CaptureState.initialize(this)
    SyncStatusStore.initialize(this)
    registerActivityLifecycleCallbacks(object : ActivityLifecycleCallbacks {
      override fun onActivityStarted(activity: Activity) {
        visibleActivityCount.incrementAndGet()
      }

      override fun onActivityStopped(activity: Activity) {
        visibleActivityCount.updateAndGet { count -> (count - 1).coerceAtLeast(0) }
      }

      override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) = Unit
      override fun onActivityResumed(activity: Activity) = Unit
      override fun onActivityPaused(activity: Activity) = Unit
      override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit
      override fun onActivityDestroyed(activity: Activity) = Unit
    })
    database = Room.databaseBuilder(this, CaptureDatabase::class.java, "dayflow-captures.db")
      .fallbackToDestructiveMigration(false)
      .build()
    pairingStore = PairingStore(this)
    repository = CaptureRepository(this, database.captureDao())
    applicationScope.launch { repository.cleanup() }
  }

  override val workManagerConfiguration: Configuration
    get() = Configuration.Builder().setMinimumLoggingLevel(android.util.Log.INFO).build()
}
