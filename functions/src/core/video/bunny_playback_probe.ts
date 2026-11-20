/**
 * ADR-010 Amendment 3 — Bunny Stream playback probes (PURE).
 *
 * `verifyBunnyLibrary` proves a library's protection mode by listing one real
 * video with that library's own Stream key and requesting its HLS playlist:
 *
 * 1. `signed`   — a directory-token URL returns 2xx, so the pull zone enforces
 *                 CDN token authentication and this library's token key works.
 * 2. `unsigned` — the plain playlist returns 2xx, so the pull zone serves
 *                 unsigned playback (an external constraint for libraries an
 *                 older platform consumes).
 *
 * Contract:
 * - No Firestore, Secret Manager or `process.env` access.
 * - The HTTP transport is INJECTED (`deps.fetch`), so every unit test runs
 *   against a mock and the production callable passes nothing (the platform
 *   `fetch`). No test needs Bunny to be reachable.
 * - A probe result never contains a URL, a token, a key or a video id; only a
 *   boolean outcome and a typed reason.
 * - Every request carries the platform Referer: all pull zones in this account
 *   set `BlockNoneReferrer`, so a probe without it would measure the hotlink
 *   rule instead of token enforcement (Mission 24 finding).
 */

import {createHmac} from "node:crypto";
import {bunnyProbeFailureReasonForStatus} from "./bunny_library_lifecycle";

/** The Referer every client sends for Bunny CDN requests. */
export const BUNNY_PLAYBACK_REFERER = "https://dr-tarek-platform.web.app/";

/** Minimal response surface a probe needs. */
export interface BunnyProbeResponse {
  status: number;
  json: () => Promise<unknown>;
}

/** Minimal request surface a probe needs. */
export interface BunnyProbeInit {
  method: string;
  headers: Record<string, string>;
  signal: AbortSignal;
}

/** Injectable HTTP transport. */
export type BunnyProbeFetch = (
  url: string,
  init: BunnyProbeInit,
) => Promise<BunnyProbeResponse>;

/** Optional probe dependencies (tests inject both). */
export interface BunnyProbeDeps {
  fetch?: BunnyProbeFetch;
  /** Clock in ms; defaults to `Date.now`. */
  nowMs?: () => number;
  /** Per-request timeout in ms; defaults to 8000. */
  timeoutMs?: number;
}

export type BunnyProbeOutcome =
  | {ok: true; videoId: string}
  | {ok: false; reason: string};

export type BunnyProbeVerdict = {ok: true} | {ok: false; reason: string};

const PROBE_TIMEOUT_MS = 8000;

/**
 * Run one timed request through the (injected) transport.
 * @param {BunnyProbeFetch} transport HTTP transport.
 * @param {string} url Request URL.
 * @param {object} init Request method/headers.
 * @param {number} timeoutMs Abort timeout.
 * @return {Promise<BunnyProbeResponse>} The response.
 */
async function timedRequest(
  transport: BunnyProbeFetch,
  url: string,
  init: {method: string; headers: Record<string, string>},
  timeoutMs: number,
): Promise<BunnyProbeResponse> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await transport(url, {...init, signal: controller.signal});
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Ask the Stream API for one existing video id in a library.
 *
 * The id is only a probe target (the first listed video); it is never returned
 * to a client and never stored.
 * @param {object} input Library id and that library's Stream API key.
 * @param {BunnyProbeDeps} deps Injected transport/clock/timeout.
 * @return {Promise<object>} `{ok:true, videoId}` or `{ok:false, reason}`.
 */
export async function findBunnyProbeVideo(
  input: {libraryId: string; apiKey: string},
  deps: BunnyProbeDeps = {},
): Promise<BunnyProbeOutcome> {
  const transport: BunnyProbeFetch =
    deps.fetch ?? ((url, init) => fetch(url, init));
  try {
    const response = await timedRequest(
      transport,
      `https://video.bunnycdn.com/library/${encodeURIComponent(input.libraryId)}` +
        "/videos?page=1&itemsPerPage=1",
      {method: "GET", headers: {AccessKey: input.apiKey}},
      deps.timeoutMs ?? PROBE_TIMEOUT_MS,
    );
    const statusReason = bunnyProbeFailureReasonForStatus(response.status);
    if (statusReason !== null) return {ok: false, reason: statusReason};

    let body: unknown = null;
    try {
      body = await response.json();
    } catch {
      body = null;
    }
    const items = (body as {items?: unknown})?.items;
    const first = Array.isArray(items) ? items[0] : null;
    const videoId =
      typeof (first as {guid?: unknown})?.guid === "string" ?
        ((first as {guid: string}).guid).trim() :
        "";
    if (!/^[0-9a-fA-F-]{16,64}$/.test(videoId)) {
      return {ok: false, reason: "no_probe_target"};
    }
    return {ok: true, videoId};
  } catch {
    return {ok: false, reason: "probe_unreachable"};
  }
}

/**
 * Build the directory-token HLS URL for one video.
 * @param {string} playbackHost Pull-zone hostname.
 * @param {string} tokenKey That library's CDN token-signing key.
 * @param {string} videoId Probe video id.
 * @param {number} nowMs Current epoch ms.
 * @return {string} Signed playlist URL.
 */
export function buildBunnySignedProbeUrl(
  playbackHost: string,
  tokenKey: string,
  videoId: string,
  nowMs: number,
): string {
  const expires = Math.floor(nowMs / 1000) + 300;
  const scope = `/${videoId}/`;
  const signature = createHmac("sha256", tokenKey)
    .update(scope)
    .update(String(expires))
    .update(`token_path=${scope}`)
    .digest("base64url");
  return `https://${playbackHost}/bcdn_token=HS256-${signature}` +
    `&token_path=${encodeURIComponent(scope)}` +
    `&expires=${expires}${scope}playlist.m3u8`;
}

/**
 * Prove that a library ENFORCES token authentication.
 *
 * Lists one video in that library, signs a directory token for it and requests
 * the HLS playlist. A 2xx proves token authentication is genuinely enforced and
 * that this library's key can serve it. Never returns the URL or the key.
 * @param {object} input Library id, playback host and that library's own keys.
 * @param {BunnyProbeDeps} deps Injected transport/clock/timeout.
 * @return {Promise<object>} `{ok:true}` or `{ok:false, reason}`.
 */
export async function probeBunnyLibraryPlayback(
  input: {
    libraryId: string;
    playbackHost: string;
    tokenKey: string;
    apiKey: string;
  },
  deps: BunnyProbeDeps = {},
): Promise<BunnyProbeVerdict> {
  const transport: BunnyProbeFetch =
    deps.fetch ?? ((url, init) => fetch(url, init));
  const found = await findBunnyProbeVideo(
    {libraryId: input.libraryId, apiKey: input.apiKey},
    {...deps, fetch: transport},
  );
  if (!found.ok) return found;

  try {
    const url = buildBunnySignedProbeUrl(
      input.playbackHost,
      input.tokenKey,
      found.videoId,
      (deps.nowMs ?? Date.now)(),
    );
    const response = await timedRequest(
      transport,
      url,
      {method: "GET", headers: {Referer: BUNNY_PLAYBACK_REFERER}},
      deps.timeoutMs ?? PROBE_TIMEOUT_MS,
    );
    if (response.status >= 200 && response.status < 300) return {ok: true};
    return {ok: false, reason: "signed_url_probe_failed"};
  } catch {
    return {ok: false, reason: "probe_unreachable"};
  }
}

/**
 * Prove that a library does NOT enforce token authentication (Amendment 3).
 *
 * Requests the plain playlist of one real video with the client Referer. A 2xx
 * is the evidence that the pull zone serves unsigned playback; a 401/403 means
 * the zone IS protected (so the signed probe result stands).
 * @param {object} input Library id, playback host and that library's API key.
 * @param {BunnyProbeDeps} deps Injected transport/clock/timeout.
 * @return {Promise<object>} `{ok:true}` or `{ok:false, reason}`.
 */
export async function probeBunnyLibraryUnsignedPlayback(
  input: {libraryId: string; playbackHost: string; apiKey: string},
  deps: BunnyProbeDeps = {},
): Promise<BunnyProbeVerdict> {
  const transport: BunnyProbeFetch =
    deps.fetch ?? ((url, init) => fetch(url, init));
  const found = await findBunnyProbeVideo(
    {libraryId: input.libraryId, apiKey: input.apiKey},
    {...deps, fetch: transport},
  );
  if (!found.ok) return found;

  try {
    const url = `https://${input.playbackHost}/${found.videoId}/playlist.m3u8`;
    const response = await timedRequest(
      transport,
      url,
      {method: "GET", headers: {Referer: BUNNY_PLAYBACK_REFERER}},
      deps.timeoutMs ?? PROBE_TIMEOUT_MS,
    );
    if (response.status >= 200 && response.status < 300) return {ok: true};
    if (response.status === 401 || response.status === 403) {
      return {ok: false, reason: "token_auth_enforced"};
    }
    return {ok: false, reason: "unsigned_url_probe_failed"};
  } catch {
    return {ok: false, reason: "probe_unreachable"};
  }
}
