/**
 * ADR-010 Mission 21 — `APP_CHECK_ENFORCEMENT` must never fail open silently.
 *
 * Production carried a 97-character flattened `.env` blob in that variable, so
 * `=== "true"` evaluated to `false` and App Check was off on every callable.
 * These checks lock the parsing contract and the detection of a malformed
 * value. Pure module — no emulator, no network, no secret values.
 */
const assert = require("node:assert/strict");

const helpers = require("../lib/core/utils/security_helpers.js");

let passed = 0;
function check(name, actual, expected) {
  assert.deepEqual(actual, expected, name);
  passed++;
  console.log(`ok - ${name}`);
}

const {
  APP_CHECK_ENFORCEMENT_VAR,
  describeAppCheckEnforcement,
} = helpers;

check("variable name is unchanged", APP_CHECK_ENFORCEMENT_VAR, "APP_CHECK_ENFORCEMENT");

// --- the two valid literals ---
check(
  "exactly true enables enforcement",
  describeAppCheckEnforcement("true"),
  {enabled: true, malformed: false, mode: "enforced"},
);
check(
  "exactly false disables enforcement cleanly",
  describeAppCheckEnforcement("false"),
  {enabled: false, malformed: false, mode: "disabled"},
);

// --- absent / empty are a deliberate disable, not a corruption ---
check(
  "absent variable is disabled, not malformed",
  describeAppCheckEnforcement(undefined),
  {enabled: false, malformed: false, mode: "disabled"},
);
check(
  "empty variable is disabled, not malformed",
  describeAppCheckEnforcement(""),
  {enabled: false, malformed: false, mode: "disabled"},
);

// --- the production incident shape ---
const FLATTENED =
  "falseBUNNY_STREAM_API_KEY=BUNNY_STREAM_LIBRARY_ID=736742";
check(
  "a flattened multi-line .env value is reported as malformed",
  describeAppCheckEnforcement(FLATTENED),
  {enabled: false, malformed: true, mode: "malformed", rawLength: FLATTENED.length},
);
check(
  "a malformed value never enables enforcement",
  describeAppCheckEnforcement(FLATTENED).enabled,
  false,
);

// --- near misses stay disabled and are surfaced ---
for (const raw of ["TRUE", "True", "1", "yes", " true", "true ", "true\n", "false=true"]) {
  check(
    `"${raw.replace(/\n/g, "\\n")}" is malformed and does not enable enforcement`,
    describeAppCheckEnforcement(raw),
    {enabled: false, malformed: true, mode: "malformed", rawLength: raw.length},
  );
}

// --- the malformed report never carries the value ---
check(
  "the malformed report exposes only a length, never the value",
  Object.keys(describeAppCheckEnforcement(FLATTENED)).sort(),
  ["enabled", "malformed", "mode", "rawLength"],
);

console.log(`\n${passed} checks passed`);
