"use strict";

function positiveVersionCode(value) {
  const parsed = Number.parseInt(String(value || ""), 10);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : null;
}

// A release that is only part-way through a staged rollout is still installable
// by the users it has reached, so it counts. Only accepting the single
// "published" state meant that during every staged rollout the app advertised
// the *previous* build and prompted nobody to update - the rollout of 47 sat
// invisible while owners stayed on 45.
// A whitelist, so an unfamiliar state is never mistaken for an available
// build: a draft, a halted rollout and a release still in review are all
// things users cannot install, and prompting someone to fetch one leaves them
// tapping an Update button that does nothing.
const INSTALLABLE_RELEASE_STATES = new Set([
  "RELEASE_LIFECYCLE_STATE_PUBLISHED",
  "RELEASE_LIFECYCLE_STATE_COMPLETED",
  // A staged rollout is live for the users it has reached.
  "RELEASE_LIFECYCLE_STATE_IN_PROGRESS",
  "COMPLETED",
  "IN_PROGRESS",
]);

function releaseIsInstallable(release) {
  return INSTALLABLE_RELEASE_STATES.has(
      String(release?.releaseLifecycleState || "").trim(),
  );
}

function highestPublishedVersionCode(payload) {
  const releases = Array.isArray(payload?.releases) ? payload.releases :
    Array.isArray(payload?.releaseSummaries) ? payload.releaseSummaries : [];
  let highest = null;
  for (const release of releases) {
    if (!releaseIsInstallable(release)) {
      continue;
    }
    const artifacts = Array.isArray(release.activeArtifacts) ?
      release.activeArtifacts : [];
    for (const artifact of artifacts) {
      const versionCode = positiveVersionCode(artifact?.versionCode);
      if (versionCode !== null &&
          (highest === null || versionCode > highest)) {
        highest = versionCode;
      }
    }
  }
  return highest;
}

function resolveAndroidUpdateVersion({
  lastConfirmedPublicVersion,
  candidateVersion,
  configuredVersion,
  playPublishedVersion,
}) {
  const lastConfirmed = positiveVersionCode(lastConfirmedPublicVersion) || 1;
  const candidate = Math.max(
    positiveVersionCode(candidateVersion) || lastConfirmed,
    positiveVersionCode(configuredVersion) || lastConfirmed,
  );
  const published = positiveVersionCode(playPublishedVersion);
  if (published === null) {
    return lastConfirmed;
  }
  return Math.max(lastConfirmed, Math.min(candidate, published));
}

module.exports = {
  highestPublishedVersionCode,
  releaseIsInstallable,
  resolveAndroidUpdateVersion,
};
