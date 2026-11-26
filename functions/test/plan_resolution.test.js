/**
 * Pure unit tests for canonical plan resolution and active subscription ranking.
 */
const assert = require("node:assert/strict");
const {
  planTierRank,
  selectCanonicalPlanDoc,
  partitionSubscriptionsForSubject,
} = require("../lib/plan_resolution.js");

// Tier ranking checks.
assert.equal(planTierRank("max"), 3);
assert.equal(planTierRank("plan_center_max"), 3);
assert.equal(planTierRank("pro"), 2);
assert.equal(planTierRank("plan_center_pro"), 2);
assert.equal(planTierRank("free"), 1);
assert.equal(planTierRank("guest"), 0);
assert.equal(planTierRank(null), -1);

// Production regression: Firestore lists "plan_center_pro" before "pro"
// alphabetically; canonical "pro" MUST win.
const selectedPro = selectCanonicalPlanDoc(
  [
    {
      id: "plan_center_pro",
      data: {
        plan_key: "center_pro",
        student_type: "center_student",
        is_active: true,
      },
    },
    {
      id: "pro",
      data: {
        plan_key: "pro",
        student_type: "center_student",
        is_active: true,
      },
    },
  ],
  {studentType: "center_student", plan: "pro"},
);
assert.equal(selectedPro?.id, "pro");

// Free plan must prefer "free" over "e2e_center_free" or "plan_center_free".
const selectedFree = selectCanonicalPlanDoc(
  [
    {
      id: "e2e_center_free",
      data: {
        plan_key: "free",
        student_type: "center_student",
        is_active: true,
      },
    },
    {
      id: "plan_center_free",
      data: {
        plan_key: "center_free",
        student_type: "center_student",
        is_active: true,
      },
    },
    {
      id: "free",
      data: {
        plan_key: "free",
        student_type: "center_student",
        is_active: true,
      },
    },
  ],
  {studentType: "center_student", plan: "free", preferredPlanKey: "free"},
);
assert.equal(selectedFree?.id, "free");

// Subscription partitioning ignores deleted/archived docs and prefers Pro over Free.
const partitioned = partitionSubscriptionsForSubject([
  {
    id: "sub_deleted_max",
    data: {status: "active", is_deleted: true, plan_id: "max"},
  },
  {
    id: "sub_free",
    data: {status: "active", is_deleted: false, plan_id: "free"},
  },
  {
    id: "sub_pro",
    data: {status: "active", is_deleted: false, plan_id: "pro"},
  },
]);
assert.equal(partitioned.primary?.id, "sub_pro");
assert.deepEqual(
  partitioned.extras.map((d) => d.id),
  ["sub_free"],
);

// Canonical plan ID "pro" beats legacy "plan_center_pro" within same tier.
const canonicalOverStub = partitionSubscriptionsForSubject([
  {
    id: "sub_stub",
    data: {status: "active", is_deleted: false, plan_id: "plan_center_pro"},
  },
  {
    id: "sub_canonical",
    data: {status: "active", is_deleted: false, plan_id: "pro"},
  },
]);
assert.equal(canonicalOverStub.primary?.id, "sub_canonical");
assert.deepEqual(
  canonicalOverStub.extras.map((d) => d.id),
  ["sub_stub"],
);

console.log("plan_resolution.test.js passed");
