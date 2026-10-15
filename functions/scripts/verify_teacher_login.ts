// @ts-nocheck
/**
 * End-to-end login verification for the dashboard teacher account.
 *
 * Mirrors exactly what the dashboard does:
 *   1. Exchange an App Check debug token for an App Check token
 *      (stands in for the browser-minted reCAPTCHA Enterprise token).
 *   2. Call the deployed `verifyPhonePassword` callable with the
 *      X-Firebase-AppCheck header.
 *   3. Exchange the returned custom token via Identity Toolkit
 *      (same as `signInWithCustomToken` in the app).
 *
 * The debug-token secret is NEVER stored in the repo. Provide it via:
 *   APPCHECK_DEBUG_TOKEN=<uuid4> npx ts-node scripts/verify_teacher_login.ts
 *
 * Usage:
 *   npx ts-node scripts/verify_teacher_login.ts [phone] [password]
 * Defaults: phone=01115800180 password=12345678
 *
 * QUARANTINE NOTE (post ADR-005 Doctor migration) — documentation only, no
 * behavior change. This script is READ-ONLY (writes nothing) and needs no
 * safety fix, but its name/defaults predate the migration: post-migration
 * the owner signs in with role "doctor", and a "teacher" claim (if ever seen
 * here) is inert by design. Updating defaults or renaming requires an owner
 * decision.
 */
import * as https from "node:https";

const PROJECT_ID = "dr-tarek-platform";
const WEB_APP_ID = "1:606744934510:web:b809f2ed62c9c9ffc54e7f";
const WEB_API_KEY =
  process.env.DASHBOARD_WEB_API_KEY ?? "AIzaSyCCZFmVdGUd3n7hRX8vWpvWlp_t4TcUNj0";
const CALLABLE_URL = `https://us-central1-${PROJECT_ID}.cloudfunctions.net/verifyPhonePassword`;
const EXPECTED_UID = "2B1pvLZ0p5W3hwoXlBi1rUtp0Iy2";

function postJson(
  url: string,
  body: unknown,
  headers: Record<string, string> = {},
): Promise<{ status: number; json: any }> {
  const payload = JSON.stringify(body);
  const parsed = new URL(url);
  return new Promise((resolve, reject) => {
    const req = https.request(
      {
        hostname: parsed.hostname,
        path: parsed.pathname + parsed.search,
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Content-Length": Buffer.byteLength(payload),
          ...headers,
        },
      },
      (res) => {
        let data = "";
        res.on("data", (chunk) => (data += chunk));
        res.on("end", () => {
          try {
            resolve({status: res.statusCode ?? 0, json: JSON.parse(data)});
          } catch {
            resolve({status: res.statusCode ?? 0, json: {raw: data}});
          }
        });
      },
    );
    req.on("error", reject);
    req.write(payload);
    req.end();
  });
}

export async function verifyTeacherLogin(
  phone = "01115800180",
  password = "12345678",
): Promise<void> {
  const debugSecret = process.env.APPCHECK_DEBUG_TOKEN;
  if (!debugSecret) {
    throw new Error(
      "APPCHECK_DEBUG_TOKEN env var is required (Firebase console > App Check > Apps > three dots > Manage debug tokens).",
    );
  }

  // 1. Mint an App Check token from the debug secret.
  console.log("[1/3] Exchanging App Check debug token...");
  const appCheckRes = await postJson(
    `https://firebaseappcheck.googleapis.com/v1/projects/${PROJECT_ID}/apps/${encodeURIComponent(WEB_APP_ID)}:exchangeDebugToken?key=${WEB_API_KEY}`,
    {debug_token: debugSecret},
  );
  if (appCheckRes.status !== 200 || !appCheckRes.json.token) {
    throw new Error(
      `App Check exchange failed (HTTP ${appCheckRes.status}): ${JSON.stringify(appCheckRes.json).slice(0, 300)}`,
    );
  }
  const appCheckToken = appCheckRes.json.token as string;
  console.log("      App Check token minted.");

  // 2. Call verifyPhonePassword exactly like the dashboard datasource does.
  console.log("[2/3] Calling verifyPhonePassword callable...");
  const callableRes = await postJson(
    CALLABLE_URL,
    {data: {phoneNumber: phone, password}},
    {"X-Firebase-AppCheck": appCheckToken},
  );
  const result = callableRes.json?.result;
  if (callableRes.status !== 200 || !result?.token || !result?.userId) {
    throw new Error(
      `verifyPhonePassword failed (HTTP ${callableRes.status}): ${JSON.stringify(callableRes.json).slice(0, 300)}`,
    );
  }
  console.log(`      Callable OK. userId=${result.userId}`);
  if (result.userId !== EXPECTED_UID) {
    throw new Error(`Unexpected userId ${result.userId} (expected ${EXPECTED_UID}).`);
  }

  // 3. Exchange the custom token (what signInWithCustomToken does).
  // Note: VerifyCustomToken returns {idToken, refreshToken, ...} with no
  // localId field, so the uid/role are asserted from the JWT payload.
  console.log("[3/3] Exchanging custom token (sign-in proof)...");
  const signInRes = await postJson(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${WEB_API_KEY}`,
    {token: result.token, returnSecureToken: true},
  );
  if (!signInRes.json.idToken) {
    throw new Error(
      `Custom-token sign-in failed: ${JSON.stringify(signInRes.json).slice(0, 300)}`,
    );
  }
  const payload = JSON.parse(
    Buffer.from(
      String(signInRes.json.idToken).split(".")[1].replace(/-/g, "+").replace(/_/g, "/"),
      "base64",
    ).toString("utf8"),
  );
  if (payload.user_id !== EXPECTED_UID) {
    throw new Error(`Signed in as unexpected uid ${payload.user_id}.`);
  }
  console.log(
    `      Signed in as user_id=${payload.user_id} role=${payload.role} approved=${payload.approved}.`,
  );

  console.log(`PASS: login works for ${phone} (uid ${EXPECTED_UID}).`);
}

if (require.main === module) {
  verifyTeacherLogin(process.argv[2], process.argv[3])
    .then(() => process.exit(0))
    .catch((err) => {
      console.error(`FAIL: ${err instanceof Error ? err.message : err}`);
      process.exit(1);
    });
}
