package so.dayflow.capture.data

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.io.File
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class CaptureRepositoryCleanupInstrumentationTest {
  @get:Rule
  val temporaryFolder = TemporaryFolder()

  private val context = ApplicationProvider.getApplicationContext<Context>()
  private val database = Room.inMemoryDatabaseBuilder(context, CaptureDatabase::class.java).build()
  private val dao = database.captureDao()
  private val repository = CaptureRepository(context, dao)

  @After
  fun closeDatabase() {
    database.close()
  }

  @Test
  fun acknowledgementDeletesFileAndDatabaseRecord() = runBlocking {
    val file = temporaryFolder.newFile("capture.jpg").apply { writeBytes(byteArrayOf(1, 2, 3)) }
    val capture = capture(file)
    dao.insert(capture)

    repository.acknowledgeAndCleanup(capture)

    assertFalse(file.exists())
    assertEquals(0, dao.countById(capture.captureId))
  }

  @Test
  fun startupCleanupFinishesInterruptedAcknowledgement() = runBlocking {
    val file = temporaryFolder.newFile("interrupted.jpg").apply { writeBytes(byteArrayOf(4, 5, 6)) }
    val capture = capture(file).copy(
      state = SyncState.ACKNOWLEDGED,
      acknowledgedAtUTCMS = 100,
      deleteAfterUTCMS = 100
    )
    dao.insert(capture)

    repository.cleanup()

    assertFalse(file.exists())
    assertEquals(0, dao.countById(capture.captureId))
  }

  private fun capture(file: File) = CaptureEntity(
    captureId = file.nameWithoutExtension,
    deviceId = "device",
    sessionId = "session",
    sequence = 1,
    capturedAtUTCMS = 100,
    timezoneId = "Asia/Shanghai",
    utcOffsetSeconds = 28_800,
    foregroundAppId = "example.app",
    foregroundAppName = "Example",
    orientation = "portrait",
    pixelWidth = 10,
    pixelHeight = 20,
    captureKind = "image",
    mimeType = "image/jpeg",
    byteLength = file.length(),
    sha256 = "hash",
    filePath = file.absolutePath
  )
}
