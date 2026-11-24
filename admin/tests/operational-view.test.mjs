import assert from "node:assert/strict";
import test from "node:test";
import {
  isCurrentOperationalBooking, isCurrentOperationalAlert,
  operationalDayStart, recentTerminalBookings,
} from "../app/operational-view.ts";

const now = Date.parse("2026-11-12T12:00:00+05:30");
const day = 86_400_000;
const booking = (changes = {}) => ({
  id: "booking", salonId: "salon", status: "confirmed",
  startMillis: now - 60_000, durationMinutes: 30, ...changes,
});
const alert = (changes = {}) => ({
  status: "active", detectedAtMillis: now, targetType: "booking",
  targetId: "booking", type: "overdue_arrival", ...changes,
});
const visibleAlert = (item, bookings = [booking()], rules = []) =>
  isCurrentOperationalAlert(item, bookings, [{ id: "salon", rating: 4.5 }], rules, now);

test("operational day uses India midnight, independent of browser timezone", () => {
  assert.equal(operationalDayStart(now), Date.parse("2026-11-12T00:00:00+05:30"));
  assert.equal(operationalDayStart(Date.parse("2026-11-12T00:01:00+05:30")), operationalDayStart(now));
});

test("live queue retains current and upcoming work and excludes historical statuses", () => {
  for (const status of ["pending", "confirmed", "inProgress"]) {
    assert.equal(isCurrentOperationalBooking(booking({ status }), now), true);
    assert.equal(isCurrentOperationalBooking(booking({ status, startMillis: now - 30 * day }), now), false);
  }
  assert.equal(isCurrentOperationalBooking(booking({ startMillis: now + day }), now), true);
  for (const status of ["completed", "cancelled", "rejected"]) {
    assert.equal(isCurrentOperationalBooking(booking({ status }), now), false);
  }
});

test("overnight service stays visible while its service window is current", () => {
  const midnight = Date.parse("2026-11-12T00:10:00+05:30");
  const started = midnight - 30 * 60_000;
  assert.equal(isCurrentOperationalBooking(booking({ status: "inProgress", startMillis: started, startedAtMillis: started, durationMinutes: 45 }), midnight), true);
  assert.equal(isCurrentOperationalBooking(booking({ startMillis: 0 }), now), false);
});

test("a fresh scan cannot resurrect a months-old booking alert", () => {
  assert.equal(visibleAlert(alert(), [booking({ startMillis: now - 60 * day })]), false);
  assert.equal(visibleAlert(alert()), true);
  assert.equal(visibleAlert(alert({ detectedAtMillis: now - day })), false);
  assert.equal(visibleAlert(alert({ status: "resolved" })), false);
  assert.equal(visibleAlert(alert(), []), false);
});

test("changed booking status and disabled monitors remove outdated alerts", () => {
  assert.equal(visibleAlert(alert(), [booking({ status: "completed" })]), false);
  assert.equal(visibleAlert(alert(), [booking({ status: "inProgress" })]), false);
  assert.equal(visibleAlert(alert(), [booking()], [{ id: "overdue_arrival", enabled: false, threshold: 10 }]), false);
});

test("old cancellations do not keep a salon in current intelligence", () => {
  const old = Array.from({ length: 5 }, (_, index) => booking({ id: String(index), status: "cancelled", startMillis: now - 60 * day }));
  const recent = old.map((item) => ({ ...item, cancelledAtMillis: now - day }));
  const cancellation = alert({ targetType: "salon", targetId: "salon", type: "cancellation_spike" });
  assert.equal(visibleAlert(cancellation, old), false);
  assert.equal(visibleAlert(cancellation, recent), true);
  assert.equal(recentTerminalBookings([...old, ...recent], now).length, 5);
});
