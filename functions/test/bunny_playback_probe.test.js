/**
 * ADR-010 Amendment 3 — Bunny verification probes, unit-tested with a MOCK
 * transport.
 *
 * Nothing here touches the network: every request goes through the injected
 * `fetch` returned by `mockTransport()`. The suite proves the request shape
 * (URL, AccessKey header, platform Referer, directory-token signature), the
 * typed failure mapping, and that no credential, URL or video id can leak
 * through a probe result.
 */
const assert = require("node:assert/strict");
const {createHmac} = require("node:crypto");
const path = require("node:path");

const probe = require(path.join(
  __dirname,
  "..",
  "lib",
  "core",
  "video",
  "bunny_playback_probe.js",
));

const {
  BUNNY_PLAYBACK_REFERER,
  buildBunnySignedProbeUrl,
  findBunnyProbeVideo,
  probeBunnyLibraryPlayback,
  probeBunnyLibraryUnsignedPlayback,
} = probe;

const LIBRARY = "776525";
const HOST = "vz-a9e3d4cc-384.b-cdn.net";
const GUID = "7ddd0e6e-a0ae-43f6-a11c-ff7ca5db1c31";
const API_KEY = "fixture-stream-key";
const TOKEN_KEY = "fixture-token-key";
const FIXED_NOW = 1_700_000_000_000;

let passed = 0;
function ok(name, condition) {
  assert.ok(condition, name);
  passed += 1;
  console.log(`ok - ${name}`);
}

/**
 * Build a transport that replays canned responses and records every call.
 * @param {Array} responses statuses/bodies/errors to replay.
 * @return {Function} transport with a `calls` array.
 */
function mockTransport(responses) {
  const queue = responses.slice();
  const transport = async (url, init) => {
    transport.calls.push({url, init});
    if (queue.length === 0) throw new Error("unexpected extra request");
    const next = queue.shift();
    if (next instanceof Error) throw next;
    return {status: next.status, json: async () => next.body ?? {}};
  };
  transport.calls = [];
  return transport;
}

const listOk = {status: 200, body: {items: [{guid: GUID}]}};

async function run() {
  // --- signed mode: request shape and success ---------------------------
  {
    const transport = mockTransport([listOk, {status: 200}]);
    const result = await probeBunnyLibraryPlayback(
      {libraryId: LIBRARY, playbackHost: HOST, tokenKey: TOKEN_KEY, apiKey: API_KEY},
      {fetch: transport, nowMs: () => FIXED_NOW},
    );
    ok("signed probe succeeds on 2xx", result.ok === true);
    ok("signed probe makes exactly two requests (list + playlist)", transport.calls.length === 2);

    const [list, playlist] = transport.calls;
    ok(
      "signed probe lists videos with that library's own key",
      list.url ===
        "https://video.bunnycdn.com/library/776525/videos?page=1&itemsPerPage=1" &&
        list.init.headers.AccessKey === API_KEY &&
        list.init.method === "GET",
    );
    ok(
      "signed probe sends the platform Referer (never a bare request)",
      playlist.init.headers.Referer === BUNNY_PLAYBACK_REFERER,
    );
    ok(
      "signed probe requests the HLS playlist on the library's playback host",
      playlist.url.startsWith(`https://${HOST}/`) && playlist.url.endsWith(`/${GUID}/playlist.m3u8`),
    );
    ok(
      "signed probe URL matches the documented directory-token builder",
      playlist.url === buildBunnySignedProbeUrl(HOST, TOKEN_KEY, GUID, FIXED_NOW),
    );

    // Independently recompute the HMAC: the URL must carry a genuine signature
    // for this exact video scope and expiry, not a placeholder.
    const expires = Math.floor(FIXED_NOW / 1000) + 300;
    const scope = `/${GUID}/`;
    const expected = createHmac("sha256", TOKEN_KEY)
      .update(scope)
      .update(String(expires))
      .update(`token_path=${scope}`)
      .digest("base64url");
    ok("signed probe carries a valid HS256 directory token", playlist.url.includes(`bcdn_token=HS256-${expected}`));
    ok("signed probe carries the token expiry", playlist.url.includes(`&expires=${expires}`));
    ok("signed probe result carries no key, URL or video id", !JSON.stringify(result).includes("bcdn_token") && !JSON.stringify(result).includes(TOKEN_KEY) && !JSON.stringify(result).includes(GUID));
  }

  // --- signed mode: typed failures --------------------------------------
  {
    const transport = mockTransport([listOk, {status: 403}]);
    const result = await probeBunnyLibraryPlayback(
      {libraryId: LIBRARY, playbackHost: HOST, tokenKey: TOKEN_KEY, apiKey: API_KEY},
      {fetch: transport, nowMs: () => FIXED_NOW},
    );
    ok("signed probe reports a failed signature as signed_url_probe_failed", result.reason === "signed_url_probe_failed");
  }

  // --- list failures are mapped, never thrown ---------------------------
  for (const [status, reason] of [
    [404, "library_not_found"],
    [401, "credential_rejected"],
    [403, "credential_rejected"],
    [500, "video_list_unavailable"],
  ]) {
    const transport = mockTransport([{status}]);
    const result = await findBunnyProbeVideo(
      {libraryId: LIBRARY, apiKey: API_KEY},
      {fetch: transport},
    );
    ok(`list ${status} maps to ${reason}`, result.ok === false && result.reason === reason);
  }

  {
    const transport = mockTransport([{status: 200, body: {items: []}}]);
    const result = await findBunnyProbeVideo(
      {libraryId: LIBRARY, apiKey: API_KEY},
      {fetch: transport},
    );
    ok("an empty video list is no_probe_target, not a mode", result.reason === "no_probe_target");
  }
  {
    const transport = mockTransport([{status: 200, body: {items: [{guid: "not-a-guid"}]}}]);
    const result = await findBunnyProbeVideo(
      {libraryId: LIBRARY, apiKey: API_KEY},
      {fetch: transport},
    );
    ok("a malformed video id is rejected before any playlist request", result.reason === "no_probe_target" && transport.calls.length === 1);
  }
  {
    const transport = mockTransport([new Error("socket hang up")]);
    const result = await findBunnyProbeVideo(
      {libraryId: LIBRARY, apiKey: API_KEY},
      {fetch: transport},
    );
    ok("a transport error is probe_unreachable", result.reason === "probe_unreachable");
  }

  // --- unsigned mode ----------------------------------------------------
  {
    const transport = mockTransport([listOk, {status: 200}]);
    const result = await probeBunnyLibraryUnsignedPlayback(
      {libraryId: LIBRARY, playbackHost: HOST, apiKey: API_KEY},
      {fetch: transport},
    );
    ok("unsigned probe succeeds on 2xx", result.ok === true);
    const playlist = transport.calls[1];
    ok(
      "unsigned probe requests the plain playlist (no token)",
      playlist.url === `https://${HOST}/${GUID}/playlist.m3u8` &&
        !playlist.url.includes("bcdn_token"),
    );
    ok(
      "unsigned probe still sends the platform Referer",
      playlist.init.headers.Referer === BUNNY_PLAYBACK_REFERER,
    );
  }
  {
    const transport = mockTransport([listOk, {status: 403}]);
    const result = await probeBunnyLibraryUnsignedPlayback(
      {libraryId: LIBRARY, playbackHost: HOST, apiKey: API_KEY},
      {fetch: transport},
    );
    ok("a protected zone reports token_auth_enforced, not success", result.reason === "token_auth_enforced");
  }
  {
    const transport = mockTransport([listOk, {status: 404}]);
    const result = await probeBunnyLibraryUnsignedPlayback(
      {libraryId: LIBRARY, playbackHost: HOST, apiKey: API_KEY},
      {fetch: transport},
    );
    ok("an unexpected unsigned status is unsigned_url_probe_failed", result.reason === "unsigned_url_probe_failed");
  }
  {
    const transport = mockTransport([listOk, new Error("timeout")]);
    const result = await probeBunnyLibraryUnsignedPlayback(
      {libraryId: LIBRARY, playbackHost: HOST, apiKey: API_KEY},
      {fetch: transport},
    );
    ok("an unsigned transport error is probe_unreachable", result.reason === "probe_unreachable");
  }

  // --- default transport is the process fetch (so callables need no wiring)
  {
    const realFetch = global.fetch;
    const transport = mockTransport([listOk, {status: 200}]);
    global.fetch = transport;
    try {
      const result = await probeBunnyLibraryUnsignedPlayback({
        libraryId: LIBRARY,
        playbackHost: HOST,
        apiKey: API_KEY,
      });
      ok("the probe uses the injected process fetch when no transport is passed", result.ok === true && transport.calls.length === 2);
    } finally {
      global.fetch = realFetch;
    }
  }

  console.log(`bunny_playback_probe tests passed (${passed}).`);
  process.exit(0);
}

run().catch((error) => {
  console.error("FAIL", error);
  process.exit(1);
});
