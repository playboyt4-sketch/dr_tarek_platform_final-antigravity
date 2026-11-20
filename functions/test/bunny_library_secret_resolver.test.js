/**
 * ADR-010 Mission 17 — per-library Secret Manager resolver (pure, no emulator).
 *
 * Proves the resolver contract with mocked catalog + Secret Manager surfaces:
 *   - Library A never uses Library B's Stream API key or token-signing key.
 *   - Unknown / disabled / incomplete catalog entries fail closed.
 *   - A catalog row that names another library's secret is rejected BEFORE any
 *     read (`credential_name_mismatch`).
 *   - Missing secret, permission denial, service failure and malformed values
 *     fail closed with typed reasons.
 *   - Positive caching is bounded (rotation is never masked indefinitely);
 *     failures are never cached.
 *   - No secret value, secret name or Secret Manager path appears in an error.
 *   - Mission 19: the compiled Production default id is NOT a library in an
 *     environment whose canonical default is different; an explicit foreign
 *     id fails closed and never inherits the local default's credentials,
 *     template or Stream API path.
 *
 * No Firestore and no network: the catalog and the Secret Manager client are
 * injected doubles.
 */
const assert = require("node:assert/strict");

const registry = require("../lib/core/video/bunny_library_registry.js");
const resolver = require("../lib/core/video/bunny_library_secret_resolver.js");
const {
  BunnySecretAccessError,
  bunnyCredentialFailureReason,
  createBunnySecretAccessor,
  deriveCatalogLibraryDefinition,
  planBunnyLibraryCredentialResolution,
  resolveBunnyLibraryCredentials,
  resolveBunnyPlaybackCredentials,
  resolveBunnyStreamApiCredentials,
} = resolver;

const LIB_A = "780700";
const LIB_B = "781800";
const LIB_DEFAULT = "736742";
const LIB_INACTIVE = "775315";

const SECRETS = {
  BUNNY_780700_STREAM_API_KEY: "A-stream-api-key-0001",
  BUNNY_780700_TOKEN_KEY: "A-token-signing-key-0001",
  BUNNY_781800_STREAM_API_KEY: "B-stream-api-key-0002",
  BUNNY_781800_TOKEN_KEY: "B-token-signing-key-0002",
  BUNNY_736742_STREAM_API_KEY: "default-stream-key-0003",
  BUNNY_736742_TOKEN_KEY: "default-token-key-0003",
};

const BASE_ENV = {
  BUNNY_DEFAULT_LIBRARY_ID: LIB_DEFAULT,
  BUNNY_ACTIVE_LIBRARY_IDS: `${LIB_A},${LIB_B},${LIB_INACTIVE}`,
  BUNNY_PLAYBACK_URL_TEMPLATE:
    "https://default.b-cdn.net/{video_id}/playlist.m3u8",
  BUNNY_780700_PLAYBACK_URL_TEMPLATE:
    "https://a.b-cdn.net/{video_id}/playlist.m3u8",
  BUNNY_781800_PLAYBACK_URL_TEMPLATE:
    "https://b.b-cdn.net/{video_id}/playlist.m3u8",
  BUNNY_775315_PLAYBACK_URL_TEMPLATE:
    "https://inactive.b-cdn.net/{video_id}/playlist.m3u8",
  BUNNY_STREAM_API_KEY: "legacy-default-stream-key",
  BUNNY_STREAM_LIBRARY_ID: LIB_DEFAULT,
  BUNNY_TOKEN_KEY: "legacy-default-token-key",
};

function catalogDocument(libraryId, overrides = {}) {
  return {
    id: libraryId,
    data: {
      library_id: libraryId,
      display_name: `Library ${libraryId}`,
      status: "active",
      pull_zone_id: 123456,
      playback_host: "vz-test.b-cdn.net",
      source: "manual_registration",
      token_auth_enabled: true,
      token_auth_verified: true,
      credential_refs: {
        stream_api_key: `BUNNY_${libraryId}_STREAM_API_KEY`,
        token_key: `BUNNY_${libraryId}_TOKEN_KEY`,
      },
      ...overrides,
    },
  };
}

function catalogOf(documents) {
  const reads = [];
  return {
    reads,
    async get(libraryId) {
      reads.push(libraryId);
      return documents[libraryId] ?? null;
    },
  };
}

function secretsOf(values) {
  const reads = [];
  return {
    reads,
    async readSecret(name) {
      reads.push(name);
      if (!Object.prototype.hasOwnProperty.call(values, name)) {
        throw new BunnySecretAccessError("not_found");
      }
      return values[name];
    },
  };
}

function failingSecrets(kind) {
  const reads = [];
  return {
    reads,
    async readSecret(name) {
      reads.push(name);
      throw new BunnySecretAccessError(kind);
    },
  };
}

function depsFor({documents = {}, values = SECRETS, env = BASE_ENV, secrets}) {
  const catalog = catalogOf(documents);
  const secretAccessor = secrets ?? secretsOf(values);
  return {
    catalog,
    secrets: secretAccessor,
    env,
    async resolvePlayback(libraryId) {
      return resolveBunnyPlaybackCredentials({
        libraryId,
        deps: {catalog, secrets: secretAccessor, env},
      });
    },
    async resolveStream(libraryId) {
      return resolveBunnyStreamApiCredentials({
        libraryId,
        deps: {catalog, secrets: secretAccessor, env},
      });
    },
  };
}

function assertNoSecretLeak(payload, label) {
  const serialized = typeof payload === "string" ?
    payload :
    JSON.stringify(payload);
  for (const value of Object.values(SECRETS)) {
    assert.ok(
      !serialized.includes(value),
      `${label}: leaked a secret VALUE`,
    );
  }
  for (const name of Object.keys(SECRETS)) {
    assert.ok(
      !serialized.includes(name),
      `${label}: leaked a secret NAME`,
    );
  }
  assert.ok(
    !serialized.includes("/secrets/"),
    `${label}: leaked a Secret Manager resource path`,
  );
}

async function run() {
  console.log("Starting bunny_library_secret_resolver (pure) tests...");
  let passed = 0;
  const ok = (name) => {
    passed++;
    console.log(`ok - ${name}`);
  };

  const twoLibraries = {
    [LIB_A]: catalogDocument(LIB_A),
    [LIB_B]: catalogDocument(LIB_B),
  };

  // --- 1. Library A resolves ONLY A's Stream API key -----------------------
  {
    const deps = depsFor({documents: twoLibraries});
    const a = await deps.resolveStream(LIB_A);
    assert.equal(a.ok, true, "A stream credentials resolve");
    assert.equal(a.runtime.apiKey, SECRETS.BUNNY_780700_STREAM_API_KEY);
    assert.equal(a.runtime.apiLibraryId, LIB_A);
    assert.deepEqual(
      deps.secrets.reads,
      ["BUNNY_780700_STREAM_API_KEY"],
      "A reads exactly one secret: its own Stream API key",
    );
    assert.ok(
      !a.runtime.apiKey.includes("0002"),
      "A never receives B's Stream API key",
    );
    ok("Library A uses only its own Stream API key");
  }

  // --- 2. Library A resolves ONLY A's token-signing key --------------------
  {
    const deps = depsFor({documents: twoLibraries});
    const a = await deps.resolvePlayback(LIB_A);
    assert.equal(a.ok, true, "A playback credentials resolve");
    assert.equal(a.runtime.tokenKey, SECRETS.BUNNY_780700_TOKEN_KEY);
    assert.equal(
      a.runtime.playbackUrlTemplate,
      BASE_ENV.BUNNY_780700_PLAYBACK_URL_TEMPLATE,
    );
    assert.deepEqual(
      deps.secrets.reads,
      ["BUNNY_780700_TOKEN_KEY"],
      "A playback reads exactly one secret: its own token key",
    );
    assert.notEqual(a.runtime.tokenKey, SECRETS.BUNNY_781800_TOKEN_KEY);
    ok("Library A uses only its own token-signing key");
  }

  // --- 3. Library B resolves ONLY B's credentials --------------------------
  {
    const deps = depsFor({documents: twoLibraries});
    const bStream = await deps.resolveStream(LIB_B);
    const bPlayback = await deps.resolvePlayback(LIB_B);
    assert.equal(bStream.runtime.apiKey, SECRETS.BUNNY_781800_STREAM_API_KEY);
    assert.equal(bPlayback.runtime.tokenKey, SECRETS.BUNNY_781800_TOKEN_KEY);
    assert.deepEqual(deps.secrets.reads, [
      "BUNNY_781800_STREAM_API_KEY",
      "BUNNY_781800_TOKEN_KEY",
    ]);
    assert.ok(
      !bStream.runtime.apiKey.includes("0001") &&
        !bPlayback.runtime.tokenKey.includes("0001"),
      "B never receives A's credentials",
    );
    ok("Library B uses only its own credentials");
  }

  // --- 4. Metadata-only flow never reads the token key ---------------------
  {
    const deps = depsFor({documents: twoLibraries});
    await deps.resolveStream(LIB_A);
    assert.ok(
      !deps.secrets.reads.includes("BUNNY_780700_TOKEN_KEY"),
      "metadata-only resolution must not read the token-signing key",
    );
    ok("metadata-only resolution reads only the Stream API key");
  }

  // --- 5. Signing-only flow never reads the Stream API key -----------------
  {
    const deps = depsFor({documents: twoLibraries});
    await deps.resolvePlayback(LIB_A);
    assert.ok(
      !deps.secrets.reads.includes("BUNNY_780700_STREAM_API_KEY"),
      "playback signing must not read the Stream API key",
    );
    ok("playback signing reads only the token-signing key");
  }

  // --- 6. Unknown library fails closed with no catalog/secret read ---------
  {
    const deps = depsFor({documents: twoLibraries});
    const result = await deps.resolvePlayback("999999");
    assert.equal(result.ok, false);
    assert.equal(result.reason, "unknown_library");
    assert.deepEqual(deps.catalog.reads, ["999999"], "catalog was consulted");
    assert.deepEqual(deps.secrets.reads, [], "no secret read for unknown id");
    assertNoSecretLeak(result, "unknown library failure");
    ok("unknown library id fails closed without reading secrets");
  }

  // --- 7. Malformed library id fails closed --------------------------------
  {
    const deps = depsFor({documents: twoLibraries});
    for (const bad of ["", "   ", "../736742", "abc", null, 42]) {
      const result = await deps.resolvePlayback(bad);
      assert.equal(result.ok, false, `malformed id ${String(bad)} rejected`);
      assert.equal(result.reason, "unknown_library");
    }
    assert.deepEqual(deps.secrets.reads, [], "no secret read for malformed ids");
    ok("malformed library ids fail closed without reading secrets");
  }

  // --- 8. Disabled library fails closed ------------------------------------
  {
    const deps = depsFor({
      documents: {
        [LIB_A]: catalogDocument(LIB_A, {status: "disabled"}),
      },
    });
    const result = await deps.resolvePlayback(LIB_A);
    assert.equal(result.ok, false);
    assert.equal(result.reason, "library_not_activated");
    assert.deepEqual(deps.secrets.reads, [], "no secret read for disabled id");
    ok("disabled library fails closed without reading secrets");
  }

  // --- 9. Library missing from the activation allow-list fails closed ------
  {
    const env = {...BASE_ENV, BUNNY_ACTIVE_LIBRARY_IDS: LIB_B};
    const deps = depsFor({documents: twoLibraries, env});
    const result = await deps.resolvePlayback(LIB_A);
    assert.equal(result.ok, false);
    assert.equal(result.reason, "library_not_activated");
    assert.deepEqual(deps.secrets.reads, []);
    ok("catalog library outside the allow-list fails closed");
  }

  // --- 10. Incomplete catalog entries fail closed --------------------------
  {
    for (const [overrides, expected] of [
      [{token_auth_verified: false}, "incomplete_configuration"],
      [{token_auth_enabled: false}, "incomplete_configuration"],
      [{status: "pending_verification"}, "library_not_activated"],
    ]) {
      const deps = depsFor({
        documents: {[LIB_A]: catalogDocument(LIB_A, overrides)},
      });
      const result = await deps.resolvePlayback(LIB_A);
      assert.equal(result.ok, false, `${JSON.stringify(overrides)} rejected`);
      assert.equal(result.reason, expected);
      assert.deepEqual(deps.secrets.reads, []);
    }
    ok("incomplete (unverified) catalog entries fail closed");
  }

  // --- 11. Structurally invalid catalog entries fail closed ----------------
  {
    for (const overrides of [
      {playback_host: "https://evil.example.com"},
      {display_name: ""},
      {credential_refs: {}},
      {pull_zone_id: 0},
    ]) {
      const deps = depsFor({
        documents: {[LIB_A]: catalogDocument(LIB_A, overrides)},
      });
      const result = await deps.resolvePlayback(LIB_A);
      assert.equal(result.ok, false, `${JSON.stringify(overrides)} rejected`);
      assert.equal(result.reason, "invalid_catalog_entry");
      assert.deepEqual(deps.secrets.reads, []);
    }
    ok("invalid catalog entries fail closed");
  }

  // --- 12. A catalog row may never point at another library's secret -------
  {
    const deps = depsFor({
      documents: {
        [LIB_A]: catalogDocument(LIB_A, {
          credential_refs: {
            stream_api_key: "BUNNY_781800_STREAM_API_KEY",
            token_key: "BUNNY_781800_TOKEN_KEY",
          },
        }),
      },
    });
    const result = await deps.resolveStream(LIB_A);
    assert.equal(result.ok, false);
    assert.equal(result.reason, "credential_name_mismatch");
    assert.deepEqual(
      deps.secrets.reads,
      [],
      "mismatch is rejected BEFORE any secret read",
    );
    ok("cross-library secret reference is rejected before any read");
  }

  // --- 13. Document id must equal the requested library id -----------------
  {
    const deps = depsFor({
      documents: {
        [LIB_A]: catalogDocument(LIB_B),
      },
    });
    const result = await deps.resolvePlayback(LIB_A);
    assert.equal(result.ok, false);
    assert.equal(result.reason, "invalid_catalog_entry");
    assert.deepEqual(deps.secrets.reads, []);
    ok("catalog document id must match the requested library");
  }

  // --- 14. Missing Stream API secret fails closed --------------------------
  {
    const values = {...SECRETS};
    delete values.BUNNY_780700_STREAM_API_KEY;
    const deps = depsFor({documents: twoLibraries, values});
    const result = await deps.resolveStream(LIB_A);
    assert.equal(result.ok, false);
    assert.equal(result.reason, "secret_not_found");
    assertNoSecretLeak(result, "missing stream secret");
    ok("missing Stream API secret fails closed");
  }

  // --- 15. Missing token-signing secret fails closed -----------------------
  {
    const values = {...SECRETS};
    delete values.BUNNY_780700_TOKEN_KEY;
    const deps = depsFor({documents: twoLibraries, values});
    const result = await deps.resolvePlayback(LIB_A);
    assert.equal(result.ok, false);
    assert.equal(result.reason, "secret_not_found");
    ok("missing token-signing secret fails closed");
  }

  // --- 16. Permission denial / service failure fail closed -----------------
  {
    for (const [kind, expected] of [
      ["permission_denied", "secret_permission_denied"],
      ["unavailable", "secret_unavailable"],
    ]) {
      const deps = depsFor({
        documents: twoLibraries,
        secrets: failingSecrets(kind),
      });
      const result = await deps.resolveStream(LIB_A);
      assert.equal(result.ok, false, `${kind} rejected`);
      assert.equal(result.reason, expected);
      assertNoSecretLeak(result, `${kind} failure`);
    }
    ok("Secret Manager permission denial and service failure fail closed");
  }

  // --- 17. Invalid secret values fail closed -------------------------------
  {
    for (const bad of ["", "   ", "short", "has space in value", "a".repeat(513)]) {
      const deps = depsFor({
        documents: twoLibraries,
        values: {...SECRETS, BUNNY_780700_STREAM_API_KEY: bad},
      });
      const result = await deps.resolveStream(LIB_A);
      assert.equal(result.ok, false, `invalid value ${JSON.stringify(bad)} rejected`);
      assert.equal(result.reason, "invalid_secret_value");
      assertNoSecretLeak(result, "invalid secret value");
    }
    ok("malformed secret values fail closed");
  }

  // --- 18. Catalog read failure fails closed -------------------------------
  {
    const catalog = {
      async get() {
        throw new Error("firestore unavailable");
      },
    };
    const result = await resolveBunnyPlaybackCredentials({
      libraryId: LIB_A,
      deps: {catalog, secrets: secretsOf(SECRETS), env: BASE_ENV},
    });
    assert.equal(result.ok, false);
    assert.equal(result.reason, "catalog_unavailable");
    ok("catalog read failure fails closed");
  }

  // --- 19. No legacy fallback for a non-default library --------------------
  {
    // Not compiled into the registry AND no catalog row: unknown, not legacy.
    const deps = depsFor({documents: {}});
    const result = await deps.resolveStream(LIB_A);
    assert.equal(result.ok, false);
    assert.equal(result.reason, "unknown_library");
    assert.deepEqual(deps.secrets.reads, []);

    // Compiled non-default library, allow-listed, but no catalog row: it may
    // not fall back to the legacy default credentials either.
    const compiled = await deps.resolveStream(LIB_INACTIVE);
    assert.equal(compiled.ok, false);
    assert.equal(compiled.reason, "incomplete_configuration");
    assert.deepEqual(deps.secrets.reads, []);
    ok("non-default library without a catalog row never borrows global keys");
  }

  // --- 20. Legacy default path reads only its own env keys -----------------
  {
    const deps = depsFor({documents: {}});
    const playback = await deps.resolvePlayback(LIB_DEFAULT);
    assert.equal(playback.ok, true);
    assert.equal(playback.runtime.tokenKey, "legacy-default-token-key");
    assert.deepEqual(
      deps.secrets.reads,
      [],
      "legacy default does not read Secret Manager",
    );
    const stream = await deps.resolveStream(LIB_DEFAULT);
    assert.equal(stream.ok, true);
    assert.equal(stream.runtime.apiKey, "legacy-default-stream-key");
    ok("legacy default library keeps its own pre-existing env credentials");
  }

  // --- 21. Legacy fallback can be disabled ---------------------------------
  {
    const env = {...BASE_ENV, BUNNY_LEGACY_LIBRARY_FALLBACK: "false"};
    const deps = depsFor({documents: {}, env});
    const result = await deps.resolvePlayback(LIB_DEFAULT);
    assert.equal(result.ok, false);
    assert.equal(result.reason, "incomplete_configuration");
    ok("legacy default fallback can be disabled");
  }

  // --- 22. Catalog-backed default library uses its own SM entry ------------
  {
    const deps = depsFor({
      documents: {[LIB_DEFAULT]: catalogDocument(LIB_DEFAULT)},
    });
    const result = await deps.resolvePlayback(LIB_DEFAULT);
    assert.equal(result.ok, true);
    assert.equal(result.runtime.tokenKey, SECRETS.BUNNY_736742_TOKEN_KEY);
    assert.deepEqual(deps.secrets.reads, ["BUNNY_736742_TOKEN_KEY"]);
    ok("catalog-backed default library reads its own deterministic secret");
  }

  // --- 23. Plan never widens the registry for uncatalogued ids -------------
  {
    const planned = planBunnyLibraryCredentialResolution({
      libraryId: "999999",
      document: null,
      env: BASE_ENV,
    });
    assert.equal(planned.ok, false);
    assert.equal(planned.reason, "unknown_library");
    ok("uncatalogued id is unknown even when an allow-list entry exists");
  }

  // --- 24. Derived catalog definition follows the naming convention --------
  {
    const definition = deriveCatalogLibraryDefinition(LIB_A);
    assert.equal(definition.streamApiKeyVar, "BUNNY_780700_STREAM_API_KEY");
    assert.equal(definition.tokenKeyVar, "BUNNY_780700_TOKEN_KEY");
    assert.equal(
      definition.playbackUrlTemplateVar,
      "BUNNY_780700_PLAYBACK_URL_TEMPLATE",
    );
    assert.equal(definition.isDefault, false);
    assert.equal(deriveCatalogLibraryDefinition("nope"), null);
    ok("derived catalog definition uses the approved naming convention");
  }

  // --- 25. Positive cache is bounded; failures are never cached ------------
  {
    let nowMs = 1000;
    const env = {...SECRETS};
    const accessor = createBunnySecretAccessor({
      isEmulator: true,
      env,
      cacheTtlMs: 500,
      now: () => nowMs,
    });
    assert.equal(
      await accessor.readSecret("BUNNY_780700_TOKEN_KEY"),
      "A-token-signing-key-0001",
    );
    // Rotation within the TTL: the cached value is still served...
    env.BUNNY_780700_TOKEN_KEY = "A-token-signing-key-rotated";
    assert.equal(
      await accessor.readSecret("BUNNY_780700_TOKEN_KEY"),
      "A-token-signing-key-0001",
    );
    // ...but never beyond it.
    nowMs += 501;
    assert.equal(
      await accessor.readSecret("BUNNY_780700_TOKEN_KEY"),
      "A-token-signing-key-rotated",
      "rotation takes effect once the positive TTL expires",
    );
    // A negative result is never cached: a newly created secret is visible
    // on the very next read.
    await assert.rejects(
      accessor.readSecret("BUNNY_781800_TOKEN_KEY_REMOVED"),
      (error) => error instanceof BunnySecretAccessError &&
        error.kind === "not_found",
    );
    env.BUNNY_781800_TOKEN_KEY_REMOVED = "now-present-secret-value";
    assert.equal(
      await accessor.readSecret("BUNNY_781800_TOKEN_KEY_REMOVED"),
      "now-present-secret-value",
      "negative results are not cached",
    );
    ok("positive cache is bounded and failures are never cached");
  }

  // --- 26. Production accessor path (mocked Secret Manager client) ---------
  {
    const calls = [];
    const accessor = createBunnySecretAccessor({
      isEmulator: false,
      env: {GCLOUD_PROJECT: "demo-project"},
      cacheTtlMs: 0,
      clientFactory: () => ({
        async accessSecretVersion(request) {
          calls.push(request.name);
          return [{payload: {data: Buffer.from("production-secret-value")}}];
        },
      }),
    });
    assert.equal(
      await accessor.readSecret("BUNNY_780700_TOKEN_KEY"),
      "production-secret-value",
    );
    assert.deepEqual(calls, [
      "projects/demo-project/secrets/BUNNY_780700_TOKEN_KEY/versions/latest",
    ]);
    ok("production accessor reads versions/latest through the official client");
  }

  // --- 27. Secret Manager error mapping -----------------------------------
  {
    for (const [code, expected] of [
      [7, "permission_denied"],
      [5, "not_found"],
      [14, "unavailable"],
    ]) {
      const accessor = createBunnySecretAccessor({
        isEmulator: false,
        env: {GCLOUD_PROJECT: "demo-project"},
        cacheTtlMs: 0,
        clientFactory: () => ({
          async accessSecretVersion() {
            const error = new Error("provider failure");
            error.code = code;
            throw error;
          },
        }),
      });
      await assert.rejects(
        accessor.readSecret("BUNNY_780700_TOKEN_KEY"),
        (error) => {
          assert.ok(error instanceof BunnySecretAccessError);
          assert.equal(error.kind, expected);
          assert.ok(
            !error.message.includes("BUNNY_780700_TOKEN_KEY"),
            "accessor error must not carry the secret name",
          );
          assert.ok(
            !error.message.includes("provider failure"),
            "accessor error must not carry the raw provider message",
          );
          return true;
        },
      );
    }
    ok("Secret Manager errors map to typed, redacted failures");
  }

  // --- 28. Client-visible reason mapping never reveals secret state --------
  {
    assert.equal(bunnyCredentialFailureReason("unknown_library"), "unknown_library");
    assert.equal(
      bunnyCredentialFailureReason("library_not_activated"),
      "library_not_activated",
    );
    for (const reason of [
      "secret_not_found",
      "secret_permission_denied",
      "secret_unavailable",
      "invalid_secret_value",
      "credential_name_mismatch",
      "invalid_catalog_entry",
      "catalog_unavailable",
      "incomplete_configuration",
    ]) {
      assert.equal(
        bunnyCredentialFailureReason(reason),
        "incomplete_configuration",
        `${reason} collapses for clients`,
      );
    }
    ok("secret-specific failures collapse to incomplete_configuration");
  }

  // --- 29. Resolved credentials never carry the other library's values -----
  {
    const deps = depsFor({documents: twoLibraries});
    const a = await resolveBunnyLibraryCredentials({
      libraryId: LIB_A,
      need: {streamApiKey: true, tokenKey: true},
      deps,
    });
    assert.equal(a.ok, true);
    assert.equal(a.credentials.libraryId, LIB_A);
    assert.equal(a.credentials.source, "catalog");
    assert.equal(a.credentials.streamApiKey, SECRETS.BUNNY_780700_STREAM_API_KEY);
    assert.equal(a.credentials.tokenKey, SECRETS.BUNNY_780700_TOKEN_KEY);
    assert.ok(!JSON.stringify(a).includes("0002"), "no B credential in A result");
    ok("resolved credential object is scoped to the requested library");
  }

  // =====================================================================
  // Mission 19 — default-library identity isolation (S-1 regression)
  //
  // Staging-like environment: the canonical default is 780700 while the
  // compiled Production default 736742 still exists in source. The compiled
  // default slot must never be served for an explicit foreign id, and no
  // failure may fall back to another library's credentials or template.
  // =====================================================================
  const STAGING_ENV = {
    BUNNY_DEFAULT_LIBRARY_ID: LIB_A,
    BUNNY_STREAM_LIBRARY_ID: LIB_A,
    BUNNY_ACTIVE_LIBRARY_IDS: "",
    BUNNY_PLAYBACK_URL_TEMPLATE:
      "https://staging-default.b-cdn.net/{video_id}/playlist.m3u8",
    BUNNY_TOKEN_KEY: "legacy-staging-token-key-0001",
    BUNNY_STREAM_API_KEY: "legacy-staging-stream-key-0001",
    BUNNY_780700_PLAYBACK_URL_TEMPLATE:
      "https://a.b-cdn.net/{video_id}/playlist.m3u8",
    BUNNY_781800_PLAYBACK_URL_TEMPLATE:
      "https://b.b-cdn.net/{video_id}/playlist.m3u8",
  };
  const STAGING_VALUES = {
    ...SECRETS,
    BUNNY_TOKEN_KEY: STAGING_ENV.BUNNY_TOKEN_KEY,
    BUNNY_STREAM_API_KEY: STAGING_ENV.BUNNY_STREAM_API_KEY,
  };
  const stagingLeakValues = [
    STAGING_ENV.BUNNY_TOKEN_KEY,
    STAGING_ENV.BUNNY_STREAM_API_KEY,
    ...Object.values(SECRETS),
  ];
  function assertNoLeak(payload, label) {
    const serialized = JSON.stringify(payload);
    for (const value of stagingLeakValues) {
      assert.ok(
        !serialized.includes(value),
        `${label}: leaked a secret VALUE`,
      );
    }
    for (const name of Object.keys(STAGING_VALUES)) {
      assert.ok(
        !serialized.includes(name),
        `${label}: leaked a secret NAME`,
      );
    }
    assert.ok(
      !serialized.includes("/secrets/"),
      `${label}: leaked a Secret Manager resource path`,
    );
  }

  // --- 30. Staging explicit 780700 (catalog-backed) uses its own identity --
  {
    const env = {...STAGING_ENV, BUNNY_ACTIVE_LIBRARY_IDS: LIB_A};
    const deps = depsFor({
      documents: {[LIB_A]: catalogDocument(LIB_A)},
      env,
    });
    const playback = await deps.resolvePlayback(LIB_A);
    assert.equal(playback.ok, true, "staging default playback resolves");
    assert.equal(playback.runtime.libraryId, LIB_A);
    assert.equal(playback.runtime.tokenKey, SECRETS.BUNNY_780700_TOKEN_KEY);
    assert.equal(
      playback.runtime.playbackUrlTemplate,
      STAGING_ENV.BUNNY_PLAYBACK_URL_TEMPLATE,
      "the canonical default keeps the environment's default template",
    );
    assert.deepEqual(
      deps.secrets.reads,
      ["BUNNY_780700_TOKEN_KEY"],
      "only the default library's own token key is read",
    );

    const stream = await deps.resolveStream(LIB_A);
    assert.equal(stream.ok, true, "staging default Stream config resolves");
    assert.equal(stream.runtime.libraryId, LIB_A);
    assert.equal(stream.runtime.apiLibraryId, LIB_A, "no API-path substitution");
    assert.equal(stream.runtime.apiKey, SECRETS.BUNNY_780700_STREAM_API_KEY);
    assert.deepEqual(deps.secrets.reads, [
      "BUNNY_780700_TOKEN_KEY",
      "BUNNY_780700_STREAM_API_KEY",
    ]);
    ok("staging explicit 780700 resolves only its own catalog identity");
  }

  // --- 31. Staging explicit 780700 (approved legacy path) is exact ---------
  {
    const deps = depsFor({documents: {}, env: STAGING_ENV});
    const playback = await deps.resolvePlayback(LIB_A);
    assert.equal(playback.ok, true);
    assert.equal(playback.runtime.libraryId, LIB_A);
    assert.equal(playback.runtime.tokenKey, STAGING_ENV.BUNNY_TOKEN_KEY);
    assert.equal(
      playback.runtime.playbackUrlTemplate,
      STAGING_ENV.BUNNY_PLAYBACK_URL_TEMPLATE,
    );
    const stream = await deps.resolveStream(LIB_A);
    assert.equal(stream.ok, true);
    assert.equal(stream.runtime.libraryId, LIB_A);
    assert.equal(stream.runtime.apiLibraryId, LIB_A);
    assert.equal(stream.runtime.apiKey, STAGING_ENV.BUNNY_STREAM_API_KEY);
    assert.deepEqual(
      deps.secrets.reads,
      [],
      "the approved legacy default path reads its own env values only",
    );
    ok("staging explicit 780700 legacy path keeps the exact default identity");
  }

  // --- 32. Staging explicit 736742 fails closed, even if allow-listed ------
  {
    for (const env of [
      STAGING_ENV,
      {...STAGING_ENV, BUNNY_ACTIVE_LIBRARY_IDS: LIB_DEFAULT},
    ]) {
      const deps = depsFor({documents: {}, env});
      const playback = await deps.resolvePlayback(LIB_DEFAULT);
      assert.equal(playback.ok, false);
      assert.equal(playback.reason, "unknown_library");
      assert.equal(playback.libraryId, LIB_DEFAULT);
      const stream = await deps.resolveStream(LIB_DEFAULT);
      assert.equal(stream.ok, false);
      assert.equal(stream.reason, "unknown_library");
      assert.deepEqual(deps.secrets.reads, [], "no secret read for 736742");
      assert.equal(
        registry.findBunnyLibraryDefinition(LIB_DEFAULT, env),
        null,
        "the compiled default slot is not a standalone library here",
      );
      assert.deepEqual(
        registry.resolveBunnyLibraryForResource(
          {storedLibraryId: LIB_DEFAULT},
          env,
        ),
        {ok: false, reason: "unknown_library", libraryId: LIB_DEFAULT},
      );
      assertNoLeak(playback, "736742 playback");
      assertNoLeak(stream, "736742 stream");
    }
    ok("staging explicit 736742 is rejected (allow-list cannot resurrect it)");
  }

  // --- 33. Staging explicit 775315 / 999999 stay rejected ------------------
  {
    const deps = depsFor({documents: {}, env: STAGING_ENV});
    const inactive = await deps.resolvePlayback(LIB_INACTIVE);
    assert.equal(inactive.ok, false);
    assert.equal(inactive.reason, "library_not_activated");
    const unknown = await deps.resolvePlayback("999999");
    assert.equal(unknown.ok, false);
    assert.equal(unknown.reason, "unknown_library");
    assert.deepEqual(deps.secrets.reads, []);

    // Allow-listing an uncatalogued non-default library still fails closed:
    // it can never borrow the configured default's credentials.
    const allowed = depsFor({
      documents: {},
      env: {...STAGING_ENV, BUNNY_ACTIVE_LIBRARY_IDS: LIB_INACTIVE},
    });
    const allowedInactive = await allowed.resolvePlayback(LIB_INACTIVE);
    assert.equal(allowedInactive.ok, false);
    assert.equal(allowedInactive.reason, "incomplete_configuration");
    assert.deepEqual(allowed.secrets.reads, []);
    assertNoLeak(inactive, "775315 playback");
    assertNoLeak(unknown, "999999 playback");
    assertNoLeak(allowedInactive, "allow-listed 775315 playback");
    ok("staging 775315 and 999999 stay rejected with no fallback");
  }

  // --- 34. Explicit incomplete/disabled id never falls back ---------------
  {
    const incompleteId = "781801";
    const disabledId = "781802";
    const env = {
      ...STAGING_ENV,
      BUNNY_ACTIVE_LIBRARY_IDS: `${incompleteId},${disabledId}`,
    };
    const incompleteDeps = depsFor({
      documents: {
        [incompleteId]: catalogDocument(incompleteId, {
          token_auth_verified: false,
        }),
      },
      env,
    });
    const incomplete = await incompleteDeps.resolvePlayback(incompleteId);
    assert.equal(incomplete.ok, false);
    assert.equal(incomplete.reason, "incomplete_configuration");

    const disabledDeps = depsFor({
      documents: {
        [disabledId]: catalogDocument(disabledId, {status: "disabled"}),
      },
      env,
    });
    const disabled = await disabledDeps.resolvePlayback(disabledId);
    assert.equal(disabled.ok, false);
    assert.equal(disabled.reason, "library_not_activated");

    assert.deepEqual(incompleteDeps.secrets.reads, []);
    assert.deepEqual(disabledDeps.secrets.reads, []);
    assertNoLeak(incomplete, "incomplete library");
    assertNoLeak(disabled, "disabled library");
    ok("explicit incomplete/disabled ids fail closed without default fallback");
  }

  // --- 35. No explicit id + valid configured default resolves exactly ------
  {
    const resolution = registry.resolveBunnyLibraryForResource(
      {storedLibraryId: null},
      STAGING_ENV,
    );
    assert.deepEqual(resolution, {
      ok: true,
      libraryId: LIB_A,
      source: "legacy_default",
    });
    const deps = depsFor({documents: {}, env: STAGING_ENV});
    const playback = await deps.resolvePlayback(resolution.libraryId);
    const stream = await deps.resolveStream(resolution.libraryId);
    assert.equal(playback.runtime.libraryId, LIB_A);
    assert.equal(playback.runtime.tokenKey, STAGING_ENV.BUNNY_TOKEN_KEY);
    assert.equal(stream.runtime.libraryId, LIB_A);
    assert.equal(stream.runtime.apiLibraryId, LIB_A);
    assert.equal(stream.runtime.apiKey, STAGING_ENV.BUNNY_STREAM_API_KEY);
    assert.deepEqual(deps.secrets.reads, []);
    ok("no explicit id resolves the exact configured default");
  }

  // --- 36. Configured default absent/ineligible from the catalog ----------
  {
    const noFallback = depsFor({
      documents: {},
      env: {...STAGING_ENV, BUNNY_LEGACY_LIBRARY_FALLBACK: "false"},
    });
    const absent = await noFallback.resolvePlayback(LIB_A);
    assert.equal(absent.ok, false);
    assert.equal(absent.reason, "incomplete_configuration");

    const disabled = depsFor({
      documents: {[LIB_A]: catalogDocument(LIB_A, {status: "disabled"})},
      env: STAGING_ENV,
    });
    const disabledResult = await disabled.resolvePlayback(LIB_A);
    assert.equal(disabledResult.ok, false);
    assert.equal(disabledResult.reason, "library_not_activated");

    const unverified = depsFor({
      documents: {
        [LIB_A]: catalogDocument(LIB_A, {token_auth_verified: false}),
      },
      env: STAGING_ENV,
    });
    const unverifiedResult = await unverified.resolvePlayback(LIB_A);
    assert.equal(unverifiedResult.ok, false);
    assert.equal(unverifiedResult.reason, "incomplete_configuration");

    assert.deepEqual(noFallback.secrets.reads, []);
    assert.deepEqual(disabled.secrets.reads, []);
    assert.deepEqual(unverified.secrets.reads, []);
    ok("configured default absent or ineligible from the catalog fails closed");
  }

  // --- 37. isDefault never makes a foreign id eligible --------------------
  {
    const compiledDefault = registry.BUNNY_LIBRARIES.find(
      (entry) => entry.isDefault,
    );
    assert.equal(compiledDefault.libraryId, LIB_DEFAULT);
    assert.equal(
      registry.isBunnyLibraryActive(compiledDefault, STAGING_ENV),
      false,
      "isDefault is not a permission grant for a foreign id",
    );
    const runtime = registry.resolveBunnyPlaybackRuntime(
      STAGING_ENV,
      LIB_DEFAULT,
      compiledDefault,
    );
    assert.equal(runtime.ok, false);
    assert.equal(runtime.reason, "library_not_activated");

    // The same definition IS active in the environment whose default it is.
    const productionEnv = {
      ...STAGING_ENV,
      BUNNY_DEFAULT_LIBRARY_ID: LIB_DEFAULT,
      BUNNY_STREAM_LIBRARY_ID: LIB_DEFAULT,
    };
    assert.equal(
      registry.isBunnyLibraryActive(compiledDefault, productionEnv),
      true,
    );
    ok("isDefault is scoped to the environment's own canonical default");
  }

  // --- 38. Legacy fallback never serves an explicit non-default id --------
  {
    const deps = depsFor({documents: {}, env: STAGING_ENV});
    const result = await deps.resolvePlayback(LIB_INACTIVE);
    assert.equal(result.ok, false);
    assert.equal(result.reason, "library_not_activated");
    assert.deepEqual(deps.secrets.reads, []);
    assert.deepEqual(
      registry.resolveBunnyLibraryForResource(
        {storedLibraryId: LIB_INACTIVE},
        STAGING_ENV,
      ),
      {ok: false, reason: "library_not_activated", libraryId: LIB_INACTIVE},
    );
    ok("legacy fallback never serves an explicit non-default id");
  }

  // --- 39. Library A and Library B never resolve each other's identity ----
  {
    const env = {
      ...STAGING_ENV,
      BUNNY_ACTIVE_LIBRARY_IDS: `${LIB_A},${LIB_B}`,
    };
    const documents = {
      [LIB_A]: catalogDocument(LIB_A),
      [LIB_B]: catalogDocument(LIB_B),
    };
    const aDeps = depsFor({documents, env});
    const aPlayback = await aDeps.resolvePlayback(LIB_A);
    const aStream = await aDeps.resolveStream(LIB_A);
    assert.equal(aPlayback.runtime.libraryId, LIB_A);
    assert.equal(aPlayback.runtime.tokenKey, SECRETS.BUNNY_780700_TOKEN_KEY);
    assert.equal(
      aPlayback.runtime.playbackUrlTemplate,
      STAGING_ENV.BUNNY_PLAYBACK_URL_TEMPLATE,
      "Library A is this environment's canonical default, so it keeps the default template",
    );
    assert.equal(aStream.runtime.libraryId, LIB_A);
    assert.equal(aStream.runtime.apiLibraryId, LIB_A);
    assert.equal(aStream.runtime.apiKey, SECRETS.BUNNY_780700_STREAM_API_KEY);
    assert.deepEqual(aDeps.secrets.reads, [
      "BUNNY_780700_TOKEN_KEY",
      "BUNNY_780700_STREAM_API_KEY",
    ]);

    const bDeps = depsFor({documents, env});
    const bPlayback = await bDeps.resolvePlayback(LIB_B);
    const bStream = await bDeps.resolveStream(LIB_B);
    assert.equal(bPlayback.runtime.libraryId, LIB_B);
    assert.equal(bPlayback.runtime.tokenKey, SECRETS.BUNNY_781800_TOKEN_KEY);
    assert.equal(
      bPlayback.runtime.playbackUrlTemplate,
      STAGING_ENV.BUNNY_781800_PLAYBACK_URL_TEMPLATE,
    );
    assert.equal(bStream.runtime.libraryId, LIB_B);
    assert.equal(bStream.runtime.apiLibraryId, LIB_B);
    assert.equal(bStream.runtime.apiKey, SECRETS.BUNNY_781800_STREAM_API_KEY);
    assert.deepEqual(bDeps.secrets.reads, [
      "BUNNY_781800_TOKEN_KEY",
      "BUNNY_781800_STREAM_API_KEY",
    ]);

    assert.notEqual(aPlayback.runtime.tokenKey, bPlayback.runtime.tokenKey);
    assert.notEqual(aStream.runtime.apiKey, bStream.runtime.apiKey);
    ok("library A and B never resolve each other's credentials or identity");
  }

  // --- 40. The exact Mission 18 probes now fail closed --------------------
  {
    const deps = depsFor({documents: {}, env: STAGING_ENV});
    const playbackProbe = await deps.resolvePlayback(LIB_DEFAULT);
    assert.deepEqual(playbackProbe, {
      ok: false,
      reason: "unknown_library",
      libraryId: LIB_DEFAULT,
    });
    const streamProbe = await deps.resolveStream(LIB_DEFAULT);
    assert.deepEqual(streamProbe, {
      ok: false,
      reason: "unknown_library",
      libraryId: LIB_DEFAULT,
    });
    assert.deepEqual(deps.secrets.reads, []);
    assert.deepEqual(
      registry.resolveBunnyLibraryForResource(
        {storedLibraryId: LIB_DEFAULT},
        STAGING_ENV,
      ),
      {ok: false, reason: "unknown_library", libraryId: LIB_DEFAULT},
    );
    assertNoLeak(playbackProbe, "Mission 18 playback probe");
    assertNoLeak(streamProbe, "Mission 18 stream probe");
    ok("Mission 18 probes for 736742 now fail closed");
  }

  console.log(`bunny_library_secret_resolver tests passed (${passed}).`);
  process.exit(0);
}

run().catch((error) => {
  console.error("FAIL", error);
  process.exitCode = 1;
});
