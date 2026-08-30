/**
 * Grants roles/run.invoker to allUsers on every CALLABLE function's Cloud
 * Run service (the standard Firebase callable posture: transport-public,
 * authorization enforced inside the function). Scheduled/event functions
 * stay locked down.
 */
const fs = require("node:fs");

let TOKEN = "";
if (process.env.GCP_TOKEN_PATH) {
  try {
    TOKEN = fs.readFileSync(process.env.GCP_TOKEN_PATH, "utf8").trim();
  } catch (err) {
    console.error(`Error reading GCP_TOKEN_PATH from "${process.env.GCP_TOKEN_PATH}":`, err.message);
    process.exit(1);
  }
} else {
  const path = require("node:path");
  const os = require("node:os");
  const home = os.homedir();
  const possiblePaths = [
    path.join(home, ".config/configstore/firebase-tools.json"),
    path.join(process.env.APPDATA || "", "configstore/firebase-tools.json"),
    path.join(process.env.LOCALAPPDATA || "", "configstore/firebase-tools.json"),
  ];
  let foundToken = false;
  for (const p of possiblePaths) {
    try {
      if (fs.existsSync(p)) {
        const config = JSON.parse(fs.readFileSync(p, "utf8"));
        if (config.tokens && config.tokens.access_token) {
          TOKEN = config.tokens.access_token;
          foundToken = true;
          break;
        }
      }
    } catch (_) {}
  }
  if (!foundToken) {
    console.error(`
Error: GCP_TOKEN_PATH environment variable is not set, and no active Firebase CLI token was found.

Please:
1. Run "firebase login" in your terminal to authenticate.
2. Or set the GCP_TOKEN_PATH environment variable to a file containing a valid Google Cloud/Firebase access token.
`);
    process.exit(1);
  }
}
const H = { Authorization: `Bearer ${TOKEN}`, "Content-Type": "application/json" };
const PROJECT = "dr-tarek-platform";
const REGION = "us-central1";

const SCHEDULED = new Set(["processNotificationQueue", "cleanupInvalidDeviceTokens"]);
const EVENT_ONLY = new Set([
  "onStudentApproved",
  "recalculateSubjectProgress",
  "enforceOneSubscriptionPerSubject",
  "sendPushNotification",
  "onPasswordResetRequest",
]);

async function asJson(res, tag) {
  const text = await res.text();
  try {
    return JSON.parse(text);
  } catch (_) {
    throw new Error(`${tag} -> HTTP ${res.status} non-JSON: ${text.slice(0, 160)}`);
  }
}

async function main() {
  const listRes = await fetch(
    `https://cloudfunctions.googleapis.com/v2/projects/${PROJECT}/locations/${REGION}/functions?pageSize=200`,
    { headers: H },
  );
  const list = await asJson(listRes, "functions:list");

  let granted = 0;
  let already = 0;
  let skipped = 0;

  for (const fn of list.functions ?? []) {
    const shortName = fn.name.split("/").pop();
    if (SCHEDULED.has(shortName) || EVENT_ONLY.has(shortName)) {
      skipped += 1;
      continue;
    }
    const service = fn.serviceConfig?.service;
    if (!service) {
      skipped += 1;
      continue;
    }

    const polRes = await fetch(`https://run.googleapis.com/v2/${service}:getIamPolicy`, {
      method: "GET", headers: H,
    });
    const pol = await asJson(polRes, `getIamPolicy ${shortName}`);

    const bindings = pol.bindings ?? [];
    const hasPublic = bindings.some(
      (b) => b.role === "roles/run.invoker" && (b.members ?? []).includes("allUsers"),
    );
    if (hasPublic) {
      already += 1;
      continue;
    }

    bindings.push({ role: "roles/run.invoker", members: ["allUsers"] });
    const setRes = await fetch(`https://run.googleapis.com/v2/${service}:setIamPolicy`, {
      method: "POST",
      headers: H,
      body: JSON.stringify({ policy: { bindings }, etag: pol.etag }),
    });
    if (setRes.ok) {
      granted += 1;
      process.stdout.write(`PUBLIC ${shortName}\n`);
    } else {
      const errText = await setRes.text();
      console.log(`FAIL ${shortName} :: ${errText.slice(0, 160)}`);
    }
  }

  console.log(`\ndone: newly-granted=${granted} already-public=${already} locked-down=${skipped}`);
}

main().catch((e) => {
  console.error("FATAL:", e.message);
  process.exit(1);
});
