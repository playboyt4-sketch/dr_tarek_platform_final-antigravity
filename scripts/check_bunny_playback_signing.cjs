/**
 * Safe Bunny Stream playback diagnostic (status codes only).
 *
 * Reproduces exactly the URL `generateBunnySignedUrl` issues for a video
 * (Bunny Advanced/HMAC directory token, path-embedded) and reports the CDN
 * response status. It never prints the URL, token, key, template host, or
 * response body — only HTTP status codes and a short classification, so it
 * is safe to paste into an issue or chat.
 *
 * Why: a student-facing `403 Forbidden` can come from a wrong signing key,
 * Basic/query token mode instead of Advanced/path, a hotlink/referer/geo
 * rule, or a template that points at the Stream management host instead of
 * the pull zone. This script separates those cases without touching data.
 *
 * Usage:
 *   $env:BUNNY_TOKEN_KEY = '<library token authentication key>'
 *   $env:BUNNY_PLAYBACK_URL_TEMPLATE = 'https://<pull-zone>.b-cdn.net/{video_id}/playlist.m3u8'
 *   node scripts\check_bunny_playback_signing.cjs --video-id <bunny-video-guid>
 *
 * Read-only: performs two GET requests (signed + unsigned) against the CDN.
 * The signing construction below MUST stay identical to
 * `hashVideoDirectoryToken` in functions/src/index.ts.
 */
const crypto = require("crypto");

const MANAGEMENT_HOST_PATTERN = /(^|\.)video\.bunnycdn\.com$/i;

function getEnv(name) {
  const value = (process.env[name] ?? "").trim();
  if (!value) {
    console.error(`ERROR: ${name} is not set.`);
    process.exit(1);
  }
  return value;
}

function parseArgs(argv) {
  const out = {videoId: null};
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === "--video-id") {
      out.videoId = (argv[i + 1] ?? "").trim();
      i += 1;
    }
  }
  return out;
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

function buildSignedUrl(template, secret, videoId, expiresInSeconds) {
  const expanded = template
    .replaceAll("{video_id}", encodeURIComponent(videoId))
    .replaceAll("{videoId}", encodeURIComponent(videoId))
    .replaceAll("{id}", encodeURIComponent(videoId))
    .replaceAll("{quality}", encodeURIComponent("720p"))
    .replaceAll("{res}", encodeURIComponent("720p"));
  if (expanded.includes("{") && expanded.includes("}")) {
    throw new Error(
      "BUNNY_PLAYBACK_URL_TEMPLATE has unresolved placeholders; expected " +
        "e.g. https://<pull-zone>.b-cdn.net/{video_id}/playlist.m3u8",
    );
  }
  const url = new URL(expanded);
  const expires = Math.floor(Date.now() / 1000) + expiresInSeconds;
  const directoryScope = `/${videoId}/`;
  const token = hashVideoDirectoryToken(secret, directoryScope, expires);
  return {
    url: new URL(
      `${url.origin}/bcdn_token=${token}` +
        `&token_path=${encodeURIComponent(directoryScope)}` +
        `&expires=${expires}${url.pathname}`,
    ),
    original: url,
  };
}

async function probe(url) {
  const response = await fetch(url, {redirect: "follow"});
  // Drain without inspecting or printing the body.
  await response.arrayBuffer().catch(() => null);
  return {
    status: response.status,
    contentType: (response.headers.get("content-type") ?? "").split(";")[0],
  };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args.videoId) {
    console.error("ERROR: --video-id <bunny-video-guid> is required.");
    process.exit(1);
  }
  const template = getEnv("BUNNY_PLAYBACK_URL_TEMPLATE");
  const secret = getEnv("BUNNY_TOKEN_KEY");

  let built;
  try {
    built = buildSignedUrl(template, secret, args.videoId, 300);
  } catch (error) {
    console.error(`ERROR: ${error.message}`);
    process.exit(1);
  }

  const host = built.original.hostname;
  console.log("=== Bunny playback signing check ===");
  console.log(`template host is management host: ${MANAGEMENT_HOST_PATTERN.test(host) ? "YES (WRONG)" : "no"}`);
  if (MANAGEMENT_HOST_PATTERN.test(host)) {
    console.log(
      "Hint: BUNNY_PLAYBACK_URL_TEMPLATE must be the pull-zone direct-play " +
        "URL, not https://video.bunnycdn.com/play/...",
    );
  }

  const [signed, unsigned] = await Promise.all([
    probe(built.url),
    probe(built.original),
  ]);

  console.log(`signed URL status: ${signed.status}${signed.contentType ? ` (${signed.contentType})` : ""}`);
  console.log(`unsigned URL status: ${unsigned.status}${unsigned.contentType ? ` (${unsigned.contentType})` : ""}`);

  console.log("=== interpretation ===");
  if (signed.status === 200 || signed.status === 206) {
    console.log("OK - signing and template are valid for this video.");
    if (unsigned.status === 200 || unsigned.status === 206) {
      console.log(
        "WARNING - the unsigned URL also succeeds: token authentication is " +
          "not enforcing on this path/pull zone.",
      );
    }
  } else if (signed.status === 403) {
    if (unsigned.status === 403) {
      console.log(
        "Both signed and unsigned URLs return 403. Likely causes: token key " +
          "does not match the pull zone, token mode is Basic/query instead of " +
          "Advanced (HMAC) path mode, token auth is enabled on the wrong pull " +
          "zone/directory, or a hotlink/referer/geo rule blocks the request.",
      );
    } else {
      console.log(
        "Signed URL is rejected while the unsigned URL is not: the token " +
          "construction/key does not match the pull-zone configuration " +
          "(key source, HMAC mode, or signature scope).",
      );
    }
  } else if (signed.status === 404) {
    console.log(
      "404 - token is accepted but the path is wrong. Confirm the template is " +
        "https://<pull-zone>.b-cdn.net/{video_id}/playlist.m3u8 (canonical HLS " +
        "master) and that the video finished encoding in this library.",
    );
  } else if (signed.status === 401) {
    console.log(
      "401 - the pull zone expects a different authentication scheme or the " +
        "token is malformed/expired.",
    );
  } else {
    console.log(
      `Unexpected status ${signed.status}. Check Bunny pull-zone status, DNS, ` +
        "and whether the hostname belongs to the Stream pull zone.",
    );
  }

  // A usable signed URL must succeed. Keep the process exit code simple for CI.
  if (![200, 206].includes(signed.status)) process.exitCode = 1;
}

main().catch((error) => {
  // Never include URL/token values in the failure output.
  console.error(`ERROR: ${error?.name ?? "request failed"}: ${error?.message ?? ""}`.trim());
  process.exitCode = 1;
});
