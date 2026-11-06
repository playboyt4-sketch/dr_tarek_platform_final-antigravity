/**
 * REMOVAL NOTICE (owner-authorized): the legacy teacher-promotion block that
 * used to live in this file was removed entirely. It wrote the LEGACY role
 * "teacher" to Auth custom claims and the users document, which post-ADR-005
 * is inert (denied by Rules, Functions, and clients). No doctor-promotion
 * mechanism replaces it here: first-Doctor creation requires a separate,
 * explicitly authorized out-of-band procedure and must never be smuggled
 * into a reference-data seed. This script seeds reference data only and
 * accepts no phone number or identity argument of any kind.
 */
import { initializeApp, getApps, getApp } from "firebase-admin/app";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { getAuth } from "firebase-admin/auth";

if (getApps().length === 0) {
  initializeApp();
}

// Staging-only safety guard (no behavior change to seeded data).
//
// The Admin SDK resolves its project from several ambient sources, and NO
// single source proves the destination on its own: `app.options.projectId`
// is empty under ambient initializeApp(), while an environment variable
// alone can disagree with the credential file actually used at request
// time. The rule is therefore unanimity over every resolvable candidate:
// pass only when at least one candidate resolves AND every resolved
// candidate equals dr-tarek-staging. Unknown (no candidate) or any
// disagreement aborts before any write.
const STAGING_PROJECT_ID = "dr-tarek-staging";

export interface ProjectCandidate {
  source: string;
  projectId: string;
}

export interface ProjectResolutionDeps {
  /** app.options.projectId from the initialized Admin app (explicit init). */
  optionsProjectId: string | undefined;
  /** Environment record (production code passes process.env). */
  env: Record<string, string | undefined>;
  /**
   * Reads a credential file and returns its raw text, or null when the
   * file is absent/unreadable. Only the `project_id` field is ever parsed
   * out of it; secrets are never read.
   */
  readCredentialFile: (path: string) => string | null;
}

/**
 * Pure project-identity resolver (unit-testable, no Firebase I/O).
 * Collects every resolvable project candidate without assuming defaults.
 */
export function resolveProjectCandidates(
  deps: ProjectResolutionDeps,
): ProjectCandidate[] {
  const candidates: ProjectCandidate[] = [];
  if (deps.optionsProjectId) {
    candidates.push({
      source: "app.options.projectId",
      projectId: deps.optionsProjectId,
    });
  }
  const firebaseConfigRaw = deps.env.FIREBASE_CONFIG;
  if (firebaseConfigRaw) {
    try {
      const parsed = JSON.parse(firebaseConfigRaw) as {projectId?: unknown};
      if (typeof parsed.projectId === "string" && parsed.projectId) {
        candidates.push({
          source: "FIREBASE_CONFIG.projectId",
          projectId: parsed.projectId,
        });
      }
    } catch {
      // Malformed FIREBASE_CONFIG contributes no candidate (never a pass).
    }
  }
  for (const name of ["GOOGLE_CLOUD_PROJECT", "GCLOUD_PROJECT"]) {
    const value = deps.env[name];
    if (value) {
      candidates.push({source: `env:${name}`, projectId: value});
    }
  }
  const credentialPath = deps.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (credentialPath) {
    const raw = deps.readCredentialFile(credentialPath);
    if (raw) {
      try {
        const parsed = JSON.parse(raw) as {project_id?: unknown};
        if (typeof parsed.project_id === "string" && parsed.project_id) {
          candidates.push({
            source: "credential-file:project_id",
            projectId: parsed.project_id,
          });
        }
      } catch {
        // Malformed credential file contributes no candidate (never a pass).
      }
    }
  }
  return candidates;
}

export interface ProjectVerdict {
  pass: boolean;
  reason: string;
}

/**
 * Unanimity decision over resolved candidates (pure, unit-testable):
 * pass only when at least one candidate resolved and all equal staging.
 */
export function evaluateProjectCandidates(
  candidates: ProjectCandidate[],
): ProjectVerdict {
  if (candidates.length === 0) {
    return {
      pass: false,
      reason: "no project candidate resolved (unknown destination)",
    };
  }
  const bad = candidates.filter((c) => c.projectId !== STAGING_PROJECT_ID);
  if (bad.length > 0) {
    return {
      pass: false,
      reason: `conflicting candidates: ${bad.map((c) => `${c.source}="${c.projectId}"`).join(", ")}`,
    };
  }
  return {pass: true, reason: "all candidates agree on staging"};
}

function defaultCredentialReader(path: string): string | null {
  try {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const fs = require("node:fs") as typeof import("node:fs");
    return fs.readFileSync(path, "utf8");
  } catch {
    return null;
  }
}

export function assertStagingProject(): void {
  const candidates = resolveProjectCandidates({
    optionsProjectId: getApp().options.projectId,
    env: process.env,
    readCredentialFile: defaultCredentialReader,
  });
  const verdict = evaluateProjectCandidates(candidates);
  if (!verdict.pass) {
    throw new Error(
      `Refusing to seed: ${verdict.reason}; expected every candidate to ` +
        `equal "${STAGING_PROJECT_ID}". No writes were made.`,
    );
  }
}

const db = getFirestore();
const auth = getAuth();

/**
 * Complete Database Seeding for Dr. Tarek Platform
 * Configures:
 * 1. Plans (guest, free, pro, max)
 *    - Guest plan: document ID "guest", student_type "guest", plan_key "free"
 *      (plan_key "free" is shared with the Center Free plan by design; plan
 *      identity is the document ID + student_type, never plan_key alone).
 *    - Center plans: document IDs "free" / "pro" / "max"
 *      (Phase 4 simplification of center_free/center_pro/center_max),
 *      student_type "center_student", plan_keys "free" / "pro" / "max".
 * 2. Plan Features (Entitlements for video, quality, pdf, downloads, device limits)
 * 3. Core Academic Periods (Term 1, Term 2, Summer Course)
 * 4. Platform Features toggles
 *
 * Deliberately NOT included: any staff identity or role promotion. The
 * removed legacy teacher-promotion block is not replaced here.
 * PHASE 1 migration: legacy plans/public_free (if present from a pre-migration
 * seed) is explicitly deactivated below so the seed never leaves two active
 * Guest plans behind. Legacy plan_features docs with plan_id "public_free"
 * are NOT deleted here (non-destructive); run
 * scripts/migrate_public_to_guest.cjs --apply to move them to plan_id "guest".
 */
export async function seedDatabase(): Promise<void> {
  // Pre-write abort guard: must run before any Firestore/Auth write below.
  assertStagingProject();
  console.log("=== Starting Dr. Tarek Platform Database Seeding ===");

  // 1. Seed Plans
  const plans = [
    {
      id: "guest",
      plan_key: "free",
      student_type: "guest",
      title: "الباقة المجانية الخارجية",
      description: "معاينة مجانية للمحاضرات لغير طلاب السنتر",
      price: 0,
      currency: "EGP",
      billing_period: "free",
      is_active: true,
      display_order: 1,
    },
    {
      id: "free",
      plan_key: "free",
      student_type: "center_student",
      title: "باقة السنتر الأساسية",
      description: "الباقة المجانية التلقائية لطلاب السنتر المعتمدين",
      price: 0,
      currency: "EGP",
      billing_period: "term",
      is_active: true,
      display_order: 2,
    },
    {
      id: "pro",
      plan_key: "pro",
      student_type: "center_student",
      title: "باقة السنتر الاحترافية (Pro)",
      description: "مشاهدة بجودة عالية وتحكم كامل في السرعة والشاشات المصغرة",
      price: 150,
      currency: "EGP",
      billing_period: "term",
      is_active: true,
      display_order: 3,
    },
    {
      id: "max",
      plan_key: "max",
      student_type: "center_student",
      title: "باقة السنتر الشاملة (Max)",
      description: "كل المميزات + تحميل بدون إنترنت + جهازين مصرح بهما",
      price: 250,
      currency: "EGP",
      billing_period: "term",
      is_active: true,
      display_order: 4,
    },
  ];

  for (const plan of plans) {
    const { id, ...data } = plan;
    await db.collection("plans").doc(id).set(
      {
        ...data,
        updated_at: FieldValue.serverTimestamp(),
        created_at: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    console.log(`[Plan] Seeded: ${id}`);
  }

  // PHASE 4 migration safety: a pre-migration seed leaves
  // plans/center_free, plans/center_pro, plans/center_max behind
  // (merge:true never deletes). Active legacy docs would duplicate the
  // simplified plans, so deactivate them explicitly — never delete
  // (reversible, auditable). Their plan_features rows are left untouched
  // here; the dedicated migration script
  // (scripts/migrate_center_plan_ids.cjs) moves them.
  for (const legacyId of ["center_free", "center_pro", "center_max"]) {
    const legacySnap = await db.collection("plans").doc(legacyId).get();
    if (legacySnap.exists && (legacySnap.data() ?? {}).is_active === true) {
      await db.collection("plans").doc(legacyId).set(
        {
          is_active: false,
          updated_at: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
      console.log(`[Plan] Deactivated legacy plans/${legacyId} (superseded by Phase 4 plan IDs).`);
    }
  }
  // PHASE 1 migration safety: a pre-migration seed leaves plans/public_free
  // behind (merge:true never deletes). An active legacy doc would duplicate
  // the Guest plan, so deactivate it explicitly — never delete (reversible,
  // auditable). Its plan_features rows are left untouched here; the dedicated
  // migration script (scripts/migrate_public_to_guest.cjs) moves them.
  const legacyGuestSnap = await db.collection("plans").doc("public_free").get();
  if (legacyGuestSnap.exists) {
    const legacyData = legacyGuestSnap.data() ?? {};
    if (legacyData.is_active === true) {
      await db.collection("plans").doc("public_free").set(
        {
          is_active: false,
          updated_at: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
      console.log("[Plan] Deactivated legacy plans/public_free (superseded by plans/guest).");
    } else {
      console.log("[Plan] Legacy plans/public_free already inactive; left as-is.");
    }
  }

  // 2. Seed Plan Features
  const planFeatures: Record<string, Record<string, any>> = {
    guest: {
      "video.access": { enabled: true, value_type: "boolean" },
      "video.preview_duration": { enabled: true, value_type: "number", value: 5 },
      "video.quality.max": { enabled: true, value_type: "string", value: "480p" },
      "video.quality.480p": { enabled: true, value_type: "boolean" },
      "video.rolling_window.enabled": { enabled: false, value_type: "boolean" },
      "video.rolling_window.hours": { enabled: false, value_type: "number", value: 24 },
      "video.playback_speed": { enabled: false, value_type: "boolean" },
      "video.pip": { enabled: false, value_type: "boolean" },
      "video.cast": { enabled: false, value_type: "boolean" },
      "video.download": { enabled: false, value_type: "boolean" },
      "pdf.access": { enabled: false, value_type: "boolean" },
      "pdf.download": { enabled: false, value_type: "boolean" },
      "offline.mode": { enabled: false, value_type: "boolean" },
      "device.max_count": { enabled: true, value_type: "number", value: 1 },
    },
    free: {
      "video.access": { enabled: true, value_type: "boolean" },
      "video.preview_duration": { enabled: false, value_type: "number", value: 0 },
      "video.rolling_window.enabled": { enabled: true, value_type: "boolean" },
      "video.rolling_window.hours": { enabled: true, value_type: "number", value: 24 },
      "video.quality.max": { enabled: true, value_type: "string", value: "720p" },
      "video.quality.480p": { enabled: true, value_type: "boolean" },
      "video.quality.720p": { enabled: true, value_type: "boolean" },
      "video.playback_speed": { enabled: false, value_type: "boolean" },
      "video.pip": { enabled: false, value_type: "boolean" },
      "video.cast": { enabled: false, value_type: "boolean" },
      "video.download": { enabled: false, value_type: "boolean" },
      "pdf.access": { enabled: true, value_type: "boolean" },
      "pdf.download": { enabled: false, value_type: "boolean" },
      "offline.mode": { enabled: false, value_type: "boolean" },
      "device.max_count": { enabled: true, value_type: "number", value: 1 },
    },
    pro: {
      "video.access": { enabled: true, value_type: "boolean" },
      "video.preview_duration": { enabled: false, value_type: "number", value: 0 },
      "video.rolling_window.enabled": { enabled: false, value_type: "boolean" },
      "video.rolling_window.hours": { enabled: false, value_type: "number", value: 24 },
      "video.quality.max": { enabled: true, value_type: "string", value: "1080p" },
      "video.quality.480p": { enabled: true, value_type: "boolean" },
      "video.quality.720p": { enabled: true, value_type: "boolean" },
      "video.quality.1080p": { enabled: true, value_type: "boolean" },
      "video.playback_speed": { enabled: true, value_type: "boolean" },
      "video.pip": { enabled: true, value_type: "boolean" },
      "video.cast": { enabled: false, value_type: "boolean" },
      "video.download": { enabled: false, value_type: "boolean" },
      "pdf.access": { enabled: true, value_type: "boolean" },
      "pdf.download": { enabled: false, value_type: "boolean" },
      "offline.mode": { enabled: false, value_type: "boolean" },
      "device.max_count": { enabled: true, value_type: "number", value: 1 },
    },
    max: {
      "video.access": { enabled: true, value_type: "boolean" },
      "video.preview_duration": { enabled: false, value_type: "number", value: 0 },
      "video.rolling_window.enabled": { enabled: false, value_type: "boolean" },
      "video.rolling_window.hours": { enabled: false, value_type: "number", value: 24 },
      "video.quality.max": { enabled: true, value_type: "string", value: "1080p" },
      "video.quality.480p": { enabled: true, value_type: "boolean" },
      "video.quality.720p": { enabled: true, value_type: "boolean" },
      "video.quality.1080p": { enabled: true, value_type: "boolean" },
      "video.playback_speed": { enabled: true, value_type: "boolean" },
      "video.pip": { enabled: true, value_type: "boolean" },
      "video.cast": { enabled: true, value_type: "boolean" },
      "video.download": { enabled: true, value_type: "boolean" },
      "video.download.max_count": { enabled: true, value_type: "number", value: 5 },
      "pdf.access": { enabled: true, value_type: "boolean" },
      "pdf.download": { enabled: true, value_type: "boolean" },
      "offline.mode": { enabled: true, value_type: "boolean" },
      "device.max_count": { enabled: true, value_type: "number", value: 2 },
    },
  };

  for (const [planId, features] of Object.entries(planFeatures)) {
    for (const [featureKey, featureData] of Object.entries(features)) {
      const docId = `${planId}_${featureKey.replace(/\./g, "_")}`;
      await db.collection("plan_features").doc(docId).set(
        {
          plan_id: planId,
          feature_key: featureKey,
          enabled: featureData.enabled,
          value_type: featureData.value_type,
          value: featureData.value ?? null,
          // Dual write (mirrors setPlanFeature in src/index.ts): entitlement
          // readers consume `feature_value` (Approved 05_DATABASE_v1.7
          // plan_features "Feature Value"); `value` is kept for the legacy
          // seed-script shape. Both are always written together.
          feature_value: featureData.value ?? null,
          updated_at: FieldValue.serverTimestamp(),
          created_at: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    }
    console.log(`[PlanFeatures] Seeded features for: ${planId}`);
  }

  // 3. Seed Core Academic Periods
  const corePeriods = [
    {
      id: "core_term_1",
      label: "الفصل الدراسي الأول",
      is_core: true,
      display_order: 1,
      status: "active",
      period_type: "term_1",
      started_at: FieldValue.serverTimestamp(),
      ended_at: null,
      created_by: "system_seed",
    },
    {
      id: "core_term_2",
      label: "الفصل الدراسي الثاني",
      is_core: true,
      display_order: 2,
      status: "ended",
      period_type: "term_2",
      started_at: null,
      ended_at: null,
      created_by: "system_seed",
    },
    {
      id: "core_summer",
      label: "الدورة الصيفية",
      is_core: true,
      display_order: 3,
      status: "ended",
      period_type: "summer",
      started_at: null,
      ended_at: null,
      created_by: "system_seed",
    },
  ];

  for (const period of corePeriods) {
    const { id, ...data } = period;
    await db.collection("academic_periods").doc(id).set(
      {
        ...data,
        updated_at: FieldValue.serverTimestamp(),
        created_at: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    console.log(`[AcademicPeriod] Seeded: ${data.label}`);
  }

  // 4. Seed Platform Features
  const platformFeatures = [
    { id: "feature_exams", label: "الامتحانات العامة", enabled: true },
    { id: "feature_quizzes", label: "اختبارات الفيديوهات القصيرة", enabled: true },
    { id: "feature_notes", label: "ملاحظات الطلاب", enabled: true },
    { id: "feature_bookmarks", label: "العلامات المرجعية", enabled: true },
    { id: "feature_chat", label: "المحادثة الفورية مع السنتر", enabled: false },
    { id: "feature_device_change", label: "طلبات تغيير الأجهزة", enabled: true },
  ];

  for (const feat of platformFeatures) {
    const { id, ...data } = feat;
    await db.collection("platform_features").doc(id).set(
      {
        ...data,
        updated_at: FieldValue.serverTimestamp(),
        created_at: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    console.log(`[PlatformFeature] Seeded: ${data.label}`);
  }

  // Staff promotion intentionally absent (see file header): this script
  // must never assign roles or claims to any identity.

  console.log("=== Database Seeding Completed Successfully! ===");
}

if (require.main === module) {
  // No phone number or identity argument exists. Any positional argument is
  // rejected before anything else runs, so a stale invocation such as
  // `seed_database.ts 01000000000` can never reach the seeding logic.
  const extraArgs = process.argv.slice(2);
  if (extraArgs.length > 0) {
    console.error(
      `Refusing to seed: unexpected argument(s) ${JSON.stringify(extraArgs)}. ` +
        `This script accepts no phone number or identity argument. No writes were made.`,
    );
    process.exit(2);
  }
  seedDatabase()
    .then(() => process.exit(0))
    .catch((err) => {
      console.error("Seeding failed:", err);
      process.exit(1);
    });
}
