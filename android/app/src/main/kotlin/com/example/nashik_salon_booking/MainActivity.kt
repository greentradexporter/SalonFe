package com.trimtime.app

import android.app.Activity
import android.app.ActivityManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import com.google.android.gms.auth.api.identity.GetPhoneNumberHintIntentRequest
import com.google.android.gms.auth.api.identity.Identity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private val phoneHintChannel = "com.trimtime.app/phone_hint"
    private val ownerAlertChannel = "com.trimtime.app/owner_alerts"
    private val phoneHintRequestCode = 41091
    private var pendingPhoneHintResult: MethodChannel.Result? = null
    private var lastServiceStartError: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        handleOwnerBookingDecision(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        handleOwnerBookingDecision(intent)
        super.onNewIntent(intent)
    }

    private fun handleOwnerBookingDecision(intent: Intent?) {
        if (intent?.action != "SELECT_FOREGROUND_NOTIFICATION" ||
            intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return
        val status = when (intent.getStringExtra("actionId")) {
            "accept_instant_booking" -> "confirmed"
            "reject_instant_booking" -> "rejected"
            else -> return
        }
        val payload = try {
            JSONObject(intent.getStringExtra("payload") ?: return)
        } catch (_: Exception) {
            return
        }
        val bookingId = payload.optString("bookingId").trim()
        if (bookingId.isEmpty() || payload.optString("isInstant") != "true") return

        // Stop the tagged notification before Flutter/Firebase startup. The
        // notification plugin's foreground-action path cancels only by ID.
        val notifications = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        val id = intent.getIntExtra("notificationId", 790001)
        val tag = intent.getStringExtra("notificationTag")

        // Dart's uncached preferences use this same native file. A concurrent
        // FCM isolate can see the decision before the activity starts Dart.
        val now = System.currentTimeMillis()
        getSharedPreferences("pritze_owner_booking_actions", MODE_PRIVATE)
            .edit()
            .putLong("pritze.notifications.ownerAlertStopped.$bookingId", now + 600_000L)
            .putString("pritze.notifications.pendingOwnerBookingAction.$bookingId", "$status|$now")
            .commit()
        if (tag == null) notifications.cancel(id) else notifications.cancel(tag, id)
        notifications.cancel("pritze_owner_booking_request", 790001)
        OwnerAlertRinger.stop(bookingId)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != phoneHintRequestCode) {
            return
        }
        val methodResult = pendingPhoneHintResult ?: return
        pendingPhoneHintResult = null
        if (resultCode != Activity.RESULT_OK) {
            methodResult.error("cancelled", "Phone number selection was cancelled.", null)
            return
        }
        try {
            val phoneNumber = Identity.getSignInClient(this)
                .getPhoneNumberFromIntent(data)
            methodResult.success(phoneNumber)
        } catch (error: Exception) {
            methodResult.error("unavailable", error.message, null)
        }
    }

    // Whether this phone will actually let the booking alert behave like a
    // ringing call, and the settings screens that fix it when it will not.
    // Both conditions are silent failures otherwise: the alert is posted, the
    // owner simply never sees or hears it.
    private fun configureOwnerAlertChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ownerAlertChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canUseFullScreenIntent" -> {
                        // Granted on install before Android 14.
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                            result.success(true)
                        } else {
                            val manager =
                                getSystemService(NOTIFICATION_SERVICE) as NotificationManager
                            result.success(manager.canUseFullScreenIntent())
                        }
                    }
                    "openFullScreenIntentSettings" -> {
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                            result.success(false)
                        } else {
                            result.success(
                                startSettings(
                                    Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                                ),
                            )
                        }
                    }
                    "alertServiceDiagnostics" -> {
                        // One round trip describing what this phone is really
                        // doing, so a silent failure on someone else's device
                        // can be read remotely instead of guessed at.
                        val manager =
                            getSystemService(NOTIFICATION_SERVICE) as NotificationManager
                        val activity =
                            getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
                        val channelId = call.argument<String>("channelId")
                        val channel = channelId?.let { manager.getNotificationChannel(it) }
                        result.success(
                            mapOf(
                                "serviceRunning" to OwnerAlertService.isRunning,
                                "notificationsAllowed" to manager.areNotificationsEnabled(),
                                "channelBlocked" to (
                                    channel != null &&
                                        channel.importance ==
                                        NotificationManager.IMPORTANCE_NONE
                                    ),
                                "channelMissing" to (channelId != null && channel == null),
                                "backgroundRestricted" to activity.isBackgroundRestricted,
                                "ignoringBatteryOptimizations" to
                                    power.isIgnoringBatteryOptimizations(packageName),
                                "device" to "${Build.MANUFACTURER} ${Build.MODEL}",
                                "sdkInt" to Build.VERSION.SDK_INT,
                            ),
                        )
                    }
                    "startOwnerAlertService" -> {
                        try {
                            OwnerAlertService.start(this)
                            result.success(true)
                        } catch (error: Exception) {
                            // Android 12+ refuses a foreground service start
                            // from the background, and 14+ rejects a type it
                            // does not accept. Report it: swallowing this left
                            // a missing notification as the only symptom.
                            lastServiceStartError = error.toString()
                            result.success(false)
                        }
                    }
                    "ringOwnerAlert" -> {
                        // For a request the app learned of from Firestore rather
                        // than a push. Repeat calls for the same booking are
                        // harmless; the ringer keeps one sound going.
                        OwnerAlertService.ring(
                            applicationContext,
                            call.argument<String>("bookingId").orEmpty(),
                            call.argument<Number>("deadlineMillis")?.toLong() ?: 0L,
                        )
                        result.success(true)
                    }
                    "stopOwnerAlertRing" -> {
                        val bookingId = call.argument<String>("bookingId")
                        if (bookingId.isNullOrEmpty()) {
                            OwnerAlertRinger.stopAll()
                        } else {
                            OwnerAlertRinger.stop(bookingId)
                        }
                        result.success(true)
                    }
                    "firestoreDatabaseBytes" -> {
                        // Firestore's on-device database, journals included.
                        // A large one is the pile of writes old builds saved
                        // while offline; a healthy one is a few megabytes.
                        val databases = getDatabasePath("firestore").parentFile
                        result.success(
                            databases?.listFiles()
                                ?.filter { it.name.startsWith("firestore.") }
                                ?.sumOf { it.length() }
                                ?: 0L,
                        )
                    }
                    "lastServiceStartError" -> {
                        result.success(lastServiceStartError ?: "")
                    }
                    "stopOwnerAlertService" -> {
                        result.success(
                            try {
                                OwnerAlertService.stop(this)
                                true
                            } catch (_: Exception) {
                                false
                            },
                        )
                    }
                    "isBackgroundRestricted" -> {
                        // Distinct from the Doze whitelist below. This is the
                        // "Restricted" state in App info > Battery, and it is
                        // what actually stops background delivery: an app can
                        // be off the Doze whitelist and fine, or whitelisted
                        // and still restricted. Checking only the whitelist
                        // meant the warning stayed up after the owner had
                        // already set Unrestricted.
                        val activity =
                            getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                        result.success(activity.isBackgroundRestricted)
                    }
                    "isAlertChannelBlocked" -> {
                        // App-level permission can be granted while this one
                        // channel is switched off, in which case the booking
                        // alert is dropped silently and nothing in the app
                        // says why.
                        val manager =
                            getSystemService(NOTIFICATION_SERVICE) as NotificationManager
                        val channelId = call.argument<String>("channelId")
                        val channel = channelId?.let { manager.getNotificationChannel(it) }
                        result.success(
                            !manager.areNotificationsEnabled() ||
                                (channel != null &&
                                    channel.importance == NotificationManager.IMPORTANCE_NONE),
                        )
                    }
                    "openAlertChannelSettings" -> {
                        val channelId = call.argument<String>("channelId")
                        result.success(
                            if (channelId == null) {
                                startNotificationSettings()
                            } else {
                                startChannelSettings(channelId)
                            },
                        )
                    }
                    "isIgnoringBatteryOptimizations" -> {
                        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
                        result.success(power.isIgnoringBatteryOptimizations(packageName))
                    }
                    "openBatteryOptimizationSettings" -> {
                        // App info, not the battery-optimisation list. That list
                        // filters to "Not optimized" apps by default, so Pritze -
                        // which is optimised, that being the problem - is hidden
                        // until the owner finds the "All apps" dropdown. From App
                        // info they tap Battery and choose Unrestricted, which is
                        // the setting that actually governs background delivery on
                        // Android 13+. A direct exemption prompt would need a
                        // permission Play restricts.
                        result.success(
                            startSettings(Settings.ACTION_APPLICATION_DETAILS_SETTINGS) ||
                                startSettings(
                                    Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS,
                                    withPackage = false,
                                ),
                        )
                    }
                    "openNotificationSettings" -> {
                        // Android 13+ installs with notifications denied, so this
                        // is the first thing an owner has to turn on.
                        result.success(startNotificationSettings())
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun startChannelSettings(channelId: String): Boolean {
        return try {
            startActivity(
                Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    .putExtra(Settings.EXTRA_CHANNEL_ID, channelId),
            )
            true
        } catch (_: Exception) {
            startNotificationSettings()
        }
    }

    private fun startNotificationSettings(): Boolean {
        return try {
            startActivity(
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, packageName),
            )
            true
        } catch (_: Exception) {
            // Older or unusual builds: App info still exposes notifications.
            startSettings(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
        }
    }

    private fun startSettings(action: String, withPackage: Boolean = true): Boolean {
        return try {
            val intent = Intent(action)
            if (withPackage) intent.data = Uri.fromParts("package", packageName, null)
            startActivity(intent)
            true
        } catch (_: Exception) {
            // Some builds ship without these screens. The caller falls back to
            // telling the owner where to look.
            false
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        configureOwnerAlertChannel(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, phoneHintChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "requestPhoneNumber") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (pendingPhoneHintResult != null) {
                    result.error("in_progress", "Phone number selection is already open.", null)
                    return@setMethodCallHandler
                }
                pendingPhoneHintResult = result
                val request = GetPhoneNumberHintIntentRequest.builder().build()
                Identity.getSignInClient(this)
                    .getPhoneNumberHintIntent(request)
                    .addOnSuccessListener { pendingIntent ->
                        try {
                            startIntentSenderForResult(
                                pendingIntent.intentSender,
                                phoneHintRequestCode,
                                null,
                                0,
                                0,
                                0,
                            )
                        } catch (error: Exception) {
                            pendingPhoneHintResult = null
                            result.error("unavailable", error.message, null)
                        }
                    }
                    .addOnFailureListener { error ->
                        pendingPhoneHintResult = null
                        result.error("unavailable", error.message, null)
                    }
            }
    }
}
