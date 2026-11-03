package com.trimtime.app

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper
import android.os.PowerManager

/**
 * Plays the booking alert sounds from the app itself instead of through the
 * notification channel.
 *
 * A channel's sound is the phone's to decide, not the app's. Xiaomi's MIUI and
 * HyperOS ship every new app channel with its sound switched off, and no API
 * lets an app turn it back on, so the alert was posted, shown and silent - on
 * a phone with notifications allowed and the volume at full. A player the app
 * owns is not subject to that switch.
 *
 * Every entry point runs on the main thread, so the state below needs no
 * further locking.
 */
object OwnerAlertRinger {
    /// The server stops alerting after two minutes. A little slack covers a
    /// phone clock that runs behind, and no deadline can make it ring longer.
    private const val MAX_RING_MS = 130_000L
    private const val PREFERENCES = "pritze_owner_booking_actions"
    private const val ENABLED_KEY = "pritze.notifications.ownerAlertsEnabled"
    private const val STOPPED_PREFIX = "pritze.notifications.ownerAlertStopped."

    private val main = Handler(Looper.getMainLooper())
    private val timeouts = HashMap<String, Runnable>()
    private var player: MediaPlayer? = null
    private var chimePlayer: MediaPlayer? = null
    private var onIdle: (() -> Unit)? = null

    val isRinging: Boolean
        get() = timeouts.isNotEmpty()

    /// Same store and keys the Dart side writes, so a phone signed out of its
    /// owner account, or a request already answered, never rings.
    fun mayRing(context: Context, bookingId: String): Boolean {
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        val enabled = if (preferences.contains(ENABLED_KEY)) {
            preferences.getBoolean(ENABLED_KEY, false)
        } else {
            // Written through the legacy preferences API by older builds.
            context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .getBoolean("flutter.$ENABLED_KEY", false)
        }
        val stoppedUntil = preferences.getLong("$STOPPED_PREFIX$bookingId", 0L)
        return enabled && stoppedUntil <= System.currentTimeMillis()
    }

    /// Starts the continuous ring for [bookingId], or keeps it going if it is
    /// already ringing. Safe to call for every repeat of the same push.
    fun ring(context: Context, bookingId: String, deadlineMillis: Long) {
        if (bookingId.isEmpty() || !mayRing(context, bookingId)) return
        val remaining = minOf(deadlineMillis - System.currentTimeMillis(), MAX_RING_MS)
        if (remaining <= 0) return
        timeouts.remove(bookingId)?.let(main::removeCallbacks)
        val timeout = Runnable { stop(bookingId) }
        timeouts[bookingId] = timeout
        main.postDelayed(timeout, remaining)
        if (player == null) {
            player = createPlayer(
                context,
                R.raw.owner_booking_request,
                AudioAttributes.USAGE_ALARM,
                looping = true,
            )
        }
    }

    /// Runs [callback] once nothing is ringing: now, or when the ring ends.
    fun afterRinging(callback: () -> Unit) {
        if (isRinging) onIdle = callback else callback()
    }

    fun stop(bookingId: String) {
        timeouts.remove(bookingId)?.let(main::removeCallbacks) ?: return
        if (timeouts.isEmpty()) silence()
    }

    fun stopAll() {
        timeouts.values.forEach(main::removeCallbacks)
        timeouts.clear()
        silence()
    }

    /// The scheduled-booking tone: once, on the notification stream, so it
    /// respects silent mode the way an ordinary notification does.
    fun chime(context: Context) {
        // Held until it finishes: an unreferenced MediaPlayer can be collected
        // mid-sound.
        chimePlayer?.release()
        chimePlayer = createPlayer(
            context,
            R.raw.scheduled_booking_request,
            AudioAttributes.USAGE_NOTIFICATION,
            looping = false,
        )
    }

    private fun silence() {
        player?.let {
            try {
                it.stop()
            } catch (_: Exception) {
                // Already stopped or never prepared; releasing is what matters.
            }
            it.release()
        }
        player = null
        val idle = onIdle
        onIdle = null
        idle?.invoke()
    }

    private fun createPlayer(
        context: Context,
        resource: Int,
        usage: Int,
        looping: Boolean,
    ): MediaPlayer? {
        return try {
            val descriptor = context.resources.openRawResourceFd(resource) ?: return null
            MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(usage)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
                descriptor.use {
                    setDataSource(it.fileDescriptor, it.startOffset, it.length)
                }
                isLooping = looping
                // Keeps the CPU awake for the sound on a phone with its screen off.
                setWakeMode(context.applicationContext, PowerManager.PARTIAL_WAKE_LOCK)
                if (!looping) {
                    setOnCompletionListener { finished ->
                        finished.release()
                        if (chimePlayer === finished) chimePlayer = null
                    }
                }
                prepare()
                start()
            }
        } catch (_: Exception) {
            // Never let the sound take the process - and the alert - down with it.
            null
        }
    }
}
