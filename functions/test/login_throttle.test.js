/**
 * Unit tests for the login brute-force lockout policy.
 *
 * Policy (approved escalation ladder):
 *   failures < 3   -> no lock
 *   3-4            -> 5 minutes
 *   5-9            -> 10 minutes
 *   10-19          -> 20 minutes
 *   20-39          -> 40 minutes
 *   40+            -> 60 minutes (maximum)
 *
 * calculateLockMinutes is a pure exported function from src/index.ts,
 * so these tests run against the real production policy code.
 */
const assert = require("node:assert/strict");

const {calculateLockMinutes} = require("../lib/index.js");

function run() {
  // Below threshold: no lock.
  for (let f = 0; f <= 2; f++) {
    assert.equal(calculateLockMinutes(f), 0, `${f} failures must not lock`);
  }

  // Approved escalation ladder boundaries.
  const expected = [
    [3, 5],
    [4, 5],
    [5, 10],
    [9, 10],
    [10, 20],
    [19, 20],
    [20, 40],
    [39, 40],
    [40, 60], // maximum reached
    [41, 60],
    [1000, 60],
  ];
  for (const [failures, minutes] of expected) {
    assert.equal(
      calculateLockMinutes(failures),
      minutes,
      `${failures} failures must lock ${minutes}m`,
    );
  }

  console.log(
    "login_throttle.test: PASS — 3->5m, 5->10m, 10->20m, 20->40m, >=40->60m cap verified",
  );
}

run();
