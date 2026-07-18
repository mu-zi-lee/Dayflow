package so.dayflow.capture

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.text.format.DateUtils
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.BatterySaver
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Computer
import androidx.compose.material.icons.rounded.DeleteOutline
import androidx.compose.material.icons.rounded.CloudDone
import androidx.compose.material.icons.rounded.Notifications
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.QrCodeScanner
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Security
import androidx.compose.material.icons.rounded.Stop
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.viewmodel.compose.viewModel
import so.dayflow.capture.capture.CaptureActions
import so.dayflow.capture.capture.CapturePreferences
import so.dayflow.capture.capture.CaptureRequirements
import so.dayflow.capture.capture.CaptureService
import so.dayflow.capture.capture.CaptureState
import so.dayflow.capture.capture.ContinuousCaptureAccessibilityService
import so.dayflow.capture.capture.RecordingState
import so.dayflow.capture.sync.SyncPhase
import so.dayflow.capture.sync.SyncStatus

private enum class MainPage { STATUS, SETTINGS, DIAGNOSTICS }

class MainActivity : ComponentActivity() {
  private var usageAccessGranted by mutableStateOf(false)
  private var batteryUnrestricted by mutableStateOf(false)
  private var notificationsGranted by mutableStateOf(false)
  private var accessibilityGranted by mutableStateOf(false)
  private var pendingCaptureAction: String? = null

  private val notificationPermissionLauncher = registerForActivityResult(
    ActivityResultContracts.RequestPermission()
  ) { granted ->
    refreshPermissionState()
    val action = pendingCaptureAction
    pendingCaptureAction = null
    if (granted && action != null) startCaptureService(action)
    if (!granted) {
      CaptureState.update(RecordingState.ERROR, getString(R.string.notification_required_for_capture))
    }
  }

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    refreshPermissionState()
    setContent {
      DayflowTheme {
        val model: MainViewModel = viewModel()
        DayflowCaptureScreen(
          model = model,
          usageAccessGranted = usageAccessGranted,
          batteryUnrestricted = batteryUnrestricted,
          notificationsGranted = notificationsGranted,
          accessibilityGranted = accessibilityGranted,
          onStart = { action ->
            requestCapture(model.pairing.value != null, model.pairingVerified.value, action)
          },
          onAction = { action ->
            val serviceIntent = Intent(this, CaptureService::class.java).setAction(action)
            if (action == CaptureActions.RESUME) {
              ContextCompat.startForegroundService(this, serviceIntent)
            } else {
              startService(serviceIntent)
            }
          },
          onAccessibilitySettings = {
            startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
          },
          onUsageSettings = {
            startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
          },
          onBatterySettings = {
            startActivity(
              Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                .setData(Uri.parse("package:$packageName"))
            )
          },
          onNotificationPermission = {
            notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
          }
        )
      }
    }
    if (CapturePreferences.isRecordingDesired(this) &&
      !CapturePreferences.isManuallyPaused(this) &&
      ContinuousCaptureAccessibilityService.isEnabled(this) &&
      CaptureState.state.value != RecordingState.RECORDING &&
      CaptureState.state.value != RecordingState.PAUSED
    ) {
      window.decorView.post { ContinuousCaptureAccessibilityService.ensureCaptureRunning(this) }
    }
  }

  override fun onResume() {
    super.onResume()
    refreshPermissionState()
    if (CapturePreferences.isRecordingDesired(this) &&
      !CapturePreferences.isManuallyPaused(this) &&
      accessibilityGranted
    ) {
      ContinuousCaptureAccessibilityService.ensureCaptureRunning(this)
    }
  }

  private fun refreshPermissionState() {
    usageAccessGranted = CaptureRequirements.hasUsageAccess(this)
    batteryUnrestricted = isBatteryUnrestricted()
    notificationsGranted = ContextCompat.checkSelfPermission(
      this,
      Manifest.permission.POST_NOTIFICATIONS
    ) == PackageManager.PERMISSION_GRANTED
    accessibilityGranted = ContinuousCaptureAccessibilityService.isEnabled(this)
  }

  private fun requestCapture(pairingPresent: Boolean, pairingVerified: Boolean, action: String) {
    if (!pairingPresent) {
      CaptureState.update(RecordingState.ERROR, getString(R.string.pairing_required_for_capture))
      return
    }
    if (!pairingVerified) {
      CaptureState.update(RecordingState.ERROR, getString(R.string.pairing_not_verified))
      return
    }
    if (!CaptureRequirements.hasUsageAccess(this)) {
      CaptureState.update(RecordingState.ERROR, getString(R.string.usage_access_required_for_privacy))
      startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
      return
    }
    if (!ContinuousCaptureAccessibilityService.isEnabled(this)) {
      CaptureState.update(RecordingState.ERROR, getString(R.string.enable_accessibility_service))
      startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
      return
    }
    CapturePreferences.setRecordingDesired(this, true)
    CapturePreferences.setManuallyPaused(this, false)
    if (!CaptureRequirements.hasNotificationAccess(this)) {
      pendingCaptureAction = action
      notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
      return
    }
    startCaptureService(action)
  }

  private fun startCaptureService(action: String) = ContextCompat.startForegroundService(
    this,
    Intent(this, CaptureService::class.java).setAction(action)
  )

  private fun isBatteryUnrestricted(): Boolean =
    getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(packageName)
}

@Composable
private fun DayflowCaptureScreen(
  model: MainViewModel,
  usageAccessGranted: Boolean,
  batteryUnrestricted: Boolean,
  notificationsGranted: Boolean,
  accessibilityGranted: Boolean,
  onStart: (String) -> Unit,
  onAction: (String) -> Unit,
  onAccessibilitySettings: () -> Unit,
  onUsageSettings: () -> Unit,
  onBatterySettings: () -> Unit,
  onNotificationPermission: () -> Unit
) {
  val recording by model.recordingState.collectAsState()
  val message by model.recordingMessage.collectAsState()
  val lastCaptureAtUTCMS by model.lastCaptureAtUTCMS.collectAsState()
  val syncStatus by model.syncStatus.collectAsState()
  val pairing by model.pairing.collectAsState()
  val pairingVerified by model.pairingVerified.collectAsState()
  val pendingCount by model.pendingCount.collectAsState(initial = 0)
  val pendingBytes by model.pendingBytes.collectAsState(initial = 0)
  val pendingImageCount by model.pendingImageCount.collectAsState(initial = 0)
  val blockedApps by model.blockedApps.collectAsState()
  val installedApps by model.installedApps.collectAsState()
  val context = LocalContext.current
  var scansQr by remember { mutableStateOf(false) }
  var pairingError by remember { mutableStateOf<String?>(null) }
  var selectsExcludedApps by remember { mutableStateOf(false) }
  var confirmsPairingRemoval by remember { mutableStateOf(false) }
  var confirmsPendingDeletion by remember { mutableStateOf(false) }
  var confirmsStop by remember { mutableStateOf(false) }
  var mainPage by remember { mutableStateOf(MainPage.STATUS) }
  val cameraPermissionLauncher = rememberLauncherForActivityResult(
    ActivityResultContracts.RequestPermission()
  ) { granted ->
    if (granted) {
      pairingError = null
      scansQr = true
    } else {
      pairingError = context.getString(R.string.camera_required_for_pairing)
    }
  }
  val requestPairingScan = {
    if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
      PackageManager.PERMISSION_GRANTED
    ) {
      scansQr = true
    } else {
      cameraPermissionLauncher.launch(Manifest.permission.CAMERA)
    }
  }
  val setupComplete = pairing != null && pairingVerified && usageAccessGranted &&
    accessibilityGranted && notificationsGranted

  if (scansQr) {
    QrScannerView(
      onResult = { raw ->
        model.savePairing(raw)
          .onSuccess { scansQr = false; pairingError = null }
          .onFailure { pairingError = it.message }
      },
      onClose = { scansQr = false },
      onError = { error ->
        pairingError = error
        scansQr = false
      }
    )
    return
  }

  Surface(Modifier.fillMaxSize(), color = Color(0xFFF7F7F5)) {
    Column(
      modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),
      verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
      Text(stringResource(R.string.main_title), style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.SemiBold)
      TabRow(
        selectedTabIndex = mainPage.ordinal,
        containerColor = Color.Transparent,
        divider = {}
      ) {
        MainPage.entries.forEach { page ->
          Tab(
            selected = mainPage == page,
            onClick = { mainPage = page },
            text = {
              Text(
                stringResource(
                  when (page) {
                    MainPage.STATUS -> R.string.page_status
                    MainPage.SETTINGS -> R.string.page_settings
                    MainPage.DIAGNOSTICS -> R.string.page_diagnostics
                  }
                )
              )
            }
          )
        }
      }
      if (!setupComplete) {
        SectionCard(stringResource(R.string.finish_setup)) {
          Text(stringResource(R.string.finish_setup_detail), style = MaterialTheme.typography.bodySmall)
          if (pairing == null) {
            Button(onClick = requestPairingScan) {
              Icon(Icons.Rounded.QrCodeScanner, null)
              Text(stringResource(R.string.pair_mac), Modifier.padding(start = 6.dp))
            }
          } else if (!pairingVerified) {
            Text(stringResource(R.string.verifying_mac), style = MaterialTheme.typography.bodySmall)
            OutlinedButton(onClick = model::syncNow) {
              Icon(Icons.Rounded.Refresh, null)
              Text(stringResource(R.string.retry_verification), Modifier.padding(start = 6.dp))
            }
          } else if (!usageAccessGranted) {
            SetupStep(
              number = 2,
              title = stringResource(R.string.usage_access),
              detail = stringResource(R.string.usage_access_setup_detail),
              action = onUsageSettings
            )
          } else if (!accessibilityGranted) {
            SetupStep(
              number = 3,
              title = stringResource(R.string.continuous_capture_access),
              detail = stringResource(R.string.accessibility_setup_detail),
              action = onAccessibilitySettings
            )
          } else if (!notificationsGranted) {
            SetupStep(
              number = 4,
              title = stringResource(R.string.notifications),
              detail = stringResource(R.string.notification_setup_detail),
              action = onNotificationPermission
            )
          }
        }
      }
      if (mainPage == MainPage.STATUS) {
        StatusCard(recording, message, pendingCount, pendingBytes, lastCaptureAtUTCMS)
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
          when (recording) {
            RecordingState.STOPPED, RecordingState.ERROR -> PrimaryAction(stringResource(R.string.start_capture), Icons.Rounded.PlayArrow) {
              onStart(CaptureActions.START)
            }
            RecordingState.RECORDING -> PrimaryAction(stringResource(R.string.pause_capture), Icons.Rounded.Pause) {
              onAction(CaptureActions.PAUSE)
            }
            RecordingState.PAUSED -> PrimaryAction(stringResource(R.string.resume_capture), Icons.Rounded.PlayArrow) {
              onStart(CaptureActions.RESUME)
            }
          }
          OutlinedButton(onClick = { confirmsStop = true }, enabled = recording != RecordingState.STOPPED) {
            Icon(Icons.Rounded.Stop, null)
            Text(stringResource(R.string.stop_capture), Modifier.padding(start = 6.dp))
          }
        }
        SectionCard(stringResource(R.string.sync_summary)) {
          SettingRow(
            icon = Icons.Rounded.CloudDone,
            title = stringResource(R.string.pending_images, pendingImageCount),
            detail = stringResource(R.string.queue_status, pendingCount, formatBytes(pendingBytes))
          )
          SyncStatusRow(syncStatus)
        }
        SectionCard(stringResource(R.string.privacy)) {
          SettingRow(
            icon = Icons.Rounded.Security,
            title = stringResource(R.string.excluded_apps_count, blockedApps.size),
            detail = stringResource(R.string.privacy_summary_detail)
          )
          TextButton(onClick = { mainPage = MainPage.SETTINGS }) {
            Text(stringResource(R.string.manage_privacy))
          }
        }
      }

      if (mainPage == MainPage.SETTINGS) SectionCard(stringResource(R.string.mac_connection)) {
        SettingRow(
          icon = Icons.Rounded.Computer,
          title = pairing?.serviceName ?: stringResource(R.string.no_mac_paired),
          detail = if (pairing == null) {
            stringResource(R.string.scan_mac_code)
          } else {
            syncStatusDetail(syncStatus)
          }
        )
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
          Button(onClick = requestPairingScan) {
            Icon(Icons.Rounded.QrCodeScanner, null)
            Text(if (pairing == null) stringResource(R.string.pair_mac) else stringResource(R.string.pair_again), Modifier.padding(start = 6.dp))
          }
          OutlinedButton(
            onClick = model::syncNow,
            enabled = pairing != null && syncStatus.phase != SyncPhase.CONNECTING && syncStatus.phase != SyncPhase.SYNCING
          ) {
            Icon(Icons.Rounded.Refresh, null)
            Text(stringResource(R.string.sync_now), Modifier.padding(start = 6.dp))
          }
          if (pairing != null) {
            IconButton(onClick = { confirmsPairingRemoval = true }) {
              Icon(Icons.Rounded.DeleteOutline, stringResource(R.string.remove_pairing))
            }
          }
        }
        pairingError?.let { Text(it, color = MaterialTheme.colorScheme.error) }
      }

      if (mainPage == MainPage.SETTINGS) SectionCard(stringResource(R.string.device_access)) {
        PermissionRow(
          stringResource(R.string.continuous_capture_access),
          accessibilityGranted,
          Icons.Rounded.Security,
          onAccessibilitySettings
        )
        PermissionRow(stringResource(R.string.usage_access), usageAccessGranted, Icons.Rounded.Security, onUsageSettings)
        PermissionRow(stringResource(R.string.unrestricted_battery), batteryUnrestricted, Icons.Rounded.BatterySaver, onBatterySettings)
        PermissionRow(
          stringResource(R.string.notifications),
          notificationsGranted,
          Icons.Rounded.Notifications,
          onNotificationPermission
        )
      }

      if (mainPage == MainPage.SETTINGS) SectionCard(stringResource(R.string.privacy)) {
        SettingRow(
          icon = Icons.Rounded.Security,
          title = stringResource(R.string.excluded_apps),
          detail = stringResource(R.string.excluded_apps_detail)
        )
        Text(
          stringResource(R.string.automatic_sensitive_protection),
          style = MaterialTheme.typography.bodySmall,
          color = Color(0xFF777773)
        )
        installedApps.filter { blockedApps.contains(it.packageName) }.forEach { app ->
          Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
          ) {
            Column(Modifier.weight(1f)) {
              Text(app.label, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
              Text(app.packageName, style = MaterialTheme.typography.bodySmall, color = Color(0xFF777773))
            }
            IconButton(onClick = { model.setAppExcluded(app.packageName, false) }) {
              Icon(Icons.Rounded.DeleteOutline, stringResource(R.string.remove_excluded_app, app.label))
            }
          }
        }
        OutlinedButton(onClick = {
          model.refreshInstalledApps()
          selectsExcludedApps = true
        }) {
          Icon(Icons.Rounded.Add, null)
          Text(stringResource(R.string.select_apps), Modifier.padding(start = 6.dp))
        }
      }

      if (mainPage == MainPage.DIAGNOSTICS) {
        SectionCard(stringResource(R.string.upload_storage)) {
          SettingRow(
            icon = Icons.Rounded.CloudDone,
            title = stringResource(R.string.pending_images, pendingImageCount),
            detail = stringResource(R.string.queue_status, pendingCount, formatBytes(pendingBytes))
          )
          Text(
            stringResource(R.string.upload_storage_detail),
            style = MaterialTheme.typography.bodySmall,
            color = Color(0xFF777773)
          )
          SyncStatusRow(syncStatus)
          OutlinedButton(
            onClick = model::syncNow,
            enabled = pairing != null && syncStatus.phase != SyncPhase.CONNECTING &&
              syncStatus.phase != SyncPhase.SYNCING
          ) {
            Icon(Icons.Rounded.Refresh, null)
            Text(stringResource(R.string.sync_now), Modifier.padding(start = 6.dp))
          }
          if (pendingCount > 0) {
            TextButton(onClick = { confirmsPendingDeletion = true }) {
              Icon(Icons.Rounded.DeleteOutline, null)
              Text(stringResource(R.string.delete_pending), Modifier.padding(start = 6.dp))
            }
          }
        }
      }
    }
  }

  if (selectsExcludedApps) {
    AlertDialog(
      onDismissRequest = { selectsExcludedApps = false },
      title = { Text(stringResource(R.string.select_apps_title)) },
      text = {
        if (installedApps.isEmpty()) {
          Text(stringResource(R.string.no_apps_found))
        } else {
          LazyColumn(Modifier.fillMaxWidth().heightIn(max = 440.dp)) {
            items(installedApps, key = { it.packageName }) { app ->
              val exactExclusion = blockedApps.contains(app.packageName)
              val automaticExclusion = blockedApps.any { rule ->
                rule != app.packageName && (
                  app.packageName.contains(rule, ignoreCase = true) ||
                    app.label.contains(rule, ignoreCase = true)
                  )
              }
              val excluded = exactExclusion || automaticExclusion
              Row(
                modifier = Modifier
                  .fillMaxWidth()
                  .clickable(enabled = !automaticExclusion) {
                    model.setAppExcluded(app.packageName, !exactExclusion)
                  }
                  .padding(vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically
              ) {
                Checkbox(checked = excluded, onCheckedChange = null, enabled = !automaticExclusion)
                Column(Modifier.padding(start = 8.dp)) {
                  Text(app.label, fontWeight = FontWeight.Medium)
                  Text(
                    if (automaticExclusion) {
                      stringResource(R.string.automatic_protection)
                    } else {
                      app.packageName
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = Color(0xFF777773)
                  )
                }
              }
            }
          }
        }
      },
      confirmButton = {
        TextButton(onClick = { selectsExcludedApps = false }) {
          Text(stringResource(R.string.done))
        }
      }
    )
  }

  if (confirmsPairingRemoval) {
    AlertDialog(
      onDismissRequest = { confirmsPairingRemoval = false },
      title = { Text(stringResource(R.string.remove_pairing_title)) },
      text = { Text(stringResource(R.string.remove_pairing_warning, pendingCount, formatBytes(pendingBytes))) },
      confirmButton = {
        TextButton(onClick = {
          model.clearPairing()
          confirmsPairingRemoval = false
        }) {
          Text(stringResource(R.string.remove_pairing))
        }
      },
      dismissButton = {
        TextButton(onClick = { confirmsPairingRemoval = false }) { Text(stringResource(R.string.cancel)) }
      }
    )
  }

  if (confirmsPendingDeletion) {
    AlertDialog(
      onDismissRequest = { confirmsPendingDeletion = false },
      title = { Text(stringResource(R.string.delete_pending_title)) },
      text = { Text(stringResource(R.string.delete_pending_warning, pendingCount, formatBytes(pendingBytes))) },
      confirmButton = {
        TextButton(onClick = {
          model.deletePending()
          confirmsPendingDeletion = false
        }) { Text(stringResource(R.string.delete_pending)) }
      },
      dismissButton = {
        TextButton(onClick = { confirmsPendingDeletion = false }) { Text(stringResource(R.string.cancel)) }
      }
    )
  }

  if (confirmsStop) {
    AlertDialog(
      onDismissRequest = { confirmsStop = false },
      title = { Text(stringResource(R.string.stop_capture_title)) },
      text = { Text(stringResource(R.string.stop_capture_warning)) },
      confirmButton = {
        TextButton(onClick = {
          onAction(CaptureActions.STOP)
          confirmsStop = false
        }) { Text(stringResource(R.string.stop_capture)) }
      },
      dismissButton = {
        TextButton(onClick = { confirmsStop = false }) { Text(stringResource(R.string.cancel)) }
      }
    )
  }
}

@Composable
private fun StatusCard(
  state: RecordingState,
  message: String?,
  count: Int,
  bytes: Long,
  lastCaptureAtUTCMS: Long?
) {
  val color = when (state) {
    RecordingState.RECORDING -> Color(0xFF2C8B57)
    RecordingState.PAUSED -> Color(0xFFD17922)
    RecordingState.ERROR -> Color(0xFFB84A42)
    RecordingState.STOPPED -> Color(0xFF777773)
  }
  Card(shape = RoundedCornerShape(8.dp), colors = CardDefaults.cardColors(containerColor = Color.White)) {
    Row(Modifier.fillMaxWidth().padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
      Box(Modifier.size(10.dp).background(color, RoundedCornerShape(5.dp)))
      Column(Modifier.padding(start = 10.dp).weight(1f)) {
        Text(
          stringResource(
            when (state) {
              RecordingState.STOPPED -> R.string.state_stopped
              RecordingState.RECORDING -> R.string.state_recording
              RecordingState.PAUSED -> R.string.state_paused
              RecordingState.ERROR -> R.string.state_error
            }
          ),
          fontWeight = FontWeight.SemiBold
        )
        val detail = message ?: lastCaptureAtUTCMS?.let {
          stringResource(R.string.last_capture_at, relativeTime(it))
        }
        detail?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = color) }
      }
      Text(stringResource(R.string.queue_status, count, formatBytes(bytes)), style = MaterialTheme.typography.bodySmall)
    }
  }
}

@Composable
private fun SectionCard(title: String, content: @Composable ColumnScope.() -> Unit) {
  Card(shape = RoundedCornerShape(8.dp), colors = CardDefaults.cardColors(containerColor = Color.White)) {
    Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
      Text(title, fontWeight = FontWeight.SemiBold)
      content()
    }
  }
}

@Composable
private fun SettingRow(icon: ImageVector, title: String, detail: String) {
  Row(verticalAlignment = Alignment.CenterVertically) {
    Icon(icon, null, tint = Color(0xFF555550))
    Column(Modifier.padding(start = 10.dp).weight(1f)) {
      Text(title, fontWeight = FontWeight.Medium)
      Text(detail, style = MaterialTheme.typography.bodySmall, color = Color(0xFF777773))
    }
  }
}

@Composable
private fun PermissionRow(
  title: String,
  granted: Boolean,
  icon: ImageVector,
  action: (() -> Unit)?
) {
  Row(verticalAlignment = Alignment.CenterVertically) {
    Icon(icon, null, tint = if (granted) Color(0xFF2C8B57) else Color(0xFFD17922))
    Text(title, Modifier.padding(start = 10.dp).weight(1f))
    if (granted) {
      Text(stringResource(R.string.ready), color = Color(0xFF2C8B57), style = MaterialTheme.typography.bodySmall)
    } else if (action != null) {
      OutlinedButton(onClick = action) { Text(stringResource(R.string.open_settings)) }
    }
  }
}

@Composable
private fun SetupStep(number: Int, title: String, detail: String, action: () -> Unit) {
  Row(verticalAlignment = Alignment.Top) {
    Box(
      modifier = Modifier.size(28.dp).background(Color(0xFFF96E00), RoundedCornerShape(6.dp)),
      contentAlignment = Alignment.Center
    ) {
      Text(number.toString(), color = Color.White, fontWeight = FontWeight.SemiBold)
    }
    Column(Modifier.padding(start = 10.dp).weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
      Text(title, fontWeight = FontWeight.SemiBold)
      Text(detail, style = MaterialTheme.typography.bodySmall, color = Color(0xFF777773))
      OutlinedButton(onClick = action) { Text(stringResource(R.string.continue_setup)) }
    }
  }
}

@Composable
private fun PrimaryAction(label: String, icon: ImageVector, action: () -> Unit) {
  Button(
    onClick = action,
    colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFF96E00))
  ) {
    Icon(icon, null)
    Text(label, Modifier.padding(start = 6.dp))
  }
}

@Composable
private fun SyncStatusRow(status: SyncStatus) {
  val detail = when (status.phase) {
    SyncPhase.IDLE -> status.lastSuccessAtUTCMS?.let {
      stringResource(R.string.last_sync_at, relativeTime(it))
    } ?: stringResource(R.string.sync_not_completed)
    SyncPhase.WAITING_FOR_MAC -> stringResource(R.string.sync_waiting_for_mac)
    SyncPhase.CONNECTING -> stringResource(R.string.sync_connecting)
    SyncPhase.SYNCING -> stringResource(R.string.sync_progress, status.completed, status.total)
    SyncPhase.ERROR -> status.error ?: stringResource(R.string.sync_failed)
  }
  Text(
    detail,
    style = MaterialTheme.typography.bodySmall,
    color = if (status.phase == SyncPhase.ERROR) MaterialTheme.colorScheme.error else Color(0xFF777773)
  )
}

@Composable
private fun syncStatusDetail(status: SyncStatus): String = when (status.phase) {
  SyncPhase.IDLE -> status.lastSuccessAtUTCMS?.let {
    stringResource(R.string.last_sync_at, relativeTime(it))
  } ?: stringResource(R.string.encrypted_sync_enabled)
  SyncPhase.WAITING_FOR_MAC -> stringResource(R.string.sync_waiting_for_mac)
  SyncPhase.CONNECTING -> stringResource(R.string.sync_connecting)
  SyncPhase.SYNCING -> stringResource(R.string.sync_progress, status.completed, status.total)
  SyncPhase.ERROR -> status.error ?: stringResource(R.string.sync_failed)
}

private fun relativeTime(timeUTCMS: Long): String = DateUtils.getRelativeTimeSpanString(
  timeUTCMS,
  System.currentTimeMillis(),
  DateUtils.SECOND_IN_MILLIS,
  DateUtils.FORMAT_ABBREV_RELATIVE
).toString()

private fun formatBytes(bytes: Long): String = when {
  bytes >= 1_000_000_000 -> "%.1f GB".format(bytes / 1_000_000_000.0)
  bytes >= 1_000_000 -> "%.1f MB".format(bytes / 1_000_000.0)
  bytes >= 1_000 -> "%.1f KB".format(bytes / 1_000.0)
  else -> "$bytes B"
}

@Composable
private fun DayflowTheme(content: @Composable () -> Unit) {
  MaterialTheme(
    colorScheme = MaterialTheme.colorScheme.copy(
      primary = Color(0xFFF96E00),
      secondary = Color(0xFF2C8B57),
      surface = Color.White,
      background = Color(0xFFF7F7F5)
    ),
    content = content
  )
}
