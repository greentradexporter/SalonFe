package com.trimtime.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat

/**
 * Keeps the app's process alive while a salon owner is signed in.
 *
 * The booking alert is a data-only FCM message, and Android does not deliver
 * those to an app it has put in the "Restricted" background state, nor to one
 * an aggressive vendor battery manager has stopped. Those states are reached
 * without the owner doing anything, and re-applied after they clear them,
 * which is why a phone that was fixed on Monday is silent again by Wednesday.
 *
 * A running foreground service is exempt: the process stays resident, so the
 * message arrives and the alert can ring even with the app closed. The cost is
 * the permanent notification below, which Android requires and which doubles
 * as an honest indicator that the salon is reachable.
 *
 * It does not survive a reboot on vendors that gate Autostart; the service
 * restarts when the app is next opened, and `ownerAlertBlockerMessage` still
 * tells the owner to grant Autostart.
 */
class OwnerAlertService : android.app.Service() {
    companion object {
        /// Set by the service itself, so the app reports what actually
        /// happened rather than what it intended. A start can fail silently -
        /// the system refuses it, or startForeground throws - and without this
        /// the only symptom is a missing notification on someone else's phone.
        @Volatile
        var isRunning: Boolean = false
            private set

        const val CHANNEL_ID = "pritze_owner_alert_service"
        const val NOTIFICATION_ID = 790002
        const val ACTION_START = "com.trimtime.app.OWNER_ALERT_START"
        const val ACTION_STOP = "com.trimtime.app.OWNER_ALERT_STOP"
        const val ACTION_RING = "com.trimtime.app.OWNER_ALERT_RING"
        private const val EXTRA_BOOKING_ID = "bookingId"
        private const val EXTRA_DEADLINE = "deadlineMillis"

        /// Whether the app wants the listener running (salon open, owner
        /// signed in), as opposed to it running only to finish a ring.
        @Volatile
        private var listening: Boolean = false

        /// Rings for a booking request. With the listener running the process
        /// is already kept alive, so the ring starts directly. Otherwise the
        /// service is brought up for the length of the ring - a high-priority
        /// push allows that from the background - so the process is not
        /// reclaimed mid-ring.
        fun ring(context: Context, bookingId: String, deadlineMillis: Long) {
            if (isRunning) {
                OwnerAlertRinger.ring(context, bookingId, deadlineMillis)
                return
            }
            val intent = Intent(context, OwnerAlertService::class.java)
                .setAction(ACTION_RING)
                .putExtra(EXTRA_BOOKING_ID, bookingId)
                .putExtra(EXTRA_DEADLINE, deadlineMillis)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (_: Exception) {
                // Refused a background start: ring anyway for as long as the
                // process lives.
                OwnerAlertRinger.ring(context, bookingId, deadlineMillis)
            }
        }

        fun start(context: Context) {
            val intent = Intent(context, OwnerAlertService::class.java)
                .setAction(ACTION_START)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.startService(
                Intent(context, OwnerAlertService::class.java).setAction(ACTION_STOP),
            )
        }
    }

    override fun onBind(intent: Intent?) = null

    override fun onDestroy() {
        isRunning = false
        super.onDestroy()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            listening = false
            // The app also asks for a stop while it is still loading the
            // salon, which can be the very moment a request is ringing. Let
            // that ring finish; its own deadline or the owner's answer ends it.
            OwnerAlertRinger.afterRinging(::stopUnlessListening)
            return START_NOT_STICKY
        }
        try {
            startForeground(NOTIFICATION_ID, buildNotification())
        } catch (_: Exception) {
            // A START_STICKY restart happens in the background, where Android
            // 12+ may refuse a foreground start. Uncaught, that crashes the
            // whole process - and the FCM isolate that rings the alert with it.
            // The app restarts the service the next time it is opened.
            isRunning = false
            stopSelf()
            if (intent?.action == ACTION_RING) {
                // Still ring, for as long as the process lives.
                OwnerAlertRinger.ring(
                    applicationContext,
                    intent.getStringExtra(EXTRA_BOOKING_ID).orEmpty(),
                    intent.getLongExtra(EXTRA_DEADLINE, 0L),
                )
            }
            return START_NOT_STICKY
        }
        isRunning = true
        if (intent?.action == ACTION_RING) {
            OwnerAlertRinger.ring(
                this,
                intent.getStringExtra(EXTRA_BOOKING_ID).orEmpty(),
                intent.getLongExtra(EXTRA_DEADLINE, 0L),
            )
            OwnerAlertRinger.afterRinging(::stopUnlessListening)
            return START_NOT_STICKY
        }
        // ACTION_START, or a sticky restart (null intent) of a running listener.
        listening = true
        // Ask Android to bring the service back if the process is reclaimed.
        return START_STICKY
    }

    /// Checked when the ring ends, not when it was asked for: the app may have
    /// started listening in between, and then the service must stay.
    private fun stopUnlessListening() {
        if (!listening) stopService()
    }

    private fun stopService() {
        isRunning = false
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun buildNotification(): Notification {
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // Lowest importance that still permits a foreground service: silent,
            // no badge, collapsed at the bottom of the shade.
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Booking request listener",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description =
                    "Keeps SalonFe reachable so booking requests ring even when the app is closed."
                setShowBadge(false)
                enableVibration(false)
                setSound(null, null)
            }
            manager.createNotificationChannel(channel)
        }
        // Return to the running app rather than launching another copy of it.
        // A bare activity intent only reuses MainActivity when it is on top of
        // the task; after the owner used a Fix button, a settings screen is on
        // top, so each tap stacked a new MainActivity - a second Flutter engine
        // starting from scratch, which is the long wait on reopening.
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP,
            ),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Ready for booking requests")
            .setContentText("SalonFe will ring when a customer books.")
            .setSmallIcon(R.drawable.ic_stat_salonfe)
            .setColor(android.graphics.Color.rgb(255, 123, 84))
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setSilent(true)
            .setShowWhen(false)
            .setContentIntent(open)
            .build()
    }
}
