type OperationalBooking = {
  id: string;
  salonId: string;
  status: string;
  startMillis: number;
  startedAtMillis?: number;
  completedAtMillis?: number;
  cancelledAtMillis?: number;
  rejectedAtMillis?: number;
  durationMinutes: number;
};

const minute = 60_000;
const day = 24 * 60 * minute;
const indiaOffset = 330 * minute;

export function operationalDayStart(now: number): number {
  return Math.floor((now + indiaOffset) / day) * day - indiaOffset;
}

export function isCurrentOperationalBooking(booking: OperationalBooking, now: number): boolean {
  if (!["pending", "confirmed", "inProgress"].includes(booking.status)) return false;
  const reference = booking.status === "inProgress"
    ? Math.max(booking.startMillis, booking.startedAtMillis || 0)
    : booking.startMillis;
  if (!Number.isFinite(reference) || reference <= 0) return false;
  if (reference >= operationalDayStart(now)) return true;
  // Keep a real overnight service until its expected end plus an hour's grace.
  return booking.status === "inProgress" && Boolean(booking.startedAtMillis) &&
    booking.startedAtMillis! + (booking.durationMinutes + 60) * minute >= now;
}

export function recentTerminalBookings<T extends OperationalBooking>(bookings: T[], now: number): T[] {
  return bookings.filter((booking) => {
    if (!["completed", "cancelled", "rejected"].includes(booking.status)) return false;
    const timestamp = booking.completedAtMillis || booking.cancelledAtMillis ||
      booking.rejectedAtMillis || booking.startMillis;
    return timestamp >= now - 7 * day && timestamp <= now;
  });
}

export function isCurrentOperationalAlert(
  alert: { status: string; detectedAtMillis: number; targetType: string; targetId: string; type: string },
  bookings: OperationalBooking[],
  salons: { id: string; rating: number }[],
  rules: { id: string; enabled: boolean; threshold: number }[],
  now: number,
): boolean {
  if (alert.status === "resolved" || alert.detectedAtMillis < operationalDayStart(now)) return false;
  const rule = rules.find((item) => item.id === alert.type);
  if (rule && !rule.enabled) return false;
  if (alert.targetType === "booking") {
    const booking = bookings.find((item) => item.id === alert.targetId);
    if (!booking || !isCurrentOperationalBooking(booking, now)) return false;
    if (alert.type === "instant_response") return booking.status === "pending";
    if (alert.type === "overdue_arrival") return booking.status === "confirmed";
    if (alert.type === "unassigned_booking") {
      return ["pending", "confirmed"].includes(booking.status) &&
        !("barberId" in booking && booking.barberId);
    }
    return true;
  }
  if (alert.type === "cancellation_spike") {
    const terminal = recentTerminalBookings(bookings.filter((item) => item.salonId === alert.targetId), now);
    const cancelled = terminal.filter((item) => ["cancelled", "rejected"].includes(item.status));
    return terminal.length >= 5 && cancelled.length / terminal.length * 100 >= (rule?.threshold ?? 30);
  }
  if (alert.type === "low_rating") {
    const salon = salons.find((item) => item.id === alert.targetId);
    return Boolean(salon && salon.rating > 0 && salon.rating < (rule?.threshold ?? 3.5));
  }
  return true;
}
