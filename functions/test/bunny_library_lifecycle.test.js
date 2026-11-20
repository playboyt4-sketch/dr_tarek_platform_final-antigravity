// ADR-010 Option C — pure tests for the Bunny library lifecycle module.
// No Firestore, no Secret Manager, no network: only the registration plan,
// the status state machine, the verification write mapping, the audit payload
// shape and the N5 receipt-key resolution are exercised.
const assert = require("node:assert");
const path = require("node:path");

const lib = require(path.join(__dirname, "..", "lib", "core", "video", "bunny_library_lifecycle.js"));

const VALID = Object.freeze({
  libraryId: "780700",
  displayName: "Test Library",
  pullZoneId: 123456,
  playbackHost: "vz-abc123-def.b-cdn.net",
});

let passed = 0;
function ok(name, condition) {
  assert.ok(condition, name);
  passed += 1;
  console.log(`ok - ${name}`);
}

function register(overrides = {}) {
  return lib.planBunnyLibraryRegistration({...VALID, ...overrides});
}

function registerReason(overrides) {
  const result = register(overrides);
  return result.ok ? "ok" : result.reason;
}

// --- registration: accepted input --------------------------------------
const accepted = register();
ok("accepts a well-formed registration", accepted.ok === true);
ok("registration returns the library id", accepted.libraryId === "780700");
ok("registration is never active", accepted.document.status === "pending_verification");
ok("registration leaves token auth disabled", accepted.document.token_auth_enabled === false);
ok("registration leaves token auth unverified", accepted.document.token_auth_verified === false);
ok("registration has no verification timestamp", accepted.document.last_verified_at === null);
ok("registration has no error code", accepted.document.last_error_code === null);
ok(
  "registration derives the Stream API secret name from the id",
  accepted.document.credential_refs.stream_api_key === "BUNNY_780700_STREAM_API_KEY",
);
ok(
  "registration derives the token secret name from the id",
  accepted.document.credential_refs.token_key === "BUNNY_780700_TOKEN_KEY",
);
ok(
  "registration default source is manual_registration",
  accepted.document.source === "manual_registration",
);
ok(
  "registration stores exactly the two credential names",
  Object.keys(accepted.document.credential_refs).sort().join(",") === "stream_api_key,token_key",
);
ok(
  "registration document stores no URL or key value",
  (() => {
    const {playback_host: playbackHost, ...rest} = accepted.document;
    const text = JSON.stringify(rest);
    return playbackHost === "vz-abc123-def.b-cdn.net" &&
      !text.includes("http") &&
      !text.includes("b-cdn.net");
  })(),
);
ok(
  "registration stores credential names, never values",
  Object.values(accepted.document.credential_refs).every((name) => /^BUNNY_[0-9]+_(STREAM_API_KEY|TOKEN_KEY)$/.test(name)),
);

// --- registration: rejected input --------------------------------------
ok("rejects an empty library id", registerReason({libraryId: ""}) === "invalid_library_id");
ok("rejects a non-numeric library id", registerReason({libraryId: "lib-abc"}) === "invalid_library_id");
ok("rejects a path as a library id", registerReason({libraryId: "/780700"}) === "invalid_library_id");
ok("rejects a missing library id", registerReason({libraryId: undefined}) === "invalid_library_id");
ok("rejects a whitespace-only display name", registerReason({displayName: "   "}) === "missing_display_name");
ok("rejects a missing display name", registerReason({displayName: undefined}) === "missing_display_name");
ok("rejects a zero pull-zone id", registerReason({pullZoneId: 0}) === "invalid_pull_zone_id");
ok("rejects a negative pull-zone id", registerReason({pullZoneId: -5}) === "invalid_pull_zone_id");
ok("rejects a fractional pull-zone id", registerReason({pullZoneId: 1.5}) === "invalid_pull_zone_id");
ok("rejects a non-numeric pull-zone id", registerReason({pullZoneId: "abc"}) === "invalid_pull_zone_id");
ok("rejects a missing pull-zone id", registerReason({pullZoneId: undefined}) === "invalid_pull_zone_id");
ok("rejects a URL as the playback host", registerReason({playbackHost: "https://vz-abc.b-cdn.net"}) === "invalid_playback_host");
ok("rejects a foreign playback host", registerReason({playbackHost: "cdn.example.com"}) === "invalid_playback_host");
ok("rejects an unknown source", registerReason({source: "operator_guess"}) === "invalid_source");

// --- registration: normalization ---------------------------------------
ok(
  "accepts a numeric-string pull-zone id",
  register({pullZoneId: "123456"}).document.pull_zone_id === 123456,
);
ok(
  "lowercases the playback host",
  register({playbackHost: "VZ-ABC123-DEF.B-CDN.NET"}).document.playback_host === "vz-abc123-def.b-cdn.net",
);
ok(
  "trims the library id and display name",
  register({libraryId: " 780700 ", displayName: "  Test Library  "}).document.display_name === "Test Library",
);
ok(
  "accepts an explicit legacy_env source",
  register({source: "legacy_env"}).document.source === "legacy_env",
);
ok(
  "accepts an explicit auto_discovered source",
  register({source: "auto_discovered"}).document.source === "auto_discovered",
);
ok(
  "ignores operator-supplied credential names",
  (() => {
    const result = lib.planBunnyLibraryRegistration({
      ...VALID,
      credential_refs: {stream_api_key: "ATTACKER_KEY", token_key: "ATTACKER_TOKEN"},
      credentialRefs: {stream_api_key: "ATTACKER_KEY", token_key: "ATTACKER_TOKEN"},
    });
    return result.ok === true &&
      result.document.credential_refs.stream_api_key === "BUNNY_780700_STREAM_API_KEY" &&
      result.document.credential_refs.token_key === "BUNNY_780700_TOKEN_KEY";
  })(),
);

// --- status state machine ----------------------------------------------
function transition(status, action) {
  return lib.planBunnyLibraryStatusTransition(status, action);
}

ok("deactivate moves pending_verification to disabled", (() => {
  const plan = transition("pending_verification", "deactivate");
  return plan.ok && plan.status === "disabled" && plan.previousStatus === "pending_verification";
})());
ok("deactivate moves active to disabled", (() => {
  const plan = transition("active", "deactivate");
  return plan.ok && plan.status === "disabled" && plan.previousStatus === "active";
})());
ok("deactivate moves error to disabled", (() => {
  const plan = transition("error", "deactivate");
  return plan.ok && plan.status === "disabled";
})());
ok("deactivate on disabled is rejected", transition("disabled", "deactivate").reason === "already_disabled");
ok("reactivate moves disabled to pending_verification", (() => {
  const plan = transition("disabled", "reactivate");
  return plan.ok && plan.status === "pending_verification";
})());
ok("reactivate never returns active", transition("disabled", "reactivate").status !== "active");
ok("reactivate on active is rejected", transition("active", "reactivate").reason === "not_disabled");
ok("reactivate on pending_verification is rejected", transition("pending_verification", "reactivate").reason === "not_disabled");
ok("retry moves error to pending_verification", (() => {
  const plan = transition("error", "retry");
  return plan.ok && plan.status === "pending_verification";
})());
ok("retry on active is rejected", transition("active", "retry").reason === "invalid_status");
ok("retry on pending_verification is rejected", transition("pending_verification", "retry").reason === "invalid_status");
ok("retry on disabled is rejected", transition("disabled", "retry").reason === "invalid_status");

// --- verification write mapping ----------------------------------------
function verification(status, outcome) {
  return lib.planBunnyLibraryVerificationWrite(status, outcome);
}

const verified = verification("pending_verification", {
  tokenAuthEnabled: true,
  tokenAuthVerified: true,
  errorCode: null,
});
ok("verified probe activates the library", verified.status === "active");
ok("verified probe sets both token flags", verified.token_auth_enabled === true && verified.token_auth_verified === true);
ok("verified probe clears the error code", verified.last_error_code === null);
ok("verified probe reports verified", verified.verified === true);

const enabledOnly = verification("pending_verification", {
  tokenAuthEnabled: true,
  tokenAuthVerified: false,
  errorCode: "signed_url_probe_failed",
});
ok("enabled but unproven stays pending", enabledOnly.status === "pending_verification");
ok("enabled but unproven is not verified", enabledOnly.verified === false && enabledOnly.token_auth_verified === false);
ok("enabled but unproven keeps the typed code", enabledOnly.last_error_code === "signed_url_probe_failed");

const disabledAuth = verification("pending_verification", {
  tokenAuthEnabled: false,
  tokenAuthVerified: false,
  errorCode: "token_auth_disabled",
});
ok("disabled token auth never activates", disabledAuth.status === "pending_verification");
ok("disabled token auth records the typed code", disabledAuth.last_error_code === "token_auth_disabled");

const regressed = verification("active", {
  tokenAuthEnabled: false,
  tokenAuthVerified: false,
  errorCode: "token_auth_disabled",
});
ok("a failing probe demotes an active library to error", regressed.status === "error");
ok("a demoted library is not verified", regressed.verified === false && regressed.token_auth_verified === false);

const noCode = verification("pending_verification", {
  tokenAuthEnabled: false,
  tokenAuthVerified: false,
  errorCode: null,
});
ok("a missing error code falls back to token_auth_unverified", noCode.last_error_code === "token_auth_unverified");
ok("a probe claiming verification without enablement cannot activate", verification("pending_verification", {
  tokenAuthEnabled: false,
  tokenAuthVerified: true,
  errorCode: null,
}).status === "pending_verification");

// --- audit payload -----------------------------------------------------
const audit = lib.buildBunnyLibraryAuditEntry({
  action: "bunny_library_deactivate",
  actorId: "uid-doctor",
  actorRole: "doctor",
  permissionBasis: "doctor",
  libraryId: "780700",
  previousStatus: "active",
  newStatus: "disabled",
  reason: "operator requested",
});
ok("audit action is recorded", audit.action === "bunny_library_deactivate");
ok("audit entity is bunny_library", audit.entity === "bunny_library");
ok("audit target matches the library id", audit.target_id === "780700" && audit.library_id === "780700");
ok("audit records actor and permission basis", audit.actor_id === "uid-doctor" && audit.actor_role === "doctor" && audit.permission_basis === "doctor");
ok("audit records both statuses", audit.previous_status === "active" && audit.new_status === "disabled");
ok("audit records the operator reason", audit.reason === "operator requested");
ok("audit omits absent optional fields", (() => {
  const minimal = lib.buildBunnyLibraryAuditEntry({
    action: "bunny_library_register",
    actorId: "uid-doctor",
    actorRole: "doctor",
    permissionBasis: "doctor",
    libraryId: "780700",
    previousStatus: null,
    newStatus: "pending_verification",
  });
  return !("reason" in minimal) && !("reason_code" in minimal) && !("source" in minimal);
})());
ok("audit includes reason_code and source when supplied", (() => {
  const full = lib.buildBunnyLibraryAuditEntry({
    action: "bunny_library_verify",
    actorId: "uid-doctor",
    actorRole: "doctor",
    permissionBasis: "doctor",
    libraryId: "780700",
    previousStatus: "pending_verification",
    newStatus: "active",
    reasonCode: null,
    source: "manual_registration",
  });
  return full.source === "manual_registration";
})());
ok("audit payload contains no credential or host material", (() => {
  const text = JSON.stringify(lib.buildBunnyLibraryAuditEntry({
    action: "bunny_library_verify",
    actorId: "uid-doctor",
    actorRole: "doctor",
    permissionBasis: "doctor",
    libraryId: "780700",
    previousStatus: "pending_verification",
    newStatus: "active",
  }));
  return !text.includes("BUNNY_") && !text.includes("b-cdn.net") && !text.includes("http");
})());

// --- N5 receipt key resolution -----------------------------------------
const RECEIPT_VAR = lib.BUNNY_ASSOCIATION_RECEIPT_KEY_VAR;
ok("receipt key variable name is stable", RECEIPT_VAR === "BUNNY_ASSOCIATION_RECEIPT_KEY");

ok("legacy token key signs and verifies when no dedicated key exists", (() => {
  const keys = lib.resolveBunnyReceiptSigningKeys({
    env: {BUNNY_TOKEN_KEY: "legacy-key"},
  });
  return keys !== null &&
    keys.signKey === "legacy-key" &&
    keys.verifyKeys.length === 1 &&
    keys.verifyKeys[0] === "legacy-key";
})());
ok("a mounted dedicated key becomes the signer", (() => {
  const keys = lib.resolveBunnyReceiptSigningKeys({
    env: {BUNNY_TOKEN_KEY: "legacy-key"},
    mountedReceiptKey: "receipt-key",
  });
  return keys !== null && keys.signKey === "receipt-key";
})());
ok("the transition window verifies both keys", (() => {
  const keys = lib.resolveBunnyReceiptSigningKeys({
    env: {BUNNY_TOKEN_KEY: "legacy-key"},
    mountedReceiptKey: "receipt-key",
  });
  return keys !== null &&
    keys.verifyKeys.includes("receipt-key") &&
    keys.verifyKeys.includes("legacy-key") &&
    keys.verifyKeys.length === 2;
})());
ok("a dedicated key in env is honoured", (() => {
  const keys = lib.resolveBunnyReceiptSigningKeys({
    env: {[RECEIPT_VAR]: "env-receipt-key", BUNNY_TOKEN_KEY: "legacy-key"},
  });
  return keys !== null && keys.signKey === "env-receipt-key";
})());
ok("the mounted key wins over the env value", (() => {
  const keys = lib.resolveBunnyReceiptSigningKeys({
    env: {[RECEIPT_VAR]: "env-receipt-key", BUNNY_TOKEN_KEY: "legacy-key"},
    mountedReceiptKey: "mounted-receipt-key",
  });
  return keys !== null && keys.signKey === "mounted-receipt-key";
})());
ok("an explicit legacy key argument is accepted", (() => {
  const keys = lib.resolveBunnyReceiptSigningKeys({
    env: {},
    legacyTokenKey: "argument-key",
  });
  return keys !== null && keys.signKey === "argument-key";
})());
ok("a dedicated key alone needs no legacy key", (() => {
  const keys = lib.resolveBunnyReceiptSigningKeys({
    env: {[RECEIPT_VAR]: "receipt-key"},
  });
  return keys !== null &&
    keys.signKey === "receipt-key" &&
    keys.verifyKeys.length === 1 &&
    keys.verifyKeys[0] === "receipt-key";
})());
ok("no usable key resolves to null", lib.resolveBunnyReceiptSigningKeys({env: {}}) === null);
ok("blank values never count as keys", lib.resolveBunnyReceiptSigningKeys({
  env: {[RECEIPT_VAR]: "   ", BUNNY_TOKEN_KEY: ""},
  mountedReceiptKey: "  ",
}) === null);

console.log(`bunny_library_lifecycle: ${passed} assertions passed`);
