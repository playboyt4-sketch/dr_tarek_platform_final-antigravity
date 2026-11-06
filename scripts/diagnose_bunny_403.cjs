/**
 * diagnose_bunny_403.cjs — safe, read-only 403 classification.
 *
 * Reports only HTTP status codes, boolean keyword matches, and a whitelist of
 * response headers. Never prints the URL, token, signing key, API key, or
 * response body.
 *
 * Usage:
 *   set BUNNY_TOKEN_KEY / BUNNY_PLAYBACK_URL_TEMPLATE (or load them first)
 *   node scripts\diagnose_bunny_403.cjs --video-id <guid>
 */
"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

function argValue(flag) {
  const index = process.argv.indexOf(flag);
  return index >= 0 ? String(process.argv[index + 1] ?? "").trim() : "";
}

function requireEnv(name) {
  const value = String(process.env[name] ?? "").trim();
  if (!value) {
    console.error(`ERROR: ${name} is not set.`);
    process.exit(1);
  }
  return value;
}

function hashVideoDirectoryToken(secret, directoryScope, expires) {
  const signingData = `token_path=${directoryScope}`;
  const signature = crypto
    .createHmac("sha256", secret)
    .update(directoryScope)
    .update(String(expires))
    .update(signingData)
    .digest("base64url");
  return `HS256-${signature}`;
}

function buildUrls(template, secret, videoId, pathSuffix) {
  const expanded = template
    .replaceAll("{video_id}", encodeURIComponent(videoId))
    .replaceAll("{videoId}", encodeURIComponent(videoId))
    .replaceAll("{id}", encodeURIComponent(videoId))
    .replaceAll("{quality}", "720p")
    .replaceAll("{res}", "720p");
  const base = new URL(expanded);
  const unsigned = new URL(base.origin + pathSuffix);
  const expires = Math.floor(Date.now() / 1000) + 300;
  const scope = `/${videoId}/`;
  const token = hashVideoDirectoryToken(secret, scope, expires);
  const signed = new URL(
    `${base.origin}/bcdn_token=${token}&token_path=${encodeURIComponent(scope)}&expires=${expires}${pathSuffix}`,
  );
  return {unsigned, signed, host: base.hostname};
}

const HEADER_ALLOWLIST = new Set([
  "server",
  "content-type",
  "cache-control",
  "x-cache",
  "cache-status",
  "x-cdn",
  "x-cdn-provider",
  "x-bunnycdn-request-id",
]);

const KEYWORDS = [
  "hotlink",
  "referer",
  "referrer",
  "token",
  "signature",
  "expired",
  "geo",
  "country",
  "blocked",
  "forbidden",
  "denied",
  "not found",
  "access denied",
];

async function probe(url, headers) {
  let response;
  try {
    response = await fetch(url, {redirect: "follow", headers});
  } catch (error) {
    return {status: "network-error", error: error?.name ?? "unknown"};
  }
  const text = await response.text().catch(() => "");
  const lower = text.toLowerCase();
  const headerSnapshot = {};
  for (const [name, value] of response.headers.entries()) {
    if (HEADER_ALLOWLIST.has(name.toLowerCase())) headerSnapshot[name.toLowerCase()] = value;
  }
  return {
    status: response.status,
    contentType: (response.headers.get("content-type") ?? "").split(";")[0],
    headers: headerSnapshot,
    keywords: KEYWORDS.filter((word) => lower.includes(word)),
    bodyLength: text.length,
  };
}

function describe(name, result) {
  const parts = [`status=${result.status}`];
  if (result.contentType) parts.push(`type=${result.contentType}`);
  if (result.bodyLength !== undefined) parts.push(`body=${result.bodyLength}b`);
  if (result.keywords && result.keywords.length > 0) parts.push(`keywords=[${result.keywords.join(",")}]`);
  if (result.headers && Object.keys(result.headers).length > 0) {
    parts.push(`headers={${Object.entries(result.headers).map(([k, v]) => `${k}:${v}`).join(" ")}}`);
  }
  if (result.error) parts.push(`error=${result.error}`);
  console.log(`  ${name}: ${parts.join(" ")}`);
}

async function streamVideoStatus(videoId) {
  const envText = fs.readFileSync(path.join(__dirname, "..", "functions", ".env"), "utf8");
  const env = {};
  for (const line of envText.split(/\r?\n/)) {
    const match = line.match(/^\s*([A-Za-z0-9_]+)\s*=\s*(.*)$/);
    if (match) env[match[1]] = match[2].trim();
  }
  const apiKey = env.BUNNY_STREAM_API_KEY;
  const libraryId = env.BUNNY_STREAM_LIBRARY_ID;
  if (!apiKey || !libraryId) {
    console.log("stream api: not configured locally (cannot check encoding state)");
    return;
  }
  const response = await fetch(
    `https://video.bunnycdn.com/library/${encodeURIComponent(libraryId)}/videos/${encodeURIComponent(videoId)}`,
    {headers: {AccessKey: apiKey, accept: "application/json"}},
  );
  if (!response.ok) {
    console.log(`stream api: video lookup status=${response.status}`);
    return;
  }
  const data = await response.json();
  console.log("stream api: video exists");
  for (const key of [
    "status",
    "encodeProgress",
    "length",
    "storageSize",
    "availableResolutions",
    "hasMP4Fallback",
    "isPlayable",
    "transcodingStatus",
  ]) {
    if (data[key] !== undefined) console.log(`  ${key}: ${JSON.stringify(data[key])}`);
  }
}

async function main() {
  const videoId = argValue("--video-id");
  if (!videoId) {
    console.error("ERROR: --video-id <guid> is required.");
    process.exit(1);
  }
  const template = requireEnv("BUNNY_PLAYBACK_URL_TEMPLATE");
  const secret = requireEnv("BUNNY_TOKEN_KEY");

  console.log("=== Bunny 403 classification ===");
  await streamVideoStatus(videoId);

  const master = buildUrls(template, secret, videoId, `/${videoId}/playlist.m3u8`);
  console.log(`host classification: b-cdn=${/\.b-cdn\.net$/i.test(master.host)} management=${/video\.bunnycdn\.com$/i.test(master.host)}`);

  console.log("master playlist probes:");
  describe("unsigned/no headers", await probe(master.unsigned, {}));
  describe("unsigned/web referer", await probe(master.unsigned, {"Referer": "https://dr-tarek-platform.web.app/"}));
  describe("unsigned/firebaseapp referer", await probe(master.unsigned, {"Referer": "https://dr-tarek-platform.firebaseapp.com/"}));
  describe("unsigned/origin", await probe(master.unsigned, {"Origin": "https://dr-tarek-platform.web.app"}));
  describe("unsigned/native UA", await probe(master.unsigned, {"User-Agent": "AppleCoreMedia/1.0.0 (iPhone; U; CPU OS 18_5 like Mac OS X)"}));
  describe("signed/no headers", await probe(master.signed, {}));
  describe("signed/web referer", await probe(master.signed, {"Referer": "https://dr-tarek-platform.web.app/"}));

  const missing = buildUrls(template, secret, videoId, `/${videoId}/definitely-not-a-file-12345`);
  console.log("nonexistent-path probes (zone-wide vs path-specific):");
  describe("unsigned/missing", await probe(missing.unsigned, {}));
  describe("signed/missing", await probe(missing.signed, {}));

  const root = buildUrls(template, secret, videoId, "/");
  console.log("zone-root probe:");
  describe("unsigned/root", await probe(root.unsigned, {}));
}

main().catch((error) => {
  console.error(`ERROR: ${error?.name ?? "failed"}: ${error?.message ?? ""}`.trim());
  process.exitCode = 1;
});
