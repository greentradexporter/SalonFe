package com.trimtime.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Hears every FCM message alongside the Firebase plugin's own receiver, and
 * starts or stops the booking alert's sound natively.
 *
 * The Dart handlers still post the notification itself. The sound lives here
 * because it must not depend on a Flutter engine starting in time, nor on the
 * channel's sound switch, which some phones ship turned off.
 */
class OwnerAlertPushReceiver : BroadcastReceiver() {
    companion object {
        /// Every generation the server may name for an owner booking request.
        /// The server still addresses current builds as v4; v5 is only the
        /// app's own silent channel.
        private val OWNER_CHANNELS = setOf(
            "pritze_owner_booking_requests_v2",
            "pritze_owner_booking_requests_v3",
            "pritze_owner_booking_requests_v4",
            "pritze_owner_booking_requests_v5",
        )
        private val SCHEDULED_CHANNELS = setOf(
            "pritze_scheduled_booking_requests_v1",
            "pritze_scheduled_booking_requests_v2",
        )
        private val RESOLVED_STATUSES =
            setOf("confirmed", "rejected", "cancelled", "inProgress", "completed")
        private const val RESPONSE_TIMEOUT_MS = 120_000L
    }

    override fun onReceive(context: Context, intent: Intent) {
        val extras = intent.extras ?: return
        fun data(key: String) = extras.get(key)?.toString()?.trim().orEmpty()
        val bookingId = data("bookingId")
        if (bookingId.isEmpty()) return
        val channel = data("channel")

        // Mirrors `_isOwnerBookingResolution` on the Dart side.
        if (data("action") == "stop_owner_booking_alarm" ||
            (data("isInstant") == "true" && data("status") in RESOLVED_STATUSES)
        ) {
            OwnerAlertRinger.stop(bookingId)
            return
        }
        val app = context.applicationContext
        when (channel) {
            in OWNER_CHANNELS -> OwnerAlertService.ring(app, bookingId, deadline(::data))
            in SCHEDULED_CHANNELS ->
                if (OwnerAlertRinger.mayRing(app, bookingId)) OwnerAlertRinger.chime(app)
        }
    }

    /// Mirrors `_ownerAlertMessageDeadline`: the explicit deadline, else the
    /// creation time, else the send time, plus the two-minute window.
    private fun deadline(data: (String) -> String): Long {
        data("responseDeadlineMillis").toLongOrNull()?.takeIf { it > 0 }?.let { return it }
        data("createdAtMillis").toLongOrNull()?.takeIf { it > 0 }
            ?.let { return it + RESPONSE_TIMEOUT_MS }
        data("google.sent_time").toLongOrNull()?.takeIf { it > 0 }
            ?.let { return it + RESPONSE_TIMEOUT_MS }
        return System.currentTimeMillis() + RESPONSE_TIMEOUT_MS
    }
}
