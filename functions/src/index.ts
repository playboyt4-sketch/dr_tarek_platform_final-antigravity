import {SECURE_CALL_OPTS} from "./core/utils/security_helpers";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {
  onDocumentCreated,
  onDocumentUpdated,
  onDocumentWritten,
} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {
  getFirestore,
  FieldPath,
  FieldValue,
  Timestamp,
  DocumentData,
} from "firebase-admin/firestore";
import {getAuth} from "firebase-admin/auth";
import {getMessaging, Message} from "firebase-admin/messaging";
import {getStorage} from "firebase-admin/storage";
import {initializeApp} from "firebase-admin/app";
import {defineSecret} from "firebase-functions/params";

// --- Helpers for restored functions ---

const SECRET_BUNNY_TOKEN_KEY = defineSecret("BUNNY_TOKEN_KEY");

const SECRET_BUNNY_PLAYBACK_URL_TEMPLATE = defineSecret("BUNNY_PLAYBACK_URL_TEMPLATE");

const SECRET_BUNNY_STORAGE_BASE_URL = defineSecret("BUNNY_STORAGE_BASE_URL");

const SECRET_BUNNY_STORAGE_ZONE_NAME = defineSecret("BUNNY_STORAGE_ZONE_NAME");

const SECRET_BUNNY_STORAGE_PASSWORD = defineSecret("BUNNY_STORAGE_PASSWORD");

async function assertLoginNotLocked(scope: string, key: string): Promise<void> {
  const snap = await throttleRef(scope, key).get();
  if (!snap.exists) return;
  const lockedUntil = dataOf(snap.data()).locked_until;
  const untilMs =
    lockedUntil && typeof lockedUntil.toMillis === "function" ?
      lockedUntil.toMillis() :
      0;
  if (untilMs > Date.now()) {
    const minutes = Math.max(1, Math.ceil((untilMs - Date.now()) / 60000));
    throw new HttpsError(
      "resource-exhausted",
      `Too many failed attempts. Try again in ${minutes} minute(s).`,
    );
  }
}

async function recordLoginFailure(
  scope: string,
  key: string,
  maxFailures: number = MAX_LOGIN_FAILURES,
): Promise<void> {
  await db.runTransaction(async (tx) => {
    const ref = throttleRef(scope, key);
    const snap = await tx.get(ref);
    const prevData = snap.exists ? dataOf(snap.data()) : {};
    // Staff lockout-stretch hardening (approved, staff_login scope only):
    // once the staff identity is already inside an active lockout period,
    // additional failures must not increment the counter, extend the lock,
    // or create a new lock. The pre-check in verifyStaffPassword already
    // rejects such attempts, but a concurrent attempt that passed the
    // pre-check before the lock committed must still be a no-op here.
    // All other scopes keep their existing behavior.
    if (scope === "staff_login") {
      const prevLocked = prevData.locked_until;
      const prevLockedMs =
        prevLocked && typeof prevLocked.toMillis === "function" ?
          prevLocked.toMillis() :
          0;
      if (prevLockedMs > Date.now()) {
        return;
      }
    }
    const prevFailures =
      typeof prevData.fail_count === "number" ? (prevData.fail_count as number) : 0;
    const failures = prevFailures + 1;

    let lockMinutes = 0;
    if (failures >= maxFailures) {
      lockMinutes = calculateLockMinutes(failures);
    }

    const update: Record<string, unknown> = {
      scope,
      key,
      fail_count: failures,
      updated_at: FieldValue.serverTimestamp(),
    };
    if (lockMinutes > 0) {
      update.locked_until = Timestamp.fromDate(
        new Date(Date.now() + lockMinutes * 60_000),
      );
      update.last_lock_minutes = lockMinutes;
      // Audit-only lock-transition event (fresh locks, not every hammered
      // failure): append-only auth_security_events write using the hashed
      // throttle doc id — never raw phone/name/IP, never secrets. No
      // notification behavior (alerting policy undefined).
      const prevUntil = prevData.locked_until;
      const prevUntilMs =
        prevUntil && typeof prevUntil.toMillis === "function" ?
          prevUntil.toMillis() :
          0;
      if (prevUntilMs <= Date.now()) {
        tx.set(db.collection("auth_security_events").doc(), {
          event_type: "login_lock_engaged",
          scope,
          key_hash: ref.id,
          fail_count: failures,
          lock_minutes: lockMinutes,
          locked_until: update.locked_until,
          created_at: FieldValue.serverTimestamp(),
          created_by: "system",
        });
      }
    }
    tx.set(ref, update, {merge: true});
  });
}

async function clearLoginFailures(scope: string, key: string): Promise<void> {
  await throttleRef(scope, key).delete();
}

async function slidingWindowAllowed(
  scope: string,
  key: string,
  max: number,
  windowMs: number,
): Promise<boolean> {
  const ref = db.collection(scope).doc(key);
  const nowMs = Date.now();
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.exists ? dataOf(snap.data()) : {};
    const timestamps: number[] = Array.isArray(data.recent) ?
      (data.recent as Timestamp[])
        .filter((t) => t?.toMillis && t.toMillis() > nowMs - windowMs)
        .map((t) => t.toMillis()) :
      [];
    if (timestamps.length >= max) return false;
    timestamps.push(nowMs);
    tx.set(ref, {recent: timestamps.map((ms) => Timestamp.fromMillis(ms))}, {merge: true});
    return true;
  });
}

function requestIp(request: CallableRequest): string | null {
  if (typeof request.rawRequest?.ip === "string") return request.rawRequest.ip;
  const socketAddress = request.rawRequest?.socket?.remoteAddress;
  if (typeof socketAddress === "string") return socketAddress;
  return null;
}

async function assertStaffDirectoryAllowed(request: CallableRequest): Promise<void> {
  const ip = requestIp(request);
  if (!ip) return;
  const key = createHash("sha256").update(`staff_directory:${ip}`).digest("hex");
  const allowed = await slidingWindowAllowed(
    "public_rate_limits",
    key,
    STAFF_DIRECTORY_RATE_LIMIT,
    STAFF_DIRECTORY_WINDOW_MS,
  );
  if (!allowed) {
    await db.collection("auth_security_events").add({
      event_type: "staff_directory_rate_limited",
      created_at: FieldValue.serverTimestamp(),
      created_by: "system",
    });
    throw new HttpsError("resource-exhausted", "Too many requests. Try again later.");
  }
}

function buildBunnyResourceAccessUrl(storagePath: string, expiresInSeconds = 300): {url: string; expiresAt: number} {
  const secret = getEnv("BUNNY_TOKEN_KEY");
  const expires = Math.floor(Date.now() / 1000) + expiresInSeconds;
  const url = bunnyResourceUrl(storagePath);
  const token = hashPathToken(secret, url.pathname, expires);
  url.searchParams.set("token", token);
  url.searchParams.set("expires", String(expires));
  return {url: url.toString(), expiresAt: expires};
}

async function bunnyStorageRequest(
  method: "PUT" | "DELETE",
  storagePath: string,
  body?: Buffer,
): Promise<void> {
  const password = getEnv("BUNNY_STORAGE_PASSWORD");
  const zoneName = getEnv("BUNNY_STORAGE_ZONE_NAME");
  const url = `${bunnyResourceUrl(storagePath).toString().replace(/^https:\/\//, "")}`;
  const target = new URL(`https://${url}`);
  // Bunny storage API addresses the zone as the first path segment.
  const zonedPath = `/${zoneName}${target.pathname}`;
  const response = await fetch(`https://${target.host}${zonedPath}`, {
    method,
    headers: {
      AccessKey: password,
      ...(body ? {"Content-Type": "application/octet-stream"} : {}),
    },
    body: body ? new Uint8Array(body) : undefined,
  });
  if (!response.ok) {
    // Never include the password (or any credential material) in errors.
    throw new HttpsError("internal", `Bunny storage request failed (${response.status}).`);
  }
}

const BUNNY_UPLOAD_CONTENT_TYPES = new Set([
  "application/pdf",
  "application/zip",
  "application/x-zip-compressed",
  "application/octet-stream",
  "application/msword",
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  "application/vnd.ms-excel",
  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  "application/vnd.ms-powerpoint",
  "application/vnd.openxmlformats-officedocument.presentationml.presentation",
  "text/plain",
  "image/jpeg",
  "image/png",
]);

const BUNNY_PROXY_MAX_BYTES = 24 * 1024 * 1024;

export function pickDueLectures(
  docs: Array<{id: string; status: unknown; isDeleted: unknown; publishDateMs: number | null}>,
  nowMs: number,
): string[] {
  return docs
    .filter((doc) =>
      doc.status === "draft" &&
      doc.isDeleted !== true &&
      doc.publishDateMs !== null &&
      doc.publishDateMs <= nowMs)
    .map((doc) => doc.id);
}

// PHASE 1 terminology migration: public_student -> guest, public_free -> guest.
// PHASE 4 plan ID simplification: center_free -> free, center_pro -> pro,
// center_max -> max (document IDs only).
// plan_key ("free") is NOT migrated: both the Guest plan and the Center Free
// plan (plans/free) legitimately share plan_key = "free". Plan identity is
// the document ID (plans/guest, plans/free, plans/pro, plans/max)
// plus plans.student_type, never plan_key alone.
export const GUEST_STUDENT_TYPE = "guest";
export const CENTER_STUDENT_TYPE = "center_student";
export const GUEST_PLAN_ID = "guest";

/**
 * Identity-safe Guest plan check.
 *
 * Must NOT use `plan_key == "free"` alone: plans/free also carries
 * plan_key = "free". The Guest plan is identified by its document ID
 * (plans/guest) together with plans.student_type = "guest".
 * @param {string|null} planId Plan document ID (subscriptions.plan_id).
 * @param {object} plan Plan document data.
 * @return {boolean} True only for the Guest plan.
 */
export function isGuestPlan(
  planId: string | null | undefined,
  plan: {student_type?: unknown} | null | undefined,
): boolean {
  return planId === GUEST_PLAN_ID && !!plan && plan.student_type === GUEST_STUDENT_TYPE;
}

/**
 * Guest per-lecture preview cap (FINAL_DECISIONS §11).
 * Exported for unit testing.
 *
 * Gate not armed (`guestEnabled` false) returns null (not applicable).
 * Per-lecture minutes win over the plan's video.preview_duration default;
 * null lecture minutes fall back to the plan default. When neither source
 * defines minutes the cap is 0 — the student sees the upgrade prompt
 * immediately instead of unbounded playback.
 * @param {object} opts Preview-cap inputs.
 * @return {number|null} Preview seconds, 0 for upgrade prompt, null if gate off.
 */
export function resolveGuestPreviewSeconds(opts: {
  guestEnabled: boolean;
  lectureMinutes: number | null;
  planDefaultMinutes: number | null;
}): number | null {
  if (!opts.guestEnabled) return null;
  const minutes = opts.lectureMinutes ?? opts.planDefaultMinutes;
  if (minutes === null || !Number.isFinite(minutes) || minutes <= 0) return 0;
  return Math.round(minutes * 60);
}

/**
 * Audience discriminator for Guest preview verdicts (messaging only).
 *
 * The issuance/listing Guest contract historically carried a single
 * `previewLimitSeconds` integer, so the client could not tell an external
 * Guest apart from a Center student on an unauthorized device. This
 * additive, message-level field closes that gap: enforcement, tiers,
 * windows, and Full-tier response shapes are untouched.
 * - "guest": Guest identity or Guest plan — the client directs these
 *   students to Center enrollment instead of a paid-plan upgrade.
 * - "center": Center student resolving Guest tier (unauthorized-device
 *   fallback) — the client avoids mislabeling them as Guest.
 * Derived from plan identity only (isGuestPlan), wherever the plan
 * document is already loaded. No extra reads. Exported for unit testing.
 */
export type PreviewAudience = "guest" | "center";

export function previewAudienceForPlan(
  planId: string | null | undefined,
  plan: {student_type?: unknown} | null | undefined,
): PreviewAudience {
  return isGuestPlan(planId, plan) ? "guest" : "center";
}

/**
 * Atomic Guest issuance verdict constructor (structural contract lock).
 *
 * The Guest preview verdict is atomic: `previewLimitSeconds` and
 * `previewAudience` are ALWAYS emitted together on Guest tier, and
 * NEVER on Full tier. Emitting one without the other leaves clients
 * with an unclassifiable verdict (a numeric cap with a null audience),
 * which degrades to the generic paid wall — an upsell CTA for a
 * device-blocked student who cannot fix anything by upgrading.
 * Centralizing construction here makes a partial verdict a
 * compile-time shape error instead of a runtime ambiguity.
 * Enforcement and tiers are untouched: this only assembles the
 * already-decided values. Callers must only invoke it for Guest tier
 * after the null-preview throw above (guestPreviewSeconds non-null).
 * Exported for unit testing.
 * @param {object} input Guest verdict inputs (tier, plan identity, seconds).
 * @return {object} Both preview keys on Guest; empty object on Full.
 */
export function buildGuestIssuanceVerdict(input: {
  tier: "full" | "guest";
  subjectPlanId: string | null | undefined;
  subjectPlan: {student_type?: unknown} | null | undefined;
  guestPreviewSeconds: number | null;
}): {previewLimitSeconds: number; previewAudience: PreviewAudience} | Record<string, never> {
  if (input.tier !== "guest") return {};
  return {
    previewLimitSeconds: input.guestPreviewSeconds as number,
    previewAudience: previewAudienceForPlan(input.subjectPlanId, input.subjectPlan),
  };
}

/**
 * Lecture-identity resolution for `generateBunnySignedUrl` (identity fix).
 *
 * The `bunny_video_id` identifies the VIDEO FILE only — never the lecture.
 * When the caller asserts `requestedLectureId`, only a resource row linking
 * THAT lecture to the video may resolve (anything else is a mismatch).
 * Without an asserted identity (legacy clients), a single live row resolves
 * as before; ZERO rows is missing; MORE THAN ONE live row sharing the video
 * is ambiguous and must never collapse to `limit(1)` first-match.
 *
 * Pure function over pre-mapped rows (no Firestore) — unit-testable.
 * Exported for unit testing.
 * @param {Array} candidates Pre-mapped resource rows for the video.
 * @param {object} opts Resolution inputs.
 * @return {object} Discriminated match outcome (no Firestore, no throws).
 */
export type IssuanceResourceMatch =
  | {kind: "resolved"; resourceId: string}
  | {kind: "missing"}
  | {kind: "mismatch"}
  | {kind: "ambiguous"};

export function matchIssuanceResource(
  candidates: Array<{id: string; lectureId: string | null; deleted: boolean}>,
  opts: {requestedLectureId: string | null},
): IssuanceResourceMatch {
  if (opts.requestedLectureId != null) {
    const hit = candidates
      .filter((row) => !row.deleted)
      .find((row) => row.lectureId === opts.requestedLectureId);
    if (!hit) return {kind: "mismatch"};
    return {kind: "resolved", resourceId: hit.id};
  }
  const live = candidates.filter((row) => !row.deleted);
  if (live.length === 0) return {kind: "missing"};
  if (live.length > 1) return {kind: "ambiguous"};
  return {kind: "resolved", resourceId: live[0].id};
}

/**
 * Read the Guest preview fields from a lecture document.
 *
 * Canonical schema (Phase 1): `guest_enabled` / `guest_preview_minutes`.
 * Transitional fallback: legacy `public_free_enabled` /
 * `public_free_preview_minutes` (written by pre-Phase-2 clients/seed).
 * TODO(PHASE2): remove the legacy fallback once Flutter/Dashboard and all
 * stored lecture documents use the guest_* fields (see migration script
 * scripts/migrate_public_to_guest.cjs).
 * @param {object} lecture Lecture document data.
 * @return {object} Preview gate state.
 */
export function readGuestPreviewFields(lecture: {
  guest_enabled?: unknown;
  guest_preview_minutes?: unknown;
  public_free_enabled?: unknown;
  public_free_preview_minutes?: unknown;
}): {guestEnabled: boolean; lectureMinutes: number | null} {
  const rawEnabled =
    typeof lecture.guest_enabled === "boolean" ?
      lecture.guest_enabled :
      lecture.public_free_enabled === true;
  const rawMinutes =
    typeof lecture.guest_preview_minutes === "number" ?
      lecture.guest_preview_minutes :
      typeof lecture.public_free_preview_minutes === "number" ?
        lecture.public_free_preview_minutes :
        null;
  return {guestEnabled: rawEnabled === true, lectureMinutes: rawMinutes};
}

export interface GradingLink {
  questionId: string;
  marks: number;
}
export interface GradingQuestion {
  questionType: string;
  correctAnswer: string;
}

const EXAM_SUBMIT_TIME_GRACE_MS = 90_000;

const MAX_EXAM_ANSWERS = 500;

type ContentEntity = "subject_sections" | "lectures" | "lecture_resources" | "lecture_access_grants";

function contentAuditTrigger(entity: ContentEntity) {
  return onDocumentWritten(`${entity}/{docId}`, async (event) => {
    const before = event.data?.before.data() ?? null;
    const after = event.data?.after.data() ?? null;
    const change: ContentChange =
      !before ? "created" : !after ? "deleted" : "updated";
    const snapshot = (after ?? before) as Record<string, unknown> | null;
    const actorId =
      typeof snapshot?.updated_by === "string" ?
        snapshot.updated_by :
        typeof snapshot?.created_by === "string" ?
          snapshot.created_by :
          "unknown_staff";

    // Resolve the canonical role server-side (client-written
    // updated_by/created_by is not trusted for role attribution).
    // Falls back to the historical generic value on any failure, so audit
    // logging never breaks content writes. Historical records untouched.
    let actorRole = "staff_content";
    try {
      if (actorId !== "unknown_staff") {
        const actorSnap = await db.collection("users").doc(actorId).get();
        const actorRoleValue = actorSnap.exists ? getString(dataOf(actorSnap.data()).role) : null;
        if (actorRoleValue === "doctor" || actorRoleValue === "admin") {
          actorRole = actorRoleValue;
        }
      }
    } catch {
      actorRole = "staff_content";
    }

    await db.collection("admin_audit_log").add({
      action: `content_${change}`,
      entity,
      target_id: event.params.docId,
      actor_id: actorId,
      actor_role: actorRole,
      created_at: FieldValue.serverTimestamp(),
      timestamp: FieldValue.serverTimestamp(),
    });
  });
}


const MAX_LOGIN_FAILURES = 3;

// Pre-lookup anti-spray protection for verifyPhonePassword (approved):
// at most STUDENT_LOGIN_IP_MAX_FAILURES *failed* logins per caller IP
// before the endpoint locks for that IP. Lock durations reuse the
// existing calculateLockMinutes ladder; the per-account lockout above
// is unchanged. Keyed by IP (not phone) so rotating phone numbers does
// not evade it. Successes never clear this counter: a valid login must
// not reset another caller's spray budget behind the same NAT egress.
const STUDENT_LOGIN_IP_SCOPE = "student_login_ip";
const STUDENT_LOGIN_IP_MAX_FAILURES = 5;

// changePassword throttle (approved): at most
// CHANGE_PASSWORD_MAX_FAILURES *incorrect current-password* attempts per
// authenticated user before the flow locks for that user. Durations reuse
// the existing calculateLockMinutes ladder (5 failures -> 10 minutes).
// Scope/key are dedicated to changePassword: success clears ONLY this
// scope, and no login scope, lockout, claim, or account state is touched,
// so normal login is never affected.
const CHANGE_PASSWORD_SCOPE = "change_password";
const CHANGE_PASSWORD_MAX_FAILURES = 5;

// Registration abuse protection (approved): at most
// REGISTRATION_MAX_ATTEMPTS valid registration submissions per caller IP
// per REGISTRATION_WINDOW_MS, via the existing transactional sliding
// window (same mechanism as the password-reset request throttle). Counts
// all valid-shape attempts (successes and duplicate-phone rejections
// alike); malformed requests never consume budget. Duplicate-phone
// already-exists behavior is unchanged within budget. No permanent lock:
// the window slides, and success clears nothing because there is nothing
// to clear. Scope is isolated from login/changePassword/staff budgets.
const REGISTRATION_THROTTLE_SCOPE = "registration_throttle";
const REGISTRATION_MAX_ATTEMPTS = 10;
const REGISTRATION_WINDOW_MS = 15 * 60 * 1000;

// Staff-login anti-spray protection (approved): at most
// STAFF_LOGIN_IP_MAX_FAILURES *failed* staff logins per caller IP before
// the endpoint locks for that IP. Durations reuse the existing
// calculateLockMinutes ladder (5 failures -> 10 minutes). This complements
// (never replaces) the per-name staff_login throttle: rotating display
// names no longer resets the budget. Successes never clear this counter
// (same semantics as the student IP scope). Unknown/wrong responses stay
// identical; ambiguous-name behavior is unchanged.
const STAFF_LOGIN_IP_SCOPE = "staff_login_ip";
const STAFF_LOGIN_IP_MAX_FAILURES = 5;

// Timing-oracle mitigation for unknown-phone logins: the wrong-password
// path always performs a scrypt verification, so the unknown-phone path
// performs a discarded verification against this fixed dummy hash (a hash
// of a random value nobody knows; the result is never used). This keeps
// the two failure paths at comparable cost using the existing
// verifyPassword helper. DB read counts still differ; noted as residual.
const ENUMERATION_DUMMY_HASH =
  "scrypt$27b8077d54a3da05e8e266a760e07ad8$99d1c5b0c48b7d5000d7ddfae14bfbb7bec079ffb6d468b3b4192bb6af42a8202d4187252e575816fe1de8290747d77f84bb7bef09f89eda3b02b61eb5072a34$16384";

function throttleRef(scope: string, key: string) {
  // Firestore document IDs must not contain "/". Derive a collision-safe,
  // path-safe ID from scope+key (phones, staff names, anything).
  const id = createHash("sha256")
    .update(`${scope}:${key}`)
    .digest("hex");

  return db.collection("login_throttle").doc(id);
}

const STAFF_DIRECTORY_RATE_LIMIT = 30;

const STAFF_DIRECTORY_WINDOW_MS = 10 * 60 * 1000;

function bunnyResourceUrl(storagePath: string): URL {
  const base = getEnv("BUNNY_STORAGE_BASE_URL").replace(/\/+$/, "");
  const cleanPath = storagePath.replace(/^\/+/, "");
  return new URL(`${base}/${cleanPath}`);
}

type ContentChange = "created" | "updated" | "deleted";

import {
  createHash,
  createHmac,
  randomBytes,
  scrypt as scryptCallback,
  timingSafeEqual,
} from "node:crypto";

initializeApp();

const db = getFirestore();
const auth = getAuth();
const messaging = getMessaging();
const storage = getStorage();

export const FREE_WINDOW_BLOCKED_MESSAGE =
  "A Center Free 24-hour video window is already active for another video.";

// V1 Individual Per-Lecture Student Access (project-owner approved).
// Explicit per-student deny override: a grant with allowed === false
// denies the lecture even when plan/subject checks would pass.
// Missing grant (or allowed === true) defers to the normal eligibility
// model — the grant is an override, never a universal security bypass.
export const LECTURE_ACCESS_DENIED_MESSAGE =
  "Lecture access is not allowed for this student.";

export function decideVideoWatchWindow(
  existingWindow: {active_lecture_id: string; window_expires_at: Timestamp} | null | undefined,
  requestedLectureId: string,
  now: number
): { allowed: boolean; reason: "no_window" | "same_video" | "different_video" | "expired" } {
  if (!existingWindow || !existingWindow.window_expires_at) {
    return {allowed: true, reason: "no_window"};
  }
  const expiryMs = existingWindow.window_expires_at.toMillis();
  if (now >= expiryMs) return {allowed: true, reason: "expired"};
  if (existingWindow.active_lecture_id === requestedLectureId) {
    return {allowed: true, reason: "same_video"};
  }
  return {allowed: false, reason: "different_video"};
}

/**
 * Issuance denial precedence (Center Free A → Exit → C regression fix).
 *
 * The rolling-window verdict for the requested lecture is authoritative and
 * must win over the device-tier Guest denial: the Next flow walls from the
 * client-side window snapshot without ever calling issuance, while a direct
 * open after exit calls issuance — a Guest-tier device must still receive
 * the SAME 24-hour restriction (resource-exhausted), never Guest/device
 * behavior (Center Free → Guest downgrade). Returns "window" when the
 * window decision blocks the request (the caller throws resource-exhausted
 * BEFORE any tier evaluation), otherwise "tier" (defer to the device-tier
 * verdict below). Pure function — unit-testable without Firestore.
 */
export function issuanceDenialPrecedence(windowDecision: {
  allowed: boolean;
}): "window" | "tier" {
  return windowDecision.allowed ? "tier" : "window";
}

export interface RollingWindowPolicy {
  enforced: boolean;
  hours: number;
}

/**
 * Rolling watch-window policy ("تحديد المشاهدة كل 24 ساعة").
 *
 * Controllable from the dashboard Feature Matrix on ANY plan:
 * - `video.rolling_window.enabled == true` → enforce with
 *   `video.rolling_window.hours` (default 24, clamped 1..168).
 * - `video.rolling_window.enabled == false` → no enforcement.
 * - Feature missing entirely → legacy fallback (FINAL_DECISIONS §12):
 *   center_student + free plans stay enforced at 24h until the
 *   matrix is configured. This keeps existing deployments safe.
 *   The fallback is plan-ID based (Phase 4: plans/free). The pre-migration
 *   document ID "center_free" is still honored transitionally so the
 *   fallback keeps working on not-yet-migrated data; run
 *   scripts/migrate_center_plan_ids.cjs --apply to converge.
 *
 * Pure function — unit-testable without Firestore.
 * @param {object} opts Policy inputs from plan_features + plan doc.
 * @return {RollingWindowPolicy} Enforcement decision + window hours.
 */
export function resolveRollingWindowPolicy(opts: {
  enabledFeature?: DocumentData | null;
  hoursFeature?: DocumentData | null;
  studentType?: string | null;
  planKey?: string | null;
  planId?: string | null;
}): RollingWindowPolicy {
  const DEFAULT_HOURS = 24;
  const enabled = opts.enabledFeature?.enabled;
  if (enabled === true || enabled === false) {
    if (!enabled) return {enforced: false, hours: DEFAULT_HOURS};
    const raw = opts.hoursFeature?.feature_value ?? opts.hoursFeature?.value;
    const parsed =
      typeof raw === "number" && Number.isFinite(raw) ?
        Math.round(raw) :
        DEFAULT_HOURS;
    return {enforced: true, hours: Math.min(168, Math.max(1, parsed))};
  }
  // Never `planKey == "free"` alone: plans/guest shares that key.
  // Center Free identity = plan document ID (free, post-migration) together
  // with student_type center_student. The legacy "center_free" spellings
  // (document ID and the pre-seed plan_key convention) are accepted
  // transitionally and removed once the migration has converged.
  const legacy =
    opts.studentType === "center_student" &&
    (opts.planId === "free" ||
      opts.planId === "center_free" ||
      opts.planKey === "center_free");
  return {enforced: legacy, hours: DEFAULT_HOURS};
}

async function deriveScryptKey(
  password: string,
  salt: Buffer,
  keyLength: number,
  options: {N: number; r: number; p: number},
): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    scryptCallback(
      password,
      salt,
      keyLength,
      options,
      (error: Error | null, derivedKey: Buffer) => {
        if (error) {
          reject(error);
          return;
        }
        resolve(derivedKey);
      },
    );
  });
}

async function hashPassword(password: string): Promise<string> {
  const cost = 16384;
  const salt = randomBytes(16);
  const derived = await deriveScryptKey(password, salt, 64, {N: cost, r: 8, p: 1});
  return `scrypt$${salt.toString("hex")}$${derived.toString("hex")}$${cost}`;
}

const MAX_NOTIFICATION_RETRIES = 3;
const RETRY_DELAY_MINUTES = [1, 5, 15];
const CRITICAL_NOTIFICATION_TYPES = new Set(["approval", "payment", "security"]);
const EGYPT_PHONE_REGEX = /^01[0125][0-9]{8}$/;
const ADMIN_ROLES = new Set(["admin", "doctor"]);

function dataOf(value: DocumentData | undefined) {
  return value ?? {};
}

function getString(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : null;
}

function getNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function normalizeEgyptianPhone(value: unknown): string | null {
  const phone = getString(value);
  if (!phone || !EGYPT_PHONE_REGEX.test(phone)) return null;
  return phone;
}

const CANONICAL_STUDENT_GRADES = new Set([
  "grade_one",
  "grade_two",
  "grade_three",
  "grade_four",
]);

/**
 * Normalizes a raw grade input into its canonical `grade_*` key.
 *
 * Only the canonical key is ever persisted to `users/{studentId}.grade`;
 * UI labels (e.g. "Grade Two") and legacy spellings (e.g. "grade_2")
 * are mapped — never written verbatim. Returns null when unparseable.
 * Mirrors `normalizeAdminGradeKey` in `lib/features/admin/domain/admin_grades.dart`.
 * @param {unknown} value Raw grade input from the callable request.
 * @return {string|null} Canonical grade key, or null when unparseable.
 */
function normalizeStudentGrade(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const normalized = value.trim().toLowerCase();
  if (CANONICAL_STUDENT_GRADES.has(normalized)) return normalized;
  const aliases: Record<string, string> = {
    "1": "grade_one",
    "grade_1": "grade_one",
    "grade 1": "grade_one",
    "grade one": "grade_one",
    "2": "grade_two",
    "grade_2": "grade_two",
    "grade 2": "grade_two",
    "grade two": "grade_two",
    "3": "grade_three",
    "grade_3": "grade_three",
    "grade 3": "grade_three",
    "grade three": "grade_three",
    "4": "grade_four",
    "grade_4": "grade_four",
    "grade 4": "grade_four",
    "grade four": "grade_four",
  };
  return aliases[normalized] ?? null;
}

function getNotificationType(data: DocumentData): string {
  const value = data.notification_type ?? data.type ?? "system";
  return typeof value === "string" ? value : "system";
}

function getGroupingKey(userId: string, notificationType: string, subjectId?: string): string {
  return `${userId}:${notificationType}:${subjectId ?? "none"}`;
}

function getQuietHoursConfig(userData: DocumentData) {
  const quietHours = userData.quiet_hours;
  if (!quietHours || typeof quietHours !== "object" || quietHours.enabled !== true) return null;
  if (typeof quietHours.start !== "string" || typeof quietHours.end !== "string") return null;

  const timezone =
    typeof quietHours.timezone === "string" && quietHours.timezone.length > 0 ?
      quietHours.timezone :
      "Africa/Cairo";

  return {start: quietHours.start, end: quietHours.end, timezone};
}

function timeToMinutes(value: string): number | null {
  const parts = value.split(":");
  if (parts.length !== 2) return null;
  const hours = Number(parts[0]);
  const minutes = Number(parts[1]);
  if (!Number.isInteger(hours) || !Number.isInteger(minutes)) return null;
  if (hours < 0 || hours > 23 || minutes < 0 || minutes > 59) return null;
  return hours * 60 + minutes;
}

function isWithinQuietHours(config: ReturnType<typeof getQuietHoursConfig>): boolean {
  if (!config) return false;
  const start = timeToMinutes(config.start);
  const end = timeToMinutes(config.end);
  if (start === null || end === null) return false;

  try {
    const formatter = new Intl.DateTimeFormat("en-US", {
      timeZone: config.timezone,
      hour: "2-digit",
      minute: "2-digit",
      hourCycle: "h23",
    });
    const parts = formatter.formatToParts(new Date());
    const hour = parts.find((part) => part.type === "hour")?.value;
    const minute = parts.find((part) => part.type === "minute")?.value;
    if (!hour || !minute) return false;

    const current = Number(hour) * 60 + Number(minute);
    if (start === end) return true;
    if (start < end) return current >= start && current < end;
    return current >= start || current < end;
  } catch {
    return false;
  }
}

function isCriticalNotification(
  notificationType: string,
  data: DocumentData,
): boolean {
  return data.priority === "critical" || CRITICAL_NOTIFICATION_TYPES.has(notificationType);
}

function callerRole(request: CallableRequest<unknown>): string | null {
  const role = request.auth?.token?.role;
  return typeof role === "string" ? role : null;
}

function requireAuthenticated(request: CallableRequest<unknown>): string {
  const uid = request.auth?.uid;
  if (typeof uid !== "string" || uid.length === 0) {
    throw new HttpsError("unauthenticated", "Authentication is required.");
  }
  return uid;
}

function requireDoctor(request: CallableRequest<unknown>): string {
  const uid = requireAuthenticated(request);
  if (callerRole(request) !== "doctor") {
    throw new HttpsError("permission-denied", "Doctor (Platform Owner) permission is required.");
  }
  return uid;
}

function requireAdminOrDoctor(request: CallableRequest<unknown>): string {
  const uid = requireAuthenticated(request);
  const role = callerRole(request);
  if (!role || !ADMIN_ROLES.has(role)) {
    throw new HttpsError("permission-denied", "Admin or Doctor permission is required.");
  }
  return uid;
}

/**
 * Single staff claims synchronizer (doctor/admin).
 *
 * Persists the authoritative Firestore role to the stored Firebase Auth
 * custom claims at the trusted backend login boundary. Role is always
 * supplied by the caller from the Firestore user record — never from
 * client input. Existing claims are merged so valid entries (e.g.
 * max_devices) and any other unrelated claims are preserved; only role,
 * approved, and force_password_change are normalized. Skips the write
 * when the stored claims already match.
 * @param {string} userId Staff Firebase Auth UID.
 * @param {string} role Authoritative role from the Firestore user record.
 * @param {boolean} forcePasswordChange Force-password-change flag from Firestore.
 */
async function syncStaffStoredClaims(userId: string, role: string, forcePasswordChange: boolean): Promise<void> {
  const current = await auth.getUser(userId);
  const existing = current.customClaims ?? {};
  const next = {
    ...existing,
    role,
    approved: true,
    force_password_change: forcePasswordChange,
  };
  if (
    existing.role === next.role &&
    existing.approved === true &&
    existing.force_password_change === next.force_password_change
  ) {
    return;
  }
  await auth.setCustomUserClaims(userId, next);
}

/**
 * Repairs the identity claims owned by the student approval flow.
 *
 * `onStudentApproved` is the primary writer, but it is a Firestore trigger:
 * if it fails (or the account was approved before it was deployed) the user
 * stays approved in Firestore while Firebase Auth keeps no (or partial)
 * stored claims. `onLoginAttempt` authorizes on `request.auth.token.role`,
 * and `getIdTokenResult(true)` drops the one-time custom-token claims, so a
 * missing stored `role` locks the student out of device binding even though
 * the password was correct.
 *
 * This synchronizer runs at the trusted login boundary and only restores
 * what the Firestore record already authorizes: role, student_type, approved,
 * and force_password_change. Existing claims are merged so plan/subscription
 * claims are preserved untouched (ADR-004 resolves entitlements server-side
 * at access time, never from a client-refreshed token). The write is skipped
 * when the stored claims already match.
 * @param {string} userId Student Firebase Auth UID.
 * @param {string} studentType Authoritative student type from Firestore.
 * @param {boolean} forcePasswordChange Force-password-change flag from Firestore.
 */
async function syncStudentStoredClaims(
  userId: string,
  studentType: string,
  forcePasswordChange: boolean,
): Promise<void> {
  const current = await auth.getUser(userId);
  const existing = current.customClaims ?? {};
  const next = {
    ...existing,
    role: "student",
    student_type: studentType,
    approved: true,
    force_password_change: forcePasswordChange,
  };
  if (
    existing.role === next.role &&
    existing.student_type === next.student_type &&
    existing.approved === true &&
    existing.force_password_change === next.force_password_change
  ) {
    return;
  }
  await auth.setCustomUserClaims(userId, next);
}

async function requireStudentAccessManager(request: CallableRequest<unknown>): Promise<{
  actorId: string;
  actorRole: "doctor" | "admin";
  permissionBasis: "doctor" | "delegated:admin_students";
}> {
  const actorId = requireAuthenticated(request);
  const role = callerRole(request);
  if (role === "doctor") {
    return {actorId, actorRole: "doctor", permissionBasis: "doctor"};
  }
  if (role !== "admin") {
    throw new HttpsError("permission-denied", "Subject Access management permission is required.");
  }

  const permissionSnap = await db.collection("admin_permissions").doc(actorId).get();
  const permissionData = dataOf(permissionSnap.data());
  const permissions = permissionData.permissions;
  if (
    permissionData.is_active !== true ||
    !permissions ||
    typeof permissions !== "object" ||
    permissions.admin_students !== true
  ) {
    throw new HttpsError("permission-denied", "Delegated student-management permission is required.");
  }

  return {actorId, actorRole: "admin", permissionBasis: "delegated:admin_students"};
}

async function requirePasswordResetManager(request: CallableRequest<unknown>): Promise<{
  actorId: string;
  actorRole: "doctor" | "admin";
  permissionBasis: "doctor" | "delegated:password_reset";
}> {
  const actorId = requireAuthenticated(request);
  const role = callerRole(request);
  if (role === "doctor") {
    return {actorId, actorRole: "doctor", permissionBasis: "doctor"};
  }
  if (role !== "admin") {
    throw new HttpsError("permission-denied", "Password reset permission is required.");
  }

  const permissionSnap = await db.collection("admin_permissions").doc(actorId).get();
  const permissionData = dataOf(permissionSnap.data());
  const permissions = permissionData.permissions;
  if (
    permissionData.is_active !== true ||
    !permissions ||
    typeof permissions !== "object" ||
    (permissions.password_reset !== true)
  ) {
    throw new HttpsError("permission-denied", "Delegated password-reset permission is required.");
  }

  return {actorId, actorRole: "admin", permissionBasis: "delegated:password_reset"};
}

async function requireEnabledSubjectAccess(studentId: string, subjectId: string): Promise<DocumentData> {
  const assignmentId = `${studentId}_${subjectId}`;
  const assignmentSnap = await db.collection("subject_access_assignments").doc(assignmentId).get();
  if (!assignmentSnap.exists) {
    throw new HttpsError("permission-denied", "Subject Access assignment is required.");
  }

  const assignment = dataOf(assignmentSnap.data());
  assertEnabledSubjectAccess(studentId, subjectId, assignment);
  return assignment;
}

// Pure field predicates of requireEnabledSubjectAccess, factored so a
// request-scoped caller holding an already-read assignment snapshot can
// re-apply the IDENTICAL verification without re-reading. Existence is
// established by the reader (missing docs throw there); these predicates
// reproduce the exact mismatch verdict. Never skips verification.
function assertEnabledSubjectAccess(studentId: string, subjectId: string, assignment: DocumentData): void {
  if (
    assignment.student_id !== studentId ||
    assignment.subject_id !== subjectId ||
    assignment.is_deleted === true ||
    assignment.enabled !== true
  ) {
    throw new HttpsError("permission-denied", "Subject Access is not enabled for this subject.");
  }
}


// ---------------------------------------------------------------------------
// Subject-Level Device Authorization (ADR-004).
// The `devices` collection is a registry/audit trail only and never decides
// authorization. Authorization lives in `subject_device_authorizations` keyed
// by Student + Subject + Device. Guest is a computed outcome, never a record.
// ---------------------------------------------------------------------------

function normalizeDeviceId(value: unknown): string | null {
  const deviceId = getString(value);
  return deviceId;
}

function computeDeviceHash(userId: string, deviceId: string): string {
  return createHash("sha256").update(`${userId}|${deviceId}`).digest("hex");
}

function subjectAuthorizationId(studentId: string, subjectId: string, deviceHash: string): string {
  return `${studentId}_${subjectId}_${deviceHash}`;
}

async function requireDeviceManager(request: CallableRequest<unknown>): Promise<{
  actorId: string;
  actorRole: "doctor" | "admin";
  permissionBasis: "doctor" | "delegated:admin_devices";
}> {
  const actorId = requireAuthenticated(request);
  const role = callerRole(request);
  if (role === "doctor") {
    return {actorId, actorRole: "doctor", permissionBasis: "doctor"};
  }
  if (role !== "admin") {
    throw new HttpsError("permission-denied", "Device management permission is required.");
  }

  const permissionSnap = await db.collection("admin_permissions").doc(actorId).get();
  const permissionData = dataOf(permissionSnap.data());
  const permissions = permissionData.permissions;
  if (
    permissionData.is_active !== true ||
    !permissions ||
    typeof permissions !== "object" ||
    permissions.admin_devices !== true
  ) {
    throw new HttpsError("permission-denied", "Delegated device-management permission is required.");
  }

  return {actorId, actorRole: "admin", permissionBasis: "delegated:admin_devices"};
}

async function writeDeviceAudit(entry: {
  action: string;
  targetId: string;
  actorId: string;
  actorRole: string;
  permissionBasis: string;
  details?: Record<string, unknown>;
}): Promise<void> {
  const now = FieldValue.serverTimestamp();
  await db.collection("admin_audit_log").add({
    action: entry.action,
    entity: "subject_device_authorizations",
    target_id: entry.targetId,
    actor_id: entry.actorId,
    actor_role: entry.actorRole,
    permission_basis: entry.permissionBasis,
    details: entry.details ?? {},
    created_at: now,
    timestamp: now,
  });
}

async function getSubjectAllowance(planId: string, planFeatures?: DocumentData[]): Promise<number> {
  // Request-scoped consolidation: when the caller already holds the plan's
  // full feature set, derive from it (identical values, no re-query).
  // Standalone callers omit it and keep the exact legacy query behavior.
  const feature = planFeatures !== undefined
    ? findPlanFeature(planFeatures, "device.max_count")
    : await getPlanFeature(planId, "device.max_count");
  const allowance = getNumber(feature?.feature_value);
  if (allowance === null || allowance < 1) {
    throw new HttpsError("failed-precondition", "device.max_count is not configured for the active plan.");
  }
  return Math.floor(allowance);
}

async function getActiveSubjectSubscription(studentId: string, subjectId: string) {
  const subscriptionSnap = await db.collection("subscriptions")
    .where("student_id", "==", studentId)
    .where("subject_id", "==", subjectId)
    .where("status", "==", "active")
    .limit(1)
    .get();
  if (subscriptionSnap.empty) {
    throw new HttpsError("permission-denied", "Active subject subscription is required.");
  }
  const subscription = dataOf(subscriptionSnap.docs[0].data());
  assertSubjectAccess(subscription);
  const planId = getString(subscription.plan_id);
  if (!planId) throw new HttpsError("failed-precondition", "Subject subscription plan is missing.");
  const planSnap = await db.collection("plans").doc(planId).get();
  if (!planSnap.exists || dataOf(planSnap.data()).is_active !== true) {
    throw new HttpsError("failed-precondition", "Subject subscription plan is not available.");
  }
  return {subscription, planId, plan: dataOf(planSnap.data())};
}

type RegistryOutcome = {kind: "existing" | "created"; deviceDocId: string};

// Server-owned device registration. Upserts the registry row for
// (user, client-asserted device identity) and returns it. Never decides
// authorization, never rejects, never evicts.
async function registerKnownDevice(input: {
  userId: string;
  deviceId: string;
  deviceName?: string | null;
  platform?: string;
  osVersion?: string | null;
  appVersion?: string | null;
  ipAddress?: string | null;
}): Promise<RegistryOutcome> {
  const devicesRef = db.collection("devices");
  const existingSnap = await devicesRef
    .where("user_id", "==", input.userId)
    .where("device_id", "==", input.deviceId)
    .limit(1)
    .get();
  const now = FieldValue.serverTimestamp();
  if (!existingSnap.empty) {
    const existing = existingSnap.docs[0];
    await existing.ref.update({
      device_name: input.deviceName ?? dataOf(existing.data()).device_name ?? null,
      platform: input.platform ?? "unknown",
      os_version: input.osVersion ?? null,
      app_version: input.appVersion ?? null,
      last_login: now,
      ip_last_seen: input.ipAddress ?? null,
      updated_at: now,
      updated_by: "system",
    });
    return {kind: "existing", deviceDocId: existing.id};
  }
  const created = await devicesRef.add({
    user_id: input.userId,
    device_id: input.deviceId,
    device_name: input.deviceName ?? null,
    platform: input.platform ?? "unknown",
    os_version: input.osVersion ?? null,
    app_version: input.appVersion ?? null,
    last_login: now,
    ip_last_seen: input.ipAddress ?? null,
    fcm_token: null,
    created_at: now,
    updated_at: now,
    created_by: "system",
    updated_by: "system",
    is_deleted: false,
    deleted_at: null,
    deleted_by: null,
  });
  return {kind: "created", deviceDocId: created.id};
}

async function assertLectureAccessNotDenied(studentId: string, lectureId: string): Promise<void> {
  const grantSnap = await db
    .collection("lecture_access_grants")
    .doc(lectureAccessGrantId(lectureId, studentId))
    .get();
  if (grantSnap.exists && isLectureAccessDenied(dataOf(grantSnap.data()))) {
    throw new HttpsError("permission-denied", LECTURE_ACCESS_DENIED_MESSAGE);
  }
}


async function writeAnalyticsEvent(
  userId: string,
  eventType: string,
  referenceId: string,
  metadata: Record<string, unknown> = {},
  request?: CallableRequest<Record<string, unknown>>,
) {
  await db.collection("analytics_events").add({
    user_id: userId,
    event_type: eventType,
    reference_id: referenceId,
    metadata,
    device_id: getString(request?.data?.deviceId),
    ip_address: request?.rawRequest?.ip ?? null,
    user_agent: request?.rawRequest?.headers?.["user-agent"] ?? null,
    created_at: FieldValue.serverTimestamp(),
    created_by: "system",
  });
}

async function getDeviceTokens(userId: string, onlyDeviceIds?: Set<string>) {
  const devicesSnap = await db.collection("devices").where("user_id", "==", userId).get();
  const devices: Array<{id: string; token: string}> = [];

  for (const doc of devicesSnap.docs) {
    if (onlyDeviceIds && !onlyDeviceIds.has(doc.id)) continue;
    const data = dataOf(doc.data());
    // ADR-004: `active_device` no longer carries authorization meaning, so
    // notification routing ignores it. Registry rows are eligible whenever
    // they hold a usable token and are not soft-deleted.
    if (
      data.is_deleted === true ||
      typeof data.fcm_token !== "string" ||
      data.fcm_token.trim().length === 0
    ) continue;
    devices.push({id: doc.id, token: data.fcm_token});
  }

  return devices;
}

async function removeInvalidToken(deviceId: string) {
  await db.collection("devices").doc(deviceId).update({
    fcm_token: null,
    updated_at: FieldValue.serverTimestamp(),
    updated_by: "system",
  });
}

async function moveToDeadLetterQueue(
  notificationId: string,
  notificationData: DocumentData,
  reason: string,
  attempts: number,
) {
  await db.collection("notification_dlq").doc().set({
    notification_id: notificationId,
    user_id: notificationData.user_id ?? null,
    notification_type: getNotificationType(notificationData),
    title: notificationData.title ?? null,
    body: notificationData.body ?? null,
    failure_reason: reason,
    attempts,
    failed_at: FieldValue.serverTimestamp(),
    status: "pending",
    created_at: FieldValue.serverTimestamp(),
    created_by: "system",
  });
}

async function scheduleRetry(
  notificationId: string,
  notificationData: DocumentData,
  attempt: number,
  errorMessage: string,
  failedDeviceIds: string[],
) {
  const delayMinutes = RETRY_DELAY_MINUTES[attempt - 1] ?? RETRY_DELAY_MINUTES[RETRY_DELAY_MINUTES.length - 1];
  const nextAttemptAt = Timestamp.fromMillis(Date.now() + delayMinutes * 60 * 1000);

  await db.collection("notifications").doc(notificationId).collection("retries").add({
    notification_id: notificationId,
    user_id: notificationData.user_id ?? null,
    attempt,
    max_attempts: MAX_NOTIFICATION_RETRIES,
    failed_device_ids: failedDeviceIds,
    status: "pending",
    last_error: errorMessage,
    next_attempt_at: nextAttemptAt,
    created_at: FieldValue.serverTimestamp(),
    updated_at: FieldValue.serverTimestamp(),
  });
}

async function getPlanFeature(planId: string, featureKey: string): Promise<DocumentData | null> {
  const snap = await db
    .collection("plan_features")
    .where("plan_id", "==", planId)
    .where("feature_key", "==", featureKey)
    .limit(1)
    .get();
  return snap.empty ? null : snap.docs[0].data();
}

async function getPlanFeatures(planId: string): Promise<DocumentData[]> {
  const snap = await db
    .collection("plan_features")
    .where("plan_id", "==", planId)
    .get();
  return snap.docs.map((doc) => doc.data());
}

// Request-scoped lookup into ONE getPlanFeatures result. Mirrors
// getPlanFeature's single-doc contract (first match wins; null when absent)
// so consolidated readers observe identical values without re-querying.
// Plan feature keys are unique per plan; no ordering assumption beyond that.
function findPlanFeature(
  features: DocumentData[],
  featureKey: string,
): DocumentData | null {
  for (const feature of features) {
    if (feature.feature_key === featureKey) return feature;
  }
  return null;
}

function qualityRank(value: string): number {
  const ranks: Record<string, number> = {
    "144p": 144,
    "240p": 240,
    "360p": 360,
    "480p": 480,
    "720p": 720,
    "1080p": 1080,
    "1440p": 1440,
    "2k": 1440,
    "4k": 2160,
  };
  return ranks[value.toLowerCase()] ?? 0;
}

// P1 web fix: Bunny Stream MP4 fallback files exist only up to 1080p
// (play_144p..play_1080p.mp4). Maps a clamped rank back to a filename
// quality so higher plan qualities degrade to a real file, never a 404.
function mp4QualityForRank(rank: number): string {
  if (rank >= 1080) return "1080p";
  if (rank >= 720) return "720p";
  if (rank >= 480) return "480p";
  if (rank >= 360) return "360p";
  if (rank >= 240) return "240p";
  return "144p";
}

// ADR-004: removed `getUserPlan` (global single-plan resolution with system
// default fallback). It embodied the retired global-plan model: an arbitrary
// subscription could decide authorization for every Subject. All callers now
// resolve the Subject's own subscription directly (see
// `getActiveSubjectSubscription`). Per-Subject plan selection by explicit ID
// remains available to future flows through direct plan reads.
async function createNotification(
  userId: string,
  type: string,
  title: string,
  body: string,
  options: Record<string, unknown> = {},
) {
  return db.collection("notifications").add({
    user_id: userId,
    notification_type: type,
    title,
    body,
    is_read: false,
    priority: options.priority ?? "normal",
    subject_id: options.subject_id ?? null,
    deep_link: options.deep_link ?? null,
    image_url: options.image_url ?? null,
    actions: options.actions ?? [],
    delivery_status: "pending",
    created_at: FieldValue.serverTimestamp(),
    created_by: "system",
  });
}

async function notifyUsersByRole(
  role: string,
  type: string,
  title: string,
  body: string,
  options: Record<string, unknown> = {},
) {
  const usersSnap = await db.collection("users").where("role", "==", role).get();
  for (const user of usersSnap.docs) {
    await createNotification(user.id, type, title, body, options);
  }
}

async function notifyAdminsWithPermission(
  permissionKey: string,
  type: string,
  title: string,
  body: string,
  options: Record<string, unknown> = {},
) {
  await notifyUsersByRole("doctor", type, title, body, options);

  const permissionsSnap = await db.collection("admin_permissions")
    .where("is_active", "==", true)
    .get();

  for (const permDoc of permissionsSnap.docs) {
    const data = permDoc.data();
    const permissions = data.permissions;
    if (
      permissions &&
      (permissions[permissionKey] === true)
    ) {
      await createNotification(permDoc.id, type, title, body, options);
    }
  }
}

function passwordHashParts(passwordHash: string) {
  const parts = passwordHash.split("$");
  if (parts.length !== 4 || parts[0] !== "scrypt") return null;
  return {salt: parts[1], expectedHex: parts[2], cost: Number(parts[3])};
}

async function verifyPassword(password: string, passwordHash: string): Promise<boolean> {
  const parts = passwordHashParts(passwordHash);
  if (!parts || !parts.salt || !parts.expectedHex) return false;
  const cost = Number.isInteger(parts.cost) && parts.cost >= 1024 ? parts.cost : 16384;
  const derived = await deriveScryptKey(password, Buffer.from(parts.salt, "hex"), 64, {N: cost, r: 8, p: 1});
  const expected = Buffer.from(parts.expectedHex, "hex");
  return expected.length === derived.length && timingSafeEqual(expected, derived);
}

function hashPathToken(secret: string, path: string, expires: number): string {
  return createHash("sha256")
    .update(`${secret}${path}${expires}`)
    .digest("base64url");
}

// Video-zone directory token (Bunny Advanced / HMAC-SHA256, directory mode).
// Verified live against pull zone vz-c6abe953-876. Query-string tokens
// cannot work for HLS: rendition/segment URLs are relative and URI
// resolution drops the parent query, so children arrive unauthenticated.
// The path-embedded token below travels INSIDE the URL path, hence every
// relative child resolved beneath it inherits authentication automatically.
// Official BunnyWay/BunnyCDN.TokenAuthentication construction
// (isDirectory=true with token_path scope): message = scope + expires +
// signingData(`token_path=<scope>`); embedded as
// `/bcdn_token=<token>&token_path=<enc>&expires=<exp>` ahead of the path.
// Scoped to Stream video URLs ONLY — the storage-zone signer above is
// untouched (its enforced mode is unverified; do not unify without proof).
function hashVideoDirectoryToken(
  secret: string,
  directoryScope: string,
  expires: number,
): string {
  const signingData = `token_path=${directoryScope}`;
  const signature = createHmac("sha256", secret)
    .update(directoryScope)
    .update(String(expires))
    .update(signingData)
    .digest("base64url");
  return `HS256-${signature}`;
}

class NotificationDeliveryError extends Error {
  readonly failedDeviceIds: string[];

  constructor(message: string, failedDeviceIds: string[]) {
    super(message);
    this.name = "NotificationDeliveryError";
    this.failedDeviceIds = failedDeviceIds;
  }
}

function getEnv(name: string): string {
  const value = process.env[name];
  if (!value) throw new HttpsError("failed-precondition", `Server configuration ${name} is missing.`);
  return value;
}

// Signed URL for any file under a video's directory scope (posters,
// custom thumbnails). Same scheme/validity as playback signing.
function buildBunnyFileUrl(
  videoId: string,
  fileName: string,
  expiresInSeconds = 3600,
): string {
  const template = getEnv("BUNNY_PLAYBACK_URL_TEMPLATE");
  const probe = template
    .replace("{video_id}", "0")
    .replace("{videoId}", "0")
    .replace("{id}", "0")
    .replace("{quality}", "720p")
    .replace("{res}", "720p");
  const origin = new URL(probe).origin;
  const secret = getEnv("BUNNY_TOKEN_KEY");
  const expires = Math.floor(Date.now() / 1000) + expiresInSeconds;
  const scope = `/${videoId}/`;
  const token = hashVideoDirectoryToken(secret, scope, expires);
  return `${origin}/bcdn_token=${token}` +
    `&token_path=${encodeURIComponent(scope)}` +
    `&expires=${expires}/${videoId}/${fileName}`;
}

// ---- Bunny Stream poster filename lookup (card/cover thumbnails) ----
// The selected poster is NOT always `thumbnail.jpg` (custom selections
// live under their own filename) — the only authoritative source is the
// Stream API (`thumbnailFileName`). Optional by design: configured via
// functions/.env (gitignored, never committed):
//   BUNNY_STREAM_API_KEY=<library API key>
//   BUNNY_STREAM_LIBRARY_ID=<numeric library id>
// Unset → null (callers keep their existing fallbacks). Results cached
// per video (1h positive, 10min negative); never throws.
interface BunnyPosterCacheEntry {
  file: string | null;
  hasHQPreview: boolean;
  cachedAt: number;
}
const bunnyPosterCache = new Map<string, BunnyPosterCacheEntry>();
const BUNNY_POSTER_CACHE_TTL_MS = 60 * 60 * 1000;
const BUNNY_POSTER_NEG_TTL_MS = 10 * 60 * 1000;

function bunnyStreamApiConfig(): {apiKey: string; libraryId: string} | null {
  const apiKey = (process.env.BUNNY_STREAM_API_KEY ?? "").trim();
  const libraryId = (process.env.BUNNY_STREAM_LIBRARY_ID ?? "").trim();
  return apiKey !== "" && libraryId !== "" ? {apiKey, libraryId} : null;
}

// Stream video metadata needed for display media: the selected poster
// filename plus whether an HQ animated preview exists. Cached per video
// (1h positive, 10min negative); never throws (null on any failure or
// when unconfigured).
async function fetchBunnyVideoMeta(
  videoId: string,
): Promise<{file: string | null; hasHQPreview: boolean} | null> {
  const now = Date.now();
  const cached = bunnyPosterCache.get(videoId);
  if (cached) {
    const ttl = cached.file || cached.hasHQPreview ?
      BUNNY_POSTER_CACHE_TTL_MS :
      BUNNY_POSTER_NEG_TTL_MS;
    if (now - cached.cachedAt < ttl) {
      return {file: cached.file, hasHQPreview: cached.hasHQPreview};
    }
  }
  const config = bunnyStreamApiConfig();
  if (!config) return null;
  try {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 8000);
    let response: Response;
    try {
      response = await fetch(
        `https://video.bunnycdn.com/library/${encodeURIComponent(config.libraryId)}` +
          `/videos/${encodeURIComponent(videoId)}`,
        {headers: {AccessKey: config.apiKey}, signal: controller.signal},
      );
    } finally {
      clearTimeout(timer);
    }
    if (!response.ok) {
      bunnyPosterCache.set(videoId, {file: null, hasHQPreview: false, cachedAt: now});
      return null;
    }
    const data = (await response.json()) as {
      thumbnailFileName?: unknown;
      thumbnailUrl?: unknown;
      hasHighQualityPreview?: unknown;
    };
    const direct = getString(data.thumbnailFileName);
    let file: string | null = null;
    if (direct) {
      file = direct;
    } else {
      const thumbUrl = getString(data.thumbnailUrl);
      const last = thumbUrl?.split("?")[0].split("/").pop();
      if (last) file = last;
    }
    const meta = {file, hasHQPreview: data.hasHighQualityPreview === true};
    bunnyPosterCache.set(videoId, {...meta, cachedAt: now});
    return meta;
  } catch {
    bunnyPosterCache.set(videoId, {file: null, hasHQPreview: false, cachedAt: now});
    return null;
  }
}

// P2 thumbnail policy (top-level so the single-lecture listing and the
// batched section-media endpoint share it): raw `thumbnail` storage path
// → renderable short-lived URL (direct http(s) passes through, bunny
// paths get a token URL, firebase paths an Admin-SDK signed URL).
// Best-effort — null on any failure.
async function resolveResourceThumbnailUrl(
  resource: DocumentData,
): Promise<string | null> {
  const raw = getString(resource.thumbnail);
  if (!raw) return null;
  if (isDirectThumbnailUrl(raw)) return raw;
  const provider = getString(resource.thumbnail_storage_provider) ??
    getString(resource.thumbnailStorageProvider);
  try {
    if (provider === "bunny") {
      return buildBunnyResourceAccessUrl(raw, 3600).url;
    }
    const [signedUrl] = await storage.bucket().file(raw).getSignedUrl({
      action: "read",
      expires: Date.now() + 60 * 60 * 1000,
    });
    return signedUrl;
  } catch {
    return null;
  }
}

// Full display media for one resource document: explicit thumbnail first,
// then the signed Bunny poster fallback chain, plus the signed silent HQ
// preview clip (`preview_hq.mp4`, muted looping header autoplay) when the
// Stream API confirms one exists. Read-only — never touches
// windows/issuance/sessions.
async function resolveVideoDisplayMedia(
  resource: DocumentData,
): Promise<{thumbnailUrl: string | null; previewUrl: string | null}> {
  let thumbnailUrl = await resolveResourceThumbnailUrl(resource);
  let previewUrl: string | null = null;
  const storedBunnyId = getString(resource.bunny_video_id);
  const posterId = storedBunnyId ?
    (normalizeBunnyVideoIdForLookup(storedBunnyId) ?? storedBunnyId) :
    null;
  let meta: {file: string | null; hasHQPreview: boolean} | null = null;
  if (posterId) {
    try {
      meta = await fetchBunnyVideoMeta(posterId);
    } catch {
      meta = null;
    }
  }
  if (!thumbnailUrl && posterId) {
    try {
      thumbnailUrl = buildBunnyFileUrl(
        posterId,
        meta?.file ?? "thumbnail.jpg",
        3600,
      );
    } catch {
      thumbnailUrl = null;
    }
  }
  const isVideoRow =
    (getString(resource.resource_type) ?? "attachment") === "video" &&
    posterId != null;
  if (isVideoRow && posterId && meta?.hasHQPreview === true) {
    try {
      previewUrl = buildBunnyFileUrl(posterId, "preview_hq.mp4", 3600);
    } catch {
      previewUrl = null;
    }
  }
  return {thumbnailUrl, previewUrl};
}

const VIDEO_RATE_LIMIT_WINDOW_MS = 60_000;
const VIDEO_RATE_LIMIT_MAX_REQUESTS = 30;

async function assertVideoRequestAllowed(userId: string, deviceId: string) {
  if (!/^[a-zA-Z0-9._:-]{16,200}$/.test(deviceId)) {
    throw new HttpsError("invalid-argument", "A valid device identifier is required.");
  }

  const windowStart = Math.floor(Date.now() / VIDEO_RATE_LIMIT_WINDOW_MS) * VIDEO_RATE_LIMIT_WINDOW_MS;
  const key = createHash("sha256")
    .update(`${userId}:${deviceId}:${windowStart}`)
    .digest("hex");
  const ref = db.collection("video_rate_limits").doc(key);

  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const currentCount = Number(snapshot.data()?.count ?? 0);
    if (currentCount >= VIDEO_RATE_LIMIT_MAX_REQUESTS) {
      throw new HttpsError("resource-exhausted", "Too many video requests. Please retry shortly.");
    }
    transaction.set(ref, {
      user_id: userId,
      device_hash: createHash("sha256").update(deviceId).digest("hex"),
      window_start: Timestamp.fromMillis(windowStart),
      count: currentCount + 1,
      updated_at: FieldValue.serverTimestamp(),
    }, {merge: true});
  });
}

function assertSubjectAccess(subscription: DocumentData | undefined) {
  if (!subscription) throw new HttpsError("permission-denied", "Subject subscription is required.");
  if (subscription.is_deleted === true) throw new HttpsError("permission-denied", "Subscription is deleted.");
  if (subscription.status !== "active" && subscription.status !== "trial") {
    throw new HttpsError("permission-denied", "Subscription is not active.");
  }
  if (subscription.manually_disabled === true) throw new HttpsError("permission-denied", "Subscription is disciplinarily disabled by the Doctor.");
  const endDate = subscription.end_date;
  if (endDate?.toMillis && endDate.toMillis() <= Date.now()) {
    throw new HttpsError("permission-denied", "Subscription has expired.");
  }
}

/**
 * Resolves the currently active core academic period (term_1, term_2 or
 * summer_course). This is the single authoritative source for subscription
 * boundaries; the legacy system_settings.current_term_end_date field is no
 * longer read anywhere.
 */
async function getActiveCoreAcademicPeriod(): Promise<{id: string; data: DocumentData}> {
  const snapshot = await db
    .collection("academic_periods")
    .where("is_core", "==", true)
    .where("status", "==", "active")
    .get();

  const periods = snapshot.docs
    .map((doc) => ({id: doc.id, data: dataOf(doc.data())}))
    .filter((period) => period.data.is_deleted !== true);

  if (periods.length === 0) {
    throw new HttpsError(
      "failed-precondition",
      "No active core academic period. The Doctor must start a period from the dashboard first.",
    );
  }

  periods.sort(
    (a, b) =>
      (typeof a.data.display_order === "number" ? a.data.display_order : 99) -
      (typeof b.data.display_order === "number" ? b.data.display_order : 99),
  );

  return periods[0];
}

/**
 * Subscription end date is derived from the active core academic period.
 * When the period has no explicit end_date yet, the subscription is stamped
 * with the period id and its end_date is backfilled automatically when the
 * Doctor ends the period (setAcademicPeriodStatus).
 */
async function resolveSubscriptionPeriodBinding(): Promise<{
  academicPeriodId: string;
  endDate: Timestamp | null;
}> {
  const period = await getActiveCoreAcademicPeriod();
  const endDate = period.data.end_date;
  return {
    academicPeriodId: period.id,
    endDate: endDate instanceof Timestamp ? endDate : null,
  };
}

export const registerNewStudent = onCall(SECURE_CALL_OPTS, async (request) => {
  const fullName = getString(request.data?.fullName);
  const phone = normalizeEgyptianPhone(request.data?.phoneNumber);
  const grade = getString(request.data?.grade);
  const password = getString(request.data?.password);
  const profilePhoto = getString(request.data?.profilePhoto);
  const customGroupId = getString(request.data?.customGroupId);
  const customGroupName = getString(request.data?.customGroupName);

  if (!fullName || !phone || !grade || !password) {
    throw new HttpsError("invalid-argument", "Full name, Egyptian phone number, grade and password are required.");
  }
  if (fullName.length > 100) {
    throw new HttpsError("invalid-argument", "Full name must be 100 characters or fewer.");
  }
  if (password.length < 6) {
    throw new HttpsError("invalid-argument", "Password must contain at least 6 characters.");
  }

  // Pre-lookup abuse gate: evaluated after shape validation (malformed
  // requests never consume budget) and before the users query, hashing,
  // Auth creation, and notification fan-out. Uniform rejection reveals
  // nothing about phone existence. Absent IP (emulator/local) skips the
  // gate, matching assertStaffDirectoryAllowed; Firestore errors propagate
  // and fail closed.
  const registrationIp = requestIp(request);
  if (registrationIp) {
    const registrationKey = createHash("sha256").update(`registration:${registrationIp}`).digest("hex");
    const registrationAllowed = await slidingWindowAllowed(
      REGISTRATION_THROTTLE_SCOPE,
      registrationKey,
      REGISTRATION_MAX_ATTEMPTS,
      REGISTRATION_WINDOW_MS,
    );
    if (!registrationAllowed) {
      await db.collection("auth_security_events").add({
        event_type: "registration_rate_limited",
        created_at: FieldValue.serverTimestamp(),
        created_by: "system",
      });
      throw new HttpsError("resource-exhausted", "Too many requests. Try again later.");
    }
  }

  const existing = await db.collection("users").where("phone_number", "==", phone).limit(1).get();
  if (!existing.empty) {
    throw new HttpsError("already-exists", "An account with this phone number already exists.");
  }

  const passwordHash = await hashPassword(password);
  let authUser: Awaited<ReturnType<typeof auth.createUser>> | null = null;

  try {
    authUser = await auth.createUser({displayName: fullName});
    const userRef = db.collection("users").doc(authUser.uid);
    const secretRef = db.collection("user_secrets").doc(authUser.uid);
    const now = FieldValue.serverTimestamp();

    const userData = {
      id: authUser.uid,
      full_name: fullName,
      display_handle: null,
      profile_photo: profilePhoto,
      phone_number: phone,
      role: "new_student",
      student_type: null,
      grade,
      custom_group_id: customGroupId ?? null,
      custom_group_name: customGroupName ?? null,
      approval_status: "pending",
      account_status: "active",
      current_device_id: null,
      password_last_changed_at: now,
      force_password_change: false,
      is_deleted: false,
      deleted_at: null,
      deleted_by: null,
      created_at: now,
      updated_at: now,
      created_by: "system",
      updated_by: "system",
    };

    const batch = db.batch();
    batch.set(userRef, userData);
    batch.set(secretRef, {
      user_id: authUser.uid,
      password_hash: passwordHash,
      created_at: now,
      updated_at: now,
    });
    await batch.commit();

    await writeAnalyticsEvent(authUser.uid, "Registration Submitted", authUser.uid, {
      phone_number: phone,
      grade,
      custom_group_id: customGroupId ?? null,
      approval_status: "pending",
    }, request);
    await notifyAdminsWithPermission(
      "admin_students",
      "registration",
      "New registration request",
      `${fullName} submitted a new student registration request.`,
      {priority: "normal"},
    );

    return {
      userId: authUser.uid,
      approvalStatus: "pending",
    };
  } catch (error) {
    if (authUser) {
      await auth.deleteUser(authUser.uid).catch(() => undefined);
      await db.collection("users").doc(authUser.uid).delete().catch(() => undefined);
      await db.collection("user_secrets").doc(authUser.uid).delete().catch(() => undefined);
    }
    if (error instanceof HttpsError) throw error;
    throw new HttpsError("internal", "Registration could not be completed.");
  }
});

const STRONG_PASSWORD_REGEX = /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[!@#$%^&*(),.?":{}|<>_\-+=[\]/\\`~]).{8,}$/;

export const changePassword = onCall(SECURE_CALL_OPTS, async (request) => {
  const userId = requireAuthenticated(request);
  // Role scope (intentional, unchanged): authenticated self-service for the
  // caller's OWN account only — any role (student/new_student/doctor/admin)
  // may rotate its own password here. Forced-password-change ENFORCEMENT is
  // student-only by approved product decision (mobile AuthGate +
  // forced_password_change_screen; "Doctor/Admin must never enter the forced
  // state" in forced_password_change_test). Doctor/Admin self-service use is
  // legitimate and must not be removed.
  const currentPassword = getString(request.data?.currentPassword);
  const newPassword = getString(request.data?.newPassword);

  if (!currentPassword || !newPassword) {
    throw new HttpsError("invalid-argument", "Current password and new password are required.");
  }

  if (newPassword.length < 8) {
    throw new HttpsError("invalid-argument", "Password must contain at least 8 characters.");
  }

  if (!STRONG_PASSWORD_REGEX.test(newPassword)) {
    throw new HttpsError(
      "invalid-argument",
      "Password must contain uppercase and lowercase letters, a number, and a special character.",
    );
  }

  // Throttle checked after auth + shape + policy validation (malformed and
  // weak-new-password requests never consume the budget) and before the
  // expensive scrypt verification. Firestore errors propagate fail-closed.
  await assertLoginNotLocked(CHANGE_PASSWORD_SCOPE, userId);

  const secretSnap = await db.collection("user_secrets").doc(userId).get();
  if (!secretSnap.exists) {
    throw new HttpsError("not-found", "User credentials record not found.");
  }

  const storedHash = getString(secretSnap.data()?.password_hash);
  if (!storedHash) {
    throw new HttpsError("failed-precondition", "Stored credentials are not initialized.");
  }

  const isValid = await verifyPassword(currentPassword, storedHash);
  if (!isValid) {
    await recordLoginFailure(CHANGE_PASSWORD_SCOPE, userId, CHANGE_PASSWORD_MAX_FAILURES);
    throw new HttpsError("permission-denied", "Current password is incorrect.");
  }

  const newHash = await hashPassword(newPassword);
  await auth.updateUser(userId, {password: newPassword});
  const currentUser = await auth.getUser(userId);
  const hadForcedChange =
    (currentUser.customClaims ?? {}).force_password_change === true;
  const claims = {...(currentUser.customClaims ?? {}), force_password_change: false};
  await auth.setCustomUserClaims(userId, claims);

  const now = FieldValue.serverTimestamp();
  await db.collection("users").doc(userId).update({
    force_password_change: false,
    password_last_changed_at: now,
    updated_at: now,
    updated_by: userId,
  });

  await db.collection("user_secrets").doc(userId).set({
    user_id: userId,
    password_hash: newHash,
    updated_at: now,
  }, {merge: true});

  await writeAnalyticsEvent(userId, "Password Changed", userId, {});
  // Completion confirmation (approved): when this rotation clears a FORCED
  // state, the earlier "Password Reset" notice ("sign in and change it")
  // goes stale the moment this succeeds — the student reads notifications
  // AFTER completing the change. Send a success notice so the latest item
  // states reality. Plain self-service rotations (no forced flag) stay
  // silent to avoid notification spam.
  if (hadForcedChange) {
    await createNotification(
      userId,
      "system",
      "تم تغيير كلمة المرور بنجاح",
      "كلمة المرور الجديدة تعمل الآن. كلمة المرور المؤقتة لم تعد صالحة.",
      {priority: "normal"},
    );
  }
  // Success clears ONLY this flow's throttle for this user. Login scopes,
  // per-account lockout counters, claims, and account state are untouched.
  await clearLoginFailures(CHANGE_PASSWORD_SCOPE, userId);
  return {success: true};
});

export const createCustomGroup = onCall(SECURE_CALL_OPTS, async (request) => {
  const doctorId = requireDoctor(request);
  const name = getString(request.data?.name);
  const description = getString(request.data?.description);
  const grade = getString(request.data?.grade);

  if (!name) throw new HttpsError("invalid-argument", "Group name is required.");

  const now = FieldValue.serverTimestamp();
  const groupRef = await db.collection("custom_groups").add({
    name,
    description: description ?? null,
    grade: grade ?? null,
    is_active: true,
    created_at: now,
    updated_at: now,
    created_by: doctorId,
    updated_by: doctorId,
  });

  await db.collection("admin_audit_log").add({
    action: "custom_group_created",
    entity: "custom_groups",
    target_id: groupRef.id,
    group_name: name,
    actor_id: doctorId,
    actor_role: "doctor",
    created_at: now,
    timestamp: now,
  });

  return {groupId: groupRef.id, name};
});

export const updateCustomGroup = onCall(SECURE_CALL_OPTS, async (request) => {
  const doctorId = requireDoctor(request);
  const groupId = getString(request.data?.groupId);
  const name = getString(request.data?.name);
  const description = getString(request.data?.description);
  const isActive = typeof request.data?.isActive === "boolean" ? request.data.isActive : undefined;

  if (!groupId) throw new HttpsError("invalid-argument", "groupId is required.");

  const groupRef = db.collection("custom_groups").doc(groupId);
  const snap = await groupRef.get();
  if (!snap.exists) throw new HttpsError("not-found", "Custom group not found.");

  const now = FieldValue.serverTimestamp();
  const updates: Record<string, unknown> = {
    updated_at: now,
    updated_by: doctorId,
  };
  if (name) updates.name = name;
  if (description !== undefined) updates.description = description;
  if (isActive !== undefined) updates.is_active = isActive;

  await groupRef.update(updates);

  await db.collection("admin_audit_log").add({
    action: "custom_group_updated",
    entity: "custom_groups",
    target_id: groupId,
    updates,
    actor_id: doctorId,
    actor_role: "doctor",
    created_at: now,
    timestamp: now,
  });

  return {groupId, success: true};
});

export function calculateLockMinutes(failures: number): number {
  if (failures < 3) return 0;
  if (failures < 5) return 5;
  if (failures < 10) return 10;
  if (failures < 20) return 20;
  if (failures < 40) return 40;
  return 60;
}

export const verifyPhonePassword = onCall(SECURE_CALL_OPTS, async (request) => {
  const phone = normalizeEgyptianPhone(request.data?.phoneNumber);
  const password = getString(request.data?.password);

  if (!phone || !password) {
    throw new HttpsError("invalid-argument", "Valid Egyptian phone number and password are required.");
  }

  // Pre-lookup anti-spray gate: evaluated before the users query and
  // before any account-state branch, so throttled callers learn nothing
  // about phone existence. Absent IP (emulator/local) skips the gate,
  // matching assertStaffDirectoryAllowed; Firestore errors propagate and
  // fail closed.
  const loginIp = requestIp(request);
  if (loginIp) {
    await assertLoginNotLocked(STUDENT_LOGIN_IP_SCOPE, loginIp);
  }

  const userSnap = await db.collection("users").where("phone_number", "==", phone).limit(1).get();
  if (userSnap.empty) {
    await db.collection("auth_security_events").add({
      event_type: "failed_login",
      phone_number: phone,
      created_at: FieldValue.serverTimestamp(),
      created_by: "system",
    });
    // Discarded verification keeps unknown-phone timing comparable to the
    // wrong-password path below (both responses stay generic).
    await verifyPassword(password, ENUMERATION_DUMMY_HASH);
    if (loginIp) {
      await recordLoginFailure(STUDENT_LOGIN_IP_SCOPE, loginIp, STUDENT_LOGIN_IP_MAX_FAILURES);
    }
    throw new HttpsError("unauthenticated", "Invalid phone number or password.");
  }

  const userDoc = userSnap.docs[0];
  const user = dataOf(userDoc.data());

  // Enumeration hardening: account-state branches (disabled / pending /
  // rejected / locked) are evaluated ONLY after a correct password, so a
  // wrong password yields the generic response for every account state.
  // Correct-password behavior (messages, lockout enforcement, clearing)
  // is unchanged.
  const secretSnap = await db.collection("user_secrets").doc(userDoc.id).get();
  const secretData = secretSnap.exists ? dataOf(secretSnap.data()) : {};

  const passwordHash = getString(secretData.password_hash) ?? getString(user.password_hash);
  if (!passwordHash || !(await verifyPassword(password, passwordHash))) {
    const failedAttempts = (typeof secretData.failed_login_attempts === "number" ? secretData.failed_login_attempts : 0) + 1;
    const lockMinutes = calculateLockMinutes(failedAttempts);
    const updateData: any = {
      failed_login_attempts: failedAttempts,
      updated_at: FieldValue.serverTimestamp(),
    };
    if (lockMinutes > 0) {
      updateData.locked_until = Timestamp.fromDate(new Date(Date.now() + lockMinutes * 60000));
    }
    await db.collection("user_secrets").doc(userDoc.id).set(updateData, {merge: true});

    await writeAnalyticsEvent(userDoc.id, "Failed Login", userDoc.id, {reason: "invalid_credentials"}, request);
    if (loginIp) {
      await recordLoginFailure(STUDENT_LOGIN_IP_SCOPE, loginIp, STUDENT_LOGIN_IP_MAX_FAILURES);
    }
    throw new HttpsError("unauthenticated", "Invalid phone number or password.");
  }

  if (user.account_status && user.account_status !== "active") {
    throw new HttpsError("permission-denied", "Account is not active.");
  }

  if (user.approval_status !== "approved") {
    throw new HttpsError("permission-denied", "Account approval is required before login.");
  }

  if (secretData.locked_until && secretData.locked_until.toDate() > new Date()) {
    throw new HttpsError("resource-exhausted", "Account locked due to too many failed attempts. Try again later.");
  }

  // Clear failures on success
  if (secretData.failed_login_attempts > 0 || secretData.locked_until != null) {
    await db.collection("user_secrets").doc(userDoc.id).set({
      failed_login_attempts: FieldValue.delete(),
      locked_until: FieldValue.delete(),
      updated_at: FieldValue.serverTimestamp(),
    }, {merge: true});
  }

  // Migrate legacy hashes out of users/{userId} after a successful login.
  if (!secretSnap.exists && getString(user.password_hash)) {
    const now = FieldValue.serverTimestamp();
    const migrationBatch = db.batch();
    migrationBatch.set(db.collection("user_secrets").doc(userDoc.id), {
      user_id: userDoc.id,
      password_hash: passwordHash,
      created_at: now,
      updated_at: now,
    });
    migrationBatch.update(userDoc.ref, {
      password_hash: FieldValue.delete(),
      updated_at: now,
      updated_by: "security_migration",
    });
    await migrationBatch.commit();
  }

  const role = getString(user.role) ?? "student";
  const studentType = getString(user.student_type);
  if (!studentType && role === "student") {
    throw new HttpsError("failed-precondition", "Student type is not configured.");
  }

  // Stored-claim repair at the trusted login boundary. Staff: persist the
  // authoritative Firestore role. Students: restore identity claims the
  // approval trigger owns (role/student_type/approved/force_password_change)
  // so a drifted or pre-trigger account still passes the `onLoginAttempt`
  // role gate after the ID token refresh. Plan claims are left untouched.
  if (role === "doctor" || role === "admin") {
    await syncStaffStoredClaims(userDoc.id, role, user.force_password_change === true);
  } else if (role === "student" && studentType) {
    await syncStudentStoredClaims(userDoc.id, studentType, user.force_password_change === true);
  }

  // ADR-004: login succeeds regardless of subscription or device state.
  // Custom claims carry identity only; per-Subject subscription and
  // device authorization always resolve server-side at access time.
  const token = await auth.createCustomToken(userDoc.id, {
    role,
    ...(studentType ? {student_type: studentType} : {}),
    approved: user.approval_status === "approved",
    force_password_change: user.force_password_change === true,
  });

  await writeAnalyticsEvent(userDoc.id, "Login", userDoc.id, {method: "phone_password"}, request);
  return {token, userId: userDoc.id};
});

// ADR-004: device registry only. Records the calling device for
// recognition and audit. Always succeeds for a valid session — it never
// decides authorization, never evicts, never rejects, and never writes
// authorization truth (`current_device_id` / `active_device` are retired).
export const onLoginAttempt = onCall(SECURE_CALL_OPTS, async (request) => {
  const userId = getString(request.data?.userId);
  const deviceId = normalizeDeviceId(request.data?.deviceId);
  const deviceName = getString(request.data?.deviceName);
  const platform = getString(request.data?.platform) ?? "unknown";
  const osVersion = getString(request.data?.osVersion);
  const appVersion = getString(request.data?.appVersion);
  const ipAddress = typeof request.rawRequest?.ip === "string" ? request.rawRequest.ip : null;

  if (!userId || !deviceId) throw new HttpsError("invalid-argument", "userId and deviceId are required.");
  if (!request.auth || request.auth.uid !== userId) throw new HttpsError("permission-denied", "User identity mismatch.");

  const userSnap = await db.collection("users").doc(userId).get();
  if (!userSnap.exists) throw new HttpsError("not-found", "User not found.");

  const role = getString(request.auth.token.role);
  if (role !== "student") throw new HttpsError("permission-denied", "Only students register devices.");

  const outcome = await registerKnownDevice({
    userId, deviceId, deviceName, platform, osVersion, appVersion, ipAddress,
  });

  await writeAnalyticsEvent(userId, "Device Registered", outcome.deviceDocId, {
    status: outcome.kind === "existing" ? "existing_device" : "new_device",
    platform,
  }, request);

  return {
    allowed: true,
    status: outcome.kind === "existing" ? "existing_device" : "new_device",
    deviceDocumentId: outcome.deviceDocId,
  };
});

// ADR-004: shared server-side tier evaluation used by the callable below
// and by every protected-content issuer. Same 10-step order everywhere:
// assignment -> exact-pair subscription -> Subject's own plan/allowance ->
// existing authorization -> Full | free slot -> bind + Full | no slot -> Guest.
// Deny outcomes throw and bind nothing. Never trusts client-supplied plan,
// max_devices, tier flags, or subscription status; the authenticated uid is
// the only account namespace and the server computes the device hash.
async function evaluateSubjectTier(input: {
  studentId: string;
  subjectId: string;
  deviceId: string;
  deviceName?: string | null;
  platform?: string | null;
  osVersion?: string | null;
  appVersion?: string | null;
  ipAddress?: string | null;
  // When false, the evaluation is read-only: an unbound device resolves
  // Guest without claiming a slot. Heartbeat and other validations use
  // this so revocation/reset take effect instead of silently rebinding.
  bindIfFree?: boolean;
  // Request-scoped consolidation: callers holding the plan's full feature
  // set pass it so device.max_count derives without re-querying. Omitted
  // everywhere else — legacy query behavior preserved exactly.
  planFeatures?: DocumentData[];
  // Request-scoped consolidation: a caller that has ALREADY read and
  // validated the assignment, subscription, and plan through the same
  // checks below passes the snapshots so the duplicate reads are skipped.
  // Verification is NOT skipped: the identical pure predicates
  // (assertEnabledSubjectAccess, assertSubjectAccess, plan presence and
  // is_active) are re-applied to the passed snapshots. Omitted everywhere
  // else — legacy read path preserved exactly.
  verifiedSubjectContext?: {
    assignment: DocumentData;
    subscription: DocumentData;
    planId: string;
    plan: DocumentData;
  };
}): Promise<{
  tier: "full" | "guest";
  allowance: number;
  activeAuthorizationCount: number;
  authorizationId: string | null;
  deviceHash: string;
  planId: string;
  plan: DocumentData;
  boundNow: boolean;
}> {
  const {studentId, subjectId, deviceId} = input;
  // Verified-context fast path: the caller already read these documents
  // through the same checks. The pure predicates are re-applied to the
  // passed snapshots (never skipped); only the duplicate I/O is removed.
  // Without the context, the legacy read path below runs unchanged.
  let planId: string;
  let plan: DocumentData;
  if (input.verifiedSubjectContext) {
    const verified = input.verifiedSubjectContext;
    assertEnabledSubjectAccess(studentId, subjectId, verified.assignment);
    assertSubjectAccess(verified.subscription);
    const verifiedPlanId = getString(verified.subscription.plan_id);
    if (!verifiedPlanId) throw new HttpsError("failed-precondition", "Subject subscription plan is missing.");
    if (verified.plan.is_active !== true) {
      throw new HttpsError("failed-precondition", "Subject subscription plan is not available.");
    }
    planId = verifiedPlanId;
    plan = verified.plan;
  } else {
    await requireEnabledSubjectAccess(studentId, subjectId);
    ({planId, plan} = await getActiveSubjectSubscription(studentId, subjectId));
  }
  const allowance = await getSubjectAllowance(planId, input.planFeatures);
  const planKey = getString(plan.plan_key);

  const deviceHash = computeDeviceHash(studentId, deviceId);
  const authorizationId = subjectAuthorizationId(studentId, subjectId, deviceHash);
  const authorizationRef = db.collection("subject_device_authorizations").doc(authorizationId);

  // Registry is informational here; authorization never depends on it.
  await registerKnownDevice({
    userId: studentId,
    deviceId,
    deviceName: input.deviceName ?? null,
    platform: input.platform ?? "unknown",
    osVersion: input.osVersion ?? null,
    appVersion: input.appVersion ?? null,
    ipAddress: input.ipAddress ?? null,
  });

  type TierOutcome = {tier: "full" | "guest"; boundNow: boolean; activeCount: number};
  const outcome = await db.runTransaction(async (tx): Promise<TierOutcome> => {
    // All reads precede all writes: Firestore transactions reject
    // read-after-write. Both reads are issued before any update/set below.
    const existingSnap = await tx.get(authorizationRef);
    const activeSnap = await tx.get(
      db.collection("subject_device_authorizations")
        .where("student_id", "==", studentId)
        .where("subject_id", "==", subjectId)
        .where("status", "==", "active"),
    );
    const liveCount = activeSnap.docs.filter((d) => dataOf(d.data()).is_deleted !== true).length;

    if (
      existingSnap.exists &&
      dataOf(existingSnap.data()).status === "active" &&
      dataOf(existingSnap.data()).is_deleted !== true
    ) {
      tx.update(existingSnap.ref, {
        last_used_at: FieldValue.serverTimestamp(),
        updated_at: FieldValue.serverTimestamp(),
        updated_by: "system",
      });
      return {tier: "full", boundNow: false, activeCount: liveCount};
    }

    // The record at `authorizationId`, if present, is known non-active here
    // (the active case returned above), so every non-deleted hit occupies
    // a slot belonging to another device.
    if (liveCount >= allowance || input.bindIfFree === false) {
      return {tier: "guest", boundNow: false, activeCount: liveCount};
    }

    const now = FieldValue.serverTimestamp();
    tx.set(authorizationRef, {
      student_id: studentId,
      subject_id: subjectId,
      device_hash: deviceHash,
      plan_key_at_bind: planKey,
      status: "active",
      authorized_at: now,
      authorized_via: "first_access",
      last_used_at: now,
      revoked_at: null,
      revoked_by: null,
      revoke_reason: null,
      created_at: now,
      updated_at: now,
      created_by: "system",
      updated_by: "system",
      is_deleted: false,
      deleted_at: null,
      deleted_by: null,
    });
    return {tier: "full", boundNow: true, activeCount: liveCount + 1};
  });

  return {
    tier: outcome.tier,
    allowance,
    activeAuthorizationCount: outcome.activeCount,
    authorizationId: outcome.tier === "full" ? authorizationId : null,
    deviceHash,
    planId,
    plan,
    boundNow: outcome.boundNow,
  };
}

// Thin callable wrapper: self-service tier resolution with audit trail.
// Issuance functions call `evaluateSubjectTier` directly instead.
export const resolveSubjectTier = onCall(SECURE_CALL_OPTS, async (request) => {
  const callerUid = requireAuthenticated(request);
  const studentId = getString(request.data?.studentId);
  const subjectId = getString(request.data?.subjectId);
  const deviceId = normalizeDeviceId(request.data?.deviceId);
  if (!studentId || !subjectId || !deviceId) {
    throw new HttpsError("invalid-argument", "studentId, subjectId and deviceId are required.");
  }
  if (callerUid !== studentId) throw new HttpsError("permission-denied", "Students may only resolve their own tier.");

  const evaluated = await evaluateSubjectTier({
    studentId,
    subjectId,
    deviceId,
    deviceName: getString(request.data?.deviceName),
    platform: getString(request.data?.platform),
    osVersion: getString(request.data?.osVersion),
    appVersion: getString(request.data?.appVersion),
    ipAddress: typeof request.rawRequest?.ip === "string" ? request.rawRequest.ip : null,
  });
  const {tier, allowance, activeAuthorizationCount, authorizationId, deviceHash, plan, boundNow} = evaluated;
  const planKey = getString(plan.plan_key);

  if (boundNow) {
    await writeAnalyticsEvent(studentId, "Subject Device Authorized", authorizationId as string, {
      subject_id: subjectId,
      plan_key: planKey,
      allowance,
    }, request);
  } else if (tier === "guest") {
    await writeAnalyticsEvent(studentId, "Subject Guest Resolved", authorizationId as string, {
      subject_id: subjectId,
      plan_key: planKey,
      allowance,
      active_count: activeAuthorizationCount,
    }, request);
  }

  return {tier, allowance, activeAuthorizationCount, authorizationId, deviceHash};
});

// Server-side Full-tier gate for protected artifacts (ADR-004). Throws the
// existing permission-denied contract when the device resolves Guest; deny
// outcomes from evaluation propagate unchanged. Never defaults to Full.
async function requireFullSubjectTier(input: {
  studentId: string;
  subjectId: string;
  deviceId: string;
  deviceName?: string | null;
  platform?: string;
  osVersion?: string | null;
  appVersion?: string | null;
  ipAddress?: string | null;
}): Promise<{allowance: number; authorizationId: string; deviceHash: string; planId: string}> {
  const evaluated = await evaluateSubjectTier(input);
  if (evaluated.tier !== "full" || !evaluated.authorizationId) {
    throw new HttpsError(
      "permission-denied",
      "This device has Guest access for the subject and cannot receive protected content.",
    );
  }
  return {
    allowance: evaluated.allowance,
    authorizationId: evaluated.authorizationId,
    deviceHash: evaluated.deviceHash,
    planId: evaluated.planId,
  };
}

// ADR-004: approved global student reset. Revokes every active
// Subject-device authorization for the student with reason `reset`,
// preserves history, notifies, and audits. Never touches Firebase Auth,
// never deletes the registry, never requires re-login, never migrates.
export const resetStudentDevices = onCall(SECURE_CALL_OPTS, async (request) => {
  const authorization = await requireDeviceManager(request);
  const studentId = getString(request.data?.studentId);
  const reason = getString(request.data?.reason) ?? "reset_requested";
  if (!studentId) throw new HttpsError("invalid-argument", "studentId is required.");

  const activeSnap = await db.collection("subject_device_authorizations")
    .where("student_id", "==", studentId)
    .where("status", "==", "active")
    .get();
  const targets = activeSnap.docs.filter((d) => dataOf(d.data()).is_deleted !== true);

  const now = FieldValue.serverTimestamp();
  for (let index = 0; index < targets.length; index += 500) {
    const batch = db.batch();
    for (const doc of targets.slice(index, index + 500)) {
      batch.update(doc.ref, {
        status: "revoked",
        revoked_at: now,
        revoked_by: authorization.actorId,
        revoke_reason: "reset",
        updated_at: now,
        updated_by: authorization.actorId,
      });
    }
    await batch.commit();
  }

  await writeDeviceAudit({
    action: "subject_device_reset",
    targetId: studentId,
    actorId: authorization.actorId,
    actorRole: authorization.actorRole,
    permissionBasis: authorization.permissionBasis,
    details: {revoked_count: targets.length, reason},
  });
  await writeAnalyticsEvent(studentId, "Subject Devices Reset", studentId, {
    revoked_count: targets.length,
    resolved_by: authorization.actorId,
  }, request);
  await createNotification(
    studentId,
    "system",
    "Devices Reset",
    "Your device authorizations were reset. Open each subject to reconnect your devices. No need to sign in again.",
  );

  return {revokedCount: targets.length};
});

// ADR-004: per-Subject unbind of one device. Revokes the single active
// authorization for (student, subject, device) with actor/reason audit.
// History is preserved; nothing else is touched.
export const unbindSubjectDevice = onCall(SECURE_CALL_OPTS, async (request) => {
  const authorization = await requireDeviceManager(request);
  const studentId = getString(request.data?.studentId);
  const subjectId = getString(request.data?.subjectId);
  const deviceId = normalizeDeviceId(request.data?.deviceId);
  const reason = getString(request.data?.reason) ?? "admin_unbind";
  if (!studentId || !subjectId || !deviceId) {
    throw new HttpsError("invalid-argument", "studentId, subjectId and deviceId are required.");
  }

  const deviceHash = computeDeviceHash(studentId, deviceId);
  const authorizationId = subjectAuthorizationId(studentId, subjectId, deviceHash);
  const authorizationRef = db.collection("subject_device_authorizations").doc(authorizationId);
  const authorizationSnap = await authorizationRef.get();
  if (
    !authorizationSnap.exists ||
    dataOf(authorizationSnap.data()).status !== "active" ||
    dataOf(authorizationSnap.data()).is_deleted === true
  ) {
    throw new HttpsError("not-found", "No active authorization exists for this student, subject and device.");
  }

  const now = FieldValue.serverTimestamp();
  await authorizationRef.update({
    status: "revoked",
    revoked_at: now,
    revoked_by: authorization.actorId,
    revoke_reason: "admin_unbind",
    updated_at: now,
    updated_by: authorization.actorId,
  });

  await writeDeviceAudit({
    action: "subject_device_unbound",
    targetId: authorizationId,
    actorId: authorization.actorId,
    actorRole: authorization.actorRole,
    permissionBasis: authorization.permissionBasis,
    details: {student_id: studentId, subject_id: subjectId, reason},
  });
  await writeAnalyticsEvent(studentId, "Subject Device Unbound", authorizationId, {
    subject_id: subjectId,
    resolved_by: authorization.actorId,
  }, request);

  return {revoked: true, authorizationId};
});

// ---------------------------------------------------------------------------
// Max Subject Playback Sessions (ADR-004 follow-up).
// One live session per Student + Subject (never global, never per content).
// The server is the sole authority: opaque server-issued tokens, server-time
// leases, takeover by transaction. `lecture_progress.video_position_seconds`
// remains the sole durable progress truth; the session only caches a
// transient snapshot merged with max() so concurrent writers cannot lose
// forward progress and no second progress system is created.
// Lease/heartbeat durations below are TUNING values, not business policy.
// ---------------------------------------------------------------------------

const PLAYBACK_SESSION_LEASE_MS = 120_000;
const PLAYBACK_HEARTBEAT_INTERVAL_MS = 30_000;

function playbackSessionId(studentId: string, subjectId: string): string {
  return `${studentId}_${subjectId}`;
}

function newSessionToken(): string {
  return randomBytes(32).toString("hex");
}

function sessionTokenMatches(stored: unknown, presented: unknown): boolean {
  if (typeof stored !== "string" || typeof presented !== "string") return false;
  const storedBuf = Buffer.from(stored, "utf8");
  const presentedBuf = Buffer.from(presented, "utf8");
  if (storedBuf.length !== presentedBuf.length) return false;
  return timingSafeEqual(storedBuf, presentedBuf);
}

function sessionIsLive(session: DocumentData | undefined, nowMs: number): boolean {
  if (!session || session.is_deleted === true) return false;
  if (session.ended_at != null) return false;
  const lease = session.lease_expires_at;
  if (!lease?.toMillis || lease.toMillis() <= nowMs) return false;
  return true;
}

async function readPersistedPosition(
  tx: FirebaseFirestore.Transaction,
  studentId: string,
  lectureId: string | null,
): Promise<number> {
  if (!lectureId) return 0;
  const progressSnap = await tx.get(
    db.collection("lecture_progress")
      .where("student_id", "==", studentId)
      .where("lecture_id", "==", lectureId)
      .limit(1),
  );
  if (progressSnap.empty) return 0;
  const position = getNumber(dataOf(progressSnap.docs[0].data()).video_position_seconds);
  return position !== null && position > 0 ? Math.floor(position) : 0;
}

type SessionContentRef = {lecture_id: string | null; video_id: string | null};

async function resolveSessionContent(
  studentId: string,
  subjectId: string,
  input: {lectureId?: string | null; videoId?: string | null},
): Promise<SessionContentRef> {
  let lectureId = getString(input.lectureId);
  const videoId = getString(input.videoId);
  if (!lectureId && videoId) {
    const resourceSnap = await db.collection("lecture_resources")
      .where("bunny_video_id", "==", videoId)
      .limit(1)
      .get();
    if (resourceSnap.empty) throw new HttpsError("not-found", "Video resource not found.");
    lectureId = getString(resourceSnap.docs[0].data().lecture_id);
  }
  if (!lectureId) throw new HttpsError("invalid-argument", "lectureId or a known videoId is required.");
  const lectureSnap = await db.collection("lectures").doc(lectureId).get();
  if (!lectureSnap.exists || dataOf(lectureSnap.data()).is_deleted === true) {
    throw new HttpsError("not-found", "Lecture not found.");
  }
  const lecture = dataOf(lectureSnap.data());
  const lectureSubjectId = getString(lecture.subject_id);
  if (lectureSubjectId && lectureSubjectId !== subjectId) {
    throw new HttpsError("permission-denied", "Lecture does not belong to this subject.");
  }
  // Explicit deny wins over any session outcome, Full or Guest.
  await assertLectureAccessNotDenied(studentId, lectureId);
  return {lecture_id: lectureId, video_id: videoId};
}

type BeginOutcome = {
  tookOver: boolean;
  refreshed: boolean;
  previousDeviceHash: string | null;
  positionSeconds: number;
  sessionToken: string;
  leaseExpiresAtMs: number;
};

// Core takeover transaction shared by the callable and by Max video issuance.
// Exactly one live session can exist per (student, subject): concurrent
// callers serialize here and exactly one wins.
async function beginOrTakeoverSession(input: {
  studentId: string;
  subjectId: string;
  deviceHash: string;
  content: SessionContentRef;
}): Promise<BeginOutcome> {
  const {studentId, subjectId, deviceHash, content} = input;
  const sessionRef = db.collection("playback_sessions").doc(playbackSessionId(studentId, subjectId));

  return db.runTransaction(async (tx): Promise<BeginOutcome> => {
    const sessionSnap = await tx.get(sessionRef);
    const persistedPosition = await readPersistedPosition(tx, studentId, content.lecture_id);
    const nowMs = Date.now();
    const now = FieldValue.serverTimestamp();

    if (sessionSnap.exists) {
      const current = dataOf(sessionSnap.data());
      if (sessionIsLive(current, nowMs) && getString(current.active_device_hash) === deviceHash) {
        const position = Math.max(
          persistedPosition,
          getNumber(current.position_seconds) ?? 0,
        );
        tx.update(sessionRef, {
          content_ref: {lecture_id: content.lecture_id, video_id: content.video_id},
          position_seconds: position,
          lease_expires_at: Timestamp.fromMillis(nowMs + PLAYBACK_SESSION_LEASE_MS),
          heartbeat_at: now,
          updated_at: now,
          updated_by: "system",
        });
        return {
          tookOver: false,
          refreshed: true,
          previousDeviceHash: null,
          positionSeconds: position,
          sessionToken: getString(current.session_token) ?? "",
          leaseExpiresAtMs: nowMs + PLAYBACK_SESSION_LEASE_MS,
        };
      }
    }

    const previousDeviceHash = sessionSnap.exists ?
      getString(dataOf(sessionSnap.data()).active_device_hash) :
      null;
    const previousPosition = sessionSnap.exists ?
      getNumber(dataOf(sessionSnap.data()).position_seconds) ?? 0 :
      0;
    const sessionToken = newSessionToken();
    const leaseExpiresAtMs = nowMs + PLAYBACK_SESSION_LEASE_MS;
    tx.set(sessionRef, {
      student_id: studentId,
      subject_id: subjectId,
      content_ref: {lecture_id: content.lecture_id, video_id: content.video_id},
      active_device_hash: deviceHash,
      session_token: sessionToken,
      position_seconds: Math.max(persistedPosition, previousPosition),
      lease_expires_at: Timestamp.fromMillis(leaseExpiresAtMs),
      heartbeat_at: now,
      ended_at: null,
      ended_reason: null,
      created_at: sessionSnap.exists ? dataOf(sessionSnap.data()).created_at ?? now : now,
      updated_at: now,
      created_by: sessionSnap.exists ? dataOf(sessionSnap.data()).created_by ?? "system" : "system",
      updated_by: "system",
      is_deleted: false,
      deleted_at: null,
      deleted_by: null,
    });
    return {
      tookOver: previousDeviceHash !== null && previousDeviceHash !== deviceHash,
      refreshed: false,
      previousDeviceHash,
      positionSeconds: Math.max(persistedPosition, previousPosition),
      sessionToken,
      leaseExpiresAtMs,
    };
  });
}

async function validatePlaybackSession(input: {
  studentId: string;
  subjectId: string;
  deviceHash: string;
  sessionToken: string;
  reportedPositionSeconds?: number | null;
}): Promise<{positionSeconds: number; leaseExpiresAtMs: number}> {
  const {studentId, subjectId, deviceHash, sessionToken} = input;
  const sessionRef = db.collection("playback_sessions").doc(playbackSessionId(studentId, subjectId));

  return db.runTransaction(async (tx) => {
    const sessionSnap = await tx.get(sessionRef);
    const nowMs = Date.now();
    const session = sessionSnap.exists ? dataOf(sessionSnap.data()) : undefined;
    // Fail closed on every uncertainty: missing, ended, stale, foreign
    // token, or foreign device all reject with the authorization contract.
    if (!sessionIsLive(session, nowMs)) {
      throw new HttpsError("permission-denied", "Playback session is no longer active.");
    }
    if (!sessionTokenMatches(session?.session_token, sessionToken)) {
      throw new HttpsError("permission-denied", "Playback session token is not valid.");
    }
    if (getString(session?.active_device_hash) !== deviceHash) {
      throw new HttpsError("permission-denied", "Playback session belongs to another device.");
    }
    const reported = input.reportedPositionSeconds;
    const position = reported !== null && reported !== undefined && Number.isFinite(reported) && reported > 0 ?
      Math.max(Math.floor(reported), getNumber(session?.position_seconds) ?? 0) :
      getNumber(session?.position_seconds) ?? 0;
    const now = FieldValue.serverTimestamp();
    tx.update(sessionRef, {
      position_seconds: position,
      lease_expires_at: Timestamp.fromMillis(nowMs + PLAYBACK_SESSION_LEASE_MS),
      heartbeat_at: now,
      updated_at: now,
      updated_by: "system",
    });
    return {positionSeconds: position, leaseExpiresAtMs: nowMs + PLAYBACK_SESSION_LEASE_MS};
  });
}

// Callable: begin a Max playback session or take it over from the other
// authorized device. Guest devices and unauthorized devices are rejected by
// the Full-tier check below; deny/subscription/assignment failures throw
// before any session state is touched.
export const beginOrTakeoverPlayback = onCall(SECURE_CALL_OPTS, async (request) => {
  const callerUid = requireAuthenticated(request);
  const studentId = getString(request.data?.studentId);
  const subjectId = getString(request.data?.subjectId);
  const deviceId = normalizeDeviceId(request.data?.deviceId);
  if (!studentId || !subjectId || !deviceId) {
    throw new HttpsError("invalid-argument", "studentId, subjectId and deviceId are required.");
  }
  if (callerUid !== studentId) throw new HttpsError("permission-denied", "Students may only start their own playback.");

  const content = await resolveSessionContent(studentId, subjectId, {
    lectureId: getString(request.data?.lectureId),
    videoId: getString(request.data?.videoId),
  });
  // Steps 3-5 of the required flow: assignment, subscription, Full tier.
  // Guest, revoked, and inactive-subscription callers are denied here and
  // create no session state.
  const tier = await evaluateSubjectTier({
    studentId,
    subjectId,
    deviceId,
    deviceName: getString(request.data?.deviceName),
    platform: getString(request.data?.platform),
    ipAddress: typeof request.rawRequest?.ip === "string" ? request.rawRequest.ip : null,
  });
  if (tier.tier !== "full") {
    throw new HttpsError(
      "permission-denied",
      "This device has Guest access for the subject and cannot start Full playback.",
    );
  }

  const deviceHash = computeDeviceHash(studentId, deviceId);
  const outcome = await beginOrTakeoverSession({studentId, subjectId, deviceHash, content});
  await writeAnalyticsEvent(studentId, "Playback Session Started", playbackSessionId(studentId, subjectId), {
    subject_id: subjectId,
    lecture_id: content.lecture_id,
    takeover: outcome.tookOver,
  }, request);
  return {
    sessionToken: outcome.sessionToken,
    positionSeconds: outcome.positionSeconds,
    leaseExpiresAtMs: outcome.leaseExpiresAtMs,
    takeover: outcome.tookOver,
    heartbeatIntervalMs: PLAYBACK_HEARTBEAT_INTERVAL_MS,
  };
});

// Callable: heartbeat an owned live session. Rejects superseded, expired,
// foreign-token, and foreign-device heartbeats; revalidates authorization
// and subscription first so reset, revocation, and expiry take effect on
// the next server validation without any separate playback-reset workflow.
export const heartbeatPlayback = onCall(SECURE_CALL_OPTS, async (request) => {
  const callerUid = requireAuthenticated(request);
  const studentId = getString(request.data?.studentId);
  const subjectId = getString(request.data?.subjectId);
  const deviceId = normalizeDeviceId(request.data?.deviceId);
  const sessionToken = getString(request.data?.sessionToken);
  if (!studentId || !subjectId || !deviceId || !sessionToken) {
    throw new HttpsError("invalid-argument", "studentId, subjectId, deviceId and sessionToken are required.");
  }
  if (callerUid !== studentId) throw new HttpsError("permission-denied", "Students may only heartbeat their own playback.");

  await requireEnabledSubjectAccess(studentId, subjectId);
  await getActiveSubjectSubscription(studentId, subjectId);
  // Read-only: a heartbeat must never claim a slot. After reset, unbind,
  // or expiry the device resolves Guest here and the stale session below
  // additionally fails closed, so revoked authority stops within one beat.
  const tier = await evaluateSubjectTier({
    studentId,
    subjectId,
    deviceId,
    ipAddress: typeof request.rawRequest?.ip === "string" ? request.rawRequest.ip : null,
    bindIfFree: false,
  });
  if (tier.tier !== "full") {
    throw new HttpsError("permission-denied", "Playback authority was revoked for this device.");
  }

  const reported = request.data?.positionSeconds;
  return validatePlaybackSession({
    studentId,
    subjectId,
    deviceHash: computeDeviceHash(studentId, deviceId),
    sessionToken,
    reportedPositionSeconds: typeof reported === "number" ? reported : null,
  });
});

export const approveStudent = onCall(SECURE_CALL_OPTS, async (request) => {
  const authorization = await requireStudentAccessManager(request);
  const studentId = getString(request.data?.studentId);
  const studentType = getString(request.data?.studentType);
  const rawAssignments = request.data?.subjectAccess;
  if (
    !studentId ||
    (studentType !== GUEST_STUDENT_TYPE && studentType !== CENTER_STUDENT_TYPE) ||
    !Array.isArray(rawAssignments)
  ) {
    throw new HttpsError("invalid-argument", "studentId, studentType and subjectAccess are required.");
  }

  const assignments = rawAssignments.map((item: unknown) => {
    if (!item || typeof item !== "object") {
      throw new HttpsError("invalid-argument", "Each subject access item must be an object.");
    }
    const value = item as Record<string, unknown>;
    const subjectId = getString(value.subjectId);
    const enabled = value.enabled;
    if (!subjectId || typeof enabled !== "boolean") {
      throw new HttpsError("invalid-argument", "Each subject access item requires subjectId and enabled.");
    }
    return {subjectId, enabled};
  });
  if (new Set(assignments.map((item) => item.subjectId)).size !== assignments.length) {
    throw new HttpsError("invalid-argument", "Duplicate subject access assignments are not allowed.");
  }

  const userRef = db.collection("users").doc(studentId);
  const auditRef = db.collection("admin_audit_log").doc();
  const assignmentRefs = assignments.map((item) => ({
    ...item,
    ref: db.collection("subject_access_assignments").doc(`${studentId}_${item.subjectId}`),
    subjectRef: db.collection("subjects").doc(item.subjectId),
  }));

  await db.runTransaction(async (transaction) => {
    const userSnap = await transaction.get(userRef);
    if (!userSnap.exists) throw new HttpsError("not-found", "Student not found.");
    const user = dataOf(userSnap.data());
    if (user.approval_status !== "pending") {
      throw new HttpsError("failed-precondition", "Student approval is not pending.");
    }

    const subjectSnaps = await Promise.all(
      assignmentRefs.map((item) => transaction.get(item.subjectRef)),
    );
    const previousStates: Array<Record<string, unknown>> = [];
    for (let index = 0; index < assignmentRefs.length; index += 1) {
      const item = assignmentRefs[index];
      const subjectSnap = subjectSnaps[index];
      if (!subjectSnap.exists || subjectSnap.data()?.is_deleted === true) {
        throw new HttpsError("not-found", `Subject not found: ${item.subjectId}`);
      }
      const currentSnap = await transaction.get(item.ref);
      const previous = currentSnap.exists ? dataOf(currentSnap.data()) : {};
      previousStates.push({
        subject_id: item.subjectId,
        previous_enabled: previous.enabled ?? null,
        previous_is_deleted: previous.is_deleted ?? null,
        new_enabled: item.enabled,
        new_is_deleted: false,
      });
    }

    transaction.update(userRef, {
      role: "student",
      student_type: studentType,
      approval_status: "approved",
      approved_by: authorization.actorId,
      approved_at: FieldValue.serverTimestamp(),
      updated_by: authorization.actorId,
      updated_at: FieldValue.serverTimestamp(),
    });

    for (const item of assignmentRefs) {
      transaction.set(item.ref, {
        student_id: studentId,
        subject_id: item.subjectId,
        enabled: item.enabled,
        is_deleted: false,
        deleted_at: null,
        deleted_by: null,
        created_at: FieldValue.serverTimestamp(),
        created_by: authorization.actorId,
        updated_at: FieldValue.serverTimestamp(),
        updated_by: authorization.actorId,
      }, {merge: true});
    }

    transaction.set(auditRef, {
      action: "approve_student",
      entity: "student_approval",
      target_id: studentId,
      student_id: studentId,
      student_type: studentType,
      assignments: previousStates,
      actor_id: authorization.actorId,
      actor_role: authorization.actorRole,
      permission_basis: authorization.permissionBasis,
      approved_by: authorization.actorId,
      approved_at: FieldValue.serverTimestamp(),
      created_at: FieldValue.serverTimestamp(),
      timestamp: FieldValue.serverTimestamp(),
    });
  });

  return {
    approved: true,
    studentId,
    assignmentCount: assignments.length,
  };
});

export const rejectStudent = onCall(SECURE_CALL_OPTS, async (request) => {
  const authorization = await requireStudentAccessManager(request);
  const studentId = getString(request.data?.studentId);
  const reason = getString(request.data?.reason);
  if (!studentId || !reason) {
    throw new HttpsError("invalid-argument", "studentId and reason are required.");
  }
  if (reason.length > 500) {
    throw new HttpsError("invalid-argument", "Rejection reason must be 500 characters or fewer.");
  }

  const userRef = db.collection("users").doc(studentId);
  const auditRef = db.collection("admin_audit_log").doc();

  await db.runTransaction(async (transaction) => {
    const userSnap = await transaction.get(userRef);
    if (!userSnap.exists) throw new HttpsError("not-found", "Student not found.");
    const user = dataOf(userSnap.data());
    if (user.approval_status !== "pending") {
      throw new HttpsError("failed-precondition", "Student approval is not pending.");
    }

    const now = FieldValue.serverTimestamp();
    transaction.update(userRef, {
      approval_status: "rejected",
      rejection_reason: reason,
      rejected_by: authorization.actorId,
      rejected_at: now,
      updated_by: authorization.actorId,
      updated_at: now,
    });

    transaction.set(auditRef, {
      action: "reject_student",
      entity: "student_approval",
      target_id: studentId,
      student_id: studentId,
      rejection_reason: reason,
      actor_id: authorization.actorId,
      actor_role: authorization.actorRole,
      permission_basis: authorization.permissionBasis,
      rejected_by: authorization.actorId,
      rejected_at: now,
      created_at: now,
      timestamp: now,
    });
  });

  return {
    rejected: true,
    studentId,
  };
});

export const convertStudentType = onCall(SECURE_CALL_OPTS, async (request) => {
  const authorization = await requireStudentAccessManager(request);
  const studentId = getString(request.data?.studentId);
  const targetStudentType = getString(request.data?.targetStudentType);
  if (
    !studentId ||
    (targetStudentType !== GUEST_STUDENT_TYPE && targetStudentType !== CENTER_STUDENT_TYPE)
  ) {
    throw new HttpsError("invalid-argument", "studentId and targetStudentType are required.");
  }

  const userRef = db.collection("users").doc(studentId);
  const auditRef = db.collection("admin_audit_log").doc();
  const result = await db.runTransaction(async (transaction) => {
    const userSnap = await transaction.get(userRef);
    if (!userSnap.exists) throw new HttpsError("not-found", "Student not found.");
    const user = dataOf(userSnap.data());
    if (user.role !== "student" || user.approval_status !== "approved") {
      throw new HttpsError("failed-precondition", "Target user is not an approved student.");
    }
    const currentStudentType = getString(user.student_type);
    if (!currentStudentType) {
      throw new HttpsError("failed-precondition", "Current student type is not configured.");
    }
    if (currentStudentType === targetStudentType) {
      return {changed: false, currentStudentType, targetStudentType, conflicts: []};
    }

    const subscriptionsSnap = await db.collection("subscriptions")
      .where("student_id", "==", studentId)
      .where("status", "==", "active")
      .get();
    const conflicts: Array<Record<string, unknown>> = [];
    for (const subscriptionDoc of subscriptionsSnap.docs) {
      const subscription = dataOf(subscriptionDoc.data());
      if (subscription.is_deleted === true) continue;
      const planId = getString(subscription.plan_id);
      const planSnap = planId ? await transaction.get(db.collection("plans").doc(planId)) : null;
      const plan = planSnap?.exists ? dataOf(planSnap.data()) : {};
      if (plan.student_type !== targetStudentType) {
        conflicts.push({
          student_id: studentId,
          subject_id: subscription.subject_id ?? null,
          subscription_id: subscriptionDoc.id,
          current_plan_id: planId,
          target_student_type: targetStudentType,
        });
      }
    }
    if (conflicts.length > 0) {
      throw new HttpsError(
        "failed-precondition",
        JSON.stringify({
          code: "INCOMPATIBLE_SUBSCRIPTIONS",
          studentId,
          currentStudentType,
          targetStudentType,
          conflicts,
        }),
      );
    }

    transaction.update(userRef, {
      student_type: targetStudentType,
      updated_by: authorization.actorId,
      updated_at: FieldValue.serverTimestamp(),
    });
    transaction.set(auditRef, {
      action: "convert_student_type",
      entity: "user",
      target_id: studentId,
      student_id: studentId,
      previous_student_type: currentStudentType,
      new_student_type: targetStudentType,
      actor_id: authorization.actorId,
      actor_role: authorization.actorRole,
      permission_basis: authorization.permissionBasis,
      created_at: FieldValue.serverTimestamp(),
      timestamp: FieldValue.serverTimestamp(),
    });

    return {changed: true, currentStudentType, targetStudentType, conflicts: []};
  });

  if (result.changed) {
    await writeAnalyticsEvent(
      authorization.actorId,
      "Student Type Conversion",
      studentId,
      {
        previous_student_type: result.currentStudentType,
        new_student_type: result.targetStudentType,
      },
      request,
    );
  }
  return result;
});

export const updateStudentGrade = onCall(SECURE_CALL_OPTS, async (request) => {
  const authorization = await requireStudentAccessManager(request);
  const studentId = getString(request.data?.studentId);
  if (!studentId) {
    throw new HttpsError("invalid-argument", "studentId is required.");
  }
  const newGrade = normalizeStudentGrade(request.data?.grade);
  if (!newGrade) {
    throw new HttpsError(
      "invalid-argument",
      "grade must be one of: grade_one, grade_two, grade_three, grade_four.",
    );
  }

  const userRef = db.collection("users").doc(studentId);
  const auditRef = db.collection("admin_audit_log").doc();
  const result = await db.runTransaction(async (transaction) => {
    const userSnap = await transaction.get(userRef);
    if (!userSnap.exists) throw new HttpsError("not-found", "Student not found.");
    const user = dataOf(userSnap.data());
    if (user.role !== "student" && user.role !== "new_student") {
      throw new HttpsError("failed-precondition", "Target user is not a student.");
    }
    const previousGrade = getString(user.grade);
    // Normalized comparison: stored grades may be non-canonical aliases
    // (registration stores the grade verbatim), so a raw comparison would
    // miss the no-op case for such students. The raw value is kept for
    // the audit trail below.
    if (normalizeStudentGrade(previousGrade) === newGrade) {
      return {changed: false, previousGrade, newGrade};
    }

    transaction.update(userRef, {
      grade: newGrade,
      updated_by: authorization.actorId,
      updated_at: FieldValue.serverTimestamp(),
    });
    transaction.set(auditRef, {
      action: "update_student_grade",
      entity: "user",
      target_id: studentId,
      student_id: studentId,
      previous_grade: previousGrade ?? null,
      new_grade: newGrade,
      actor_id: authorization.actorId,
      actor_role: authorization.actorRole,
      permission_basis: authorization.permissionBasis,
      created_at: FieldValue.serverTimestamp(),
      timestamp: FieldValue.serverTimestamp(),
    });

    return {changed: true, previousGrade, newGrade};
  });

  return {
    success: true,
    studentId,
    previousGrade: result.previousGrade ?? null,
    newGrade: result.newGrade,
    changed: result.changed,
  };
});

/**
 * Staff edit of a student's display profile (full name / phone number).
 *
 * Client direct updates of `users/{userId}` are denied for staff by
 * `firestore.rules` (only the owning student may touch a narrow key set),
 * so the dashboard edits Name/Phone through this audited callable, gated
 * by the same `requireStudentAccessManager` permission as the other
 * student-management mutations. At least one of `fullName` / `phoneNumber`
 * must be supplied; phone numbers are normalized to the Egyptian format
 * and must be unique across `users` (excluding the target student).
 */
export const updateStudentProfileByStaff = onCall(SECURE_CALL_OPTS, async (request) => {
  const authorization = await requireStudentAccessManager(request);
  const studentId = getString(request.data?.studentId);
  if (!studentId) {
    throw new HttpsError("invalid-argument", "studentId is required.");
  }

  const rawFullName = getString(request.data?.fullName);
  const fullName = rawFullName === null ? null : rawFullName.trim();
  const rawPhone = getString(request.data?.phoneNumber);
  const phone = rawPhone === null ? null : normalizeEgyptianPhone(rawPhone);

  if (fullName === null && rawPhone === null) {
    throw new HttpsError("invalid-argument", "fullName or phoneNumber is required.");
  }
  if (rawFullName !== null && (!fullName || fullName.length > 100)) {
    throw new HttpsError("invalid-argument", "Full name must be 1-100 characters.");
  }
  if (rawPhone !== null && phone === null) {
    throw new HttpsError("invalid-argument", "Valid Egyptian phone number is required.");
  }

  // ---- Read phase (no writes): target + phone uniqueness.
  const userSnap = await db.collection("users").doc(studentId).get();
  if (!userSnap.exists) throw new HttpsError("not-found", "Student not found.");
  const user = dataOf(userSnap.data());
  if (user.role !== "student" && user.role !== "new_student") {
    throw new HttpsError("failed-precondition", "Target user is not a student.");
  }
  if (phone !== null) {
    const existing = await db.collection("users").where("phone_number", "==", phone).limit(1).get();
    if (!existing.empty && existing.docs[0].id !== studentId) {
      throw new HttpsError("already-exists", "An account with this phone number already exists.");
    }
  }

  const previousName = getString(user.full_name);
  const previousPhone = getString(user.phone_number);
  const update: Record<string, unknown> = {
    updated_by: authorization.actorId,
    updated_at: FieldValue.serverTimestamp(),
  };
  if (fullName !== null) update.full_name = fullName;
  if (phone !== null) update.phone_number = phone;
  if (
    (fullName === null || fullName === previousName) &&
    (phone === null || phone === previousPhone)
  ) {
    return {success: true, studentId, changed: false};
  }

  const auditRef = db.collection("admin_audit_log").doc();
  await db.runTransaction(async (transaction) => {
    transaction.update(db.collection("users").doc(studentId), update);
    transaction.set(auditRef, {
      action: "update_student_profile",
      entity: "user",
      target_id: studentId,
      student_id: studentId,
      previous_full_name: previousName ?? null,
      new_full_name: fullName ?? previousName ?? null,
      previous_phone_number: previousPhone ?? null,
      new_phone_number: phone ?? previousPhone ?? null,
      actor_id: authorization.actorId,
      actor_role: authorization.actorRole,
      permission_basis: authorization.permissionBasis,
      created_at: FieldValue.serverTimestamp(),
      timestamp: FieldValue.serverTimestamp(),
    });
  });

  return {success: true, studentId, changed: true};
});

/**
 * Atomic grade change with old-grade disentitlement.
 *
 * In a SINGLE Firestore transaction:
 * 1. Updates `users/{studentId}.grade` to the new canonical grade.
 * 2. Soft-deletes (`is_deleted: true`, `enabled: false`) every non-deleted
 *    `subject_access_assignments` row of this student whose subject belongs
 *    to the OLD grade, so the student is never silently still entitled to
 *    old-grade content after the grade field has already changed.
 *
 * New-grade subjects are deliberately NOT auto-created here: subject
 * selection for the new grade is a manual Admin step done afterward via
 * the Subjects tab (`grantSubjectAccessWithPlan` per subject). If any part
 * of steps 1-2 fails, the whole transaction rolls back — grade and old
 * assignments both stay as they were.
 *
 * `updateStudentGrade` is left untouched for callers that only need the
 * grade-field write.
 */
export const changeStudentGrade = onCall(SECURE_CALL_OPTS, async (request) => {
  const authorization = await requireStudentAccessManager(request);
  const studentId = getString(request.data?.studentId);
  if (!studentId) {
    throw new HttpsError("invalid-argument", "studentId is required.");
  }
  const newGrade = normalizeStudentGrade(request.data?.grade);
  if (!newGrade) {
    throw new HttpsError(
      "invalid-argument",
      "grade must be one of: grade_one, grade_two, grade_three, grade_four.",
    );
  }

  // ---- Read phase (no writes): resolve the old grade and its assignments.
  const userSnap = await db.collection("users").doc(studentId).get();
  if (!userSnap.exists) throw new HttpsError("not-found", "Student not found.");
  const user = dataOf(userSnap.data());
  if (user.role !== "student" && user.role !== "new_student") {
    throw new HttpsError("failed-precondition", "Target user is not a student.");
  }
  const previousGrade = normalizeStudentGrade(getString(user.grade));
  if (previousGrade === newGrade) {
    return {success: true, studentId, previousGrade, newGrade, changed: false, archivedCount: 0};
  }

  const assignmentsSnap = await db.collection("subject_access_assignments")
    .where("student_id", "==", studentId)
    .get();
  const liveRows = assignmentsSnap.docs.filter(
    (doc) => dataOf(doc.data()).is_deleted !== true,
  );
  const oldGradeSubjectIds: string[] = [];
  for (const doc of liveRows) {
    const subjectId = getString(doc.data().subject_id);
    if (!subjectId) continue;
    const subjectSnap = await db.collection("subjects").doc(subjectId).get();
    if (!subjectSnap.exists) continue;
    if (previousGrade !== null && normalizeStudentGrade(subjectSnap.data()?.grade) === previousGrade) {
      oldGradeSubjectIds.push(subjectId);
    }
  }

  // ---- Atomic phase: grade update + old-grade archival together. ----
  const userRef = db.collection("users").doc(studentId);
  const auditRef = db.collection("admin_audit_log").doc();
  const result = await db.runTransaction(async (transaction) => {
    const liveUserSnap = await transaction.get(userRef);
    if (!liveUserSnap.exists) throw new HttpsError("not-found", "Student not found.");
    const liveUser = dataOf(liveUserSnap.data());
    // Compare normalized-to-normalized: stored grades may be non-canonical
    // aliases (registration stores the grade verbatim), so comparing the
    // raw stored value against the normalized read-phase value would
    // falsely report a concurrent change on every call for such students.
    if (normalizeStudentGrade(getString(liveUser.grade)) !== previousGrade) {
      throw new HttpsError(
        "failed-precondition",
        "Student grade changed while this request was in flight. Please retry.",
      );
    }

    let archivedCount = 0;
    const archived: Array<Record<string, unknown>> = [];
    // Reads first: Firestore transactions require every read to precede
    // every write, so the user update and all archival writes happen only
    // after every snapshot below has been fetched.
    const assignmentSnaps = await Promise.all(
      oldGradeSubjectIds.map((subjectId) =>
        transaction.get(
          db.collection("subject_access_assignments").doc(`${studentId}_${subjectId}`),
        ),
      ),
    );

    transaction.update(userRef, {
      grade: newGrade,
      updated_by: authorization.actorId,
      updated_at: FieldValue.serverTimestamp(),
    });
    for (let index = 0; index < oldGradeSubjectIds.length; index += 1) {
      const subjectId = oldGradeSubjectIds[index];
      const assignmentRef =
        db.collection("subject_access_assignments").doc(`${studentId}_${subjectId}`);
      const assignmentSnap = assignmentSnaps[index];
      if (!assignmentSnap.exists) continue;
      const current = dataOf(assignmentSnap.data());
      if (current.is_deleted === true) continue;
      transaction.set(assignmentRef, {
        student_id: studentId,
        subject_id: subjectId,
        enabled: false,
        is_deleted: true,
        deleted_at: FieldValue.serverTimestamp(),
        deleted_by: authorization.actorId,
        updated_at: FieldValue.serverTimestamp(),
        updated_by: authorization.actorId,
      }, {merge: true});
      archived.push({
        subject_id: subjectId,
        previous_enabled: current.enabled ?? null,
        previous_is_deleted: current.is_deleted ?? null,
      });
      archivedCount += 1;
    }

    transaction.set(auditRef, {
      action: "change_student_grade",
      entity: "user",
      target_id: studentId,
      student_id: studentId,
      previous_grade: previousGrade ?? null,
      new_grade: newGrade,
      archived_assignments: archived,
      archived_count: archivedCount,
      actor_id: authorization.actorId,
      actor_role: authorization.actorRole,
      permission_basis: authorization.permissionBasis,
      created_at: FieldValue.serverTimestamp(),
      timestamp: FieldValue.serverTimestamp(),
    });

    return {archivedCount};
  });

  await writeAnalyticsEvent(studentId, "Student Grade Changed", studentId, {
    previous_grade: previousGrade ?? null,
    new_grade: newGrade,
    archived_count: result.archivedCount,
    changed_by: authorization.actorId,
  });

  return {
    success: true,
    studentId,
    previousGrade: previousGrade ?? null,
    newGrade,
    changed: true,
    archivedCount: result.archivedCount,
  };
});

export const onStudentApproved = onDocumentUpdated("users/{userId}", async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (!before || !after) return;
  if (before.approval_status === "approved" || after.approval_status !== "approved") return;

  const userId = event.params.userId;
  const studentType = getString(after.student_type);
  if (studentType !== GUEST_STUDENT_TYPE && studentType !== CENTER_STUDENT_TYPE) {
    throw new Error(`Invalid student_type for approved student: ${userId}`);
  }

  const settingsDoc = await db.collection("system_settings").doc("default").get();
  if (!settingsDoc.exists) throw new Error("system_settings/default configuration was not found.");
  const settings = dataOf(settingsDoc.data());
  if (settings.free_plan_enabled !== true) throw new Error("Free Plan is disabled in system settings.");

  const configuredDefaultPlan = getString(settings.default_plan);
  if (!configuredDefaultPlan) throw new Error("system_settings.default_plan is missing or invalid.");

  const planSnap = await db.collection("plans")
    .where("plan_key", "==", configuredDefaultPlan)
    .where("student_type", "==", studentType)
    .where("is_active", "==", true)
    .limit(1)
    .get();
  if (planSnap.empty) throw new Error(`Active default plan was not found: ${configuredDefaultPlan}`);

  const planDoc = planSnap.docs[0];
  const maxDevicesFeature = await getPlanFeature(planDoc.id, "device.max_count");
  const maxDevices = getNumber(maxDevicesFeature?.feature_value);
  if (maxDevices === null || maxDevices < 1) throw new Error(`device.max_count is invalid for plan ${planDoc.id}.`);

  await auth.setCustomUserClaims(userId, {
    role: "student",
    student_type: studentType,
    plan_id: planDoc.id,
    max_devices: maxDevices,
    approved: true,
    subscription_status: "active",
    force_password_change: after.force_password_change === true,
  });

  await db.collection("users").doc(userId).update({
    role: "student",
    updated_at: FieldValue.serverTimestamp(),
    updated_by: "system",
  });

  await createNotification(
    userId,
    "system",
    "Account Approved",
    "Your student account has been approved.",
    {priority: "critical", deep_link: "/home"},
  );

  await writeAnalyticsEvent(userId, "Account Approved", userId, {
    student_type: studentType,
    plan_id: planDoc.id,
    max_devices: maxDevices,
  });
});

export async function calculateAndSetSubjectProgress(db: any, studentId: string, lectureId: string) {
  const lectureSnap = await db.collection("lectures").doc(lectureId).get();
  if (!lectureSnap.exists) throw new Error(`Lecture not found: ${lectureId}`);
  const sectionId = getString(lectureSnap.data()?.section_id);
  if (!sectionId) throw new Error(`Lecture ${lectureId} has no valid section_id.`);

  const sectionSnap = await db.collection("subject_sections").doc(sectionId).get();
  if (!sectionSnap.exists) throw new Error(`Subject section not found: ${sectionId}`);
  const subjectId = getString(sectionSnap.data()?.subject_id);
  if (!subjectId) throw new Error(`Subject section ${sectionId} has no valid subject_id.`);

  const sectionsSnap = await db.collection("subject_sections").where("subject_id", "==", subjectId).get();
  const sectionIds = sectionsSnap.docs.map((doc: any) => doc.id);
  if (sectionIds.length === 0) throw new Error(`No sections found for subject: ${subjectId}`);

  const lectureIds: string[] = [];
  for (const currentSectionId of sectionIds) {
    const lecturesSnap = await db.collection("lectures").where("section_id", "==", currentSectionId).get();
    lectureIds.push(...lecturesSnap.docs
      .filter((doc: any) => doc.data().is_deleted !== true && doc.data().status === "published")
      .map((doc: any) => doc.id));
  }

  if (lectureIds.length === 0) {
    await db.collection("subject_progress_summary").doc(`${studentId}_${subjectId}`).set({
      student_id: studentId,
      subject_id: subjectId,
      total_lectures: 0,
      completed_lectures: 0,
      completion_percentage: 0,
      updated_at: FieldValue.serverTimestamp(),
    });
    return;
  }

  let completedLectures = 0;
  for (let offset = 0; offset < lectureIds.length; offset += 30) {
    const batchIds = lectureIds.slice(offset, offset + 30);
    const progressSnap = await db.collection("lecture_progress")
      .where("student_id", "==", studentId)
      .where("lecture_id", "in", batchIds)
      .get();

    const completed = new Set(
      progressSnap.docs
        .filter((doc: any) => doc.data().is_completed === true || doc.data().completed === true)
        .map((doc: any) => getString(doc.data().lecture_id))
    );
    completedLectures += completed.size;
  }

  const completionPercentage = Number(((completedLectures / lectureIds.length) * 100).toFixed(2));
  const summaryRef = db.collection("subject_progress_summary").doc(`${studentId}_${subjectId}`);
  await summaryRef.set({
    student_id: studentId,
    subject_id: subjectId,
    total_lectures: lectureIds.length,
    completed_lectures: completedLectures,
    completion_percentage: completionPercentage,
    updated_at: FieldValue.serverTimestamp(),
  });

  await writeAnalyticsEvent(studentId, "Complete Video", lectureId, {
    subject_id: subjectId,
    total_lectures: lectureIds.length,
    completed_lectures: completedLectures,
    completion_percentage: completionPercentage,
  });
}

export const recalculateSubjectProgress = onDocumentUpdated("lecture_progress/{progressId}", async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (!before || !after ||
    (before.is_completed === true || before.completed === true) ===
    (after.is_completed === true || after.completed === true)) return;

  const studentId = getString(after.student_id);
  const lectureId = getString(after.lecture_id);
  if (!studentId || !lectureId) throw new Error(`Invalid lecture_progress data: ${event.params.progressId}`);

  await calculateAndSetSubjectProgress(db, studentId, lectureId);
});

export const enforceDisplayHandleUniqueness = onCall(SECURE_CALL_OPTS, async (request) => {
  const requesterId = requireAuthenticated(request);
  const displayHandleRaw = request.data?.displayHandle;
  const userId = getString(request.data?.userId) ?? requesterId;

  if (displayHandleRaw !== null && displayHandleRaw !== undefined && typeof displayHandleRaw !== "string") {
    throw new HttpsError("invalid-argument", "displayHandle must be a string or null.");
  }

  if (userId !== requesterId && callerRole(request) !== "doctor" && callerRole(request) !== "admin") {
    throw new HttpsError("permission-denied", "You cannot validate another user's display handle.");
  }

  const normalizedHandle = typeof displayHandleRaw === "string" ? displayHandleRaw.trim() : null;
  if (!normalizedHandle) return {available: true, displayHandle: null};

  const existingSnap = await db.collection("users").where("display_handle", "==", normalizedHandle).limit(2).get();
  const takenByAnotherUser = existingSnap.docs.some((doc) => doc.id !== userId);
  return {available: !takenByAnotherUser, displayHandle: normalizedHandle};
});

export const enforceOneSubscriptionPerSubject = onDocumentCreated("subscriptions/{subscriptionId}", async (event) => {
  const snapshot = event.data;
  if (!snapshot) return;
  const subscription = snapshot.data();
  if (!subscription) return;
  const subscriptionId = event.params.subscriptionId;
  const studentId = getString(subscription.student_id);
  const subjectId = getString(subscription.subject_id);
  if (!studentId || !subjectId) throw new Error(`Invalid subscription data: ${subscriptionId}`);

  if (
    subscription.duration_type === "semester" &&
    (subscription.status === "active" || subscription.status === "trial") &&
    (!(subscription.end_date instanceof Timestamp) ||
      typeof subscription.academic_period_id !== "string")
  ) {
    const binding = await resolveSubscriptionPeriodBinding();
    await snapshot.ref.update({
      academic_period_id: binding.academicPeriodId,
      ...(binding.endDate ? {end_date: binding.endDate} : {}),
    });
  }

  if (subscription.is_deleted === true || subscription.status !== "active") return;

  const subscriptionsSnap = await db.collection("subscriptions")
    .where("student_id", "==", studentId)
    .where("subject_id", "==", subjectId)
    .where("status", "==", "active")
    .get();

  const activeOthers = subscriptionsSnap.docs.filter(
    (doc) => doc.id !== subscriptionId && doc.data().is_deleted !== true,
  );
  if (activeOthers.length === 0) return;

  const currentSubscription = event.data;
  if (!currentSubscription) return;

  await currentSubscription.ref.update({
    is_deleted: true,
    deleted_at: FieldValue.serverTimestamp(),
    deleted_by: "system",
    updated_at: FieldValue.serverTimestamp(),
    updated_by: "system",
  });

  await writeAnalyticsEvent(studentId, "Duplicate Subscription Rejected", subscriptionId, {
    subject_id: subjectId,
    rejected_subscription_id: subscriptionId,
    existing_subscription_id: activeOthers[0].id,
  });
});

async function sendNotificationNow(
  notificationId: string,
  notificationData: DocumentData,
  onlyDeviceIds?: Set<string>,
) {
  const userId = getString(notificationData.user_id);
  if (!userId) throw new Error(`Notification ${notificationId} has no valid user_id.`);

  const userSnap = await db.collection("users").doc(userId).get();
  if (!userSnap.exists) throw new Error(`User not found: ${userId}`);
  const userData = dataOf(userSnap.data());
  const notificationType = getNotificationType(notificationData);
  const critical = isCriticalNotification(notificationType, notificationData);

  if (!critical && isWithinQuietHours(getQuietHoursConfig(userData))) {
    await db.collection("notifications").doc(notificationId).update({
      delivery_status: "queued_quiet_hours",
      updated_at: FieldValue.serverTimestamp(),
      updated_by: "system",
    });
    return {queued: true, sent: 0, failed: 0, failedDeviceIds: [] as string[]};
  }

  const devices = await getDeviceTokens(userId, onlyDeviceIds);
  if (devices.length === 0) {
    await db.collection("notifications").doc(notificationId).update({
      delivery_status: "in_app_only",
      updated_at: FieldValue.serverTimestamp(),
      updated_by: "system",
    });
    return {queued: false, sent: 0, failed: 0, failedDeviceIds: [] as string[]};
  }

  const subjectId = getString(notificationData.subject_id) ?? undefined;
  const groupingKey = getGroupingKey(userId, notificationType, subjectId);
  const imageUrl = getString(notificationData.image_url);
  const deepLink = getString(notificationData.deep_link);
  const actions = Array.isArray(notificationData.actions) ? notificationData.actions : [];
  const androidActions = actions
    .filter((action: unknown): action is Record<string, unknown> =>
      typeof action === "object" &&
      action !== null &&
      typeof (action as Record<string, unknown>).action_type === "string" &&
      typeof (action as Record<string, unknown>).title === "string")
    .slice(0, 3)
    .map((action: Record<string, unknown>) => ({
      action_type: action.action_type as string,
      title: action.title as string,
      reference_id: action.reference_id ?? null,
    }));

  const recentSnap = await db.collection("notifications")
    .where("user_id", "==", userId)
    .where("notification_type", "==", notificationType)
    .limit(50)
    .get();
  const groupCount = recentSnap.docs.filter((doc) => {
    const data = doc.data();
    return getString(data.subject_id) === subjectId && data.is_read !== true;
  }).length;

  const messages: Message[] = devices.map((device) => ({
    token: device.token,
    notification: {
      title: getString(notificationData.title) ?? "Dr. Tarek Platform",
      body: getString(notificationData.body) ?? "",
      ...(imageUrl ? {imageUrl} : {}),
    },
    data: {
      notification_id: notificationId,
      notification_type: notificationType,
      grouping_key: groupingKey,
      group_count: String(Math.max(groupCount, 1)),
      ...(subjectId ? {subject_id: subjectId} : {}),
      ...(deepLink ? {deep_link: deepLink} : {}),
      actions: JSON.stringify(androidActions),
    },
    android: {
      priority: critical || notificationData.priority === "high" ? "high" : "normal",
      notification: {
        tag: groupingKey,
        ...(imageUrl ? {imageUrl} : {}),
      },
    },
    apns: {
      headers: {"apns-collapse-id": groupingKey},
      payload: {
        aps: {
          "thread-id": groupingKey,
          "mutable-content": 1,
          ...(critical ? {"content-available": 1} : {}),
        },
      },
    },
  }));

  const response = await messaging.sendEach(messages);
  let sent = 0;
  let failed = 0;
  const failedDeviceIds: string[] = [];
  const failureMessages: string[] = [];

  for (let index = 0; index < response.responses.length; index += 1) {
    const result = response.responses[index];
    const device = devices[index];
    if (result.success) {
      sent += 1;
      continue;
    }

    failed += 1;
    failedDeviceIds.push(device.id);
    const errorCode = result.error?.code ?? "unknown";
    const errorMessage = result.error?.message ?? "Unknown FCM error.";
    failureMessages.push(`${errorCode}: ${errorMessage}`);

    if (errorCode === "messaging/registration-token-not-registered" || errorCode === "messaging/invalid-registration-token") {
      await removeInvalidToken(device.id);
    }
  }

  await db.collection("notifications").doc(notificationId).update({
    sent_at: sent > 0 ? FieldValue.serverTimestamp() : null,
    delivery_status: failed === 0 ? "sent" : sent > 0 ? "partially_sent" : "failed",
    grouping_key: groupingKey,
    group_count: Math.max(groupCount, 1),
    updated_at: FieldValue.serverTimestamp(),
    updated_by: "system",
  });

  if (sent > 0) {
    await writeAnalyticsEvent(userId, "Notification Sent", notificationId, {
      notification_type: notificationType,
      grouping_key: groupingKey,
      sent_devices: sent,
      failed_devices: failed,
    });
  }

  if (failed > 0) {
    throw new NotificationDeliveryError(
      failureMessages.join(" | "),
      failedDeviceIds,
    );
  }
  return {queued: false, sent, failed, failedDeviceIds};
}

export const sendPushNotification = onDocumentCreated("notifications/{notificationId}", async (event) => {
  const notificationData = event.data?.data();
  if (!notificationData) return;
  const notificationId = event.params.notificationId;

  try {
    await sendNotificationNow(notificationId, notificationData);
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    const retrySnap = await db.collection("notifications").doc(notificationId).collection("retries")
      .where("status", "==", "pending").get();
    const usedAttempts = retrySnap.docs.reduce(
      (max, doc) => Math.max(max, getNumber(doc.data().attempt) ?? 0),
      0,
    );

    const failedDeviceIds =
      error instanceof NotificationDeliveryError ?
        error.failedDeviceIds :
        [];

    if (usedAttempts >= MAX_NOTIFICATION_RETRIES) {
      await moveToDeadLetterQueue(notificationId, notificationData, errorMessage, usedAttempts);
      await db.collection("notifications").doc(notificationId).update({
        delivery_status: "failed",
        updated_at: FieldValue.serverTimestamp(),
        updated_by: "system",
      });
      const userId = getString(notificationData.user_id);
      if (userId) {
        await writeAnalyticsEvent(
          userId,
          "Notification Delivery Failed",
          notificationId,
          {reason: errorMessage, attempts: usedAttempts},
        );
      }
      return;
    }

    await scheduleRetry(
      notificationId,
      notificationData,
      usedAttempts + 1,
      errorMessage,
      failedDeviceIds,
    );
  }
});

export const processNotificationQueue = onSchedule("every 1 minutes", async () => {
  const now = Timestamp.now();

  const retrySnap = await db.collectionGroup("retries").where("status", "==", "pending").limit(50).get();
  for (const retryDoc of retrySnap.docs) {
    const retryData = retryDoc.data();
    const nextAttemptAt = retryData.next_attempt_at;
    if (nextAttemptAt?.toMillis && nextAttemptAt.toMillis() > now.toMillis()) continue;

    const notificationId = getString(retryData.notification_id);
    if (!notificationId) {
      await retryDoc.ref.update({status: "invalid", updated_at: FieldValue.serverTimestamp()});
      continue;
    }

    const notificationSnap = await db.collection("notifications").doc(notificationId).get();
    if (!notificationSnap.exists) {
      await retryDoc.ref.update({status: "invalid", updated_at: FieldValue.serverTimestamp()});
      continue;
    }
    const notificationData = notificationSnap.data();
    if (!notificationData) continue;

    const failedDeviceIds = Array.isArray(retryData.failed_device_ids) ? new Set<string>(retryData.failed_device_ids.filter((id: unknown): id is string => typeof id === "string")) : undefined;

    try {
      await sendNotificationNow(notificationId, notificationData, failedDeviceIds);
      await retryDoc.ref.update({status: "completed", completed_at: FieldValue.serverTimestamp(), updated_at: FieldValue.serverTimestamp()});
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      const currentAttempt = getNumber(retryData.attempt) ?? 1;
      const nextFailedIds =
        error instanceof NotificationDeliveryError ?
          error.failedDeviceIds :
          (Array.isArray(retryData.failed_device_ids) ?
            retryData.failed_device_ids as string[] : []);

      if (currentAttempt >= MAX_NOTIFICATION_RETRIES) {
        await retryDoc.ref.update({status: "exhausted", last_error: errorMessage, updated_at: FieldValue.serverTimestamp()});
        await moveToDeadLetterQueue(notificationId, notificationData, errorMessage, currentAttempt);
        await db.collection("notifications").doc(notificationId).update({delivery_status: "failed", updated_at: FieldValue.serverTimestamp(), updated_by: "system"});
        const userId = getString(notificationData.user_id);
        if (userId) await writeAnalyticsEvent(userId, "Notification Delivery Failed", notificationId, {reason: errorMessage, attempts: currentAttempt});
        continue;
      }

      const delayMinutes = RETRY_DELAY_MINUTES[currentAttempt] ?? RETRY_DELAY_MINUTES[RETRY_DELAY_MINUTES.length - 1];
      await retryDoc.ref.update({
        attempt: currentAttempt + 1,
        last_error: errorMessage,
        failed_device_ids: nextFailedIds,
        next_attempt_at: Timestamp.fromMillis(Date.now() + delayMinutes * 60 * 1000),
        updated_at: FieldValue.serverTimestamp(),
      });
    }
  }

  const quietSnap = await db.collection("notifications")
    .where("delivery_status", "==", "queued_quiet_hours")
    .limit(50)
    .get();
  for (const notificationDoc of quietSnap.docs) {
    try {
      await sendNotificationNow(notificationDoc.id, notificationDoc.data());
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      const failedDeviceIds =
        error instanceof NotificationDeliveryError ?
          error.failedDeviceIds :
          [];
      await scheduleRetry(
        notificationDoc.id,
        notificationDoc.data(),
        1,
        errorMessage,
        failedDeviceIds,
      );
    }
  }
});

export const setPlanQualityFeature = onCall(SECURE_CALL_OPTS, async (request) => {
  const actorId = requireAdminOrDoctor(request);
  const planId = getString(request.data?.planId);
  const quality = getString(request.data?.quality)?.toLowerCase();
  const enabled = request.data?.enabled;
  const allowedQualities = new Set([
    "144p",
    "240p",
    "360p",
    "480p",
    "720p",
    "1080p",
    "1440p",
    "2k",
    "4k",
  ]);
  if (!planId || !quality || typeof enabled !== "boolean") {
    throw new HttpsError("invalid-argument", "planId, quality, and enabled are required.");
  }
  if (!allowedQualities.has(quality)) {
    throw new HttpsError("invalid-argument", "Unsupported video quality.");
  }
  const featureKey = `video.quality.${quality}`;
  const featureSnap = await db
    .collection("plan_features")
    .where("plan_id", "==", planId)
    .where("feature_key", "==", featureKey)
    .limit(1)
    .get();
  const featureRef = featureSnap.empty ?
    db.collection("plan_features").doc() :
    featureSnap.docs[0].ref;
  const data = {
    plan_id: planId,
    feature_key: featureKey,
    feature_value: quality,
    enabled,
    updated_at: FieldValue.serverTimestamp(),
    updated_by: actorId,
  };
  await featureRef.set(data, {merge: true});
  await writeAnalyticsEvent(actorId, "Update Plan Video Quality", planId, {
    feature_key: featureKey,
    enabled,
  }, request);
  return {ok: true, planId, quality, enabled};
});

/**
 * Feature Matrix keys with direct monetization impact.
 *
 * Accidentally enabling the rolling watch window on a paid plan (or
 * disabling it on Center Free) changes what paying students receive, so
 * these keys are Doctor (Platform Owner) only — consistent with doc 14
 * ("Configure Feature Matrix: Doctor only"). All other keys remain
 * Admin-or-Doctor, matching the existing quality-matrix precedent.
 * The dashboard mirrors this by locking these rows for Admin sessions;
 * the backend gate below is the true enforcement boundary.
 */
const SENSITIVE_PLAN_FEATURES: ReadonlySet<string> = new Set([
  "video.rolling_window.enabled",
  "video.rolling_window.hours",
]);

/**
 * Generic Feature Matrix writer for the Subscription Plans dashboard.
 *
 * One callable drives every toggle/value on the plans page
 * (Public FREE / Center FREE / Center PRO / Center MAX), instead of a
 * separate callable per feature family. Mirrors the audited
 * `setPlatformFeature` pattern: server-side auth, find-or-create by
 * (plan_id, feature_key), dual `value`/`feature_value` write for
 * reader compatibility, analytics + admin_audit_log entries.
 *
 * Reads: `planId`, `featureKey`, `enabled` (boolean). Optional `value`
 * for number/string features (preview minutes, quality max, counters).
 * `valueType` is stored as documentation for dashboard editors.
 */
export const setPlanFeature = onCall(SECURE_CALL_OPTS, async (request) => {
  const actorId = requireAuthenticated(request);
  const planId = getString(request.data?.planId);
  const featureKey = getString(request.data?.featureKey);
  if (!planId || !featureKey) {
    throw new HttpsError(
      "invalid-argument",
      "planId and featureKey are required.",
    );
  }
  if (SENSITIVE_PLAN_FEATURES.has(featureKey)) {
    if (callerRole(request) !== "doctor") {
      throw new HttpsError(
        "permission-denied",
        "Doctor (Platform Owner) permission is required for this feature.",
      );
    }
  } else {
    const role = callerRole(request);
    if (!role || !ADMIN_ROLES.has(role)) {
      throw new HttpsError(
        "permission-denied",
        "Admin or Doctor permission is required.",
      );
    }
  }
  const actorRole = callerRole(request) === "doctor" ? "doctor" : "admin";
  const enabled = request.data?.enabled;
  const rawValue = request.data?.value;
  const valueType = getString(request.data?.valueType) ?? "boolean";

  if (typeof enabled !== "boolean") {
    throw new HttpsError(
      "invalid-argument",
      "enabled must be a boolean.",
    );
  }
  if (!/^[a-z0-9]+(\.[a-z0-9_]+)+$/i.test(featureKey)) {
    throw new HttpsError("invalid-argument", "Unsupported feature key.");
  }

  const planSnap = await db.collection("plans").doc(planId).get();
  if (!planSnap.exists) {
    throw new HttpsError("not-found", "Membership plan was not found.");
  }

  const value =
    rawValue === undefined || rawValue === null ? null : rawValue;
  if (value !== null && !["number", "string", "boolean"].includes(typeof value) &&
    !Array.isArray(value) && typeof value !== "object") {
    throw new HttpsError("invalid-argument", "Unsupported feature value.");
  }

  const featureSnap = await db
    .collection("plan_features")
    .where("plan_id", "==", planId)
    .where("feature_key", "==", featureKey)
    .limit(1)
    .get();
  const featureRef = featureSnap.empty ?
    db.collection("plan_features").doc(`${planId}_${featureKey.replace(/\./g, "_")}`) :
    featureSnap.docs[0].ref;
  const previous = featureSnap.empty ? null : dataOf(featureSnap.docs[0].data());

  const now = FieldValue.serverTimestamp();
  await featureRef.set({
    plan_id: planId,
    feature_key: featureKey,
    enabled,
    // Dual write: seed scripts use `value`, entitlement readers use
    // `feature_value`. Keep both in sync until readers are unified.
    value,
    feature_value: value,
    value_type: valueType,
    updated_at: now,
    updated_by: actorId,
    ...(previous ? {} : {created_at: now, created_by: actorId}),
  }, {merge: true});

  await writeAnalyticsEvent(actorId, "Update Plan Feature", planId, {
    feature_key: featureKey,
    previous_enabled: previous?.enabled ?? null,
    new_enabled: enabled,
    value,
  }, request);
  await db.collection("admin_audit_log").add({
    action: "plan_feature_toggled",
    entity: "plan_feature",
    target_id: featureRef.id,
    plan_id: planId,
    feature_key: featureKey,
    previous_enabled: previous?.enabled ?? null,
    new_enabled: enabled,
    previous_value: previous?.value ?? previous?.feature_value ?? null,
    new_value: value,
    actor_id: actorId,
    actor_role: actorRole,
    created_at: now,
    timestamp: now,
  });

  return {ok: true, planId, featureKey, enabled, value};
});

export const generateBunnySignedUrl = onCall({
  ...SECURE_CALL_OPTS,
  secrets: [SECRET_BUNNY_TOKEN_KEY, SECRET_BUNNY_PLAYBACK_URL_TEMPLATE],
}, async (request) => {
  const userId = requireAuthenticated(request);
  const videoId = getString(request.data?.videoId);
  const requestedQuality = getString(request.data?.quality);
  const subjectId = getString(request.data?.subjectId);
  const deviceId = getString(request.data?.deviceId);
  // Identity fix: the route lecture asserted by the client (optional for
  // backward compatibility). When present it — not the video file — is the
  // authorization identity; the video file only selects the bytes.
  const requestedLectureId = getString(request.data?.lectureId);

  if (!videoId) throw new HttpsError("invalid-argument", "videoId is required.");
  // VIDEO-ID-ONLY: URLs/embed links are invalid even when they embed a
  // GUID segment — only a bare GUID may issue playback.
  if (!isValidBunnyVideoId(videoId)) {
    throw new HttpsError(
      "invalid-argument",
      "videoId must be a bare Bunny Video ID (GUID) — URLs are not accepted.",
    );
  }
  if (!deviceId) throw new HttpsError("invalid-argument", "deviceId is required.");
  // Startup-latency optimization (I/O concurrency only): the rate-limit
  // check, the issuer user read, and the lecture-resource lookup depend
  // only on request fields — none consumes another's result. They are
  // issued together so one round trip covers all three. Verdicts below
  // are enforced in the EXACT original order, so allow/deny outcomes and
  // error codes/messages are identical.
  // VIDEO-ID-ONLY: exact GUID match only — no URL → GUID fallback.
  // Identity fix: when the client asserts a lecture, the lookup is scoped
  // to (lecture, video) so a shared bunny_video_id can never resolve the
  // wrong lecture. Legacy lookups fetch up to 2 rows so a duplicated video
  // fails closed (ambiguous) instead of collapsing to limit(1) first-match.
  const [rateLimitOutcome, issuerOutcome, resourceOutcome] = await Promise.allSettled([
    assertVideoRequestAllowed(userId, deviceId),
    db.collection("users").doc(userId).get(),
    (async () => {
      if (requestedLectureId != null) {
        return db.collection("lecture_resources")
          .where("lecture_id", "==", requestedLectureId)
          .where("bunny_video_id", "==", videoId.trim())
          .limit(1)
          .get();
      }
      return db.collection("lecture_resources")
        .where("bunny_video_id", "==", videoId.trim())
        .limit(2)
        .get();
    })(),
  ]);
  // Ordered rethrow preserves the original sequential error precedence:
  // rate-limit verdict first, then user existence, then resource lookup.
  if (rateLimitOutcome.status === "rejected") throw rateLimitOutcome.reason;
  if (issuerOutcome.status === "rejected") throw issuerOutcome.reason;
  const issuerSnap = issuerOutcome.value;
  if (!issuerSnap.exists) throw new HttpsError("not-found", "User not found.");

  // ADR-004: no global plan is consulted. The student's type comes from
  // their own user document; the Subject's plan comes from that Subject's
  // subscription below; the device tier resolves server-side per Subject.
  const issuerStudentType = getString(dataOf(issuerSnap.data()).student_type);

  if (resourceOutcome.status === "rejected") throw resourceOutcome.reason;
  const resourceSnap = resourceOutcome.value;
  // Identity fix: resolve through the pure matcher (fail-closed). Legacy
  // outcomes are byte-identical (missing keeps its exact error); every new
  // denial below only fires on states the old code resolved unsoundly.
  const resourceMatch = matchIssuanceResource(
    resourceSnap.docs.map((doc) => {
      const data = dataOf(doc.data());
      return {
        id: doc.id,
        lectureId: getString(data.lecture_id),
        deleted: data.is_deleted === true,
      };
    }),
    {requestedLectureId},
  );
  if (resourceMatch.kind === "mismatch") {
    throw new HttpsError(
      "invalid-argument",
      "The requested lecture is not linked to this video.",
    );
  }
  if (resourceMatch.kind === "missing") {
    throw new HttpsError("not-found", "Video resource not found.");
  }
  if (resourceMatch.kind === "ambiguous") {
    throw new HttpsError(
      "failed-precondition",
      "Video resource is ambiguous; lecture identity cannot be resolved.",
    );
  }
  const resourceDoc = resourceSnap.docs.find(
    (doc) => doc.id === resourceMatch.resourceId,
  );
  if (!resourceDoc) {
    throw new HttpsError("not-found", "Video resource not found.");
  }
  const resource = dataOf(resourceDoc.data());
  const derivedLectureId = getString(resource.lecture_id);
  if (!derivedLectureId) {
    throw new HttpsError(
      "failed-precondition",
      "Video resource is not linked to a lecture.",
    );
  }
  // Defense in depth: the scoped lookup above already guarantees this, but
  // an asserted identity must never silently resolve elsewhere.
  if (requestedLectureId != null && derivedLectureId !== requestedLectureId) {
    throw new HttpsError(
      "invalid-argument",
      "Lecture identity mismatch for this video.",
    );
  }
  // The route lecture (asserted by the client, verified above) is the
  // authorization identity; the video file only selects the bytes.
  const lectureId = requestedLectureId ?? derivedLectureId;
  // V1 per-lecture access: explicit deny wins before any plan checks.
  await assertLectureAccessNotDenied(userId, lectureId);

  const lectureSnap = await db.collection("lectures").doc(lectureId).get();
  if (!lectureSnap.exists) {
    // A client-asserted identity pointing nowhere is a client fault.
    if (requestedLectureId != null) {
      throw new HttpsError(
        "invalid-argument",
        "The requested lecture does not exist.",
      );
    }
    throw new HttpsError("not-found", "Lecture not found.");
  }
  const lecture = dataOf(lectureSnap.data());
  const lectureSubjectId = getString(lecture.subject_id);
  const linkedSubjectId = subjectId ?? lectureSubjectId;

  let resolvedSubjectId = linkedSubjectId;
  let sectionSubjectId: string | null = null;
  if (!resolvedSubjectId) {
    const sectionId = getString(lecture.section_id);
    if (!sectionId) throw new HttpsError("failed-precondition", "Lecture section is missing.");
    const sectionSnap = await db.collection("subject_sections").doc(sectionId).get();
    sectionSubjectId = getString(sectionSnap.data()?.subject_id);
    resolvedSubjectId = sectionSubjectId;
  }
  if (!resolvedSubjectId) throw new HttpsError("failed-precondition", "Subject cannot be resolved.");
  // Fail closed on cross-subject mismatch: the lecture's own subject
  // (lecture.subject_id, else its section's subject_id) is authoritative.
  // A caller-supplied subjectId that disagrees must never authorize issuance
  // under a different subject's subscription/plan/device verdicts below.
  const authoritativeSubjectId = lectureSubjectId ?? sectionSubjectId;
  if (authoritativeSubjectId && resolvedSubjectId !== authoritativeSubjectId) {
    throw new HttpsError("invalid-argument", "Subject does not match this video.");
  }
  // The returned assignment snapshot is preserved below for the
  // request-scoped verifiedSubjectContext (same call, same verdict).
  const subjectAssignment = await requireEnabledSubjectAccess(userId, resolvedSubjectId);

  const subscriptionSnap = await db.collection("subscriptions")
    .where("student_id", "==", userId)
    .where("subject_id", "==", resolvedSubjectId)
    .where("status", "==", "active")
    .limit(1)
    .get();
  if (subscriptionSnap.empty) throw new HttpsError("permission-denied", "Active subject subscription is required.");

  const subjectSubscription = subscriptionSnap.docs[0].data();
  assertSubjectAccess(subjectSubscription);

  const subjectPlanId = getString(subjectSubscription.plan_id);
  if (!subjectPlanId) {
    throw new HttpsError("failed-precondition", "Subject subscription plan is missing.");
  }

  const subjectPlanSnap = await db.collection("plans").doc(subjectPlanId).get();
  if (!subjectPlanSnap.exists) {
    throw new HttpsError("failed-precondition", "Subject subscription plan was not found.");
  }

  const subjectPlan = dataOf(subjectPlanSnap.data());
  if (
    subjectPlan.is_active !== true ||
    subjectPlan.student_type !== issuerStudentType
  ) {
    throw new HttpsError("permission-denied", "Subject subscription plan is not valid for this student.");
  }

  // Request-scoped consolidation: ONE plan_features read for this issuance.
  // video.access, device.max_count (via the tier evaluator below),
  // video.preview_duration, the quality matrix, and the rolling-window
  // policy ALL derive from this single result — identical values, no
  // re-queries. Missing features behave exactly as before (null lookups).
  const planFeatures = await getPlanFeatures(subjectPlanId);

  // Rolling watch window ("تحديد المشاهدة كل 24 ساعة"): matrix-driven
  // on any plan via video.rolling_window.enabled/_hours, with a legacy
  // fallback to free/24h while the matrix is unconfigured.
  const windowPolicy = resolveRollingWindowPolicy({
    enabledFeature: findPlanFeature(planFeatures, "video.rolling_window.enabled"),
    hoursFeature: findPlanFeature(planFeatures, "video.rolling_window.hours"),
    studentType: issuerStudentType,
    planKey: getString(subjectPlan.plan_key),
    planId: subjectPlanId,
  });

  // Window-before-tier precedence (Center Free A → Exit → C regression
  // fix): when the caller's rolling window is active for a DIFFERENT
  // lecture, issuance must fail with the SAME 24-hour restriction
  // (resource-exhausted) regardless of device tier — never Guest preview,
  // public fallback, or device-unauthorized behavior. Read-only: blocked
  // requests throw before any tier evaluation or window write; allowed
  // requests fall through to the existing transactional check+create
  // below unchanged (identical side effects).
  if (windowPolicy.enforced) {
    const precheckSnap = await db.collection("video_watch_windows").doc(userId).get();
    const precheckDecision = decideVideoWatchWindow(
      precheckSnap.data() as any,
      lectureId,
      Date.now(),
    );
    if (issuanceDenialPrecedence(precheckDecision) === "window") {
      const precheckWindow = precheckSnap.data() as any;
      console.log(
        `generateBunnySignedUrl identity requestedLecture=${requestedLectureId ?? "-"} ` +
        `resolvedLecture=${lectureId} subject=${resolvedSubjectId} video=${videoId} ` +
        `tier=preempted window=blocked:${precheckDecision.reason}`,
      );
      throw new HttpsError("resource-exhausted", FREE_WINDOW_BLOCKED_MESSAGE, {
        windowExpiresAtMs: precheckWindow.window_expires_at.toMillis(),
        activeLectureId: precheckWindow.active_lecture_id,
        windowHours: windowPolicy.hours,
      });
    }
  }

  // ADR-004 tier gate: Full proceeds below; Guest receives the existing
  // structural preview contract (per-lecture gate + plan default) or a
  // permission-denied when preview is not enabled. No consumption
  // accounting exists yet (open business policy) — nothing is tracked here.
  const tier = await evaluateSubjectTier({
    studentId: userId,
    subjectId: resolvedSubjectId,
    deviceId,
    ipAddress: typeof request.rawRequest?.ip === "string" ? request.rawRequest.ip : null,
    planFeatures,
    // Request-scoped verified snapshots: the assignment, subscription, and
    // plan above already passed the same checks the tier evaluator would
    // re-read. Predicates are re-applied inside; only duplicate I/O is cut.
    verifiedSubjectContext: {
      assignment: subjectAssignment,
      subscription: subjectSubscription,
      planId: subjectPlanId,
      plan: subjectPlan,
    },
  });
  let guestPreviewSeconds: number | null = null;
  if (tier.tier === "guest") {
    const guestFields = readGuestPreviewFields(lecture);
    const planDefault = findPlanFeature(planFeatures, "video.preview_duration");
    guestPreviewSeconds = resolveGuestPreviewSeconds({
      guestEnabled: guestFields.guestEnabled,
      lectureMinutes: guestFields.lectureMinutes,
      planDefaultMinutes: planDefault ? getNumber(planDefault.feature_value) : null,
    });
    if (guestPreviewSeconds === null) {
      throw new HttpsError("permission-denied", "Guest preview is not enabled for this lecture.");
    }
  }

  // ADR-004 Max continuity: on a 2-allowance Subject, Full video issuance
  // runs the same begin-or-takeover transaction as the session callable, so
  // starting playback here supersedes the other authorized device and
  // resumes from the persisted position. Single-allowance Subjects and
  // Guest requests never touch session state.
  let playbackSession: BeginOutcome | null = null;
  if (tier.tier === "full" && tier.allowance >= 2) {
    const content = await resolveSessionContent(userId, resolvedSubjectId, {
      lectureId,
      videoId,
    });
    playbackSession = await beginOrTakeoverSession({
      studentId: userId,
      subjectId: resolvedSubjectId,
      deviceHash: tier.deviceHash,
      content,
    });
  }

  const accessFeature = findPlanFeature(planFeatures, "video.access");
  if (accessFeature?.enabled !== true) {
    throw new HttpsError("permission-denied", "Video access is not enabled for your plan.");
  }

  const qualityFeatures = planFeatures
    .filter((feature) =>
      typeof feature.feature_key === "string" &&
      feature.feature_key.startsWith("video.quality.") &&
      feature.enabled === true,
    );
  // Mirror the Flutter entitlement contract: `video.quality.max` is a cap,
  // not a literal quality. Expand it to every quality at or below the cap
  // and never emit the literals `max`/`auto` as a Bunny quality segment.
  const allowedQualities = new Set<string>();
  const RANK_ORDER = ["144p", "240p", "360p", "480p", "720p", "1080p", "1440p", "4k"];
  const rankOf = (q: string) => qualityRank(q);
  for (const feature of qualityFeatures) {
    const suffix = getString(feature.feature_key)?.replace("video.quality.", "") ?? "";
    if (!suffix) continue;
    const lower = suffix.toLowerCase();
    if (lower === "max") {
      const capRaw = getString(feature.feature_value) ?? getString((feature as any).value);
      const cap = (capRaw ?? "").toLowerCase();
      const capRank = rankOf(cap);
      if (capRank <= 0) continue;
      for (const q of RANK_ORDER) {
        if (rankOf(q) <= capRank) allowedQualities.add(q);
      }
      continue;
    }
    if (lower === "auto") continue;
    if (rankOf(lower) > 0) allowedQualities.add(lower);
  }
  if (allowedQualities.size === 0) {
    throw new HttpsError("failed-precondition", "No video quality is configured for this plan.");
  }
  const normalizedRequested = requestedQuality?.toLowerCase() ?? null;
  if (normalizedRequested && !allowedQualities.has(normalizedRequested)) {
    throw new HttpsError("permission-denied", "Requested video quality is not enabled for this plan.");
  }
  const selectedQuality = normalizedRequested ??
    [...allowedQualities].sort((left, right) => qualityRank(right) - qualityRank(left))[0];

  // Transactional window check+create. The policy was resolved above
  // (shared with the read-only window-before-tier pre-check); this
  // transaction re-decides atomically and owns all window writes.
  // Blocked requests never reach this point (the pre-check threw first).

  // Diagnostic identity line (§15): requested vs resolved lecture, subject,
  // resource, tier and window decision. IDs only — never URLs or secrets.
  let windowDecision = windowPolicy.enforced ? "unknown" : "not_enforced";
  if (windowPolicy.enforced) {
    const windowRef = db.collection("video_watch_windows").doc(userId);
    await db.runTransaction(async (t) => {
      const windowSnap = await t.get(windowRef);
      const existingWindow = windowSnap.data() as any;
      const now = Date.now();
      const decision = decideVideoWatchWindow(existingWindow, lectureId, now);
      windowDecision = decision.allowed ?
        `allowed:${decision.reason}` :
        `blocked:${decision.reason}`;

      if (!decision.allowed) {
        throw new HttpsError("resource-exhausted", FREE_WINDOW_BLOCKED_MESSAGE, {
          windowExpiresAtMs: existingWindow.window_expires_at.toMillis(),
          activeLectureId: existingWindow.active_lecture_id,
          windowHours: windowPolicy.hours,
        });
      }

      if (decision.reason === "no_window" || decision.reason === "expired") {
        const expiresAt = Timestamp.fromMillis(now + windowPolicy.hours * 60 * 60 * 1000);
        t.set(windowRef, {
          active_lecture_id: lectureId,
          window_expires_at: expiresAt,
          user_id: userId,
        });
      }
    });
  }
  console.log(
    `generateBunnySignedUrl identity requestedLecture=${requestedLectureId ?? "-"} ` +
    `resolvedLecture=${lectureId} subject=${resolvedSubjectId} video=${videoId} ` +
    `tier=${tier.tier} window=${windowDecision}`,
  );

  const template = getEnv("BUNNY_PLAYBACK_URL_TEMPLATE");
  const secret = getEnv("BUNNY_TOKEN_KEY");
  const expires = Math.floor(Date.now() / 1000) + 300;
  // Accept every historical placeholder spelling so a misconfigured
  // template fails loudly instead of emitting a URL with `{...}` in it.
  let rawUrl = template
    .replace("{video_id}", encodeURIComponent(videoId))
    .replace("{videoId}", encodeURIComponent(videoId))
    .replace("{id}", encodeURIComponent(videoId))
    .replace("{quality}", encodeURIComponent(selectedQuality))
    .replace("{res}", encodeURIComponent(selectedQuality));
  if (rawUrl.includes("{") && rawUrl.includes("}")) {
    throw new HttpsError("failed-precondition", "Server configuration BUNNY_PLAYBACK_URL_TEMPLATE has unresolved placeholders.");
  }
  // P1 web fix: Flutter Web (Chrome/Edge/Firefox) feeds the URL into a
  // plain <video> element, which cannot demux HLS playlists
  // (DEMUXER_ERROR_COULD_NOT_PARSE). When the client passes format=mp4
  // (web only), rewrite the Bunny Stream HLS playlist path to the
  // direct-play MP4 rendition (`.../playlist.m3u8` -> `.../play_720p.mp4`).
  // Per Bunny docs the MP4 filename is play_{height}p.mp4 capped at 1080p
  // (higher renditions have no MP4 file and would 404), and only videos
  // uploaded after enabling "MP4 Fallback" on the library have MP4 files
  // at all. Requires "MP4 Fallback / Direct MP4" enabled on the Bunny
  // Stream library; non-playlist templates pass through unchanged. The
  // directory token below authorizes the whole video directory, so both
  // playlist and MP4 paths validate.
  const requestedFormat = getString(request.data?.format)?.toLowerCase();
  if (requestedFormat === "mp4" && /playlist\.m3u8/i.test(rawUrl)) {
    const mp4Rank = Math.min(qualityRank(selectedQuality), qualityRank("1080p"));
    const mp4Quality = mp4QualityForRank(mp4Rank);
    rawUrl = rawUrl.replace(/playlist\.m3u8/i, `play_${mp4Quality}.mp4`);
  }
  const url = new URL(rawUrl);
  // Directory-token mode: authorizes the video directory `/{videoId}/`
  // (master playlist, rendition playlists, segments, MP4 rendition alike),
  // so relative HLS children inherit authentication by path resolution.
  // The returned contract (url, expiresAt, quality, session fields) and
  // the expiry policy are unchanged; only the URL shape carries the token
  // in-path instead of in-query.
  const directoryScope = `/${videoId}/`;
  const token = hashVideoDirectoryToken(secret, directoryScope, expires);
  const signedUrl =
    `${url.origin}/bcdn_token=${token}` +
    `&token_path=${encodeURIComponent(directoryScope)}` +
    `&expires=${expires}${url.pathname}`;
  const signed = new URL(signedUrl);

  await writeAnalyticsEvent(userId, "Open Video", videoId, {
    subject_id: resolvedSubjectId,
    quality: selectedQuality,
    tier: tier.tier,
    preview_limit_seconds: guestPreviewSeconds,
  });
  // Full responses keep their exact existing shape. Guest responses add
  // previewLimitSeconds from the existing structural preview contract
  // (0 means the client shows the upgrade prompt immediately) plus the
  // additive previewAudience discriminator (messaging only — enforcement
  // and tiers are unchanged). Assembled atomically: both keys together
  // on Guest, neither on Full — never one without the other.
  const guestVerdict = buildGuestIssuanceVerdict({
    tier: tier.tier,
    subjectPlanId,
    subjectPlan,
    guestPreviewSeconds,
  });
  return {
    url: signed.toString(),
    expiresAt: expires,
    quality: selectedQuality,
    ...guestVerdict,
    ...(playbackSession ? {
      sessionToken: playbackSession.sessionToken,
      positionSeconds: playbackSession.positionSeconds,
      takeover: playbackSession.tookOver,
      heartbeatIntervalMs: PLAYBACK_HEARTBEAT_INTERVAL_MS,
    } : {}),
  };
});

export const getVideoWatchWindow = onCall(SECURE_CALL_OPTS, async (request) => {
  const userId = requireAuthenticated(request);
  const windowSnap = await db.collection("video_watch_windows").doc(userId).get();
  if (!windowSnap.exists) return {active: false};
  const window = windowSnap.data() as any;
  if (!window.window_expires_at) return {active: false};

  const now = Date.now();
  const expiresAtMs = window.window_expires_at.toMillis();
  if (now >= expiresAtMs) return {active: false};

  return {
    active: true,
    activeLectureId: window.active_lecture_id,
    windowExpiresAtMs: expiresAtMs,
  };
});

export const revalidateOfflineAccess = onCall(SECURE_CALL_OPTS, async (request) => {
  const userId = requireAuthenticated(request);
  const subjectIds = Array.isArray(request.data?.subjectIds) ? request.data.subjectIds.filter((id: unknown): id is string => typeof id === "string" && id.length > 0) : [];
  // ADR-004: offline authority is per (student, subject, device). The
  // device identity is required so Guest devices resolve to wipe; it is
  // namespaced by the authenticated uid and never trusted beyond that.
  const deviceId = normalizeDeviceId(request.data?.deviceId);
  if (!deviceId) throw new HttpsError("invalid-argument", "deviceId is required.");
  const results: Array<{subjectId: string; allowed: boolean; wipeRequired: boolean; reason?: string}> = [];

  for (const subjectId of subjectIds) {
    try {
      await requireEnabledSubjectAccess(userId, subjectId);
    } catch (error) {
      results.push({subjectId, allowed: false, wipeRequired: true, reason: error instanceof Error ? error.message : "subject_access_denied"});
      continue;
    }

    const subscriptionSnap = await db.collection("subscriptions")
      .where("student_id", "==", userId)
      .where("subject_id", "==", subjectId)
      .where("status", "==", "active")
      .limit(1)
      .get();

    if (subscriptionSnap.empty) {
      results.push({subjectId, allowed: false, wipeRequired: true, reason: "no_active_subscription"});
      continue;
    }

    try {
      assertSubjectAccess(subscriptionSnap.docs[0].data());
      const planId = getString(subscriptionSnap.docs[0].data().plan_id);
      if (!planId) throw new Error("missing_plan_id");
      // Read-only tier check: revalidation answers whether kept offline
      // bytes stay usable. It never claims a slot, never mutates, and
      // Guest resolves to wipe without a Full fallback key.
      const tier = await evaluateSubjectTier({
        studentId: userId,
        subjectId,
        deviceId,
        ipAddress: typeof request.rawRequest?.ip === "string" ? request.rawRequest.ip : null,
        bindIfFree: false,
      });
      if (tier.tier !== "full") {
        results.push({subjectId, allowed: false, wipeRequired: true, reason: "guest_tier"});
        continue;
      }
      const offlineFeature = await getPlanFeature(planId, "offline.mode");
      const allowed = offlineFeature?.enabled === true;
      results.push({subjectId, allowed, wipeRequired: !allowed, reason: allowed ? undefined : "offline_not_enabled"});
    } catch (error) {
      results.push({subjectId, allowed: false, wipeRequired: true, reason: error instanceof Error ? error.message : "access_revoked"});
    }
  }

  const wipeSubjects = results.filter((item) => item.wipeRequired).map((item) => item.subjectId);
  if (wipeSubjects.length > 0) {
    const devices = await getDeviceTokens(userId);
    for (const device of devices) {
      await messaging.send({
        token: device.token,
        data: {type: "subscription_revoked", subject_ids: JSON.stringify(wipeSubjects)},
        android: {priority: "high"},
        apns: {payload: {aps: {"content-available": 1}}},
      }).catch(() => undefined);
    }
  }

  return {results};
});

/**
/**
 * Shared helper: resolves document resource â†’ subject â†’ subscription â†’ plan,
 * verifies subject access and subscription, and returns context needed
 * by both the viewing and download endpoints.
 * @param {string} userId The student user ID.
 * @param {string} resourceId The lecture resource document ID.
 * @return {Promise<any>} The resolved document access data.
 */
async function resolveDocumentAccess(userId: string, resourceId: string) {
  const resourceSnap = await db.collection("lecture_resources").doc(resourceId).get();
  if (!resourceSnap.exists) throw new HttpsError("not-found", "Document resource not found.");
  const resource = dataOf(resourceSnap.data());
  const type = getString(resource.resource_type) ?? "attachment";
  if (!isDocumentResourceType(type)) throw new HttpsError("invalid-argument", "Resource is not a document.");

  const lectureId = getString(resource.lecture_id);
  if (!lectureId) throw new HttpsError("failed-precondition", "Document resource is not linked to a lecture.");
  // V1 per-lecture access: explicit deny wins before any plan checks.
  await assertLectureAccessNotDenied(userId, lectureId);
  const lectureSnap = await db.collection("lectures").doc(lectureId).get();
  if (!lectureSnap.exists) throw new HttpsError("not-found", "Lecture not found.");
  const sectionId = getString(lectureSnap.data()?.section_id);
  if (!sectionId) throw new HttpsError("failed-precondition", "Lecture section is missing.");
  const sectionSnap = await db.collection("subject_sections").doc(sectionId).get();
  const subjectId = getString(sectionSnap.data()?.subject_id);
  if (!subjectId) throw new HttpsError("failed-precondition", "Subject is missing.");
  await requireEnabledSubjectAccess(userId, subjectId);

  const subscriptionSnap = await db.collection("subscriptions")
    .where("student_id", "==", userId)
    .where("subject_id", "==", subjectId)
    .where("status", "==", "active")
    .limit(1)
    .get();
  if (subscriptionSnap.empty) throw new HttpsError("permission-denied", "Active subject subscription is required.");
  assertSubjectAccess(subscriptionSnap.docs[0].data());

  const planId = getString(subscriptionSnap.docs[0].data().plan_id);
  if (!planId) throw new HttpsError("failed-precondition", "Subscription plan is missing.");

  const storagePath = getString(resource.storage_path) ?? getString(resource.resource_url);
  if (!storagePath) throw new HttpsError("failed-precondition", "Document storage path is missing.");

  return {planId, subjectId, lectureId, storagePath, storageProvider: getString(resource.storage_provider) || "firebase", resourceTitle: getString(resource.title), resourceType: type};
}

/**
 * Generate a short-lived signed URL for **viewing** a document in-app.
 * Requires corresponding plan feature.
 */
export const generateProtectedPdfUrl = onCall(SECURE_CALL_OPTS, async (request) => {
  const userId = requireAuthenticated(request);
  const resourceId = getString(request.data?.resourceId);
  const deviceId = normalizeDeviceId(request.data?.deviceId);
  if (!resourceId) throw new HttpsError("invalid-argument", "resourceId is required.");
  if (!deviceId) throw new HttpsError("invalid-argument", "deviceId is required.");

  const ctx = await resolveDocumentAccess(userId, resourceId);
  // ADR-004: Guest devices never receive protected documents. The existing
  // permission-denied contract is reused; Full behavior below is unchanged.
  await requireFullSubjectTier({
    studentId: userId,
    subjectId: ctx.subjectId,
    deviceId,
    ipAddress: typeof request.rawRequest?.ip === "string" ? request.rawRequest.ip : null,
  });
  const keys = documentFeatureKeys(ctx.resourceType);

  const access = await getPlanFeature(ctx.planId, keys.view);
  if (access?.enabled !== true) throw new HttpsError("permission-denied", "Document access is not enabled for your plan.");

  const bucket = storage.bucket();
  const file = bucket.file(ctx.storagePath);
  const [signedUrl] = await file.getSignedUrl({
    action: "read",
    expires: Date.now() + 5 * 60 * 1000,
    responseDisposition: "inline",
  });

  await writeAnalyticsEvent(userId, "View Document", resourceId, {subject_id: ctx.subjectId, lecture_id: ctx.lectureId, type: ctx.resourceType});
  return {url: signedUrl, expiresAt: Date.now() + 5 * 60 * 1000, canDownload: false};
});

/**
 * Generate a short-lived signed URL for **downloading** a document.
 * Requires corresponding plan feature (stricter than viewing).
 */
export const generatePdfDownloadUrl = onCall(SECURE_CALL_OPTS, async (request) => {
  const userId = requireAuthenticated(request);
  const resourceId = getString(request.data?.resourceId);
  const deviceId = normalizeDeviceId(request.data?.deviceId);
  if (!resourceId) throw new HttpsError("invalid-argument", "resourceId is required.");
  if (!deviceId) throw new HttpsError("invalid-argument", "deviceId is required.");

  const ctx = await resolveDocumentAccess(userId, resourceId);
  // ADR-004: Guest devices never receive protected downloads.
  await requireFullSubjectTier({
    studentId: userId,
    subjectId: ctx.subjectId,
    deviceId,
    ipAddress: typeof request.rawRequest?.ip === "string" ? request.rawRequest.ip : null,
  });
  const keys = documentFeatureKeys(ctx.resourceType);

  const download = await getPlanFeature(ctx.planId, keys.download);
  if (download?.enabled !== true) throw new HttpsError("permission-denied", "Document download is not enabled for your plan.");

  const bucket = storage.bucket();
  const file = bucket.file(ctx.storagePath);
  const fileName = ctx.resourceTitle ? `${ctx.resourceTitle}.${ctx.resourceType === "pdf" ? "pdf" : "ext"}` : "document";
  const [signedUrl] = await file.getSignedUrl({
    action: "read",
    expires: Date.now() + 5 * 60 * 1000,
    responseDisposition: `attachment; filename="${fileName}"`,
  });

  await writeAnalyticsEvent(userId, "Download Document", resourceId, {subject_id: ctx.subjectId, lecture_id: ctx.lectureId, type: ctx.resourceType});
  return {url: signedUrl, expiresAt: Date.now() + 5 * 60 * 1000};
});

export const getLectureResources = onCall({
  ...SECURE_CALL_OPTS,
  // P2 thumbnails: bunny-hosted thumbnail bytes reuse the token-signing
  // scheme, so both secrets must be present at runtime. The playback
  // template origin is additionally needed for the signed Bunny poster
  // fallback (selected library poster per video).
  secrets: [SECRET_BUNNY_TOKEN_KEY, SECRET_BUNNY_STORAGE_BASE_URL, SECRET_BUNNY_PLAYBACK_URL_TEMPLATE],
}, async (request) => {
  const userId = requireAuthenticated(request);
  const lectureId = getString(request.data?.lectureId);
  const deviceId = normalizeDeviceId(request.data?.deviceId);
  if (!lectureId) throw new HttpsError("invalid-argument", "lectureId is required.");

  const lectureSnap = await db.collection("lectures").doc(lectureId).get();
  if (!lectureSnap.exists) throw new HttpsError("not-found", "Lecture not found.");
  const lecture = dataOf(lectureSnap.data());
  const subjectId = getString(lecture.subject_id);
  if (!subjectId) throw new HttpsError("failed-precondition", "Lecture subject is missing.");
  // Startup-latency optimization (I/O concurrency only): once subjectId is
  // known, the Subject-access check, the per-lecture deny check, the active
  // subscription query, and the visible-resources listing are mutually
  // independent — none consumes another's result. They are issued together
  // so one round trip covers all four. Verdicts below are enforced in the
  // EXACT original order, so allow/deny outcomes and error codes/messages
  // are identical; resources are never returned unless every check passes.
  // V1 per-lecture access: explicit deny wins over subscription/plan.
  const resourcesQuery = db.collection("lecture_resources")
    .where("lecture_id", "==", lectureId)
    .where("is_visible", "==", true)
    .orderBy("display_order")
    .get();
  const [accessOutcome, grantOutcome, subscriptionOutcome, resourcesOutcome] = await Promise.allSettled([
    requireEnabledSubjectAccess(userId, subjectId),
    assertLectureAccessNotDenied(userId, lectureId),
    db.collection("subscriptions")
      .where("student_id", "==", userId)
      .where("subject_id", "==", subjectId)
      .where("status", "==", "active")
      .limit(1)
      .get(),
    resourcesQuery,
  ]);
  // Ordered rethrow preserves the original sequential error precedence:
  // assignment verdict first, then per-lecture deny, then subscription.
  if (accessOutcome.status === "rejected") throw accessOutcome.reason;
  if (grantOutcome.status === "rejected") throw grantOutcome.reason;
  if (subscriptionOutcome.status === "rejected") throw subscriptionOutcome.reason;
  const subscriptionSnap = subscriptionOutcome.value;
  if (subscriptionSnap.empty) throw new HttpsError("permission-denied", "Active subject subscription is required.");
  const subjectSubscription = subscriptionSnap.docs[0].data();
  assertSubjectAccess(subjectSubscription);
  if (resourcesOutcome.status === "rejected") throw resourcesOutcome.reason;
  const resourcesSnap = resourcesOutcome.value;
  // Phase 2 alignment: drop soft-deleted rows (still marked visible) before
  // serialization so they can never become the first video — or be served
  // at all. Both response branches below share this filtered list.
  const liveDocs = resourcesSnap.docs.filter((doc) => isServedLectureResource(dataOf(doc.data())));

  const subjectPlanId = getString(subjectSubscription.plan_id);
  let guestPreviewSeconds: number | null = null;
  // Messaging-only audience for the Guest verdicts below (same helper as
  // issuance; plan-based, no extra reads). The plan document is hoisted so
  // both the legacy and the tier-aware branches share it.
  let listingPlan: DocumentData | null = null;
  let listingAudience: PreviewAudience | null = null;
  if (subjectPlanId) {
    const subjectPlanSnap = await db.collection("plans").doc(subjectPlanId).get();
    if (subjectPlanSnap.exists) {
      const subjectPlan = dataOf(subjectPlanSnap.data());
      listingPlan = subjectPlan;
      // Identity-safe Guest check: document ID + student_type. Never
      // `plan_key == "free"` alone — plans/free shares that key.
      if (isGuestPlan(subjectPlanId, subjectPlan)) {
        // Guest per-lecture cap: per-lecture minutes win, falling back
        // to the plan's video.preview_duration default (FINAL_DECISIONS §11).
        const previewFeature = await getPlanFeature(subjectPlanId, "video.preview_duration");
        const previewFields = readGuestPreviewFields(lecture);
        guestPreviewSeconds = resolveGuestPreviewSeconds({
          guestEnabled: previewFields.guestEnabled,
          lectureMinutes: previewFields.lectureMinutes,
          planDefaultMinutes: previewFeature ? getNumber(previewFeature.feature_value) : null,
        });
        listingAudience = previewAudienceForPlan(subjectPlanId, subjectPlan);
      }
    }
  }

  // `resourcesSnap` was already fetched concurrently with the authorization
  // reads above; display media below resolves per resource through the
  // shared top-level helper (explicit thumbnails, Bunny poster fallback,
  // silent preview). Best-effort per resource — nulls on any failure,
  // never fails the listing. The legacy `thumbnail` key is preserved so
  // older clients keep parsing.

  const serializeResource = async (doc: (typeof liveDocs)[number]) => {
    const resource = dataOf(doc.data());
    const media = await resolveVideoDisplayMedia(resource);
    return {
      id: doc.id,
      resourceType: getString(resource.resource_type) ?? "attachment",
      title: getString(resource.title) ?? getString(resource.resource_title) ?? "مورد تعليمي",
      bunnyVideoId: getString(resource.bunny_video_id),
      storagePath: getString(resource.storage_path),
      thumbnail: getString(resource.thumbnail),
      thumbnailUrl: media.thumbnailUrl,
      previewUrl: media.previewUrl,
      thumbnailProvider: getString(resource.thumbnail_storage_provider) ??
        getString(resource.thumbnailStorageProvider) ??
        undefined,
      duration: resource.duration,
      displayOrder: typeof resource.display_order === "number" ? resource.display_order : 0,
    };
  };

  // Canonical Phase 1 contract: `guestPreview`. The legacy `publicFreePreview`
  // key is a BOUNDED transition alias for pre-Phase-2 Flutter clients only.
  // TODO(PHASE2): remove `publicFreePreview` once Flutter reads `guestPreview`.
  // Both keys carry the additive previewAudience discriminator (messaging
  // only); legacy-branch verdicts are Guest-plan verdicts by construction.
  const guestPreview = guestPreviewSeconds != null ?
    {
      previewLimitSeconds: guestPreviewSeconds,
      previewAudience: listingAudience ?? previewAudienceForPlan(subjectPlanId, listingPlan),
    } :
    null;
  const fullResponse = {
    guestPreview,
    publicFreePreview: guestPreview,
    resources: await Promise.all(liveDocs.map(serializeResource)),
  };

  // ADR-004: when the caller identifies its device, the listing becomes
  // tier-aware. Full keeps the exact behavior above. Guest exposes only
  // video resources (no protected PDFs, downloads, or offline artifacts)
  // with the preview cap resolved from the existing structural contract.
  // Without a deviceId the legacy plan-based response is preserved.
  if (!deviceId) return fullResponse;
  const tier = await evaluateSubjectTier({
    studentId: userId,
    subjectId,
    deviceId,
    ipAddress: typeof request.rawRequest?.ip === "string" ? request.rawRequest.ip : null,
  });
  if (tier.tier === "full") return fullResponse;

  const deviceGuestFields = readGuestPreviewFields(lecture);
  const deviceGuestDefault = subjectPlanId ?
    await getPlanFeature(subjectPlanId, "video.preview_duration") :
    null;
  const deviceGuestSeconds = resolveGuestPreviewSeconds({
    guestEnabled: deviceGuestFields.guestEnabled,
    lectureMinutes: deviceGuestFields.lectureMinutes,
    planDefaultMinutes: deviceGuestDefault ? getNumber(deviceGuestDefault.feature_value) : null,
  });
  const deviceGuestPreview =
    deviceGuestSeconds != null ?
      {
        previewLimitSeconds: deviceGuestSeconds,
        previewAudience: previewAudienceForPlan(subjectPlanId, listingPlan),
      } :
      null;
  const deviceResources = await Promise.all(liveDocs.map(serializeResource));
  return {
    guestPreview: deviceGuestPreview,
    publicFreePreview: deviceGuestPreview,
    resources: deviceResources
      .filter((resource) => resource.resourceType === "video" || resource.bunnyVideoId !== null),
  };
});

// Batched display media for a whole section (subject-page cards + header
// cover): ONE callable round trip for every lecture instead of one
// `getLectureResources` per card (~4s each). Same read-only posture —
// auth + enabled subject access + active subscription are verified ONCE
// for the section's subject; device tiers, windows, and issuance are
// untouched (posters/previews are non-protected teaser art, and no signed
// playback URL is ever minted here). Per-lecture failures degrade to
// nulls; the listing itself never fails because of media.
export const getSectionDisplayMedia = onCall({
  ...SECURE_CALL_OPTS,
  secrets: [SECRET_BUNNY_TOKEN_KEY, SECRET_BUNNY_STORAGE_BASE_URL, SECRET_BUNNY_PLAYBACK_URL_TEMPLATE],
}, async (request) => {
  const userId = requireAuthenticated(request);
  const sectionId = getString(request.data?.sectionId);
  if (!sectionId) throw new HttpsError("invalid-argument", "sectionId is required.");

  const sectionSnap = await db.collection("subject_sections").doc(sectionId).get();
  if (!sectionSnap.exists) throw new HttpsError("not-found", "Section not found.");
  const subjectId = getString(sectionSnap.data()?.subject_id);
  if (!subjectId) throw new HttpsError("failed-precondition", "Section subject is missing.");

  await requireEnabledSubjectAccess(userId, subjectId);
  const subscriptionSnap = await db.collection("subscriptions")
    .where("student_id", "==", userId)
    .where("subject_id", "==", subjectId)
    .where("status", "==", "active")
    .limit(1)
    .get();
  if (subscriptionSnap.empty) throw new HttpsError("permission-denied", "Active subject subscription is required.");
  assertSubjectAccess(subscriptionSnap.docs[0].data());

  const lecturesSnap = await db.collection("lectures")
    .where("section_id", "==", sectionId)
    .where("is_deleted", "==", false)
    .where("status", "==", "published")
    .orderBy("display_order")
    .get();

  const items = await Promise.all(lecturesSnap.docs.map(async (ldoc) => {
    try {
      const lectureData = dataOf(ldoc.data());
      const docThumb =
        getString(lectureData.thumbnail_url) ?? getString(lectureData.thumbnail);
      const resourcesSnap = await db.collection("lecture_resources")
        .where("lecture_id", "==", ldoc.id)
        .where("is_visible", "==", true)
        .orderBy("display_order")
        .get();
      const firstVideoDoc = resourcesSnap.docs
        .map((doc) => dataOf(doc.data()))
        .filter((resource) => isServedLectureResource(resource))
        .find((resource) =>
          (getString(resource.resource_type) ?? "attachment") === "video" &&
          getString(resource.bunny_video_id) != null,
        );
      let thumbnailUrl = (docThumb && docThumb.length > 0) ? docThumb : null;
      let previewUrl: string | null = null;
      if (firstVideoDoc) {
        const media = await resolveVideoDisplayMedia(firstVideoDoc);
        if (!thumbnailUrl) thumbnailUrl = media.thumbnailUrl;
        previewUrl = media.previewUrl;
      }
      return {lectureId: ldoc.id, thumbnailUrl, previewUrl};
    } catch {
      return {lectureId: ldoc.id, thumbnailUrl: null, previewUrl: null};
    }
  }));
  return {items};
});

export const onDeviceChangeRequest = onCall(SECURE_CALL_OPTS, async (request) => {
  // ADR-004: device management requires the Doctor or an Admin explicitly
  // holding the device-management delegation (see 15_Admin_Permissions).
  const deviceAuthorization = await requireDeviceManager(request);
  const approverId = deviceAuthorization.actorId;
  const requestId = getString(request.data?.requestId);
  const approve = request.data?.approve === true;
  if (!requestId) throw new HttpsError("invalid-argument", "requestId is required.");

  const requestRef = db.collection("device_change_requests").doc(requestId);
  const requestSnap = await requestRef.get();
  if (!requestSnap.exists) throw new HttpsError("not-found", "Device change request not found.");
  const change = dataOf(requestSnap.data());
  if (change.status !== "pending") throw new HttpsError("failed-precondition", "Request is no longer pending.");

  const studentId = getString(change.student_id);
  const oldDeviceId = getString(change.old_device_id);
  const newDeviceId = getString(change.new_device_id);
  if (!studentId || !newDeviceId) throw new HttpsError("failed-precondition", "Device change request is incomplete.");

  if (!approve) {
    await requestRef.update({status: "rejected", resolved_by: approverId, resolved_at: FieldValue.serverTimestamp(), updated_at: FieldValue.serverTimestamp()});
    await createNotification(studentId, "system", "Device Change Rejected", "Your device replacement request was rejected.");
    await writeAnalyticsEvent(studentId, "Device Change Rejected", requestId, {resolved_by: approverId});
    return {approved: false};
  }

  // ADR-004: approval revokes the old device's Subject authorizations so the
  // replacement device can bind via first-access. Registry rows and the
  // Firebase Auth session are untouched; no re-login is required and no
  // global device pointer exists anymore. `old_device_id` may be a legacy
  // registry document ID or a raw device identity — both resolve the same way.
  let revokedCount = 0;
  if (oldDeviceId) {
    let oldDeviceIdentity: string | null = null;
    const oldDeviceSnap = await db.collection("devices").doc(oldDeviceId).get();
    if (oldDeviceSnap.exists) {
      oldDeviceIdentity = getString(dataOf(oldDeviceSnap.data()).device_id);
    }
    if (!oldDeviceIdentity) oldDeviceIdentity = oldDeviceId;
    const oldDeviceHash = computeDeviceHash(studentId, oldDeviceIdentity);
    const oldAuthorizations = await db.collection("subject_device_authorizations")
      .where("student_id", "==", studentId)
      .where("device_hash", "==", oldDeviceHash)
      .where("status", "==", "active")
      .get();
    const targets = oldAuthorizations.docs.filter((d) => dataOf(d.data()).is_deleted !== true);
    const now = FieldValue.serverTimestamp();
    for (let index = 0; index < targets.length; index += 500) {
      const batch = db.batch();
      for (const doc of targets.slice(index, index + 500)) {
        batch.update(doc.ref, {
          status: "revoked",
          revoked_at: now,
          revoked_by: approverId,
          revoke_reason: "device_change",
          updated_at: now,
          updated_by: approverId,
        });
      }
      await batch.commit();
    }
    revokedCount = targets.length;
  }

  await requestRef.update({status: "approved", resolved_by: approverId, resolved_at: FieldValue.serverTimestamp(), updated_at: FieldValue.serverTimestamp()});
  const auditNow = FieldValue.serverTimestamp();
  await db.collection("admin_audit_log").add({
    action: "device_change_approved",
    entity: "device_change_requests",
    target_id: requestId,
    actor_id: approverId,
    actor_role: deviceAuthorization.actorRole,
    permission_basis: deviceAuthorization.permissionBasis,
    details: {student_id: studentId, revoked_count: revokedCount},
    created_at: auditNow,
    timestamp: auditNow,
  });
  await createNotification(studentId, "system", "Device Change Approved", "Your new device has been approved. Open each subject to connect it. No need to sign in again.", {priority: "critical"});
  await writeAnalyticsEvent(studentId, "Device Replaced", requestId, {old_device_id: oldDeviceId, new_device_id: newDeviceId, resolved_by: approverId, revoked_count: revokedCount});

  return {approved: true, revokedCount};
});

export const onPasswordResetRequest = onDocumentCreated("password_reset_requests/{requestId}", async (event) => {
  const snapshot = event.data;
  if (!snapshot) return;
  const data = snapshot.data();
  if (!data) return;
  const requestId = event.params.requestId;
  const studentId = getString(data.student_id);
  if (!studentId) return;

  await notifyAdminsWithPermission(
    "password_reset",
    "system",
    "Password Reset Request",
    "A student has requested a password reset.",
    {priority: "critical", deep_link: `/admin/password-reset/${requestId}`},
  );
  await snapshot.ref.update({status: "pending", notified_at: FieldValue.serverTimestamp(), updated_at: FieldValue.serverTimestamp()});
  await writeAnalyticsEvent(studentId, "Password Reset Requested", requestId, {phone_number: data.phone_number ?? null});
});

export const onPasswordResetApproved = onCall(SECURE_CALL_OPTS, async (request) => {
  const authorization = await requirePasswordResetManager(request);
  const requestId = getString(request.data?.requestId);
  const newPassword = getString(request.data?.newPassword);
  if (!requestId || !newPassword) throw new HttpsError("invalid-argument", "requestId and newPassword are required.");
  // Temporary-password policy (intentionally SIMPLE — approved product
  // decision): staff set short, easy-to-dictate passwords (e.g. letter +
  // digits) because the student MUST replace it on next login
  // (force_password_change = true below) and all sessions are revoked
  // (revokeRefreshTokens). Floor is 6 chars — the Firebase Auth minimum
  // (auth.updateUser rejects shorter). NO complexity requirement here.
  // The STUDENT-chosen permanent password keeps the strong policy in
  // `changePassword` (8 + upper/lower/digit/special) — unchanged.
  if (newPassword.length < 6) {
    throw new HttpsError("invalid-argument", "Password must contain at least 6 characters.");
  }

  const requestRef = db.collection("password_reset_requests").doc(requestId);
  // Single-flight claim (transactional): exactly one approval proceeds past
  // this point. Mirrors the approveStudent/submitAssessmentAttempt
  // status-claim pattern. A "processing" claim owned by the SAME actor is
  // reclaimable (safe retry after a crash between claim and resolve);
  // other actors get failed-precondition. This guards Firestore-side
  // double-execution; Auth writes below cannot be transactional, so Auth
  // atomicity is explicitly NOT claimed here.
  await db.runTransaction(async (transaction) => {
    const snap = await transaction.get(requestRef);
    if (!snap.exists) throw new HttpsError("not-found", "Password reset request not found.");
    const current = dataOf(snap.data());
    if (current.status === "processing") {
      if (getString(current.claimed_by) === authorization.actorId) {
        transaction.update(requestRef, {
          claimed_at: FieldValue.serverTimestamp(),
          updated_at: FieldValue.serverTimestamp(),
        });
        return;
      }
      throw new HttpsError("failed-precondition", "Password reset request is already being processed.");
    }
    if (current.status !== "pending") throw new HttpsError("failed-precondition", "Password reset request is not pending.");
    transaction.update(requestRef, {
      status: "processing",
      claimed_by: authorization.actorId,
      claimed_at: FieldValue.serverTimestamp(),
      updated_at: FieldValue.serverTimestamp(),
    });
  });

  const requestSnap = await requestRef.get();
  if (!requestSnap.exists) throw new HttpsError("not-found", "Password reset request not found.");
  const resetRequest = dataOf(requestSnap.data());

  const studentId = getString(resetRequest.student_id);
  if (!studentId) throw new HttpsError("failed-precondition", "Student ID is missing.");

  // Staff-target hardening: the reset workflow is student-only. Creation is
  // student-gated (submitPasswordResetRequest), but approval must re-validate
  // the target because request docs are staff-writable — otherwise a crafted
  // request pointing at a doctor/admin UID would overwrite a staff account's
  // Auth password, claims, users doc, and secrets (staff-account takeover).
  // new_student is a student lifecycle state and stays eligible; doctor/admin
  // targets are rejected. Legitimate student resets are unchanged.
  const targetSnap = await db.collection("users").doc(studentId).get();
  if (!targetSnap.exists) throw new HttpsError("not-found", "Target user not found.");
  const targetRole = getString(targetSnap.data()?.role);
  if (targetRole !== "student" && targetRole !== "new_student") {
    throw new HttpsError("permission-denied", "Password reset is available for student accounts only.");
  }

  const passwordHash = await hashPassword(newPassword);

  await auth.updateUser(studentId, {password: newPassword});
  const currentUser = await auth.getUser(studentId);
  const claims = {...(currentUser.customClaims ?? {}), force_password_change: true};
  await auth.setCustomUserClaims(studentId, claims);

  const now = FieldValue.serverTimestamp();
  await db.collection("users").doc(studentId).update({
    force_password_change: true,
    password_last_changed_at: now,
    updated_at: now,
    updated_by: authorization.actorId,
  });

  await db.collection("user_secrets").doc(studentId).set({
    user_id: studentId,
    password_hash: passwordHash,
    updated_at: now,
  }, {merge: true});

  // Mid-session staleness fix (approved): revoke all refresh tokens AFTER
  // the password change and the student reset data are durably updated, so
  // a revoke failure can never strand mismatched credentials (new password
  // in Auth while users/secrets still carry the old state). Existing
  // sequential error handling applies: a revoke failure propagates, the
  // request stays processing, and the same actor can reclaim and retry.
  await auth.revokeRefreshTokens(studentId);

  await requestRef.update({
    status: "resolved",
    resolved_by: authorization.actorId,
    resolved_at: now,
    updated_at: now,
  });

  await db.collection("admin_audit_log").add({
    action: "password_reset_approved",
    entity: "password_reset_requests",
    target_id: studentId,
    request_id: requestId,
    actor_id: authorization.actorId,
    actor_role: authorization.actorRole,
    permission_basis: authorization.permissionBasis,
    created_at: now,
    timestamp: now,
  });

  await createNotification(studentId, "system", "Password Reset", "Your password was reset by the platform. Please sign in and change it.", {priority: "critical"});
  await writeAnalyticsEvent(studentId, "Password Reset Completed", requestId, {resolved_by: authorization.actorId});

  return {resolved: true};
});

export const onSecurityEvent = onCall(SECURE_CALL_OPTS, async (request) => {
  const userId = requireAuthenticated(request);
  const eventType = getString(request.data?.eventType);
  const severity = getString(request.data?.severity) ?? "medium";
  const context = request.data?.context && typeof request.data.context === "object" ? request.data.context : {};
  const deviceInfo = request.data?.deviceInfo && typeof request.data.deviceInfo === "object" ? request.data.deviceInfo : {};
  if (!eventType) throw new HttpsError("invalid-argument", "eventType is required.");

  const securityRef = await db.collection("security_events").add({
    user_id: userId,
    event_type: eventType,
    severity,
    context,
    device_info: deviceInfo,
    screenshot_detected: request.data?.screenshotDetected === true,
    screen_record_detected: request.data?.screenRecordDetected === true,
    action_taken: getString(request.data?.actionTaken) ?? "notify_admin",
    created_at: FieldValue.serverTimestamp(),
  });

  await writeAnalyticsEvent(userId, "Security Event", securityRef.id, {event_type: eventType, severity, context});

  if (["high", "critical"].includes(severity)) {
    await notifyUsersByRole("doctor", "system", "Security Alert", `A security event was detected: ${eventType}`, {priority: "critical", deep_link: `/admin/security-events/${securityRef.id}`});
    await notifyUsersByRole("admin", "system", "Security Alert", `A security event was detected: ${eventType}`, {priority: "critical", deep_link: `/admin/security-events/${securityRef.id}`});
  }

  return {logged: true, securityEventId: securityRef.id};
});

export const setSubjectAccess = onCall(SECURE_CALL_OPTS, async (request) => {
  const authorization = await requireStudentAccessManager(request);
  const studentId = getString(request.data?.studentId);
  const subjectId = getString(request.data?.subjectId);
  const enabled = request.data?.enabled;
  if (!studentId || !subjectId || typeof enabled !== "boolean") {
    throw new HttpsError("invalid-argument", "studentId, subjectId and enabled are required.");
  }

  const assignmentId = `${studentId}_${subjectId}`;
  const assignmentRef = db.collection("subject_access_assignments").doc(assignmentId);
  const auditRef = db.collection("admin_audit_log").doc();

  const result = await db.runTransaction(async (transaction) => {
    const studentRef = db.collection("users").doc(studentId);
    const subjectRef = db.collection("subjects").doc(subjectId);
    const studentSnap = await transaction.get(studentRef);
    const subjectSnap = await transaction.get(subjectRef);
    const currentSnap = await transaction.get(assignmentRef);

    if (!studentSnap.exists) throw new HttpsError("not-found", "Student not found.");
    const student = dataOf(studentSnap.data());
    if (student.role !== "student" || student.approval_status !== "approved") {
      throw new HttpsError("failed-precondition", "Target user is not an approved student.");
    }
    if (!subjectSnap.exists || subjectSnap.data()?.is_deleted === true) {
      throw new HttpsError("not-found", "Subject not found.");
    }

    const previous = currentSnap.exists ? dataOf(currentSnap.data()) : null;
    if (
      previous &&
      (previous.student_id !== studentId || previous.subject_id !== subjectId)
    ) {
      throw new HttpsError("failed-precondition", "Subject Access assignment identity is invalid.");
    }

    const requestedDeleted = request.data?.isDeleted;
    const nextDeleted = typeof requestedDeleted === "boolean" ? requestedDeleted : previous?.is_deleted === true;
    const action = !previous ?
      "create" :
      previous.is_deleted === true && !nextDeleted ?
        "restore" :
        previous.is_deleted !== true && nextDeleted ?
          "soft_delete" :
          previous.enabled !== enabled ? (enabled ? "enable" : "disable") : "update";

    const nextData: Record<string, unknown> = {
      student_id: studentId,
      subject_id: subjectId,
      enabled,
      updated_at: FieldValue.serverTimestamp(),
      updated_by: authorization.actorId,
      is_deleted: nextDeleted,
      deleted_at: nextDeleted ? FieldValue.serverTimestamp() : null,
      deleted_by: nextDeleted ? authorization.actorId : null,
    };
    if (!previous) {
      nextData.created_at = FieldValue.serverTimestamp();
      nextData.created_by = authorization.actorId;
    }

    transaction.set(assignmentRef, nextData, {merge: true});
    transaction.set(auditRef, {
      action,
      entity: "subject_access_assignment",
      target_id: assignmentId,
      student_id: studentId,
      subject_id: subjectId,
      previous_enabled: previous?.enabled ?? null,
      new_enabled: enabled,
      previous_is_deleted: previous?.is_deleted ?? null,
      new_is_deleted: nextDeleted,
      actor_id: authorization.actorId,
      actor_role: authorization.actorRole,
      permission_basis: authorization.permissionBasis,
      created_at: FieldValue.serverTimestamp(),
      timestamp: FieldValue.serverTimestamp(),
    });

    return {assignmentId, action, enabled, isDeleted: nextDeleted};
  });

  return result;
});

async function getActiveEntitlements(planId: string): Promise<string[]> {
  const planFeatures = await getPlanFeatures(planId);
  return planFeatures
    .filter((f) => f.enabled === true || f.feature_value === true)
    .map((f) => f.feature_key);
}

/**
 * Shared read of the subject-access plan gate in `system_settings/default`.
 *
 * The canonical settings document is `system_settings/default` (fixed ID —
 * never an unordered `.limit(1)` first-doc read, which is ambiguous when
 * the collection holds more than one document). Returns whether the Free
 * plan may currently be granted together with the configured default plan
 * key. Throws when the settings document itself is missing so callers
 * fail closed instead of inventing a plan.
 */
async function readSubjectAccessSettings(): Promise<{
  freePlanEnabled: boolean;
  defaultPlanKey: string | null;
}> {
  const settingsDoc = await db.collection("system_settings").doc("default").get();
  if (!settingsDoc.exists) {
    throw new HttpsError("failed-precondition", "System settings configuration was not found.");
  }
  const settings = dataOf(settingsDoc.data());
  return {
    freePlanEnabled: settings.free_plan_enabled === true,
    defaultPlanKey: getString(settings.default_plan),
  };
}

function normalizeSubjectPlan(value: unknown): "free" | "pro" | "max" | null {
  const plan = getString(value)?.toLowerCase() ?? null;
  if (plan === "free" || plan === "pro" || plan === "max") return plan;
  return null;
}

/**
 * Server-side plan resolution for one (studentType, plan) pair.
 *
 * Mirrors the dashboard `_resolvePlanDocId` data-driven lookup (`plan_key`
 * suffix + matching `student_type` + `is_active`) without hardcoding plan
 * document IDs. The FREE tier resolves through the configured
 * `system_settings.default_plan` key, exactly like `activateFreePlan`.
 * @param {string} studentType Student type (`center_student` or `guest`).
 * @param {string} plan Requested tier (`free`, `pro` or `max`).
 * @param {string|null} defaultPlanKey Configured default plan key.
 * @return {Promise<{id: string, data: object}>} Resolved plan reference.
 */
async function resolveSubjectPlanDoc(
  studentType: string,
  plan: "free" | "pro" | "max",
  defaultPlanKey: string | null,
): Promise<{id: string; data: DocumentData}> {
  if (plan === "free") {
    if (!defaultPlanKey) {
      throw new HttpsError("failed-precondition", "Default plan is not configured.");
    }
    const freeSnap = await db.collection("plans")
      .where("plan_key", "==", defaultPlanKey)
      .where("student_type", "==", studentType)
      .where("is_active", "==", true)
      .limit(1)
      .get();
    if (freeSnap.empty) {
      throw new HttpsError("failed-precondition", "Active default plan was not found.");
    }
    return {id: freeSnap.docs[0].id, data: dataOf(freeSnap.docs[0].data())};
  }
  const paidSnap = await db.collection("plans")
    .where("student_type", "==", studentType)
    .where("is_active", "==", true)
    .get();
  for (const doc of paidSnap.docs) {
    const key = (getString(doc.data().plan_key) ?? "").toLowerCase();
    if (key === plan || key.endsWith(`_${plan}`)) {
      return {id: doc.id, data: dataOf(doc.data())};
    }
  }
  throw new HttpsError(
    "failed-precondition",
    `No active ${plan} plan is configured for this student type.`,
  );
}

/**
 * Staff-readable subject-access plan configuration.
 *
 * `system_settings` is directly readable only by the Doctor or
 * `admin_settings` delegates (see firestore.rules), while subject managers
 * (Doctor or delegated `admin_students`) still need to know whether FREE
 * may be offered. This callable bridges that gap without weakening any
 * rule: same `requireStudentAccessManager` gate as the mutation callables,
 * read-only, no writes.
 */
export const getSubjectAccessConfig = onCall(SECURE_CALL_OPTS, async (request) => {
  await requireStudentAccessManager(request);
  const settings = await readSubjectAccessSettings();
  return {freePlanEnabled: settings.freePlanEnabled};
});

/**
 * Atomic per-subject grant: assignment + subscription in ONE transaction.
 *
 * For a single (studentId, subjectId, plan) tuple this performs the entire
 * operation — enabling/restoring the `subject_access_assignments` row,
 * validating the plan (including the `free_plan_enabled` gate), creating
 * or retargeting the subject-scoped `subscriptions` row at the resolved
 * plan tier, and stamping the assignment entitlements — inside a single
 * Firestore transaction. Validation that can reject the request (unknown
 * student/subject, type mismatch, disabled Free plan, unresolvable paid
 * plan) runs BEFORE the transaction opens, so a rejection writes nothing
 * at all — never an enabled assignment without a subscription.
 *
 * PRO/MAX subscriptions are created directly at the resolved tier; the
 * legacy "activate free first, then upgrade" two-step chain is NOT used
 * here. `setSubjectAccess`, `activateFreePlan`, and `changeMembershipPlan`
 * are left untouched for their other callers.
 */
export const grantSubjectAccessWithPlan = onCall(SECURE_CALL_OPTS, async (request) => {
  const authorization = await requireStudentAccessManager(request);
  const studentId = getString(request.data?.studentId);
  const subjectId = getString(request.data?.subjectId);
  const requestedStudentType = getString(request.data?.studentType);
  const plan = normalizeSubjectPlan(request.data?.plan);
  if (!studentId || !subjectId || !requestedStudentType || !plan) {
    throw new HttpsError(
      "invalid-argument",
      "studentId, subjectId, studentType and plan (free, pro or max) are required.",
    );
  }

  // ---- Validation phase (reads only — nothing is written yet). ----
  const studentSnap = await db.collection("users").doc(studentId).get();
  if (!studentSnap.exists) throw new HttpsError("not-found", "Student not found.");
  const student = dataOf(studentSnap.data());
  if (student.role !== "student" || student.approval_status !== "approved") {
    throw new HttpsError("failed-precondition", "Target user is not an approved student.");
  }
  if (student.student_type !== requestedStudentType) {
    throw new HttpsError("failed-precondition", "Student type does not match the student record.");
  }

  const subjectSnap = await db.collection("subjects").doc(subjectId).get();
  if (!subjectSnap.exists || subjectSnap.data()?.is_deleted === true) {
    throw new HttpsError("not-found", "Subject not found.");
  }

  const settings = await readSubjectAccessSettings();
  if (plan === "free" && !settings.freePlanEnabled) {
    throw new HttpsError("failed-precondition", "Free Plan is disabled in system settings.");
  }

  const resolvedPlan = await resolveSubjectPlanDoc(requestedStudentType, plan, settings.defaultPlanKey);
  const binding = await resolveSubscriptionPeriodBinding();
  const entitlements = await getActiveEntitlements(resolvedPlan.id);

  const existingSnap = await db.collection("subscriptions")
    .where("student_id", "==", studentId)
    .where("subject_id", "==", subjectId)
    .where("status", "==", "active")
    .limit(1)
    .get();
  const existingRef = existingSnap.empty ? null : existingSnap.docs[0].ref;
  const existingData = existingSnap.empty ? null : dataOf(existingSnap.docs[0].data());

  // ---- Atomic phase: assignment + subscription (+ audit) together. ----
  const assignmentId = `${studentId}_${subjectId}`;
  const assignmentRef = db.collection("subject_access_assignments").doc(assignmentId);
  const auditRef = db.collection("admin_audit_log").doc();

  const result = await db.runTransaction(async (transaction) => {
    const studentRef = db.collection("users").doc(studentId);
    const subjectRef = db.collection("subjects").doc(subjectId);
    const liveStudentSnap = await transaction.get(studentRef);
    const liveSubjectSnap = await transaction.get(subjectRef);
    const liveAssignmentSnap = await transaction.get(assignmentRef);
    if (!liveStudentSnap.exists) throw new HttpsError("not-found", "Student not found.");
    const liveStudent = dataOf(liveStudentSnap.data());
    if (liveStudent.role !== "student" || liveStudent.approval_status !== "approved") {
      throw new HttpsError("failed-precondition", "Target user is not an approved student.");
    }
    if (!liveSubjectSnap.exists || liveSubjectSnap.data()?.is_deleted === true) {
      throw new HttpsError("not-found", "Subject not found.");
    }

    const previous = liveAssignmentSnap.exists ? dataOf(liveAssignmentSnap.data()) : null;
    if (
      previous &&
      (previous.student_id !== studentId || previous.subject_id !== subjectId)
    ) {
      throw new HttpsError("failed-precondition", "Subject Access assignment identity is invalid.");
    }
    const action = !previous ?
      "create" :
      previous.is_deleted === true ? "restore" : "update";

    const now = FieldValue.serverTimestamp();
    const assignmentData: Record<string, unknown> = {
      student_id: studentId,
      subject_id: subjectId,
      enabled: true,
      is_deleted: false,
      deleted_at: null,
      deleted_by: null,
      entitlements,
      subscription_expires_at: binding.endDate,
      updated_at: now,
      updated_by: authorization.actorId,
    };
    if (!previous) {
      assignmentData.created_at = now;
      assignmentData.created_by = authorization.actorId;
    }
    transaction.set(assignmentRef, assignmentData, {merge: true});

    let subscriptionId: string;
    let alreadyActive = false;
    if (existingRef && existingData && existingData.is_deleted !== true) {
      const currentPlanId = getString(existingData.plan_id);
      if (currentPlanId === resolvedPlan.id) {
        alreadyActive = true;
        subscriptionId = existingRef.id;
        transaction.update(existingRef, {
          academic_period_id: binding.academicPeriodId,
          end_date: binding.endDate,
          updated_at: now,
          updated_by: authorization.actorId,
        });
      } else {
        subscriptionId = existingRef.id;
        transaction.update(existingRef, {
          previous_plan_id: currentPlanId,
          plan_id: resolvedPlan.id,
          academic_period_id: binding.academicPeriodId,
          end_date: binding.endDate,
          status: "active",
          updated_at: now,
          updated_by: authorization.actorId,
        });
      }
    } else {
      const subscriptionRef = db.collection("subscriptions").doc();
      subscriptionId = subscriptionRef.id;
      transaction.set(subscriptionRef, {
        student_id: studentId,
        subject_id: subjectId,
        plan_id: resolvedPlan.id,
        duration_type: "semester",
        academic_period_id: binding.academicPeriodId,
        start_date: FieldValue.serverTimestamp(),
        end_date: binding.endDate,
        status: "active",
        is_frozen: false,
        frozen_at: null,
        resumed_at: null,
        is_gifted: false,
        gifted_by: null,
        renewal_count: 0,
        previous_plan_id: existingData ? getString(existingData.plan_id) : null,
        is_deleted: false,
        created_at: FieldValue.serverTimestamp(),
        updated_at: FieldValue.serverTimestamp(),
        created_by: authorization.actorId,
        updated_by: authorization.actorId,
      });
    }

    transaction.set(auditRef, {
      action: `subject_access_granted_with_plan:${action}`,
      entity: "subject_access_assignment",
      target_id: assignmentId,
      student_id: studentId,
      subject_id: subjectId,
      plan,
      plan_id: resolvedPlan.id,
      subscription_id: subscriptionId,
      previous_enabled: previous?.enabled ?? null,
      new_enabled: true,
      previous_is_deleted: previous?.is_deleted ?? null,
      new_is_deleted: false,
      actor_id: authorization.actorId,
      actor_role: authorization.actorRole,
      permission_basis: authorization.permissionBasis,
      created_at: FieldValue.serverTimestamp(),
      timestamp: FieldValue.serverTimestamp(),
    });

    return {assignmentId, subscriptionId, action, alreadyActive};
  });

  await writeAnalyticsEvent(studentId, "Subject Access Granted With Plan", result.subscriptionId, {
    subject_id: subjectId,
    plan,
    plan_id: resolvedPlan.id,
    granted_by: authorization.actorId,
  });

  return {
    assignmentId: result.assignmentId,
    subscriptionId: result.subscriptionId,
    planId: resolvedPlan.id,
    plan,
    alreadyActive: result.alreadyActive,
  };
});

export const activateFreePlan = onCall(SECURE_CALL_OPTS, async (request) => {
  const authorization = await requireStudentAccessManager(request);
  const studentId = getString(request.data?.studentId);
  const subjectId = getString(request.data?.subjectId);
  const requestedStudentType = getString(request.data?.studentType);
  if (!studentId || !subjectId || !requestedStudentType) {
    throw new HttpsError("invalid-argument", "studentId, subjectId and studentType are required.");
  }

  const studentSnap = await db.collection("users").doc(studentId).get();
  if (!studentSnap.exists) throw new HttpsError("not-found", "Student not found.");
  const student = dataOf(studentSnap.data());
  if (student.student_type !== requestedStudentType) {
    throw new HttpsError("failed-precondition", "Student type does not match the student record.");
  }

  const subjectSnap = await db.collection("subjects").doc(subjectId).get();
  if (!subjectSnap.exists || subjectSnap.data()?.is_deleted === true) {
    throw new HttpsError("not-found", "Subject not found.");
  }
  await requireEnabledSubjectAccess(studentId, subjectId);

  const settingsDoc = await db.collection("system_settings").doc("default").get();
  if (!settingsDoc.exists) throw new HttpsError("failed-precondition", "System settings configuration was not found.");
  const settings = dataOf(settingsDoc.data());
  if (settings.free_plan_enabled !== true) {
    throw new HttpsError("failed-precondition", "Free Plan is disabled in system settings.");
  }
  const planKey = getString(settings.default_plan);
  if (!planKey) throw new HttpsError("failed-precondition", "Default plan is not configured.");

  const planSnap = await db.collection("plans")
    .where("plan_key", "==", planKey)
    .where("student_type", "==", requestedStudentType)
    .where("is_active", "==", true)
    .limit(1)
    .get();
  if (planSnap.empty) throw new HttpsError("failed-precondition", "Active default plan was not found.");

  const binding = await resolveSubscriptionPeriodBinding();

  // Duplicate protection (approved single-operator hardening against
  // double-click / retry): the active-subscription check and the creation
  // run inside one transaction, so two concurrent or sequential duplicate
  // submissions resolve to a single active subscription. Reference-data
  // reads above stay outside the transaction; only check-and-create is
  // transactional. Same query as before — no new index required.
  const activation = await db.runTransaction(async (tx) => {
    const existingTxSnap = await tx.get(db.collection("subscriptions")
      .where("student_id", "==", studentId)
      .where("subject_id", "==", subjectId)
      .where("status", "==", "active")
      .limit(1));
    if (!existingTxSnap.empty) {
      return {subscriptionId: existingTxSnap.docs[0].id, alreadyActive: true};
    }
    const subscriptionRef = db.collection("subscriptions").doc();
    tx.set(subscriptionRef, {
      student_id: studentId,
      subject_id: subjectId,
      plan_id: planSnap.docs[0].id,
      duration_type: "semester",
      academic_period_id: binding.academicPeriodId,
      start_date: FieldValue.serverTimestamp(),
      end_date: binding.endDate,
      status: "active",
      is_frozen: false,
      frozen_at: null,
      resumed_at: null,
      is_gifted: false,
      gifted_by: null,
      renewal_count: 0,
      previous_plan_id: null,
      is_deleted: false,
      created_at: FieldValue.serverTimestamp(),
      updated_at: FieldValue.serverTimestamp(),
      created_by: authorization.actorId,
      updated_by: authorization.actorId,
    });
    return {subscriptionId: subscriptionRef.id, alreadyActive: false};
  });
  if (activation.alreadyActive) return {subscriptionId: activation.subscriptionId, alreadyActive: true};

  await writeAnalyticsEvent(studentId, "Free Plan Activated", activation.subscriptionId, {subject_id: subjectId, plan_id: planSnap.docs[0].id, activated_by: authorization.actorId});

  const entitlements = await getActiveEntitlements(planSnap.docs[0].id);
  await db.collection("subject_access_assignments").doc(`${studentId}_${subjectId}`).update({
    entitlements,
    subscription_expires_at: binding.endDate,
  });

  return {subscriptionId: activation.subscriptionId, alreadyActive: false};
});

/**
 * Approved payment-transcription helpers (student-level payment model —
 * payments_student_level_database_change_authority.md).
 *
 * Payments are external paper transactions transcribed by the Doctor
 * (Platform Owner) for record-keeping only. No collection, processing,
 * verification, or routing of payments occurs here. Each payment is a
 * student-level transaction against the student's financial account;
 * Subject plays no financial role.
 */
const PAYMENT_METHODS = ["cash", "e_wallet", "instapay", "bank"] as const;
type PaymentMethod = (typeof PAYMENT_METHODS)[number];

function parsePaymentMethod(value: unknown): PaymentMethod {
  const normalized = typeof value === "string" ? value.trim().toLowerCase() : "";
  if (
    normalized === "cash" ||
    normalized === "e_wallet" ||
    normalized === "instapay" ||
    normalized === "bank"
  ) {
    return normalized;
  }
  throw new HttpsError(
    "invalid-argument",
    "paymentMethod must be one of cash, e_wallet, instapay, bank.",
  );
}

function parseCollectorName(value: unknown): string {
  const name = typeof value === "string" ? value.trim() : "";
  if (!name) {
    throw new HttpsError("invalid-argument", "collectorName is required.");
  }
  if (name.length > 100) {
    throw new HttpsError(
      "invalid-argument",
      "collectorName must be at most 100 characters.",
    );
  }
  return name;
}

function parseNotes(value: unknown): string | null {
  if (value === null || value === undefined) return null;
  const notes = typeof value === "string" ? value : String(value);
  if (notes.length > 500) {
    throw new HttpsError(
      "invalid-argument",
      "notes must be at most 500 characters.",
    );
  }
  return notes;
}

/**
 * Parses the transcribed paper payment date. Must be today or a past date;
 * future dates are rejected.
 * @param {unknown} value Raw client-supplied date value.
 * @return {Timestamp} Firestore Timestamp for the validated date.
 */
function parsePaymentDate(value: unknown): Timestamp {
  const raw = typeof value === "string" ? value.trim() : "";
  if (!raw) {
    throw new HttpsError("invalid-argument", "paymentDate is required.");
  }
  const parsed = new Date(raw);
  if (Number.isNaN(parsed.getTime())) {
    throw new HttpsError("invalid-argument", "paymentDate is not a valid date.");
  }
  if (parsed.getTime() > Date.now()) {
    throw new HttpsError(
      "invalid-argument",
      "paymentDate must be today or a past date.",
    );
  }
  return Timestamp.fromDate(parsed);
}

/**
 * Student-level financial account lookup (approved student-level payment
 * model — payments_student_level_database_change_authority.md).
 *
 * Each student has exactly ONE financial account at
 * `student_financial_accounts/{studentId}`. Subject plays no role.
 * @param {string} studentId Student UID.
 * @return {Promise<{netEgp: number} | null>} Net amount, or null when no
 * active account exists.
 */
async function readStudentAccount(
  studentId: string,
): Promise<{netEgp: number} | null> {
  const snap = await db
    .collection("student_financial_accounts")
    .doc(studentId)
    .get();
  if (!snap.exists) return null;
  const data = dataOf(snap.data());
  if (data.is_deleted === true) return null;
  const net = data.net_egp;
  if (typeof net !== "number" || Number.isNaN(net)) return null;
  return {netEgp: net};
}

/**
 * Sum of non-deleted recorded amounts for one student (student-level
 * aggregation). Existing `subject_id` values are legacy/descriptive
 * metadata and are deliberately NOT used as a filter.
 * @param {string} studentId Student UID.
 * @param {string} excludePaymentId Optional payment ID to exclude (correction path).
 * @return {Promise<number>} Total recorded amount.
 */
async function sumPaidForStudent(
  studentId: string,
  excludePaymentId?: string,
): Promise<number> {
  const snap = await db
    .collection("payment_logs")
    .where("student_id", "==", studentId)
    .get();
  let total = 0;
  for (const doc of snap.docs) {
    if (excludePaymentId && doc.id === excludePaymentId) continue;
    const data = dataOf(doc.data());
    if (data.is_deleted === true) continue;
    if (typeof data.amount === "number" && !Number.isNaN(data.amount)) {
      total += data.amount;
    }
  }
  return total;
}

export const onPaymentLogged = onCall(SECURE_CALL_OPTS, async (request) => {
  // Doctor-only: payment recording is transcription by the Platform Owner.
  // Student-level financial transaction (approved student-level payment
  // model). subjectId, when supplied, is nullable legacy/descriptive
  // metadata only and never participates in financial enforcement.
  const doctorId = requireDoctor(request);
  const studentId = getString(request.data?.studentId);
  const subjectId = getString(request.data?.subjectId)?.trim() || null;
  const amount = getNumber(request.data?.amount);
  const receiptNumber = getString(request.data?.receiptNumber)?.trim();
  const notes = parseNotes(request.data?.notes);
  const paymentMethod = parsePaymentMethod(request.data?.paymentMethod);
  const collectorName = parseCollectorName(request.data?.collectorName);
  const paymentDate = parsePaymentDate(request.data?.paymentDate);

  if (!studentId || amount === null || amount < 0 || !receiptNumber) {
    throw new HttpsError("invalid-argument", "studentId, amount and receiptNumber are required.");
  }

  // Over-Net protection (student-level): total Paid for the student must
  // never exceed the student financial account Net.
  const account = await readStudentAccount(studentId);
  if (!account) {
    throw new HttpsError(
      "failed-precondition",
      "No financial account exists for this student.",
    );
  }
  const paidSoFar = await sumPaidForStudent(studentId);
  if (paidSoFar + amount > account.netEgp) {
    throw new HttpsError(
      "failed-precondition",
      "Total paid would exceed the student net amount.",
    );
  }

  // Idempotency (approved single-operator hardening against double-click /
  // client / network retry): deterministic document ID derived from the
  // request's own business identity (student + paper receipt + amount +
  // method + date). An identical repeat resolves to the same document, so
  // it cannot create a second ledger row; any genuinely different payment
  // (different receipt, amount, method, or date) yields a different ID and
  // records normally. No new fields, no new collections, no new indexes:
  // single-document get-or-create inside one transaction (serialized under
  // concurrency). Side effects below run only on first creation.
  const rawPaymentDateInput = getString(request.data?.paymentDate)?.trim() ?? "";
  const paymentId =
    "pay_" +
    createHash("sha256")
      .update([studentId, receiptNumber, String(amount), paymentMethod, rawPaymentDateInput].join("|"))
      .digest("hex")
      .slice(0, 32);
  const paymentRef = db.collection("payment_logs").doc(paymentId);
  const now = FieldValue.serverTimestamp();
  const isDuplicate = await db.runTransaction(async (tx) => {
    const existingSnap = await tx.get(paymentRef);
    if (existingSnap.exists) return true;
    tx.set(paymentRef, {
      student_id: studentId,
      ...(subjectId ? {subject_id: subjectId} : {}),
      amount,
      payment_date: paymentDate,
      payment_method: paymentMethod,
      // Collector = person who physically received the money (paper record).
      // Recorder = Doctor below (created_by). Never the same source.
      collected_by: collectorName,
      receipt_number: receiptNumber,
      notes: notes,
      created_at: now,
      updated_at: now,
      created_by: doctorId,
      updated_by: doctorId,
      is_deleted: false,
      deleted_at: null,
      deleted_by: null,
    });
    return false;
  });
  if (isDuplicate) return {logged: true, paymentId};

  await db.collection("admin_audit_log").add({
    action: "payment_logged",
    entity: "payment_logs",
    target_id: paymentRef.id,
    student_id: studentId,
    ...(subjectId ? {subject_id: subjectId} : {}),
    amount,
    receipt_number: receiptNumber,
    actor_id: doctorId,
    actor_role: "doctor",
    permission_basis: "doctor",
    created_at: now,
    timestamp: now,
  });

  await createNotification(studentId, "payment", "Payment Confirmed", "Your payment has been confirmed.", {priority: "critical", ...(subjectId ? {subject_id: subjectId} : {})});
  await writeAnalyticsEvent(studentId, "Payment Logged", paymentRef.id, {...(subjectId ? {subject_id: subjectId} : {}), amount, receipt_number: receiptNumber, collected_by: collectorName});

  return {logged: true, paymentId: paymentRef.id};
});

/**
 * Doctor-only student-level financial account (approved student-level
 * payment model — payments_student_level_database_change_authority.md).
 *
 * Each student has exactly ONE financial account at
 * `student_financial_accounts/{studentId}`. Price and Discount are
 * entered manually by the Doctor. Net = Price − Discount. Accounting
 * is independent from membership/subscriptions; never stored on
 * subjects, plans, or subscriptions documents. Replaces the retired
 * per-Subject `setStudentSubjectAccount`.
 */
export const setStudentFinancialAccount = onCall(SECURE_CALL_OPTS, async (request) => {
  const doctorId = requireDoctor(request);
  const studentId = getString(request.data?.studentId);
  const price = getNumber(request.data?.priceEgp);
  const discount = getNumber(request.data?.discountEgp);

  if (!studentId) {
    throw new HttpsError("invalid-argument", "studentId is required.");
  }
  if (price === null || price < 0) {
    throw new HttpsError("invalid-argument", "priceEgp must be zero or greater.");
  }
  if (discount === null || discount < 0) {
    throw new HttpsError("invalid-argument", "discountEgp must be zero or greater.");
  }
  if (discount > price) {
    throw new HttpsError(
      "invalid-argument",
      "discountEgp must not exceed priceEgp.",
    );
  }
  const net = price - discount;

  // A narrower Net must not orphan already-recorded payments (student-level).
  const paidSoFar = await sumPaidForStudent(studentId);
  if (paidSoFar > net) {
    throw new HttpsError(
      "failed-precondition",
      "Total paid already exceeds the new net amount.",
    );
  }

  const now = FieldValue.serverTimestamp();
  const accountRef = db
    .collection("student_financial_accounts")
    .doc(studentId);
  const existing = await accountRef.get();
  if (existing.exists) {
    const prev = dataOf(existing.data());
    await accountRef.update({
      price_egp: price,
      discount_egp: discount,
      net_egp: net,
      is_deleted: false,
      deleted_at: null,
      deleted_by: null,
      updated_at: now,
      updated_by: doctorId,
    });
    await db.collection("admin_audit_log").add({
      action: "financial_account_updated",
      entity: "student_financial_accounts",
      target_id: accountRef.id,
      student_id: studentId,
      previous_net: prev.net_egp ?? null,
      net_egp: net,
      actor_id: doctorId,
      actor_role: "doctor",
      permission_basis: "doctor",
      created_at: now,
      timestamp: now,
    });
  } else {
    await accountRef.set({
      student_id: studentId,
      price_egp: price,
      discount_egp: discount,
      net_egp: net,
      created_at: now,
      updated_at: now,
      created_by: doctorId,
      updated_by: doctorId,
      is_deleted: false,
      deleted_at: null,
      deleted_by: null,
    });
    await db.collection("admin_audit_log").add({
      action: "financial_account_created",
      entity: "student_financial_accounts",
      target_id: accountRef.id,
      student_id: studentId,
      net_egp: net,
      actor_id: doctorId,
      actor_role: "doctor",
      permission_basis: "doctor",
      created_at: now,
      timestamp: now,
    });
  }

  return {accountId: accountRef.id, netEgp: net};
});

/**
 * Doctor-only manual per-Student x Subject pricing reference (approved
 * student_subject_pricing_database_change_authority.md).
 *
 * ONE callable for both Create and Correct at the deterministic document
 * `student_subject_pricing/{studentId}_{subjectId}`. Price and Discount
 * are entered manually by the Doctor; Net = Price - Discount is always
 * derived server-side and any client-supplied net value is ignored.
 *
 * DISPLAY / FINANCIAL-REFERENCE ONLY. This callable never authorizes
 * payments, never evaluates caps, never aggregates Paid/Balance, and
 * never reads or writes payment_logs, student_financial_accounts,
 * student_subject_accounts, subscriptions, or subject_access_assignments.
 */
export const setStudentSubjectPricing = onCall(SECURE_CALL_OPTS, async (request) => {
  const doctorId = requireDoctor(request);
  const studentId = getString(request.data?.studentId);
  const subjectId = getString(request.data?.subjectId);
  const price = getNumber(request.data?.priceEgp);
  const discount = getNumber(request.data?.discountEgp);

  if (!studentId) {
    throw new HttpsError("invalid-argument", "studentId is required.");
  }
  if (!subjectId) {
    throw new HttpsError("invalid-argument", "subjectId is required.");
  }
  if (price === null || price < 0) {
    throw new HttpsError("invalid-argument", "priceEgp must be zero or greater.");
  }
  if (discount === null || discount < 0) {
    throw new HttpsError("invalid-argument", "discountEgp must be zero or greater.");
  }
  if (discount > price) {
    throw new HttpsError(
      "invalid-argument",
      "discountEgp must not exceed priceEgp.",
    );
  }
  // Server-derived Net. Any client-supplied net value is never read here,
  // so the client cannot control the stored Net.
  const net = price - discount;

  const now = FieldValue.serverTimestamp();
  const pricingId = `${studentId}_${subjectId}`;
  const pricingRef = db
    .collection("student_subject_pricing")
    .doc(pricingId);
  const existing = await pricingRef.get();
  if (existing.exists) {
    const prev = dataOf(existing.data());
    await pricingRef.update({
      price_egp: price,
      discount_egp: discount,
      net_egp: net,
      is_deleted: false,
      deleted_at: null,
      deleted_by: null,
      updated_at: now,
      updated_by: doctorId,
    });
    await db.collection("admin_audit_log").add({
      action: "subject_pricing_updated",
      entity: "student_subject_pricing",
      target_id: pricingRef.id,
      student_id: studentId,
      subject_id: subjectId,
      before: {
        price_egp: prev.price_egp ?? null,
        discount_egp: prev.discount_egp ?? null,
        net_egp: prev.net_egp ?? null,
      },
      after: {
        price_egp: price,
        discount_egp: discount,
        net_egp: net,
      },
      actor_id: doctorId,
      actor_role: "doctor",
      permission_basis: "doctor",
      created_at: now,
      timestamp: now,
    });
  } else {
    await pricingRef.set({
      student_id: studentId,
      subject_id: subjectId,
      price_egp: price,
      discount_egp: discount,
      net_egp: net,
      created_at: now,
      updated_at: now,
      created_by: doctorId,
      updated_by: doctorId,
      is_deleted: false,
      deleted_at: null,
      deleted_by: null,
    });
    await db.collection("admin_audit_log").add({
      action: "subject_pricing_created",
      entity: "student_subject_pricing",
      target_id: pricingRef.id,
      student_id: studentId,
      subject_id: subjectId,
      price_egp: price,
      discount_egp: discount,
      net_egp: net,
      actor_id: doctorId,
      actor_role: "doctor",
      permission_basis: "doctor",
      created_at: now,
      timestamp: now,
    });
  }

  return {pricingId: pricingRef.id, netEgp: net};
});

/**
  * Doctor-only in-place correction of a transcribed payment record.
  *
  * The record keeps its identity; student_id linkage, created_by and
  * created_at are immutable (a historical subject_id memo, if present,
  * is frozen descriptive text and is never edited here).
  * updated_by/updated_at track the correcting
  * Doctor, and the before/after values are written to the audit log.
  */
export const correctPaymentLog = onCall(SECURE_CALL_OPTS, async (request) => {
  const doctorId = requireDoctor(request);
  const paymentId = getString(request.data?.paymentId)?.trim();
  if (!paymentId) {
    throw new HttpsError("invalid-argument", "paymentId is required.");
  }

  const paymentRef = db.collection("payment_logs").doc(paymentId);
  const snap = await paymentRef.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "Payment record was not found.");
  }
  const current = dataOf(snap.data());
  if (current.is_deleted === true) {
    throw new HttpsError(
      "failed-precondition",
      "Deleted payment records cannot be corrected.",
    );
  }

  const patch: DocumentData = {};
  if (request.data && "amount" in (request.data as object)) {
    const amount = getNumber((request.data as Record<string, unknown>).amount);
    if (amount === null || amount < 0) {
      throw new HttpsError("invalid-argument", "amount must be zero or greater.");
    }
    patch.amount = amount;
  }
  if (request.data && "paymentMethod" in (request.data as object)) {
    patch.payment_method = parsePaymentMethod(
      (request.data as Record<string, unknown>).paymentMethod,
    );
  }
  if (request.data && "collectorName" in (request.data as object)) {
    patch.collected_by = parseCollectorName(
      (request.data as Record<string, unknown>).collectorName,
    );
  }
  if (request.data && "paymentDate" in (request.data as object)) {
    patch.payment_date = parsePaymentDate(
      (request.data as Record<string, unknown>).paymentDate,
    );
  }
  if (request.data && "receiptNumber" in (request.data as object)) {
    const receipt = getString((request.data as Record<string, unknown>).receiptNumber)?.trim();
    if (!receipt) {
      throw new HttpsError("invalid-argument", "receiptNumber must be non-empty.");
    }
    patch.receipt_number = receipt;
  }
  if (request.data && "notes" in (request.data as object)) {
    patch.notes = parseNotes((request.data as Record<string, unknown>).notes);
  }
  if (Object.keys(patch).length === 0) {
    throw new HttpsError("invalid-argument", "No correctable fields supplied.");
  }

  // Over-Net protection (student-level), excluding the record being
  // corrected. Historical `subject_id` on the record is legacy metadata
  // and is never used here.
  const studentId = current.student_id as string;
  if (!studentId) {
    throw new HttpsError(
      "failed-precondition",
      "Payment record has no student linkage.",
    );
  }
  const account = await readStudentAccount(studentId);
  if (!account) {
    throw new HttpsError(
      "failed-precondition",
      "No financial account exists for this student.",
    );
  }
  const nextAmount =
    "amount" in patch ? (patch.amount as number) : (current.amount as number);
  const paidExcludingSelf = await sumPaidForStudent(studentId, paymentId);
  if (paidExcludingSelf + nextAmount > account.netEgp) {
    throw new HttpsError(
      "failed-precondition",
      "Total paid would exceed the student net amount.",
    );
  }

  const now = FieldValue.serverTimestamp();
  const before: DocumentData = {};
  for (const key of Object.keys(patch)) {
    before[key] = current[key] ?? null;
  }
  // Historical subject memo, if present, is carried into the audit as
  // descriptive text only.
  const auditSubject: {subject_id?: string} = {};
  if (typeof current.subject_id === "string" && current.subject_id) {
    auditSubject.subject_id = current.subject_id;
  }
  await paymentRef.update({
    ...patch,
    updated_at: now,
    updated_by: doctorId,
  });

  await db.collection("admin_audit_log").add({
    action: "payment_corrected",
    entity: "payment_logs",
    target_id: paymentId,
    student_id: studentId,
    ...auditSubject,
    before,
    after: patch,
    actor_id: doctorId,
    actor_role: "doctor",
    permission_basis: "doctor",
    created_at: now,
    timestamp: now,
  });

  return {corrected: true, paymentId};
});

export const onDeviceTokenRefresh = onCall(SECURE_CALL_OPTS, async (request) => {
  const userId = requireAuthenticated(request);
  const deviceId = getString(request.data?.deviceId);
  const fcmToken = getString(request.data?.fcmToken);
  if (!deviceId || !fcmToken) throw new HttpsError("invalid-argument", "deviceId and fcmToken are required.");

  const deviceSnap = await db.collection("devices").where("user_id", "==", userId).where("device_id", "==", deviceId).limit(1).get();
  if (deviceSnap.empty) throw new HttpsError("permission-denied", "Device is not registered for this user.");

  await deviceSnap.docs[0].ref.update({fcm_token: fcmToken, last_login: FieldValue.serverTimestamp(), updated_at: FieldValue.serverTimestamp(), updated_by: "system"});
  return {updated: true};
});

// ADR-004: registry hygiene only. `active_device` no longer exists as a
// signal, so pruning targets soft-deleted registry rows that still hold a
// token. Live rows keep their tokens (revocation never implies unreachable).
export const cleanupInvalidDeviceTokens = onSchedule("every 24 hours", async () => {
  const devicesSnap = await db.collection("devices").where("is_deleted", "==", true).limit(200).get();
  for (const doc of devicesSnap.docs) {
    if (doc.data().fcm_token) {
      await doc.ref.update({fcm_token: null, updated_at: FieldValue.serverTimestamp(), updated_by: "system"});
    }
  }
});

async function getMembershipForMutation(studentId: string, subjectId: string) {
  const snap = await db.collection("subscriptions")
    .where("student_id", "==", studentId)
    .where("subject_id", "==", subjectId)
    .where("status", "==", "active")
    .limit(1)
    .get();
  if (snap.empty) throw new HttpsError("not-found", "Active subscription was not found.");
  return {ref: snap.docs[0].ref, data: dataOf(snap.docs[0].data())};
}

async function validateMembershipPlan(studentId: string, planId: string) {
  const studentSnap = await db.collection("users").doc(studentId).get();
  if (!studentSnap.exists) throw new HttpsError("not-found", "Student not found.");
  const studentType = getString(studentSnap.data()?.student_type);
  if (!studentType) throw new HttpsError("failed-precondition", "Student type is not configured.");
  const planSnap = await db.collection("plans").doc(planId).get();
  if (!planSnap.exists) throw new HttpsError("not-found", "Membership plan was not found.");
  const plan = dataOf(planSnap.data());
  if (plan.is_active !== true || plan.student_type !== studentType) {
    throw new HttpsError("failed-precondition", "Membership plan is not valid for this student.");
  }
}

async function changeMembershipPlan(
  request: CallableRequest<Record<string, unknown>>,
  eventType: string,
) {
  const authorization = await requireStudentAccessManager(request);
  const studentId = getString(request.data?.studentId);
  const subjectId = getString(request.data?.subjectId);
  const newPlanId = getString(request.data?.newPlanId);
  if (!studentId || !subjectId || !newPlanId) {
    throw new HttpsError("invalid-argument", "studentId, subjectId and newPlanId are required.");
  }
  const membership = await getMembershipForMutation(studentId, subjectId);
  await validateMembershipPlan(studentId, newPlanId);
  await membership.ref.update({
    previous_plan_id: getString(membership.data.plan_id),
    plan_id: newPlanId,
    updated_at: FieldValue.serverTimestamp(),
    updated_by: authorization.actorId,
  });
  await writeAnalyticsEvent(studentId, eventType, membership.ref.id, {subject_id: subjectId, new_plan_id: newPlanId, changed_by: authorization.actorId});
  await db.collection("admin_audit_log").add({
    action: "membership_plan_changed",
    entity: "subscriptions",
    target_id: studentId,
    subscription_id: membership.ref.id,
    previous_plan_id: getString(membership.data.plan_id),
    new_plan_id: newPlanId,
    actor_id: authorization.actorId,
    actor_role: authorization.actorRole,
    permission_basis: authorization.permissionBasis,
    created_at: FieldValue.serverTimestamp(),
    timestamp: FieldValue.serverTimestamp(),
  });

  const entitlements = await getActiveEntitlements(newPlanId);
  await db.collection("subject_access_assignments").doc(`${studentId}_${subjectId}`).update({
    entitlements,
    subscription_expires_at: membership.data.end_date ?? null,
  });

  return {subscriptionId: membership.ref.id};
}

export const upgrade = onCall(SECURE_CALL_OPTS, async (request) => changeMembershipPlan(request, "Membership Upgraded"));
export const downgrade = onCall(SECURE_CALL_OPTS, async (request) => changeMembershipPlan(request, "Membership Downgraded"));

export const renew = onCall(SECURE_CALL_OPTS, async (request) => {
  const authorization = await requireStudentAccessManager(request);
  const studentId = getString(request.data?.studentId);
  const subjectId = getString(request.data?.subjectId);
  if (!studentId || !subjectId) throw new HttpsError("invalid-argument", "studentId and subjectId are required.");
  const membership = await getMembershipForMutation(studentId, subjectId);
  const binding = await resolveSubscriptionPeriodBinding();
  // Renew mirror sync (subscription-expiry drift fix): the assignment row's
  // subscription_expires_at is the server-maintained mirror of
  // subscriptions.end_date, so renew writes both with the same value in one
  // transaction — no new fields, no logic change, same return contract. The
  // mirror update is skipped only when no assignment row exists (renew keeps
  // succeeding exactly as before in that case).
  await db.runTransaction(async (tx) => {
    const assignmentRef = db.collection("subject_access_assignments").doc(`${studentId}_${subjectId}`);
    const assignmentSnap = await tx.get(assignmentRef);
    tx.update(membership.ref, {
      academic_period_id: binding.academicPeriodId,
      end_date: binding.endDate,
      status: "active",
      renewal_count: (typeof membership.data.renewal_count === "number" ? membership.data.renewal_count : 0) + 1,
      updated_at: FieldValue.serverTimestamp(),
      updated_by: authorization.actorId,
    });
    if (assignmentSnap.exists) {
      tx.update(assignmentRef, {
        subscription_expires_at: binding.endDate,
      });
    }
  });
  await writeAnalyticsEvent(studentId, "Membership Renewed", membership.ref.id, {subject_id: subjectId, renewed_by: authorization.actorId});
  await db.collection("admin_audit_log").add({
    action: "membership_renewed",
    entity: "subscriptions",
    target_id: studentId,
    subscription_id: membership.ref.id,
    actor_id: authorization.actorId,
    actor_role: authorization.actorRole,
    permission_basis: authorization.permissionBasis,
    created_at: FieldValue.serverTimestamp(),
    timestamp: FieldValue.serverTimestamp(),
  });
  return {subscriptionId: membership.ref.id};
});

export const setSubscriptionDisciplinaryStatus = onCall(SECURE_CALL_OPTS, async (request) => {
  const doctorId = requireDoctor(request);
  const subscriptionId = getString(request.data?.subscriptionId);
  const disabled = request.data?.disabled;
  const reason = getString(request.data?.reason);
  if (!subscriptionId || typeof disabled !== "boolean") {
    throw new HttpsError("invalid-argument", "subscriptionId and disabled are required.");
  }

  const subscriptionRef = db.collection("subscriptions").doc(subscriptionId);
  const auditRef = db.collection("admin_audit_log").doc();

  await db.runTransaction(async (transaction) => {
    const snap = await transaction.get(subscriptionRef);
    if (!snap.exists) throw new HttpsError("not-found", "Subscription not found.");
    const previous = dataOf(snap.data());

    transaction.update(subscriptionRef, {
      manually_disabled: disabled,
      disabled_by: disabled ? doctorId : null,
      disabled_at: disabled ? FieldValue.serverTimestamp() : null,
      disabled_reason: disabled ? (reason ?? null) : null,
      updated_at: FieldValue.serverTimestamp(),
    });

    transaction.set(auditRef, {
      action: disabled ? "disciplinary_disable" : "disciplinary_enable",
      entity: "subscription",
      target_id: subscriptionId,
      student_id: previous.student_id ?? null,
      subject_id: previous.subject_id ?? null,
      reason: reason ?? null,
      actor_id: doctorId,
      created_at: FieldValue.serverTimestamp(),
    });
  });

  return {success: true};
});

/* ============================================================
 * ACADEMIC PERIODS
 * Doctor (Platform Owner) ONLY - no delegated admin permission.
 *
 * Approved schema (collection: academic_periods):
 *   id, period_type (term_1 | term_2 | summer_course | free text),
 *   label (Arabic display name), is_core, status (active | ended),
 *   started_at, ended_at, created_by, created_at
 * ============================================================ */

const ACADEMIC_PERIOD_STATUSES = new Set(["active", "ended"]);

const CORE_ACADEMIC_PERIODS = [
  {id: "term_1", periodType: "term_1", label: "الترم الأول", displayOrder: 1},
  {id: "term_2", periodType: "term_2", label: "الترم الثاني", displayOrder: 2},
  {id: "summer_course", periodType: "summer_course", label: "السمر كورس", displayOrder: 3},
];

function normalizePeriodStatus(value: unknown): string {
  const status = getString(value);
  if (!status) return "ended";
  const normalized = status.toLowerCase();
  if (normalized === "active" || normalized === "started") return "active";
  return "ended";
}

function serializeAcademicPeriod(doc: DocumentData) {
  const data = dataOf(doc.data());
  const isCore = data.is_core === true ||
    CORE_ACADEMIC_PERIODS.some((period) => period.id === doc.id);
  return {
    id: doc.id,
    period_type: getString(data.period_type) ?? doc.id,
    label: getString(data.label) ?? getString(data.name) ?? doc.id,
    is_core: isCore,
    status: normalizePeriodStatus(data.status),
    display_order: typeof data.display_order === "number" ?
      data.display_order :
      (isCore ?
        (CORE_ACADEMIC_PERIODS.find((period) => period.id === doc.id)?.displayOrder ?? 99) :
        99),
    started_at: data.started_at ?? null,
    ended_at: data.ended_at ?? null,
  };
}

export const initializeAcademicPeriods = onCall(SECURE_CALL_OPTS, async (request) => {
  const doctorId = requireDoctor(request);

  const batch = db.batch();
  let created = 0;

  for (const period of CORE_ACADEMIC_PERIODS) {
    const ref = db.collection("academic_periods").doc(period.id);
    const snapshot = await ref.get();

    if (!snapshot.exists) {
      created += 1;
      batch.set(ref, {
        id: period.id,
        period_type: period.periodType,
        label: period.label,
        is_core: true,
        status: "ended",
        display_order: period.displayOrder,
        started_at: null,
        ended_at: null,
        created_by: doctorId,
        created_at: FieldValue.serverTimestamp(),
        updated_at: FieldValue.serverTimestamp(),
        updated_by: doctorId,
        is_deleted: false,
      });
    } else {
      // Backfill the approved schema on existing documents without
      // touching the lifecycle state.
      const data = dataOf(snapshot.data());
      const patch: Record<string, unknown> = {};
      if (getString(data.label) === null) patch.label = period.label;
      if (data.is_core !== true) patch.is_core = true;
      if (typeof data.display_order !== "number") {
        patch.display_order = period.displayOrder;
      }
      if (getString(data.period_type) === null) {
        patch.period_type = period.periodType;
      }
      if (Object.keys(patch).length > 0) {
        patch.updated_at = FieldValue.serverTimestamp();
        patch.updated_by = doctorId;
        batch.set(ref, patch, {merge: true});
      }
    }
  }

  await batch.commit();

  await db.collection("admin_audit_log").add({
    action: "academic_periods_initialized",
    actor_id: doctorId,
    actor_role: "doctor",
    target_type: "academic_periods",
    previous_state: null,
    new_state: "INITIALIZED",
    created_count: created,
    created_at: FieldValue.serverTimestamp(),
    timestamp: FieldValue.serverTimestamp(),
  });

  return {
    success: true,
    periods: CORE_ACADEMIC_PERIODS.map((period) => period.id),
  };
});


export const getAcademicPeriods = onCall(SECURE_CALL_OPTS, async (request) => {
  requireDoctor(request);

  const snapshot = await db
    .collection("academic_periods")
    .where("is_deleted", "==", false)
    .get();

  const periods = snapshot.docs
    .map(serializeAcademicPeriod)
    .sort((a, b) => {
      if (a.is_core !== b.is_core) return a.is_core ? -1 : 1;
      return a.display_order - b.display_order;
    });

  return {periods};
});

export const createExceptionalAcademicPeriod = onCall(SECURE_CALL_OPTS, async (request) => {
  const doctorId = requireDoctor(request);

  const label = getString(request.data?.label) ?? getString(request.data?.name);
  const periodType = getString(request.data?.periodType) ?? "exceptional";

  if (!label) {
    throw new HttpsError(
      "invalid-argument",
      "Exceptional academic period label is required.",
    );
  }

  const ref = db.collection("academic_periods").doc();

  await ref.set({
    id: ref.id,
    period_type: periodType,
    label,
    is_core: false,
    status: "ended",
    display_order: 99,
    started_at: null,
    ended_at: null,
    created_by: doctorId,
    created_at: FieldValue.serverTimestamp(),
    updated_at: FieldValue.serverTimestamp(),
    updated_by: doctorId,
    is_deleted: false,
  });

  await db.collection("admin_audit_log").add({
    action: "academic_period_created",
    actor_id: doctorId,
    actor_role: "doctor",
    target_id: ref.id,
    target_type: "academic_period",
    previous_state: null,
    new_state: "ended",
    created_at: FieldValue.serverTimestamp(),
    timestamp: FieldValue.serverTimestamp(),
  });

  return {
    success: true,
    periodId: ref.id,
  };
});

export const setAcademicPeriodStatus = onCall(SECURE_CALL_OPTS, async (request) => {
  const doctorId = requireDoctor(request);

  const periodId = getString(request.data?.periodId);
  const requestedStatus = getString(request.data?.status);
  const newStatus = requestedStatus === null ?
    null :
    normalizePeriodStatus(requestedStatus);

  if (!periodId) {
    throw new HttpsError(
      "invalid-argument",
      "periodId is required.",
    );
  }

  if (!newStatus || !ACADEMIC_PERIOD_STATUSES.has(newStatus)) {
    throw new HttpsError(
      "invalid-argument",
      "Invalid academic period status.",
    );
  }

  const periodRef = db.collection("academic_periods").doc(periodId);
  let endedAt: Timestamp | null = null;

  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(periodRef);

    if (!snapshot.exists) {
      throw new HttpsError(
        "not-found",
        "Academic period not found.",
      );
    }

    const current = dataOf(snapshot.data());

    if (current.is_deleted === true) {
      throw new HttpsError(
        "failed-precondition",
        "Deleted academic periods cannot be changed.",
      );
    }

    const previousStatus = normalizePeriodStatus(current.status);

    if (previousStatus === newStatus) {
      throw new HttpsError(
        "failed-precondition",
        "Academic period is already in the requested state.",
      );
    }

    const update: Record<string, unknown> = {
      status: newStatus,
      updated_at: FieldValue.serverTimestamp(),
      updated_by: doctorId,
    };

    if (newStatus === "active") {
      update.started_at = FieldValue.serverTimestamp();
      update.ended_at = null;
    }

    if (newStatus === "ended") {
      endedAt = Timestamp.now();
      update.ended_at = endedAt;
    }

    transaction.update(periodRef, update);

    const auditRef = db.collection("admin_audit_log").doc();

    transaction.set(auditRef, {
      action: "academic_period_status_changed",
      actor_id: doctorId,
      actor_role: "doctor",
      target_id: periodId,
      target_type: "academic_period",
      previous_state: previousStatus,
      new_state: newStatus,
      created_at: FieldValue.serverTimestamp(),
      timestamp: FieldValue.serverTimestamp(),
    });
  });

  // Ending a period automatically ends every subscription bound to it:
  // end_date is stamped with the period ended_at inside one batch.
  if (newStatus === "ended" && endedAt !== null) {
    const subscriptions = await db
      .collection("subscriptions")
      .where("academic_period_id", "==", periodId)
      .where("status", "==", "active")
      .get();

    let batch = db.batch();
    let operations = 0;

    for (const subscription of subscriptions.docs) {
      batch.update(subscription.ref, {
        status: "expired",
        end_date: endedAt,
        updated_at: FieldValue.serverTimestamp(),
        updated_by: doctorId,
      });
      operations++;

      const subData = subscription.data();
      const assignmentId = `${subData.student_id}_${subData.subject_id}`;
      batch.update(db.collection("subject_access_assignments").doc(assignmentId), {
        entitlements: [],
        subscription_expires_at: endedAt,
      });
      operations++;

      if (operations >= 450) {
        await batch.commit();
        batch = db.batch();
        operations = 0;
      }
    }

    if (operations > 0) {
      await batch.commit();
    }
  }

  return {
    success: true,
    periodId,
    status: newStatus,
  };
});


/* ============================================================
 * SUBJECT MANAGEMENT (Dashboard)
 * Same permission pattern as setSubjectAccess: Doctor always,
 * delegated admin only with the matching admin_permissions key.
 * ============================================================ */

async function requireContentManager(request: CallableRequest<unknown>): Promise<{
  actorId: string;
  actorRole: "doctor" | "admin";
  permissionBasis: "doctor" | "delegated:admin_content";
}> {
  const actorId = requireAuthenticated(request);
  const role = callerRole(request);
  if (role === "doctor") {
    return {actorId, actorRole: "doctor", permissionBasis: "doctor"};
  }
  if (role !== "admin") {
    throw new HttpsError("permission-denied", "Content management permission is required.");
  }

  const permissionSnap = await db.collection("admin_permissions").doc(actorId).get();
  const permissionData = dataOf(permissionSnap.data());
  const permissions = permissionData.permissions;
  if (
    permissionData.is_active !== true ||
    !permissions ||
    typeof permissions !== "object" ||
    permissions.admin_content !== true
  ) {
    throw new HttpsError("permission-denied", "Delegated content-management permission is required.");
  }

  return {actorId, actorRole: "admin", permissionBasis: "delegated:admin_content"};
}

export const createSubject = onCall(SECURE_CALL_OPTS, async (request) => {
  const authorization = await requireContentManager(request);
  const name = getString(request.data?.name) ?? getString(request.data?.title);
  const description = getString(request.data?.description);
  const displayOrder = getNumber(request.data?.displayOrder) ?? 0;
  const grade = getString(request.data?.grade);
  const posterUrl = request.data?.posterUrl;

  let validPosterUrl: string | null = null;
  if (posterUrl !== undefined && posterUrl !== null) {
    const urlStr = getString(posterUrl);
    if (!urlStr || (!urlStr.startsWith("https://firebasestorage.googleapis.com/") && !urlStr.startsWith("https://dr-tarek-platform.firebasestorage.app"))) {
      throw new HttpsError("invalid-argument", "invalid_poster_url");
    }
    validPosterUrl = urlStr;
  }

  if (!name) {
    throw new HttpsError("invalid-argument", "Subject name is required.");
  }

  const ref = db.collection("subjects").doc();
  await ref.set({
    id: ref.id,
    title: name,
    name,
    description: description ?? null,
    grade: grade ?? null,
    poster_url: validPosterUrl,
    display_order: displayOrder,
    is_visible: true,
    is_deleted: false,
    deleted_at: null,
    deleted_by: null,
    created_at: FieldValue.serverTimestamp(),
    updated_at: FieldValue.serverTimestamp(),
    created_by: authorization.actorId,
    updated_by: authorization.actorId,
  });

  await db.collection("admin_audit_log").add({
    action: "subject_created",
    entity: "subject",
    target_id: ref.id,
    actor_id: authorization.actorId,
    actor_role: authorization.actorRole,
    permission_basis: authorization.permissionBasis,
    created_at: FieldValue.serverTimestamp(),
    timestamp: FieldValue.serverTimestamp(),
  });

  return {success: true, subjectId: ref.id};
});

export const updateSubject = onCall(SECURE_CALL_OPTS, async (request) => {
  const authorization = await requireContentManager(request);
  const subjectId = getString(request.data?.subjectId);
  const name = getString(request.data?.name) ?? getString(request.data?.title);
  const description = getString(request.data?.description);
  const displayOrder = getNumber(request.data?.displayOrder);
  const isVisible = request.data?.isVisible;
  const posterUrl = request.data?.posterUrl;

  if (!subjectId) {
    throw new HttpsError("invalid-argument", "subjectId is required.");
  }

  const subjectRef = db.collection("subjects").doc(subjectId);

  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(subjectRef);
    if (!snapshot.exists || snapshot.data()?.is_deleted === true) {
      throw new HttpsError("not-found", "Subject not found.");
    }

    const update: Record<string, unknown> = {
      updated_at: FieldValue.serverTimestamp(),
      updated_by: authorization.actorId,
    };
    if (posterUrl !== undefined) {
      if (posterUrl === null) {
        update.poster_url = FieldValue.delete();
      } else {
        const urlStr = getString(posterUrl);
        if (!urlStr || (!urlStr.startsWith("https://firebasestorage.googleapis.com/") && !urlStr.startsWith("https://dr-tarek-platform.firebasestorage.app"))) {
          throw new HttpsError("invalid-argument", "invalid_poster_url");
        }
        update.poster_url = urlStr;
      }
    }
    if (name !== null) {
      update.title = name;
      update.name = name;
    }
    if (description !== null) update.description = description;
    if (displayOrder !== null) update.display_order = displayOrder;
    if (typeof isVisible === "boolean") update.is_visible = isVisible;

    transaction.update(subjectRef, update);
    transaction.set(db.collection("admin_audit_log").doc(), {
      action: "subject_updated",
      entity: "subject",
      target_id: subjectId,
      changed_fields: Object.keys(update).filter((key) =>
        !["updated_at", "updated_by"].includes(key)
      ),
      actor_id: authorization.actorId,
      actor_role: authorization.actorRole,
      permission_basis: authorization.permissionBasis,
      created_at: FieldValue.serverTimestamp(),
      timestamp: FieldValue.serverTimestamp(),
    });
  });

  return {success: true, subjectId};
});

export const deleteSubject = onCall(SECURE_CALL_OPTS, async (request) => {
  const authorization = await requireContentManager(request);
  const subjectId = getString(request.data?.subjectId);

  if (!subjectId) {
    throw new HttpsError("invalid-argument", "subjectId is required.");
  }

  const subjectRef = db.collection("subjects").doc(subjectId);

  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(subjectRef);
    if (!snapshot.exists || snapshot.data()?.is_deleted === true) {
      throw new HttpsError("not-found", "Subject not found.");
    }

    transaction.update(subjectRef, {
      is_deleted: true,
      deleted_at: FieldValue.serverTimestamp(),
      deleted_by: authorization.actorId,
      updated_at: FieldValue.serverTimestamp(),
      updated_by: authorization.actorId,
    });
    transaction.set(db.collection("admin_audit_log").doc(), {
      action: "subject_soft_deleted",
      entity: "subject",
      target_id: subjectId,
      actor_id: authorization.actorId,
      actor_role: authorization.actorRole,
      permission_basis: authorization.permissionBasis,
      created_at: FieldValue.serverTimestamp(),
      timestamp: FieldValue.serverTimestamp(),
    });
  });

  return {success: true, subjectId};
});

/* ============================================================
 * ADMIN MANAGEMENT (Dashboard)
 * Doctor (Platform Owner) ONLY - no delegated permission.
 * ============================================================ */

const ADMIN_PERMISSION_KEYS = [
  "admin_students",
  "admin_content",
  "admin_chat",
  "admin_analytics",
  "admin_devices",
  "admin_payments_view",
  "admin_payments",
  "admin_settings",
  "password_reset",
  "admin_academic_terms",
];

function sanitizeAdminPermissions(value: unknown): Record<string, boolean> {
  const input = (value && typeof value === "object" ? value : {}) as Record<string, unknown>;
  const permissions: Record<string, boolean> = {};
  for (const key of ADMIN_PERMISSION_KEYS) {
    permissions[key] = input[key] === true;
  }
  return permissions;
}

export const addAdmin = onCall(SECURE_CALL_OPTS, async (request) => {
  const doctorId = requireDoctor(request);
  const userId = getString(request.data?.userId);
  if (!userId) {
    throw new HttpsError("invalid-argument", "userId is required.");
  }
  const permissions = sanitizeAdminPermissions(request.data?.permissions);

  const userRef = db.collection("users").doc(userId);
  const permissionRef = db.collection("admin_permissions").doc(userId);

  await db.runTransaction(async (transaction) => {
    const userSnap = await transaction.get(userRef);
    if (!userSnap.exists) throw new HttpsError("not-found", "User not found.");
    const user = dataOf(userSnap.data());
    if (user.role === "doctor") {
      throw new HttpsError("failed-precondition", "The Doctor role cannot be reassigned.");
    }

    transaction.update(userRef, {
      role: "admin",
      approval_status: "approved",
      updated_at: FieldValue.serverTimestamp(),
      updated_by: doctorId,
    });
    transaction.set(permissionRef, {
      admin_id: userId,
      is_active: true,
      permissions,
      created_at: FieldValue.serverTimestamp(),
      created_by: doctorId,
      updated_at: FieldValue.serverTimestamp(),
      updated_by: doctorId,
    }, {merge: true});
    transaction.set(db.collection("admin_audit_log").doc(), {
      action: "admin_added",
      entity: "admin_permissions",
      target_id: userId,
      permissions,
      actor_id: doctorId,
      actor_role: "doctor",
      created_at: FieldValue.serverTimestamp(),
      timestamp: FieldValue.serverTimestamp(),
    });
  });

  // Merge-preserving claims write (mirrors changePassword/syncStaffStoredClaims):
  // a full overwrite here would silently strip unrelated stored claims.
  const currentAdmin = await auth.getUser(userId);
  await auth.setCustomUserClaims(userId, {...(currentAdmin.customClaims ?? {}), role: "admin", approved: true});
  return {success: true, userId};
});

export const removeAdmin = onCall(SECURE_CALL_OPTS, async (request) => {
  const doctorId = requireDoctor(request);
  const userId = getString(request.data?.userId);
  if (!userId) {
    throw new HttpsError("invalid-argument", "userId is required.");
  }

  const userRef = db.collection("users").doc(userId);
  const permissionRef = db.collection("admin_permissions").doc(userId);

  await db.runTransaction(async (transaction) => {
    const userSnap = await transaction.get(userRef);
    if (!userSnap.exists) throw new HttpsError("not-found", "User not found.");
    const user = dataOf(userSnap.data());
    if (user.role !== "admin") {
      throw new HttpsError("failed-precondition", "Target user is not an admin.");
    }

    transaction.update(userRef, {
      role: "student",
      account_status: "disabled",
      updated_at: FieldValue.serverTimestamp(),
      updated_by: doctorId,
    });
    transaction.set(permissionRef, {
      is_active: false,
      permissions: sanitizeAdminPermissions(null),
      updated_at: FieldValue.serverTimestamp(),
      updated_by: doctorId,
    }, {merge: true});
    transaction.set(db.collection("admin_audit_log").doc(), {
      action: "admin_removed",
      entity: "admin_permissions",
      target_id: userId,
      actor_id: doctorId,
      actor_role: "doctor",
      created_at: FieldValue.serverTimestamp(),
      timestamp: FieldValue.serverTimestamp(),
    });
  });

  // Merge-preserving claims write (mirrors changePassword/syncStaffStoredClaims):
  // a full overwrite here would silently strip unrelated stored claims.
  const currentRemoved = await auth.getUser(userId);
  await auth.setCustomUserClaims(userId, {...(currentRemoved.customClaims ?? {}), role: "student", approved: false});
  return {success: true, userId};
});

export const setAdminPermissions = onCall(SECURE_CALL_OPTS, async (request) => {
  const doctorId = requireDoctor(request);
  const userId = getString(request.data?.userId);
  if (!userId) {
    throw new HttpsError("invalid-argument", "userId is required.");
  }
  const permissions = sanitizeAdminPermissions(request.data?.permissions);

  const userRef = db.collection("users").doc(userId);
  const permissionRef = db.collection("admin_permissions").doc(userId);

  await db.runTransaction(async (transaction) => {
    const userSnap = await transaction.get(userRef);
    if (!userSnap.exists) throw new HttpsError("not-found", "User not found.");
    if (dataOf(userSnap.data()).role !== "admin") {
      throw new HttpsError("failed-precondition", "Target user is not an admin.");
    }

    transaction.set(permissionRef, {
      admin_id: userId,
      is_active: true,
      permissions,
      updated_at: FieldValue.serverTimestamp(),
      updated_by: doctorId,
    }, {merge: true});
    transaction.set(db.collection("admin_audit_log").doc(), {
      action: "admin_permissions_updated",
      entity: "admin_permissions",
      target_id: userId,
      permissions,
      actor_id: doctorId,
      actor_role: "doctor",
      created_at: FieldValue.serverTimestamp(),
      timestamp: FieldValue.serverTimestamp(),
    });
  });

  return {success: true, userId};
});

/* ============================================================
 * PLATFORM FEATURE MATRIX (Dashboard)
 * Platform-wide feature toggles, independent from plan features.
 * Doctor (Platform Owner) ONLY.
 * ============================================================ */

export const setPlatformFeature = onCall(SECURE_CALL_OPTS, async (request) => {
  const doctorId = requireDoctor(request);
  const featureKey = getString(request.data?.featureKey);
  const enabled = request.data?.enabled;
  const label = getString(request.data?.label);

  if (!featureKey || typeof enabled !== "boolean") {
    throw new HttpsError("invalid-argument", "featureKey and enabled are required.");
  }

  const ref = db.collection("platform_features").doc(featureKey);

  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const previous = snapshot.exists ? dataOf(snapshot.data()) : null;

    transaction.set(ref, {
      feature_key: featureKey,
      label: label ?? previous?.label ?? featureKey,
      enabled,
      updated_at: FieldValue.serverTimestamp(),
      updated_by: doctorId,
      ...(previous ? {} : {
        created_at: FieldValue.serverTimestamp(),
        created_by: doctorId,
      }),
    }, {merge: true});
    transaction.set(db.collection("admin_audit_log").doc(), {
      action: "platform_feature_toggled",
      entity: "platform_feature",
      target_id: featureKey,
      previous_enabled: previous?.enabled ?? null,
      new_enabled: enabled,
      actor_id: doctorId,
      actor_role: "doctor",
      created_at: FieldValue.serverTimestamp(),
      timestamp: FieldValue.serverTimestamp(),
    });
  });

  return {success: true, featureKey, enabled};
});

export const propagatePlanFeatureChange = onDocumentUpdated("plan_features/{featureId}", async (event) => {
  console.log("propagatePlanFeatureChange triggered for:", event.params.featureId);
  const after = event.data?.after?.data();
  if (!after) {
    console.log("No after data.");
    return;
  }

  const planId = getString(after.plan_id);
  if (!planId) {
    console.log("No plan_id found.");
    return;
  }

  console.log("Fetching active entitlements for plan:", planId);
  const entitlements = await getActiveEntitlements(planId);
  console.log("Active entitlements:", entitlements);

  let lastDoc = null;
  for (;;) {
    let query = db.collection("subscriptions")
      .where("plan_id", "==", planId)
      .where("status", "==", "active")
      .limit(500);

    if (lastDoc) {
      query = query.startAfter(lastDoc);
    }

    const snap = await query.get();
    if (snap.empty) break;

    const batch = db.batch();
    for (const doc of snap.docs) {
      const data = doc.data();
      const assignmentId = `${data.student_id}_${data.subject_id}`;
      batch.update(db.collection("subject_access_assignments").doc(assignmentId), {
        entitlements,
      });
      lastDoc = doc;
    }

    await batch.commit();
  }
});

// Phase 2 Objective Exam Grader
export function gradeObjectiveAnswers(
  studentAnswers: Array<{questionId: string; marks: number}>,
  questionBank: Map<string, {questionType: string; correctAnswer: string}>,
  submittedAnswers: Record<string, string>
) {
  let score = 0;
  let totalMarks = 0;
  let hasEssay = false;
  let missingQuestions = 0;

  for (const answer of studentAnswers) {
    const qId = answer.questionId;
    const marks = Number.isNaN(answer.marks) ? 1 : answer.marks;
    const qDef = questionBank.get(qId);

    if (!qDef) {
      missingQuestions++;
      continue;
    }

    if (qDef.questionType === "essay") {
      hasEssay = true;
      totalMarks += marks;
      continue;
    }

    totalMarks += marks;

    const submitted = submittedAnswers[qId];
    if (submitted && submitted.trim().toLowerCase() === qDef.correctAnswer.trim().toLowerCase()) {
      score += marks;
    }
  }

  const result: any = {score, totalMarks, hasEssay};
  if (missingQuestions > 0) {
    result.missingQuestions = missingQuestions;
  }
  return result;
}

// Phase 2 Storage Delivery Security
export function isDocumentResourceType(type: any): boolean {
  return type === "pdf" || type === "attachment";
}

// V1 Individual Per-Lecture Student Access: deterministic grant identity
// (lecture_access_grants/{lectureId_studentId}) and the explicit-deny
// predicate shared by every protected-content callable.
export function lectureAccessGrantId(lectureId: string, studentId: string): string {
  return `${lectureId}_${studentId}`;
}

export function isLectureAccessDenied(grantData: unknown): boolean {
  if (!grantData || typeof grantData !== "object") return false;
  const grant = grantData as {allowed?: unknown; is_deleted?: unknown};
  // Soft-deleted grants carry no override (treated as missing).
  if (grant.is_deleted === true) return false;
  return grant.allowed === false;
}

export function documentFeatureKeys(type: string) {
  return {
    view: `${type}.access`,
    download: `${type}.download`,
  };
}

export function isDirectThumbnailUrl(url: any): boolean {
  if (typeof url !== "string") return false;
  const lower = url.toLowerCase();
  return lower.startsWith("http://") || lower.startsWith("https://");
}

/**
 * Canonical listing alignment for the first-video predicate (Phase 2):
 * soft-deleted rows are never served, even while still marked visible —
 * dashboard soft-delete keeps `is_visible: true` by design, and the
 * indexed query filters visibility only. The remaining clauses stay where
 * they belong: lecture scoping, visibility, and ordering in the indexed
 * query; entitlement in the checks above; bunny presence in selection.
 * In-memory (no new composite index required). Pure — unit-testable.
 */
export function isServedLectureResource(resource: DocumentData): boolean {
  return resource?.is_deleted !== true;
}

const BUNNY_VIDEO_GUID_STRICT =
  /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

/**
 * VIDEO-ID-ONLY policy: only a bare Bunny GUID validates. Player/share
 * URLs are NEVER normalized — they are invalid input and must fail
 * closed. Kept as a pure helper so issuance + future writes share it.
 */
export function isValidBunnyVideoId(value: unknown): boolean {
  const raw = getString(value);
  if (!raw) return false;
  return BUNNY_VIDEO_GUID_STRICT.test(raw.trim());
}

/**
 * Canonical Bunny identifier for the issuance lookup — VIDEO-ID-ONLY:
 * returns the trimmed raw value unchanged (no URL → GUID extraction).
 * URLs therefore never match a stored GUID and fail closed with the
 * exact-match query below.
 */
export function normalizeBunnyVideoIdForLookup(value: unknown): string | null {
  const raw = getString(value);
  if (!raw) return null;
  return raw.trim();
}


// ============================================================
// RESTORED FUNCTIONS (recovered from dr_tarek_platform_code_review — 2026-09-01)
// Reason: functions were present on server but missing from local code after legacy sync
// ============================================================

export const getActiveCustomGroups = onCall(SECURE_CALL_OPTS, async (request) => {
  await assertStaffDirectoryAllowed(request);
  const snap = await db.collection("custom_groups")
    .where("is_active", "==", true)
    .get();
  const groups = snap.docs
    .map((doc) => ({
      id: doc.id,
      name: getString(doc.data().name) ?? "",
      grade: getString(doc.data().grade),
    }))
    .filter((group) => group.name.length > 0)
    .sort((a, b) => a.name.localeCompare(b.name));
  return {groups};
});

export const listStaffDirectory = onCall(SECURE_CALL_OPTS, async (request) => {
  await assertStaffDirectoryAllowed(request);
  const snap = await db.collection("users").where("role", "in", ["doctor", "admin"]).get();

  const staff = snap.docs
    .map((doc) => ({id: doc.id, data: dataOf(doc.data())}))
    .filter(({data}) => {
      const status = getString(data.account_status);
      return !status || status === "active";
    })
    .map(({data}) => ({
      displayName: getString(data.full_name)?.trim() ?? "",
      roleKind: data.role === "doctor" ? "dr" : "admin",
    }))
    .filter((entry) => entry.displayName.length > 0)
    .sort((a, b) => a.displayName.localeCompare(b.displayName))
    .slice(0, 25);

  return {staff};
});

export const verifyStaffPassword = onCall(SECURE_CALL_OPTS, async (request) => {
  const displayName = getString(request.data?.displayName)?.trim() ?? "";
  const password = getString(request.data?.password);

  if (!displayName || !password) {
    throw new HttpsError("invalid-argument", "Display name and password are required.");
  }

  // Pre-lookup anti-spray gate (staff path only): evaluated before the
  // users query and before any name-state branch, so throttled callers
  // learn nothing about name existence. Absent IP skips, matching the
  // student-login gate; Firestore errors propagate and fail closed.
  const staffLoginIp = requestIp(request);
  if (staffLoginIp) {
    await assertLoginNotLocked(STAFF_LOGIN_IP_SCOPE, staffLoginIp);
  }

  const throttleKey = displayName.toLowerCase();
  await assertLoginNotLocked("staff_login", throttleKey);

  const snap = await db.collection("users").where("role", "in", ["doctor", "admin"]).get();
  const matches = snap.docs.filter((doc) => {
    const user = dataOf(doc.data());
    if (!user || typeof user !== "object") return false;
    const record = user as Record<string, unknown>;
    const name = getString(record.full_name)?.trim().toLowerCase() ?? "";
    if (name !== throttleKey) return false;
    const status = getString(record.account_status);
    return !status || status === "active";
  });

  if (matches.length === 0) {
    await recordLoginFailure("staff_login", throttleKey);
    if (staffLoginIp) {
      await recordLoginFailure(STAFF_LOGIN_IP_SCOPE, staffLoginIp, STAFF_LOGIN_IP_MAX_FAILURES);
    }
    throw new HttpsError("unauthenticated", "Invalid name or password.");
  }
  if (matches.length > 1) {
    throw new HttpsError(
      "failed-precondition",
      "This display name is ambiguous. Ask the platform owner to make staff names unique.",
    );
  }

  const userDoc = matches[0];
  const user = dataOf(userDoc.data());

  const secretSnap = await db.collection("user_secrets").doc(userDoc.id).get();
  const secretData = secretSnap.exists ? dataOf(secretSnap.data()) : {};
  const passwordHash = getString(secretData.password_hash) ?? getString(user.password_hash);
  if (!passwordHash || !(await verifyPassword(password, passwordHash))) {
    await recordLoginFailure("staff_login", throttleKey);
    if (staffLoginIp) {
      await recordLoginFailure(STAFF_LOGIN_IP_SCOPE, staffLoginIp, STAFF_LOGIN_IP_MAX_FAILURES);
    }
    await writeAnalyticsEvent(userDoc.id, "Failed Login", userDoc.id, {reason: "invalid_staff_credentials"}, request);
    throw new HttpsError("unauthenticated", "Invalid name or password.");
  }

  await clearLoginFailures("staff_login", throttleKey);

  const role = getString(user.role) ?? "admin";
  // Persist the authoritative Firestore role to the stored custom claims
  // (merge preserves max_devices and other valid claims).
  await syncStaffStoredClaims(userDoc.id, role, user.force_password_change === true);
  const token = await auth.createCustomToken(userDoc.id, {
    role,
    approved: true,
    force_password_change: user.force_password_change === true,
  });

  await writeAnalyticsEvent(userDoc.id, "Login", userDoc.id, {method: "staff_name_password"}, request);
  return {token, userId: userDoc.id};
});

export const uploadBunnyResource = onCall(
  {
    ...SECURE_CALL_OPTS,
    secrets: [
      SECRET_BUNNY_TOKEN_KEY,
      SECRET_BUNNY_STORAGE_BASE_URL,
      SECRET_BUNNY_STORAGE_ZONE_NAME,
      SECRET_BUNNY_STORAGE_PASSWORD,
    ],
  },
  async (request) => {
    const authorization = await requireContentManager(request);
    const actorId = authorization.actorId;

    const lectureId = getString(request.data?.lectureId);
    const resourceId = getString(request.data?.resourceId);
    const fileName = getString(request.data?.fileName);
    const contentType = getString(request.data?.contentType);
    const dataBase64 = typeof request.data?.dataBase64 === "string" ? request.data.dataBase64 : null;

    if (!lectureId || !resourceId || !fileName || !contentType || !dataBase64) {
      throw new HttpsError("invalid-argument", "lectureId, resourceId, fileName, contentType and dataBase64 are required.");
    }
    if (!/^[\w.\- ]+$/.test(fileName)) {
      throw new HttpsError("invalid-argument", "Invalid file name.");
    }
    if (!BUNNY_UPLOAD_CONTENT_TYPES.has(contentType)) {
      throw new HttpsError("invalid-argument", "Unsupported content type.");
    }
    const bytes = Buffer.from(dataBase64, "base64");
    if (bytes.length === 0 || bytes.length > BUNNY_PROXY_MAX_BYTES) {
      throw new HttpsError("invalid-argument", "Payload exceeds the Bunny proxy upload limit.");
    }

    const storagePath = `lecture_resources/${lectureId}/${resourceId}/${fileName}`;
    await bunnyStorageRequest("PUT", storagePath, bytes);

    await db.collection("admin_audit_log").add({
      action: "bunny_resource_uploaded",
      entity: "lecture_resources",
      target_id: resourceId,
      storage_path: storagePath,
      byte_size: bytes.length,
      actor_id: actorId,
      actor_role: authorization.actorRole,
      created_at: FieldValue.serverTimestamp(),
      timestamp: FieldValue.serverTimestamp(),
    });

    return {storagePath};
  });

export const deleteBunnyResource = onCall(
  {
    ...SECURE_CALL_OPTS,
    secrets: [
      SECRET_BUNNY_TOKEN_KEY,
      SECRET_BUNNY_STORAGE_BASE_URL,
      SECRET_BUNNY_STORAGE_ZONE_NAME,
      SECRET_BUNNY_STORAGE_PASSWORD,
    ],
  },
  async (request) => {
    const authorization = await requireContentManager(request);
    const uid = authorization.actorId;
    const role = authorization.actorRole;
    const storagePath = getString(request.data?.storagePath);
    if (!storagePath || storagePath.includes("..")) {
      throw new HttpsError("invalid-argument", "A valid storagePath is required.");
    }
    await bunnyStorageRequest("DELETE", storagePath);
    await db.collection("admin_audit_log").add({
      action: "bunny_resource_deleted",
      entity: "lecture_resources",
      target_id: storagePath,
      actor_id: uid,
      actor_role: role,
      created_at: FieldValue.serverTimestamp(),
      timestamp: FieldValue.serverTimestamp(),
    });
    return {success: true};
  });

export const generateBunnyResourceUrl = onCall(
  {
    ...SECURE_CALL_OPTS,
    secrets: [
      SECRET_BUNNY_TOKEN_KEY,
      SECRET_BUNNY_STORAGE_BASE_URL,
    ],
  },
  async (request) => {
    const userId = requireAuthenticated(request);
    const resourceId = getString(request.data?.resourceId);
    const deviceId = normalizeDeviceId(request.data?.deviceId);
    const forDownload = request.data?.forDownload === true;
    if (!resourceId) throw new HttpsError("invalid-argument", "resourceId is required.");
    if (!deviceId) throw new HttpsError("invalid-argument", "deviceId is required.");

    const ctx = await resolveDocumentAccess(userId, resourceId);
    // ADR-004: Guest devices never receive protected Bunny resources.
    await requireFullSubjectTier({
      studentId: userId,
      subjectId: ctx.subjectId,
      deviceId,
      ipAddress: typeof request.rawRequest?.ip === "string" ? request.rawRequest.ip : null,
    });
    if (ctx.storageProvider !== "bunny") {
      throw new HttpsError("failed-precondition", "This resource is not Bunny-hosted; use the Firebase PDF endpoints.");
    }

    const featureKeys = documentFeatureKeys(ctx.resourceType);
    const featureKey = forDownload ? featureKeys.download : featureKeys.view;
    const feature = await getPlanFeature(ctx.planId, featureKey);
    if (feature?.enabled !== true) {
      throw new HttpsError("permission-denied", `${featureKey} is not enabled for your plan.`);
    }

    const signed = buildBunnyResourceAccessUrl(ctx.storagePath, 300);
    await writeAnalyticsEvent(
      userId,
      forDownload ? "Download PDF" : "View PDF",
      resourceId,
      {subject_id: ctx.subjectId, lecture_id: ctx.lectureId, storage_provider: "bunny", resource_type: ctx.resourceType},
    );
    return {url: signed.url, expiresAt: signed.expiresAt * 1000, canDownload: !forDownload ? false : true};
  });

export const submitPasswordResetRequest = onCall(SECURE_CALL_OPTS, async (request) => {
  const phone = normalizeEgyptianPhone(request.data?.phoneNumber);
  if (!phone) throw new HttpsError("invalid-argument", "Valid Egyptian phone number is required.");

  // Per-phone request throttling (sliding window).
  const allowed = await slidingWindowAllowed(
    "password_reset_request_throttle",
    createHash("sha256").update(phone).digest("hex"),
    3,
    15 * 60 * 1000,
  );
  if (!allowed) {
    await db.collection("auth_security_events").add({
      event_type: "password_reset_request_rate_limited",
      created_at: FieldValue.serverTimestamp(),
      created_by: "system",
    });
    throw new HttpsError("resource-exhausted", "Too many requests. Try again later.");
  }

  // Anti-enumeration: unknown or ineligible phones receive the SAME uniform
  // success response — no document is created and nothing is disclosed.
  const userSnap = await db.collection("users").where("phone_number", "==", phone).limit(1).get();
  const userDoc = userSnap.empty ? null : userSnap.docs[0];
  const userData = userDoc ? dataOf(userDoc.data()) : null;
  const role = getString(userData?.role);
  const isActive = !userData?.account_status || userData?.account_status === "active";
  const eligible =
    !!userDoc && isActive && (role === "student" || role === "new_student");

  if (userDoc && eligible) {
    // requested_at is the 08 §9.3 schema name; created_at mirrors what the
    // staff-side dashboards already write for the same collection.
    await db.collection("password_reset_requests").add({
      student_id: userDoc.id,
      phone_number: phone,
      status: "pending",
      requested_at: FieldValue.serverTimestamp(),
      created_at: FieldValue.serverTimestamp(),
    });
  }

  return {submitted: true};
});

/**
 * O6-B sanitized question delivery (Option B: results only after final submit).
 *
 * `getAssessmentQuestions` returns display-only question payloads for a
 * caller-owned, still-started attempt. It NEVER returns answer keys
 * (correct_answer/correctAnswer), explanations, scores, or grading
 * metadata — by construction `sanitizeAssessmentQuestion` below does not
 * read those fields. There is intentionally NO per-question evaluation
 * endpoint: correctness is computed only inside `submitAssessmentAttempt`
 * at final submission. Post-submit question review is not offered (the
 * score/total returned at submit is the result surface); explanations are
 * omitted entirely because no Approved assessment policy field authorizes
 * their release.
 */
export type SanitizedAssessmentQuestionType = "mcq" | "true-false" | "essay";

export interface SanitizedAssessmentQuestion {
  id: string;
  type: SanitizedAssessmentQuestionType;
  text: string;
  options: string[];
  marks: number;
  order: number;
}

export function normalizeAssessmentQuestionType(raw: unknown): SanitizedAssessmentQuestionType {
  const t = (typeof raw === "string" ? raw : "").trim().toLowerCase().replace(/[\s_/]+/g, "-");
  if (t === "true-false" || t === "truefalse" || t === "tf" || t === "boolean") return "true-false";
  if (t === "essay" || t === "written" || t === "free-text" || t === "freetext") return "essay";
  return "mcq";
}

export function sanitizeAssessmentQuestion(
  link: {questionId: string; marks: number; order: number},
  bank: DocumentData | null | undefined,
): SanitizedAssessmentQuestion | null {
  if (!bank) return null;
  let text = "";
  for (const candidate of [bank.question_text, bank.text, bank.question]) {
    if (typeof candidate === "string" && candidate.length > 0) {
      text = candidate;
      break;
    }
  }
  const rawOptions = Array.isArray(bank.options) ?
    bank.options :
    (Array.isArray(bank.choices) ? bank.choices : []);
  const options = (rawOptions as unknown[])
    .filter((o): o is string => typeof o === "string")
    .slice(0, 12);
  const marks = typeof link.marks === "number" && link.marks > 0 ? Math.floor(link.marks) : 1;
  const order = typeof link.order === "number" ? link.order : 0;
  return {
    id: link.questionId,
    type: normalizeAssessmentQuestionType(bank.question_type ?? bank.type),
    text,
    options,
    marks,
    order,
  };
}

export const getAssessmentQuestions = onCall(SECURE_CALL_OPTS, async (request) => {
  const userId = requireAuthenticated(request);
  const attemptId = getString(request.data?.attemptId);
  const attemptType = getString(request.data?.attemptType) === "quiz" ? "quiz" : "exam";
  if (!attemptId) throw new HttpsError("invalid-argument", "attemptId is required.");

  const attemptsCollection = attemptType === "quiz" ? "quiz_attempts" : "exam_attempts";
  const assessmentsCollection = attemptType === "quiz" ? "timeline_quizzes" : "exams";
  const linksCollection = attemptType === "quiz" ? "quiz_questions" : "exam_questions";
  const linkKeyField = attemptType === "quiz" ? "quiz_id" : "exam_id";

  const attemptSnap = await db.collection(attemptsCollection).doc(attemptId).get();
  if (!attemptSnap.exists) {
    throw new HttpsError("not-found", `${attemptType} attempt not found.`);
  }
  const attempt = dataOf(attemptSnap.data());
  if (getString(attempt.student_id) !== userId) {
    throw new HttpsError("permission-denied", "Attempt does not belong to the caller.");
  }
  if (getString(attempt.status) !== "started") {
    throw new HttpsError("failed-precondition", "Questions are available only before final submission.");
  }
  const assessmentId = getString(attempt.assessment_id);
  if (!assessmentId) throw new HttpsError("failed-precondition", "Attempt is missing its assessment reference.");

  const assessmentSnap = await db.collection(assessmentsCollection).doc(assessmentId).get();
  if (!assessmentSnap.exists || dataOf(assessmentSnap.data()).is_deleted === true) {
    throw new HttpsError("not-found", `${attemptType} not found.`);
  }
  const assessment = dataOf(assessmentSnap.data());
  const published =
    assessment.is_published === true || getString(assessment.status) === "published";
  if (!published) {
    throw new HttpsError("failed-precondition", `${attemptType} is not published.`);
  }

  // Subject/term entitlement (O6-B): live assignment required; staff bypass
  // covers owner preview/diagnostics. Missing subject reference fails closed.
  const subjectId = getString(assessment.subject_id);
  if (!subjectId) {
    throw new HttpsError("failed-precondition", `${attemptType} is missing its subject reference.`);
  }
  const role = callerRole(request);
  if (!role || !ADMIN_ROLES.has(role)) {
    await requireEnabledSubjectAccess(userId, subjectId);
  }

  // Same server-side time gate as final submission: expired attempts cannot
  // fetch questions. Quizzes carry no duration field → no gate (mirrors submit).
  const startedAt = attempt.started_at;
  const durationMinutes =
    getNumber(assessment.duration_minutes) ?? getNumber(assessment.duration);
  const startedMs =
    startedAt && typeof startedAt.toMillis === "function" ? startedAt.toMillis() : null;
  if (
    durationMinutes !== null &&
    durationMinutes >= 0 &&
    startedMs !== null &&
    Date.now() > startedMs + durationMinutes * 60_000 + EXAM_SUBMIT_TIME_GRACE_MS
  ) {
    throw new HttpsError("deadline-exceeded", "The assessment time limit has elapsed.");
  }

  const linksSnap = await db.collection(linksCollection).where(linkKeyField, "==", assessmentId).get();
  const questions: SanitizedAssessmentQuestion[] = [];
  const links = linksSnap.docs
    .map((doc) => {
      const data = doc.data();
      return {
        questionId: getString((data as Record<string, unknown>).question_id) ?? "",
        marks: getNumber((data as Record<string, unknown>).marks) ?? 1,
        order: getNumber((data as Record<string, unknown>).order) ?? 0,
      };
    })
    .filter((link) => link.questionId.length > 0)
    .sort((a, b) => a.order - b.order);
  for (const link of links) {
    const qSnap = await db.collection("question_bank").doc(link.questionId).get();
    const sanitized = sanitizeAssessmentQuestion(
      link,
      qSnap.exists ? dataOf(qSnap.data()) : null,
    );
    if (sanitized) questions.push(sanitized);
  }

  return {attemptType, questions};
});

export const submitAssessmentAttempt = onCall(SECURE_CALL_OPTS, async (request) => {
  const userId = requireAuthenticated(request);
  const attemptId = getString(request.data?.attemptId);
  const rawAnswers = request.data?.answers;
  const attemptType = getString(request.data?.attemptType) === "quiz" ? "quiz" : "exam";

  if (!attemptId || !rawAnswers || typeof rawAnswers !== "object" || Array.isArray(rawAnswers)) {
    throw new HttpsError("invalid-argument", "attemptId and an answers map are required.");
  }
  const answerEntries = Object.entries(rawAnswers as Record<string, unknown>);
  if (answerEntries.length > MAX_EXAM_ANSWERS) {
    throw new HttpsError("invalid-argument", "Too many answers submitted.");
  }
  const answers: Record<string, string> = {};
  for (const [key, value] of answerEntries) {
    if (typeof key === "string" && key.length > 0 && typeof value === "string" && value.length <= 4096) {
      answers[key] = value;
    }
  }

  const attemptsCollection = attemptType === "quiz" ? "quiz_attempts" : "exam_attempts";
  const assessmentsCollection = attemptType === "quiz" ? "timeline_quizzes" : "exams";
  const linksCollection = attemptType === "quiz" ? "quiz_questions" : "exam_questions";
  const linkKeyField = attemptType === "quiz" ? "quiz_id" : "exam_id";

  const attemptRef = db.collection(attemptsCollection).doc(attemptId);

  const result = await db.runTransaction(async (tx) => {
    const attemptSnap = await tx.get(attemptRef);
    if (!attemptSnap.exists) {
      throw new HttpsError("not-found", `${attemptType} attempt not found.`);
    }
    const attempt = dataOf(attemptSnap.data());
    if (getString(attempt.student_id) !== userId) {
      throw new HttpsError("permission-denied", "Attempt does not belong to the caller.");
    }
    if (getString(attempt.status) !== "started") {
      throw new HttpsError("failed-precondition", "This attempt was already submitted.");
    }
    const assessmentId = getString(attempt.assessment_id);
    if (!assessmentId) throw new HttpsError("failed-precondition", "Attempt is missing its assessment reference.");

    const assessmentSnap = await tx.get(db.collection(assessmentsCollection).doc(assessmentId));
    if (!assessmentSnap.exists || dataOf(assessmentSnap.data()).is_deleted === true) {
      throw new HttpsError("not-found", `${attemptType} not found.`);
    }
    const assessment = dataOf(assessmentSnap.data());
    const published =
      assessment.is_published === true || getString(assessment.status) === "published";
    if (!published) {
      throw new HttpsError("failed-precondition", `${attemptType} is not published.`);
    }

    // O6-B subject/term entitlement: live assignment required; staff bypass
    // covers owner preview/diagnostics. Missing subject reference fails closed.
    // Transactional read (tx.get) so the entitlement decision joins the
    // submission snapshot; repeated submits stay idempotent via the
    // started-status gate above.
    const submitSubjectId = getString(assessment.subject_id);
    const submitRole = callerRole(request);
    if (!submitRole || !ADMIN_ROLES.has(submitRole)) {
      if (!submitSubjectId) {
        throw new HttpsError("failed-precondition", `${attemptType} is missing its subject reference.`);
      }
      const assignSnap = await tx.get(
        db.collection("subject_access_assignments").doc(`${userId}_${submitSubjectId}`),
      );
      if (!assignSnap.exists) {
        throw new HttpsError("permission-denied", "Subject Access assignment is required.");
      }
      assertEnabledSubjectAccess(userId, submitSubjectId, dataOf(assignSnap.data()));
    }

    // Server-side time limit (duration in minutes; 90s network grace).
    // Quizzes have no duration field in the approved schema → no time gate.
    const startedAt = attempt.started_at;
    const durationMinutes =
      getNumber(assessment.duration_minutes) ?? getNumber(assessment.duration);
    const startedMs =
      startedAt && typeof startedAt.toMillis === "function" ? startedAt.toMillis() : null;
    if (
      durationMinutes !== null &&
      durationMinutes >= 0 &&
      startedMs !== null &&
      Date.now() > startedMs + durationMinutes * 60_000 + EXAM_SUBMIT_TIME_GRACE_MS
    ) {
      throw new HttpsError("deadline-exceeded", "The assessment time limit has elapsed.");
    }

    const linksSnap = await tx.get(
      db.collection(linksCollection).where(linkKeyField, "==", assessmentId),
    );
    const links: GradingLink[] = linksSnap.docs
      .map((doc) => {
        const data = doc.data();
        return {
          questionId: getString((data as Record<string, unknown>).question_id) ?? "",
          marks:
            getNumber((data as Record<string, unknown>).marks) ?? 1,
          order: getNumber((data as Record<string, unknown>).order) ?? 0,
        };
      })
      .filter((link) => link.questionId.length > 0)
      .sort((a, b) => a.order - b.order);

    const questionsById = new Map<string, GradingQuestion>();
    for (const link of links) {
      const qSnap = await tx.get(db.collection("question_bank").doc(link.questionId));
      if (!qSnap.exists) continue;
      const q = dataOf(qSnap.data());
      questionsById.set(link.questionId, {
        questionType: q.question_type ?? q.type,
        correctAnswer: q.correct_answer ?? q.correctAnswer,
      });
    }

    // No question linkage (e.g. quizzes before content authoring exists):
    // store answers without inventing a score. Clients cannot forge one —
    // rules deny any client write to these collections entirely.
    if (links.length === 0) {
      tx.update(attemptRef, {
        answers,
        status: "submitted",
        submitted_at: FieldValue.serverTimestamp(),
        score: null,
        percentage: null,
        needs_manual_grading: false,
        graded: false,
        graded_at: FieldValue.serverTimestamp(),
        updated_at: FieldValue.serverTimestamp(),
        updated_by: "system",
      });
      return {score: null as number | null, totalMarks: 0, hasEssay: false};
    }

    const grade = gradeObjectiveAnswers(links, questionsById, answers);
    const percentage =
      grade.totalMarks > 0 ?
        Math.round((grade.score / grade.totalMarks) * 1000) / 10 :
        null;

    tx.update(attemptRef, {
      answers,
      status: "submitted",
      submitted_at: FieldValue.serverTimestamp(),
      score: grade.score,
      percentage,
      needs_manual_grading: grade.hasEssay,
      graded: true,
      graded_at: FieldValue.serverTimestamp(),
      updated_at: FieldValue.serverTimestamp(),
      updated_by: "system",
    });

    return {score: grade.score as number | null, totalMarks: grade.totalMarks, hasEssay: grade.hasEssay};
  });

  await writeAnalyticsEvent(userId, attemptType === "quiz" ? "Quiz Submitted" : "Exam Submitted", attemptId, {
    score: result.score,
    total_marks: result.totalMarks,
    needs_manual_grading: result.hasEssay,
    server_graded: true,
  }, request);

  return {
    submitted: true,
    attemptType,
    score: result.score,
    totalMarks: result.totalMarks,
    percentage:
      result.score !== null && result.totalMarks > 0 ?
        Math.round((result.score / result.totalMarks) * 1000) / 10 :
        null,
    needsManualGrading: result.hasEssay,
  };
});

export const submitExamAttempt = submitAssessmentAttempt;

export const onSectionWritten = contentAuditTrigger("subject_sections");

export const onLectureWritten = contentAuditTrigger("lectures");

export const onLectureResourceWritten = contentAuditTrigger("lecture_resources");

export const onLectureAccessGrantWritten = contentAuditTrigger("lecture_access_grants");

export const autoPublishDueLectures = onSchedule("every 5 minutes", async () => {
  const nowMs = Date.now();
  let publishedCount = 0;

  // Paged scan so a large backlog cannot exceed function memory/time.
  // Cursor-based pagination (startAfter) guarantees forward progress even
  // when a full page holds zero due lectures (missing/future publish_date),
  // which would otherwise re-fetch the same first page forever.
  let lastDoc: any = null;
  for (;;) {
    let pageQuery = db.collection("lectures")
      .where("status", "==", "draft")
      .where("is_deleted", "==", false)
      .orderBy(FieldPath.documentId())
      .limit(200);
    if (lastDoc) pageQuery = pageQuery.startAfter(lastDoc);
    const snap = await pageQuery.get();
    if (snap.empty) break;

    const due = pickDueLectures(
      snap.docs.map((doc) => {
        const data = dataOf(doc.data());
        return {
          id: doc.id,
          status: data.status,
          isDeleted: data.is_deleted,
          publishDateMs: data.publish_date && typeof data.publish_date.toMillis === "function" ? data.publish_date.toMillis() : null,
        };
      }),
      nowMs,
    );

    for (const lectureId of due) {
      await db.collection("lectures").doc(lectureId).update({
        status: "published",
        updated_at: FieldValue.serverTimestamp(),
        updated_by: "system_scheduler",
      });
      await db.collection("analytics_events").add({
        user_id: "system_scheduler",
        event_type: "Lecture Auto Published",
        reference_id: lectureId,
        metadata: {reason: "publish_date_reached"},
        device_id: null,
        ip_address: null,
        user_agent: null,
        created_at: FieldValue.serverTimestamp(),
        created_by: "system_scheduler",
      });
      await db.collection("admin_audit_log").add({
        action: "lecture_auto_published",
        entity: "lectures",
        target_id: lectureId,
        actor_id: "system_scheduler",
        actor_role: "system_scheduler",
        created_at: FieldValue.serverTimestamp(),
        timestamp: FieldValue.serverTimestamp(),
      });
      publishedCount += 1;
    }

    lastDoc = snap.docs[snap.docs.length - 1];
    if (snap.size < 200) break;
  }

  if (publishedCount > 0) {
    console.log(`autoPublishDueLectures: published ${publishedCount} lecture(s).`);
  }
});

export const setDefaultStorageProvider = onCall(SECURE_CALL_OPTS, async (request) => {
  const doctorId = requireDoctor(request);
  const provider = getString(request.data?.provider)?.toLowerCase();

  if (provider !== "bunny" && provider !== "firebase") {
    throw new HttpsError("invalid-argument", "provider must be 'bunny' or 'firebase'.");
  }

  // Canonical settings document is `system_settings/default` (fixed ID).
  // A previous revision read an unordered first document and, when empty,
  // created a random auto-ID document — both behaviors orphan settings
  // when the collection holds more than one document.
  const settingsRef = db.collection("system_settings").doc("default");
  const settingsSnap = await settingsRef.get();

  await db.runTransaction(async (transaction) => {
    transaction.set(settingsRef, {
      default_storage_provider: provider,
      updated_at: FieldValue.serverTimestamp(),
      updated_by: doctorId,
    }, {merge: true});
    transaction.set(db.collection("admin_audit_log").doc(), {
      action: "default_storage_provider_set",
      entity: "system_settings",
      target_id: settingsRef.id,
      previous_provider: !settingsSnap.exists ? null : getString(settingsSnap.data()?.default_storage_provider),
      new_provider: provider,
      actor_id: doctorId,
      actor_role: "doctor",
      created_at: FieldValue.serverTimestamp(),
      timestamp: FieldValue.serverTimestamp(),
    });
  });

  return {success: true, provider};
});

async function verifyPasswordForDeletion(userId: string, password: string): Promise<void> {
  const secretSnap = await db.collection("user_secrets").doc(userId).get();
  const secretData = secretSnap.exists ? dataOf(secretSnap.data()) : {};

  if (secretData.locked_until && secretData.locked_until.toDate() > new Date()) {
    throw new HttpsError("resource-exhausted", "Account locked due to too many failed attempts. Try again later.");
  }

  const passwordHash = getString(secretData.password_hash);
  if (!passwordHash || !(await verifyPassword(password, passwordHash))) {
    const failedAttempts = (typeof secretData.failed_login_attempts === "number" ? secretData.failed_login_attempts : 0) + 1;
    const lockMinutes = calculateLockMinutes(failedAttempts);
    const updateData: Record<string, unknown> = {
      failed_login_attempts: failedAttempts,
      updated_at: FieldValue.serverTimestamp(),
    };
    if (lockMinutes > 0) {
      updateData.locked_until = Timestamp.fromDate(new Date(Date.now() + lockMinutes * 60000));
    }
    await db.collection("user_secrets").doc(userId).set(updateData, {merge: true});

    await writeAnalyticsEvent(userId, "Failed Account Deletion Password", userId, {reason: "invalid_credentials"});
    throw new HttpsError("unauthenticated", "Invalid password.");
  }

  if (secretData.failed_login_attempts > 0 || secretData.locked_until != null) {
    await db.collection("user_secrets").doc(userId).set({
      failed_login_attempts: FieldValue.delete(),
      locked_until: FieldValue.delete(),
      updated_at: FieldValue.serverTimestamp(),
    }, {merge: true});
  }
}

interface DeletionCounts {
  users: number;
  user_secrets: number;
  devices: number;
  notifications: number;
  analytics_events: number;
  security_events: number;
  notes: number;
  bookmarks: number;
  learning_progress: number;
  lecture_progress: number;
  subject_progress_summary: number;
  subscriptions: number;
  subject_access_assignments: number;
  quiz_attempts: number;
  exam_attempts: number;
  password_reset_requests: number;
  student_questions: number;
  student_question_replies: number;
  chat_rooms: number;
  chat_messages: number;
  video_watch_windows: number;
  device_change_requests: number;
  subject_device_authorizations: number;
  playback_sessions: number;
  student_financial_accounts: number;
  student_subject_pricing: number;
  payment_logs_updated: number;
}

// Purge writes are chunked so a large account can never exceed the
// Firestore 500-writes-per-batch limit (commit every 400 ops).
const MAX_PURGE_BATCH_OPS = 400;

async function deleteBatchWithQuery(
  query: FirebaseFirestore.Query<FirebaseFirestore.DocumentData>,
  queueDelete: (ref: FirebaseFirestore.DocumentReference) => Promise<void>,
  counts: DeletionCounts,
  key: keyof DeletionCounts,
): Promise<void> {
  const snapshot = await query.get();
  for (const doc of snapshot.docs) {
    await queueDelete(doc.ref);
    counts[key] += 1;
  }
}

async function purgeUserAccount(
  targetUid: string,
  targetSnapshot: FirebaseFirestore.DocumentSnapshot<FirebaseFirestore.DocumentData>,
  actorUid: string,
  actorRole: "doctor" | "student",
  actionType: "account_deleted_self" | "account_deleted_by_owner"
): Promise<DeletionCounts> {
  const targetData = targetSnapshot.data() as Record<string, unknown> | undefined;
  const targetRole = getString(targetData?.role) ?? "student";
  const targetPhone = getString(targetData?.phone_number) ?? "";
  const targetName = getString(targetData?.full_name) ?? "";

  const auditRef = db.collection("admin_audit_log").doc();
  const now = FieldValue.serverTimestamp();

  await auditRef.set({
    actor_uid: actorUid,
    actor_role: actorRole,
    action: actionType,
    target_uid: targetUid,
    target_role: targetRole,
    target_phone: targetPhone,
    target_name: targetName,
    status: "started",
    created_at: now,
    timestamp: now,
  });

  const counts: DeletionCounts = {
    users: 0,
    user_secrets: 0,
    devices: 0,
    notifications: 0,
    analytics_events: 0,
    security_events: 0,
    notes: 0,
    bookmarks: 0,
    learning_progress: 0,
    lecture_progress: 0,
    subject_progress_summary: 0,
    subscriptions: 0,
    subject_access_assignments: 0,
    quiz_attempts: 0,
    exam_attempts: 0,
    password_reset_requests: 0,
    student_questions: 0,
    student_question_replies: 0,
    chat_rooms: 0,
    chat_messages: 0,
    video_watch_windows: 0,
    device_change_requests: 0,
    subject_device_authorizations: 0,
    playback_sessions: 0,
    student_financial_accounts: 0,
    student_subject_pricing: 0,
    payment_logs_updated: 0,
  };

  try {
    let batch = db.batch();
    let batchOps = 0;
    const flushPurgeBatch = async (force = false): Promise<void> => {
      if (force || batchOps >= MAX_PURGE_BATCH_OPS) {
        if (batchOps > 0) {
          await batch.commit();
          batch = db.batch();
          batchOps = 0;
        }
      }
    };
    const queueDelete = async (ref: FirebaseFirestore.DocumentReference): Promise<void> => {
      batch.delete(ref);
      batchOps += 1;
      await flushPurgeBatch();
    };
    const queueUpdate = async (
      ref: FirebaseFirestore.DocumentReference,
      data: FirebaseFirestore.UpdateData<FirebaseFirestore.DocumentData>,
    ): Promise<void> => {
      batch.update(ref, data);
      batchOps += 1;
      await flushPurgeBatch();
    };

    await queueDelete(db.collection("users").doc(targetUid));
    counts.users = 1;

    await queueDelete(db.collection("user_secrets").doc(targetUid));
    counts.user_secrets = 1;

    await deleteBatchWithQuery(
      db.collection("devices").where("user_id", "==", targetUid),
      queueDelete,
      counts,
      "devices",
    );

    await deleteBatchWithQuery(
      db.collection("notifications").where("user_id", "==", targetUid),
      queueDelete,
      counts,
      "notifications",
    );

    await deleteBatchWithQuery(
      db.collection("analytics_events").where("user_id", "==", targetUid),
      queueDelete,
      counts,
      "analytics_events",
    );

    await deleteBatchWithQuery(
      db.collection("security_events").where("user_id", "==", targetUid),
      queueDelete,
      counts,
      "security_events",
    );

    const studentCollections = ["student", "new_student"];
    if (studentCollections.includes(targetRole)) {
      await deleteBatchWithQuery(
        db.collection("notes").where("student_id", "==", targetUid),
        queueDelete,
        counts,
        "notes",
      );

      await deleteBatchWithQuery(
        db.collection("bookmarks").where("student_id", "==", targetUid),
        queueDelete,
        counts,
        "bookmarks",
      );

      await deleteBatchWithQuery(
        db.collection("learning_progress").where("student_id", "==", targetUid),
        queueDelete,
        counts,
        "learning_progress",
      );

      await deleteBatchWithQuery(
        db.collection("lecture_progress").where("student_id", "==", targetUid),
        queueDelete,
        counts,
        "lecture_progress",
      );

      await deleteBatchWithQuery(
        db.collection("subject_progress_summary").where("student_id", "==", targetUid),
        queueDelete,
        counts,
        "subject_progress_summary",
      );

      await deleteBatchWithQuery(
        db.collection("subscriptions").where("student_id", "==", targetUid),
        queueDelete,
        counts,
        "subscriptions",
      );

      await deleteBatchWithQuery(
        db.collection("subject_access_assignments").where("student_id", "==", targetUid),
        queueDelete,
        counts,
        "subject_access_assignments",
      );

      await deleteBatchWithQuery(
        db.collection("quiz_attempts").where("student_id", "==", targetUid),
        queueDelete,
        counts,
        "quiz_attempts",
      );

      await deleteBatchWithQuery(
        db.collection("exam_attempts").where("student_id", "==", targetUid),
        queueDelete,
        counts,
        "exam_attempts",
      );

      await deleteBatchWithQuery(
        db.collection("password_reset_requests").where("student_id", "==", targetUid),
        queueDelete,
        counts,
        "password_reset_requests",
      );

      const questionsSnap = await db.collection("student_questions").where("student_id", "==", targetUid).get();
      const questionIds = questionsSnap.docs.map((doc) => doc.id);
      for (const qId of questionIds) {
        await queueDelete(db.collection("student_questions").doc(qId));
        counts.student_questions += 1;

        const repliesSnap = await db.collection("student_question_replies").where("question_id", "==", qId).get();
        for (const replyDoc of repliesSnap.docs) {
          await queueDelete(replyDoc.ref);
          counts.student_question_replies += 1;
        }
      }

      const chatRoomsSnap = await db.collection("chat_rooms").where("student_id", "==", targetUid).get();
      const roomIds = chatRoomsSnap.docs.map((doc) => doc.id);
      for (const roomId of roomIds) {
        await queueDelete(db.collection("chat_rooms").doc(roomId));
        counts.chat_rooms += 1;

        const messagesSnap = await db.collection("chat_messages").where("room_id", "==", roomId).get();
        for (const msgDoc of messagesSnap.docs) {
          await queueDelete(msgDoc.ref);
          counts.chat_messages += 1;
        }
      }

      await deleteBatchWithQuery(
        db.collection("subject_device_authorizations").where("student_id", "==", targetUid),
        queueDelete,
        counts,
        "subject_device_authorizations",
      );

      await deleteBatchWithQuery(
        db.collection("playback_sessions").where("student_id", "==", targetUid),
        queueDelete,
        counts,
        "playback_sessions",
      );

      await deleteBatchWithQuery(
        db.collection("student_subject_pricing").where("student_id", "==", targetUid),
        queueDelete,
        counts,
        "student_subject_pricing",
      );

      const financialAccountRef = db.collection("student_financial_accounts").doc(targetUid);
      const financialAccountSnap = await financialAccountRef.get();
      if (financialAccountSnap.exists) {
        await queueDelete(financialAccountRef);
        counts.student_financial_accounts = 1;
      }

      await deleteBatchWithQuery(
        db.collection("video_watch_windows").where("user_id", "==", targetUid),
        queueDelete,
        counts,
        "video_watch_windows",
      );

      await deleteBatchWithQuery(
        db.collection("device_change_requests").where("student_id", "==", targetUid),
        queueDelete,
        counts,
        "device_change_requests",
      );
    }

    const paymentLogsSnap = await db.collection("payment_logs").where("student_id", "==", targetUid).get();
    for (const doc of paymentLogsSnap.docs) {
      await queueUpdate(doc.ref, {student_account_deleted: true, updated_at: FieldValue.serverTimestamp(), updated_by: actorUid});
      counts.payment_logs_updated += 1;
    }

    await flushPurgeBatch(true);

    const storage = getStorage();
    const bucket = storage.bucket();
    const profilePhotosPrefix = `profile_photos/${targetUid}/`;
    const [files] = await bucket.getFiles({prefix: profilePhotosPrefix});
    for (const file of files) {
      try {
        await file.delete();
      } catch {
        // Ignore individual file deletion errors
      }
    }

    try {
      await getAuth().deleteUser(targetUid);
    } catch (authError: unknown) {
      const err = authError as {code?: string};
      if (err.code !== "auth/user-not-found") {
        throw authError;
      }
    }

    await auditRef.update({
      status: "completed",
      deleted_counts: counts,
      completed_at: FieldValue.serverTimestamp(),
      updated_at: FieldValue.serverTimestamp(),
    });

    return counts;
  } catch (error) {
    const err = error as Error;
    await auditRef.update({
      status: "failed",
      failure_stage: err.message,
      error_message: err.message,
      failed_at: FieldValue.serverTimestamp(),
      updated_at: FieldValue.serverTimestamp(),
    });
    throw new HttpsError("internal", "Account deletion failed. Please contact support.");
  }
}

export const deleteMyAccount = onCall({...SECURE_CALL_OPTS, timeoutSeconds: 300}, async (request) => {
  const callerUid = requireAuthenticated(request);

  const userSnap = await db.collection("users").doc(callerUid).get();
  if (!userSnap.exists) {
    throw new HttpsError("not-found", "User not found.");
  }
  const userData = userSnap.data();
  const role = getString(userData?.role);
  if (role !== "student" && role !== "new_student") {
    throw new HttpsError("permission-denied", "Only students can delete their own account using this function.");
  }

  const password = getString(request.data?.password);
  if (!password) {
    throw new HttpsError("invalid-argument", "Password is required for account deletion.");
  }

  await verifyPasswordForDeletion(callerUid, password);

  const counts = await purgeUserAccount(callerUid, userSnap, callerUid, "student", "account_deleted_self");

  return {success: true, deleted: counts};
});

export const deleteAccountByOwner = onCall({...SECURE_CALL_OPTS, timeoutSeconds: 300}, async (request) => {
  // Canonical authorization: trust the server-minted token claim (same as
  // every other doctor-only path), not the Firestore users doc, so claim
  // revocation/refresh semantics apply uniformly here.
  const callerUid = requireDoctor(request);

  const password = getString(request.data?.password);
  if (!password) {
    throw new HttpsError("invalid-argument", "Owner password is required for this operation.");
  }
  await verifyPasswordForDeletion(callerUid, password);

  const targetUid = getString(request.data?.targetUid);
  if (!targetUid) {
    throw new HttpsError("invalid-argument", "targetUid is required.");
  }
  if (targetUid === callerUid) {
    throw new HttpsError("invalid-argument", "Cannot delete your own account using this function. Use deleteMyAccount instead.");
  }

  const targetSnap = await db.collection("users").doc(targetUid).get();
  if (!targetSnap.exists) {
    throw new HttpsError("not-found", "Target user not found.");
  }
  const targetData = targetSnap.data();
  const targetRole = getString(targetData?.role);
  if (targetRole === "doctor") {
    throw new HttpsError("permission-denied", "Owner accounts cannot be deleted via this function.");
  }

  const counts = await purgeUserAccount(targetUid, targetSnap, callerUid, "doctor", "account_deleted_by_owner");

  return {success: true, deleted: counts};
});

