const assert = require("node:assert/strict");
const test = require("node:test");
const {adminCustomerLocation} = require("./admin_customer_location");
const capturedAt = Date.UTC(2026, 10, 24, 10);
const snapshot = {purpose: "salon_discovery", latitude: 19.05221,
  longitude: 72.89972, accuracyMeters: 12, privateField: "excluded"};

test("admin discovery snapshot stays approximate and exposes only profile fields", () => {
  assert.deepEqual(adminCustomerLocation(snapshot, capturedAt), {
    latitude: 19.052, longitude: 72.9, accuracyMeters: 100,
    capturedAtMillis: capturedAt,
  });
  assert.equal(adminCustomerLocation({...snapshot, accuracyMeters: 850}, capturedAt).accuracyMeters, 850);
  assert.equal(adminCustomerLocation({...snapshot, latitude: 0, longitude: 0}, capturedAt).latitude, 0);
});

test("missing, removed, arrival and malformed locations are never presented as saved", () => {
  for (const location of [null, undefined, {}, {...snapshot, purpose: "arrival"},
    {...snapshot, latitude: null}, {...snapshot, latitude: "19"},
    {...snapshot, longitude: Infinity}, {...snapshot, latitude: 91},
    {...snapshot, longitude: -181}]) {
    assert.equal(adminCustomerLocation(location, capturedAt), null);
  }
  for (const time of [0, -1, NaN, undefined]) {
    assert.equal(adminCustomerLocation(snapshot, time), null);
  }
});
