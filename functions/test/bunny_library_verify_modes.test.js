// ADR-010 Amendment 3 — Bunny library verification modes (PURE).
//
// Covers the Decision-4 contract for `verifyBunnyLibrary`:
//  - a token-enforcing library is proven `signed`;
//  - a library that serves plain playback is proven `unsigned` (not a failure);
//  - a failed signature probe never activates a library;
//  - a library the provider does not know is reported as `library_not_found`;
//  - the catalog only trusts a mode that a probe recorded.
const assert = require("node:assert");
const path = require("node:path");

const lifecycle = require(
  path.join(__dirname, "..", "lib", "core", "video", "bunny_library_lifecycle.js"),
);
const catalog = require(
  path.join(__dirname, "..", "lib", "core", "video", "bunny_library_catalog.js"),
);

let passed = 0;
function ok(name, condition) {
  assert.ok(condition, name);
  passed += 1;
  console.log(`ok - ${name}`);
}

function entry(overrides = {}) {
  return {
    library_id: "775315",
    display_name: "Content library",
    status: "active",
    pull_zone_id: 6771915,
    playback_host: "vz-c850a9e1-eb4.b-cdn.net",
    source: "manual_registration",
    credential_refs: {
      stream_api_key: "BUNNY_775315_STREAM_API_KEY",
      token_key: "BUNNY_775315_TOKEN_KEY",
    },
    ...overrides,
  };
}

// --- 1. token auth enforced ------------------------------------------------
const signed = lifecycle.planBunnyLibraryVerificationWrite("pending_verification", {
  tokenAuthEnabled: true,
  tokenAuthVerified: true,
  tokenAuthMode: "signed",
  errorCode: null,
});
ok("enforced token auth activates the library", signed.status === "active");
ok("enforced token auth records the signed mode", signed.token_auth_mode === "signed");
ok("enforced token auth keeps the token flag on", signed.token_auth_enabled === true);
ok("enforced token auth clears the error code", signed.last_error_code === null);

// --- 2. token auth NOT enforced (unsigned) ---------------------------------
const unsigned = lifecycle.planBunnyLibraryVerificationWrite("pending_verification", {
  tokenAuthEnabled: false,
  tokenAuthVerified: true,
  tokenAuthMode: "unsigned",
  errorCode: null,
});
ok("plain playback activates the library", unsigned.status === "active");
ok("plain playback records the unsigned mode", unsigned.token_auth_mode === "unsigned");
ok("plain playback states token auth is off", unsigned.token_auth_enabled === false);
ok("plain playback is not reported as an error", unsigned.last_error_code === null);
ok("plain playback counts as verified", unsigned.verified === true);

// --- 3. signature probe failed --------------------------------------------
const failedSignature = lifecycle.planBunnyLibraryVerificationWrite(
  "pending_verification",
  {
    tokenAuthEnabled: true,
    tokenAuthVerified: false,
    tokenAuthMode: null,
    errorCode: "signed_url_probe_failed",
  },
);
ok("a failed signature never activates", failedSignature.status === "pending_verification");
ok("a failed signature writes no mode", failedSignature.token_auth_mode === null);
ok("a failed signature keeps its typed code",
  failedSignature.last_error_code === "signed_url_probe_failed");
ok("a failed signature is not verified", failedSignature.verified === false);

const demandOnly = lifecycle.planBunnyLibraryVerificationWrite("pending_verification", {
  tokenAuthEnabled: true,
  tokenAuthVerified: false,
  tokenAuthMode: "signed",
  errorCode: null,
});
ok("a claimed signed mode without a 200 stays pending",
  demandOnly.status === "pending_verification");

const unsignedUnproven = lifecycle.planBunnyLibraryVerificationWrite(
  "pending_verification",
  {
    tokenAuthEnabled: false,
    tokenAuthVerified: false,
    tokenAuthMode: "unsigned",
    errorCode: "token_auth_enforced",
  },
);
ok("an unproven unsigned mode stays pending",
  unsignedUnproven.status === "pending_verification");
ok("an unproven unsigned mode records the code",
  unsignedUnproven.last_error_code === "token_auth_enforced");

// --- 4. library not found --------------------------------------------------
ok("a 200 list response is not a failure",
  lifecycle.bunnyProbeFailureReasonForStatus(200) === null);
ok("a 404 list response means the library is unknown",
  lifecycle.bunnyProbeFailureReasonForStatus(404) === "library_not_found");
ok("a 401 list response means the credential was rejected",
  lifecycle.bunnyProbeFailureReasonForStatus(401) === "credential_rejected");
ok("a 403 list response means the credential was rejected",
  lifecycle.bunnyProbeFailureReasonForStatus(403) === "credential_rejected");
ok("any other status is a provider failure",
  lifecycle.bunnyProbeFailureReasonForStatus(500) === "video_list_unavailable");

const missing = lifecycle.planBunnyLibraryVerificationWrite("pending_verification", {
  tokenAuthEnabled: false,
  tokenAuthVerified: false,
  tokenAuthMode: null,
  errorCode: "library_not_found",
});
ok("an unknown library never becomes active", missing.status === "pending_verification");
ok("an unknown library keeps the typed code", missing.last_error_code === "library_not_found");

// --- 5. catalog trusts only a probed mode ---------------------------------
ok("registration declares no mode yet",
  lifecycle.planBunnyLibraryRegistration({
    libraryId: "775315",
    displayName: "Content library",
    pullZoneId: 6771915,
    playbackHost: "vz-c850a9e1-eb4.b-cdn.net",
  }).document.token_auth_mode === null);

const parsedSigned = catalog.parseBunnyCatalogEntry(
  entry({token_auth_enabled: true, token_auth_verified: true, token_auth_mode: "signed"}),
);
ok("a signed row parses", parsedSigned.ok === true);
ok("a signed row keeps its mode", parsedSigned.entry.tokenAuthMode === "signed");
ok("a proved signed row is usable", catalog.isBunnyCatalogEntryUsable(
  entry({token_auth_enabled: true, token_auth_verified: true, token_auth_mode: "signed"}),
) === true);

const parsedUnsigned = catalog.parseBunnyCatalogEntry(
  entry({token_auth_enabled: false, token_auth_verified: true, token_auth_mode: "unsigned"}),
);
ok("an unsigned row parses", parsedUnsigned.ok === true);
ok("an unsigned row keeps its mode", parsedUnsigned.entry.tokenAuthMode === "unsigned");
ok("a proved unsigned row is usable", catalog.isBunnyCatalogEntryUsable(
  entry({token_auth_enabled: false, token_auth_verified: true, token_auth_mode: "unsigned"}),
) === true);
ok("an unsigned row with the token flag on is rejected", catalog.isBunnyCatalogEntryUsable(
  entry({token_auth_enabled: true, token_auth_verified: true, token_auth_mode: "unsigned"}),
) === false);
ok("a signed row with the token flag off is rejected", catalog.isBunnyCatalogEntryUsable(
  entry({token_auth_enabled: false, token_auth_verified: true, token_auth_mode: "signed"}),
) === false);

ok("an undeclared mode is never treated as unsigned", catalog.isBunnyCatalogEntryUsable(
  entry({token_auth_enabled: false, token_auth_verified: true}),
) === false);
ok("an undeclared mode with token auth on still derives signed",
  catalog.parseBunnyCatalogEntry(
    entry({token_auth_enabled: true, token_auth_verified: true}),
  ).entry.tokenAuthMode === null &&
  catalog.bunnyCatalogTokenAuthMode(
    catalog.parseBunnyCatalogEntry(
      entry({token_auth_enabled: true, token_auth_verified: true}),
    ).entry,
  ) === "signed");

const badMode = catalog.parseBunnyCatalogEntry(
  entry({token_auth_enabled: false, token_auth_verified: true, token_auth_mode: "open"}),
);
ok("an unknown mode is a hard parse failure", badMode.ok === false);
ok("an unknown mode reports its reason",
  badMode.ok === false && badMode.reason === "unknown_token_auth_mode");
ok("a row with an unknown mode is never usable",
  catalog.isBunnyCatalogEntryUsable(
    entry({token_auth_enabled: false, token_auth_verified: true, token_auth_mode: "open"}),
  ) === false);

ok("a pending unsigned row is not usable", catalog.isBunnyCatalogEntryUsable(
  entry({status: "pending_verification", token_auth_verified: false, token_auth_mode: "unsigned"}),
) === false);
ok("a disabled unsigned row is not usable", catalog.isBunnyCatalogEntryUsable(
  entry({status: "disabled", token_auth_enabled: false, token_auth_verified: true, token_auth_mode: "unsigned"}),
) === false);
ok("an unsigned row without a probe is not usable",
  catalog.isBunnyCatalogEntryUsable(
    entry({token_auth_enabled: false, token_auth_verified: false, token_auth_mode: "unsigned"}),
  ) === false);

console.log(`bunny_library_verify_modes: ${passed} assertions passed`);
