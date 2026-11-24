"use strict";

// Only the consent-based discovery snapshot belongs on a customer profile.
// Arrival-session coordinates and arbitrary fields must never be copied here.
function adminCustomerLocation(location, capturedAtMillis) {
  if (!location || location.purpose !== "salon_discovery") return null;
  const {latitude, longitude, accuracyMeters} = location;
  if (typeof latitude !== "number" || !Number.isFinite(latitude) ||
      Math.abs(latitude) > 90 || typeof longitude !== "number" ||
      !Number.isFinite(longitude) || Math.abs(longitude) > 180 ||
      !Number.isFinite(capturedAtMillis) || capturedAtMillis <= 0) return null;
  return {
    latitude: Math.round(latitude * 1000) / 1000,
    longitude: Math.round(longitude * 1000) / 1000,
    accuracyMeters: typeof accuracyMeters === "number" &&
        Number.isFinite(accuracyMeters) ? Math.max(100, accuracyMeters) : 100,
    capturedAtMillis,
  };
}

module.exports = {adminCustomerLocation};
