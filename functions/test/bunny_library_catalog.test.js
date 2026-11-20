/**
 * ADR-010 Amendment 1 — pure catalog contract.
 *
 * Locks the activation gate (active + token auth enabled + probe-verified),
 * the allow-list projection (no secrets/hosts leak to clients) and the
 * deterministic Secret Manager naming. No emulator, no network.
 */
const assert = require("node:assert/strict");
const catalog = require("../lib/core/video/bunny_library_catalog.js");

let passed = 0;
function check(name, actual, expected) {
  assert.deepEqual(actual, expected, name);
  passed++;
  console.log(`ok - ${name}`);
}

const valid = {
  library_id: "780700",
  display_name: "DrTarek-Staging-Test",
  status: "active",
  pull_zone_id: 6807898,
  playback_host: "vz-b5f9cb68-f06.b-cdn.net",
  token_auth_enabled: true,
  token_auth_verified: true,
  credential_refs: {
    stream_api_key: "BUNNY_780700_STREAM_API_KEY",
    token_key: "BUNNY_780700_TOKEN_KEY",
  },
  source: "auto_discovered",
  last_verified_at: {toMillis: () => 1763000000000},
  last_error_code: null,
};

check("valid document parses", catalog.parseBunnyCatalogEntry(valid).ok, true);
check(
  "valid document is usable",
  catalog.isBunnyCatalogEntryUsable(valid),
  true,
);
check(
  "client projection carries only id + label",
  catalog.toEligibleLibraryOption(valid),
  {libraryId: "780700", displayName: "DrTarek-Staging-Test"},
);

const reject = (patch, reason) =>
  check(
    `rejects ${reason}`,
    catalog.parseBunnyCatalogEntry({...valid, ...patch}),
    {ok: false, reason},
  );

reject({library_id: "vz-123"}, "invalid_library_id");
reject({library_id: ""}, "invalid_library_id");
reject({display_name: "   "}, "missing_display_name");
reject({status: "enabled"}, "unknown_status");
reject({pull_zone_id: "abc"}, "invalid_pull_zone_id");
reject({pull_zone_id: 0}, "invalid_pull_zone_id");
reject({playback_host: "https://vz-x.b-cdn.net/path"}, "invalid_playback_host");
reject({playback_host: "example.com"}, "invalid_playback_host");
reject({source: "operator"}, "unknown_source");
reject({credential_refs: {stream_api_key: "lower-case", token_key: "BUNNY_X_TOKEN_KEY"}}, "invalid_credential_ref");
reject({credential_refs: {stream_api_key: "BUNNY_X_STREAM_API_KEY"}}, "invalid_credential_ref");

check(
  "credential values cannot masquerade as names",
  catalog.parseBunnyCatalogEntry({
    ...valid,
    credential_refs: {stream_api_key: "a".repeat(40), token_key: "BUNNY_780700_TOKEN_KEY"},
  }),
  {ok: false, reason: "invalid_credential_ref"},
);

// --- activation gate ---
const gate = (patch) => catalog.isBunnyCatalogEntryUsable({...valid, ...patch});
check("pending verification is not usable", gate({status: "pending_verification"}), false);
check("disabled library is not usable", gate({status: "disabled"}), false);
check("error library is not usable", gate({status: "error"}), false);
check("token auth disabled is not usable", gate({token_auth_enabled: false}), false);
check("unverified token auth is not usable", gate({token_auth_verified: false}), false);
check(
  "unverified library projects to null",
  catalog.toEligibleLibraryOption({...valid, token_auth_verified: false}),
  null,
);
check(
  "malformed document projects to null",
  catalog.toEligibleLibraryOption({...valid, status: "nope"}),
  null,
);
check("null document is not usable", catalog.isBunnyCatalogEntryUsable(null), false);

// --- deterministic secret names ---
check("secret names are deterministic", catalog.bunnySecretNames("780700"), {
  streamApiKey: "BUNNY_780700_STREAM_API_KEY",
  tokenKey: "BUNNY_780700_TOKEN_KEY",
});
check(
  "secret names reject non-numeric ids",
  (() => {
    try {
      catalog.bunnySecretNames("../../etc");
      return "no-throw";
    } catch {
      return "threw";
    }
  })(),
  "threw",
);

// --- unknown fields are dropped (no smuggling) ---
check(
  "extra fields never reach the projection",
  catalog.toEligibleLibraryOption({...valid, secret: "leak", host: "evil"}),
  {libraryId: "780700", displayName: "DrTarek-Staging-Test"},
);

console.log(`\n${passed} checks passed`);
