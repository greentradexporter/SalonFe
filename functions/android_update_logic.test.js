const assert = require("node:assert/strict");
const test = require("node:test");

const {
  highestPublishedVersionCode,
  resolveAndroidUpdateVersion,
} = require("./android_update_logic");

test("only a Play-published Android release can activate a candidate", () => {
  const payload = {
    releases: [
      {
        releaseLifecycleState: "RELEASE_LIFECYCLE_STATE_IN_REVIEW",
        activeArtifacts: [{versionCode: 32}],
      },
      {
        releaseLifecycleState: "RELEASE_LIFECYCLE_STATE_PUBLISHED",
        activeArtifacts: [{versionCode: 31}],
      },
    ],
  };

  assert.equal(highestPublishedVersionCode(payload), 31);
  assert.equal(resolveAndroidUpdateVersion({
    lastConfirmedPublicVersion: 30,
    candidateVersion: 32,
    configuredVersion: 32,
    playPublishedVersion: highestPublishedVersionCode(payload),
  }), 31);
});

test("an unavailable build never becomes the mandatory fallback", () => {
  assert.equal(resolveAndroidUpdateVersion({
    lastConfirmedPublicVersion: 30,
    candidateVersion: 32,
    configuredVersion: 32,
    playPublishedVersion: null,
  }), 30);
  assert.equal(resolveAndroidUpdateVersion({
    lastConfirmedPublicVersion: 30,
    candidateVersion: 32,
    configuredVersion: 99,
    playPublishedVersion: 32,
  }), 32);
});

// A staged rollout is installable by the users it has reached. Counting only
// the single "published" state made the in-app update prompt advertise the
// previous build for the whole rollout: 47 went live on Production while the
// server kept telling clients 45 was newest, so nobody was prompted to update
// and salon owners stayed on the build that could not ring.
test("a staged rollout counts as installable", () => {
  const release = (versionCode, releaseLifecycleState) => ({
    releaseLifecycleState,
    activeArtifacts: [{versionCode}],
  });
  const published = "RELEASE_LIFECYCLE_STATE_PUBLISHED";

  assert.equal(highestPublishedVersionCode({releases: [
    release(45, published),
    release(47, "RELEASE_LIFECYCLE_STATE_IN_PROGRESS"),
  ]}), 47);

  // Drafts and halted rollouts are not installable and must not be advertised.
  assert.equal(highestPublishedVersionCode({releases: [
    release(45, published),
    release(48, "RELEASE_LIFECYCLE_STATE_DRAFT"),
  ]}), 45);
  assert.equal(highestPublishedVersionCode({releases: [
    release(45, published),
    release(48, "RELEASE_LIFECYCLE_STATE_HALTED"),
  ]}), 45);

  // The endpoint is ListReleaseSummaries, so accept that shape too.
  assert.equal(highestPublishedVersionCode({releaseSummaries: [
    release(47, "RELEASE_LIFECYCLE_STATE_IN_PROGRESS"),
  ]}), 47);

  // In review is not installable either - that is what the first test guards.
  assert.equal(highestPublishedVersionCode({releases: [
    release(45, published),
    release(48, "RELEASE_LIFECYCLE_STATE_IN_REVIEW"),
  ]}), 45);
  // An unrecognised or missing state is never treated as available.
  assert.equal(highestPublishedVersionCode({releases: [release(47, "")]}), null);
  assert.equal(highestPublishedVersionCode({}), null);
});

test("the advertised build follows a rollout that has reached users", () => {
  // What happened in production: candidate 47, Play reporting only 45.
  assert.equal(resolveAndroidUpdateVersion({
    lastConfirmedPublicVersion: 31,
    candidateVersion: 47,
    configuredVersion: 31,
    playPublishedVersion: 45,
  }), 45, "a build Play has not served must never be advertised");

  assert.equal(resolveAndroidUpdateVersion({
    lastConfirmedPublicVersion: 31,
    candidateVersion: 47,
    configuredVersion: 31,
    playPublishedVersion: 47,
  }), 47, "once the rollout is counted, clients are prompted to 47");
});
