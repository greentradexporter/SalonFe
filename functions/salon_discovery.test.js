const test = require('node:test');
const assert = require('node:assert/strict');
const {isWithinSalonHours, isInstantEnabledForSalon, normalizeClosedWeekdays} = require('./booking_workflow_logic');
const {publicSalon, renderSalonPage, validSalonId} = require('./salon_public_page');
const monday = Date.parse('2026-11-23T05:00:00Z'); // Monday 10:30 IST
const hours = {startMillis: monday, durationMinutes: 30, openTime: '9:00 AM', closeTime: '8:00 PM'};
test('weekly closures reject instant and scheduled bookings, including India date boundary', () => {
  assert.equal(isWithinSalonHours({...hours, closedWeekdays: [1]}), false);
  assert.equal(isWithinSalonHours({...hours, closedWeekdays: [2]}), true);
  assert.equal(isInstantEnabledForSalon({instantBookingsEnabled: true, closedWeekdays: [1]}, monday), false);
  assert.equal(isInstantEnabledForSalon({instantBookingsEnabled: false}, monday), false);
  assert.equal(isInstantEnabledForSalon({closedWeekdays: [1]}, Date.parse('2026-11-22T19:00:00Z')), false);
  assert.equal(isWithinSalonHours({...hours, durationMinutes: 700}), false);
});
test('closed days validate and deduplicate without coercing invalid input', () => {
  assert.deepEqual(normalizeClosedWeekdays([7,1,1]), [1,7]);
  for (const input of [[0], [8], ['1'], [1.5], null, 'Monday']) assert.throws(() => normalizeClosedWeekdays(input));
});
test('public shared page excludes private data and safely escapes salon content', () => {
  const salon = {name: '<script>alert(1)</script>', photoUrls: ['javascript:alert(1)', 'https://example.com/photo.jpg'], ownerUid: 'SECRET_UID', email: 'SECRET_EMAIL', payout: 'SECRET_PAYOUT', approvalStatus: 'approved', closedWeekdays: [1]};
  const page = renderSalonPage('salon-123', salon);
  assert.ok(page.includes('&lt;script&gt;'));
  assert.ok(page.includes('https://trimtime-46539.web.app/s/salon-123'));
  assert.ok(page.includes('salonfe://salon/salon-123'));
  assert.ok(page.includes('Closed: Mon'));
  assert.ok(!page.includes('SECRET_'));
  assert.ok(!page.includes('javascript:'));
  assert.deepEqual(Object.keys(publicSalon(salon)).sort(), ['closeTime','closedDays','name','openTime','photo','services'].sort());
  for (const patch of [{approvalStatus:'pending'}, {approvalStatus:'rejected'}, {adminSuspended:true}, {isDemo:true}]) assert.equal(publicSalon({...salon, ...patch}), null);
  assert.equal(publicSalon(undefined), null);
  assert.equal(validSalonId('../users'), false);
});
