import { SECURE_CALL_OPTS } from "./core/utils/security_helpers";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {
  onDocumentCreated,
  onDocumentUpdated,
} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {
  getFirestore,
  FieldValue,
  Timestamp,
  DocumentData,
} from "firebase-admin/firestore";
import {getAuth} from "firebase-admin/auth";
import {getMessaging, Message} from "firebase-admin/messaging";
import {getStorage} from "firebase-admin/storage";
import {initializeApp} from "firebase-admin/app";
import {
  createHash,
  randomBytes,
  scrypt as scryptCallback,
  timingSafeEqual,
} from "node:crypto";

initializeApp();

const db = getFirestore();
const auth = getAuth();
const messaging = getMessaging();
const storage = getStorage();

export const CENTER_FREE_WINDOW_BLOCKED_MESSAGE =
  'A Center Free 24-hour video window is already active for another video.';

export function decideVideoWatchWindow(
  existingWindow: {active_lecture_id: string; window_expires_at: Timestamp} | null | undefined,
  requestedLectureId: string,
  now: number
): { allowed: boolean; reason: 'no_window' | 'same_video' | 'different_video' | 'expired' } {
  if (!existingWindow || !existingWindow.window_expires_at) {
    return { allowed: true, reason: 'no_window' };
  }
  const expiryMs = existingWindow.window_expires_at.toMillis();
  if (now >= expiryMs) return { allowed: true, reason: 'expired' };
  if (existingWindow.active_lecture_id === requestedLectureId) 
    return { allowed: true, reason: 'same_video' };
  return { allowed: false, reason: 'different_video' };
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
const ADMIN_ROLES = new Set(["admin", "teacher"]);

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

function requireTeacher(request: CallableRequest<unknown>): string {
  const uid = requireAuthenticated(request);
  if (callerRole(request) !== "teacher") {
    throw new HttpsError("permission-denied", "Teacher (Platform Owner) permission is required.");
  }
  return uid;
}

function requireAdminOrTeacher(request: CallableRequest<unknown>): string {
  const uid = requireAuthenticated(request);
  const role = callerRole(request);
  if (!role || !ADMIN_ROLES.has(role)) {
    throw new HttpsError("permission-denied", "Admin or Teacher permission is required.");
  }
  return uid;
}

async function requireStudentAccessManager(request: CallableRequest<unknown>): Promise<{
  actorId: string;
  actorRole: "teacher" | "admin";
  permissionBasis: "teacher" | "delegated:admin_students";
}> {
  const actorId = requireAuthenticated(request);
  const role = callerRole(request);
  if (role === "teacher") {
    return {actorId, actorRole: "teacher", permissionBasis: "teacher"};
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
  actorRole: "teacher" | "admin";
  permissionBasis: "teacher" | "delegated:password_reset";
}> {
  const actorId = requireAuthenticated(request);
  const role = callerRole(request);
  if (role === "teacher") {
    return {actorId, actorRole: "teacher", permissionBasis: "teacher"};
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
    (permissions.password_reset !== true && permissions["password.reset"] !== true)
  ) {
    throw new HttpsError("permission-denied", "Delegated password-reset permission is required.");
  }

  return {actorId, actorRole: "admin", permissionBasis: "delegated:password_reset"};
}

async function requirePaymentManager(request: CallableRequest<unknown>): Promise<{
  actorId: string;
  actorRole: "teacher" | "admin";
  permissionBasis: "teacher" | "delegated:admin_payments";
}> {
  const actorId = requireAuthenticated(request);
  const role = callerRole(request);
  if (role === "teacher") {
    return {actorId, actorRole: "teacher", permissionBasis: "teacher"};
  }
  if (role !== "admin") {
    throw new HttpsError("permission-denied", "Payment management permission is required.");
  }

  const permissionSnap = await db.collection("admin_permissions").doc(actorId).get();
  const permissionData = dataOf(permissionSnap.data());
  const permissions = permissionData.permissions;
  if (
    permissionData.is_active !== true ||
    !permissions ||
    typeof permissions !== "object" ||
    permissions.admin_payments !== true
  ) {
    throw new HttpsError("permission-denied", "Delegated payment-management permission is required.");
  }

  return {actorId, actorRole: "admin", permissionBasis: "delegated:admin_payments"};
}

async function requireEnabledSubjectAccess(studentId: string, subjectId: string): Promise<DocumentData> {
  const assignmentId = `${studentId}_${subjectId}`;
  const assignmentSnap = await db.collection("subject_access_assignments").doc(assignmentId).get();
  if (!assignmentSnap.exists) {
    throw new HttpsError("permission-denied", "Subject Access assignment is required.");
  }

  const assignment = dataOf(assignmentSnap.data());
  if (
    assignment.student_id !== studentId ||
    assignment.subject_id !== subjectId ||
    assignment.is_deleted === true ||
    assignment.enabled !== true
  ) {
    throw new HttpsError("permission-denied", "Subject Access is not enabled for this subject.");
  }
  return assignment;
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
    if (
      data.active_device === false ||
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

function qualityRank(value: string): number {
  const ranks: Record<string, number> = {
    "144p": 144,
    "240p": 240,
    "360p": 360,
    "480p": 480,
    "720p": 720,
    "1080p": 1080,
    "1440p": 1440,
    "4k": 2160,
  };
  return ranks[value.toLowerCase()] ?? 0;
}

async function getUserPlan(userId: string, preferredPlanId?: string) {
  const userSnap = await db.collection("users").doc(userId).get();
  if (!userSnap.exists) throw new HttpsError("not-found", "User not found.");
  const user = dataOf(userSnap.data());
  const studentType = getString(user.student_type);
  if (!studentType) throw new HttpsError("failed-precondition", "Student type is not configured.");

  let planId = preferredPlanId ?? null;
  if (!planId) {
    const activeSubscription = await db
      .collection("subscriptions")
      .where("student_id", "==", userId)
      .where("status", "==", "active")
      .limit(1)
      .get();
    if (!activeSubscription.empty) planId = getString(activeSubscription.docs[0].data().plan_id);
  }

  if (!planId) {
    const settingsSnap = await db.collection("system_settings").limit(1).get();
    const settings = settingsSnap.empty ? {} : dataOf(settingsSnap.docs[0].data());
    const defaultPlan = getString(settings.default_plan);
    if (defaultPlan) {
      const planSnap = await db
        .collection("plans")
        .where("plan_key", "==", defaultPlan)
        .where("student_type", "==", studentType)
        .where("is_active", "==", true)
        .limit(1)
        .get();
      if (!planSnap.empty) planId = planSnap.docs[0].id;
    }
  }

  if (!planId) throw new HttpsError("failed-precondition", "No active membership plan is available.");

  const planSnap = await db.collection("plans").doc(planId).get();
  if (!planSnap.exists) throw new HttpsError("failed-precondition", "Membership plan was not found.");
  const plan = dataOf(planSnap.data());
  if (plan.is_active !== true || plan.student_type !== studentType) {
    throw new HttpsError("permission-denied", "Membership plan is not valid for this student.");
  }

  return {user, studentType, planId, plan};
}

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
  await notifyUsersByRole("teacher", type, title, body, options);

  const permissionsSnap = await db.collection("admin_permissions")
    .where("is_active", "==", true)
    .get();

  for (const permDoc of permissionsSnap.docs) {
    const data = permDoc.data();
    const permissions = data.permissions;
    if (
      permissions &&
      (permissions[permissionKey] === true ||
        (permissionKey === "password_reset" && permissions["password.reset"] === true))
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
  if (subscription.manually_disabled === true) throw new HttpsError("permission-denied", "Subscription is disciplinarily disabled by the Teacher.");
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
      "No active core academic period. The Teacher must start a period from the dashboard first.",
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
 * Teacher ends the period (setAcademicPeriodStatus).
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
    throw new HttpsError("permission-denied", "Current password is incorrect.");
  }

  const newHash = await hashPassword(newPassword);
  await auth.updateUser(userId, {password: newPassword});
  const currentUser = await auth.getUser(userId);
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
  return {success: true};
});

export const createCustomGroup = onCall(SECURE_CALL_OPTS, async (request) => {
  const teacherId = requireTeacher(request);
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
    created_by: teacherId,
    updated_by: teacherId,
  });

  await db.collection("admin_audit_log").add({
    action: "custom_group_created",
    entity: "custom_groups",
    target_id: groupRef.id,
    group_name: name,
    actor_id: teacherId,
    actor_role: "teacher",
    created_at: now,
    timestamp: now,
  });

  return {groupId: groupRef.id, name};
});

export const updateCustomGroup = onCall(SECURE_CALL_OPTS, async (request) => {
  const teacherId = requireTeacher(request);
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
    updated_by: teacherId,
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
    actor_id: teacherId,
    actor_role: "teacher",
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

  const userSnap = await db.collection("users").where("phone_number", "==", phone).limit(1).get();
  if (userSnap.empty) {
    await db.collection("auth_security_events").add({
      event_type: "failed_login",
      phone_number: phone,
      created_at: FieldValue.serverTimestamp(),
      created_by: "system",
    });
    throw new HttpsError("unauthenticated", "Invalid phone number or password.");
  }

  const userDoc = userSnap.docs[0];
  const user = dataOf(userDoc.data());

  if (user.account_status && user.account_status !== "active") {
    throw new HttpsError("permission-denied", "Account is not active.");
  }

  if (user.approval_status !== "approved") {
    throw new HttpsError("permission-denied", "Account approval is required before login.");
  }

  const secretSnap = await db.collection("user_secrets").doc(userDoc.id).get();
  const secretData = secretSnap.exists ? dataOf(secretSnap.data()) : {};

  if (secretData.locked_until && secretData.locked_until.toDate() > new Date()) {
    throw new HttpsError("resource-exhausted", "Account locked due to too many failed attempts. Try again later.");
  }

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
    throw new HttpsError("unauthenticated", "Invalid phone number or password.");
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

  let planId: string | null = null;
  let maxDevices: number | null = null;
  let subscriptionStatus: string | null = null;

  if (role === "student" && studentType) {
    const plan = await getUserPlan(userDoc.id);
    planId = plan.planId;
    const feature = await getPlanFeature(planId, "device.max_count");
    maxDevices = getNumber(feature?.feature_value);
    if (maxDevices === null) {
      throw new HttpsError("failed-precondition", "device.max_count is not configured for the active plan.");
    }

    const activeSubscription = await db
      .collection("subscriptions")
      .where("student_id", "==", userDoc.id)
      .where("status", "==", "active")
      .limit(1)
      .get();
    subscriptionStatus = activeSubscription.empty ? "active" : getString(activeSubscription.docs[0].data().status);
  }

  const token = await auth.createCustomToken(userDoc.id, {
    role,
    ...(studentType ? {student_type: studentType} : {}),
    ...(planId ? {plan_id: planId} : {}),
    ...(maxDevices !== null ? {max_devices: maxDevices} : {}),
    ...(subscriptionStatus ? {subscription_status: subscriptionStatus} : {}),
    approved: user.approval_status === "approved",
    force_password_change: user.force_password_change === true,
  });

  await writeAnalyticsEvent(userDoc.id, "Login", userDoc.id, {method: "phone_password"}, request);
  return {token, userId: userDoc.id};
});

export const onLoginAttempt = onCall(SECURE_CALL_OPTS, async (request) => {
  const userId = getString(request.data?.userId);
  const deviceId = getString(request.data?.deviceId);
  const deviceName = getString(request.data?.deviceName);
  const platform = getString(request.data?.platform) ?? "unknown";
  const osVersion = getString(request.data?.osVersion);
  const appVersion = getString(request.data?.appVersion);

  if (!userId || !deviceId) throw new HttpsError("invalid-argument", "userId and deviceId are required.");
  if (!request.auth || request.auth.uid !== userId) throw new HttpsError("permission-denied", "User identity mismatch.");

  const userRef = db.collection("users").doc(userId);
  const userSnap = await userRef.get();
  if (!userSnap.exists) throw new HttpsError("not-found", "User not found.");

  const role = getString(request.auth.token.role);
  if (role !== "student") throw new HttpsError("permission-denied", "Only approved students may bind devices.");

  const claimMaxDevices = getNumber(request.auth.token.max_devices);
  const maxDevices = claimMaxDevices ?? 0;
  if (maxDevices < 1) throw new HttpsError("failed-precondition", "max_devices claim is missing or invalid.");

  type BindingOutcome = { kind: "existing" | "created"; deviceDocId: string };
  const outcome = await db.runTransaction(async (tx): Promise<BindingOutcome> => {
    const devicesRef = db.collection("devices");
    const existingSnap = await tx.get(
      devicesRef.where("user_id", "==", userId).where("device_id", "==", deviceId).limit(1),
    );
    if (!existingSnap.empty) {
      const existing = existingSnap.docs[0];
      const activeSnap = await tx.get(
        devicesRef.where("user_id", "==", userId).where("active_device", "==", true),
      );
      const otherActiveDevices = activeSnap.docs.filter(d => d.id !== existing.id);
      if (otherActiveDevices.length >= maxDevices) {
        const devicesToDeactivate = otherActiveDevices.sort((a, b) => {
            const timeA = (a.data().last_login?.toMillis && a.data().last_login.toMillis()) || 0;
            const timeB = (b.data().last_login?.toMillis && b.data().last_login.toMillis()) || 0;
            return timeA - timeB;
        });
        const excessCount = otherActiveDevices.length - maxDevices + 1;
        for (let i = 0; i < excessCount && i < devicesToDeactivate.length; i++) {
            tx.update(devicesToDeactivate[i].ref, {
                active_device: false,
                updated_at: FieldValue.serverTimestamp(),
                updated_by: "system",
            });
        }
      }
      tx.update(existing.ref, {
        device_name: deviceName, platform, os_version: osVersion, app_version: appVersion,
        last_login: FieldValue.serverTimestamp(), active_device: true,
        updated_at: FieldValue.serverTimestamp(), updated_by: "system",
      });
      tx.update(userRef, {current_device_id: existing.id, updated_at: FieldValue.serverTimestamp(), updated_by: "system"});
      return {kind: "existing", deviceDocId: existing.id};
    }
    const activeSnap = await tx.get(
      devicesRef.where("user_id", "==", userId).where("active_device", "==", true),
    );
    const otherActiveDevices = activeSnap.docs;
    if (otherActiveDevices.length >= maxDevices) {
      const devicesToDeactivate = otherActiveDevices.sort((a, b) => {
          const timeA = (a.data().last_login?.toMillis && a.data().last_login.toMillis()) || 0;
          const timeB = (b.data().last_login?.toMillis && b.data().last_login.toMillis()) || 0;
          return timeA - timeB;
      });
      const excessCount = otherActiveDevices.length - maxDevices + 1;
      for (let i = 0; i < excessCount && i < devicesToDeactivate.length; i++) {
          tx.update(devicesToDeactivate[i].ref, {
              active_device: false, updated_at: FieldValue.serverTimestamp(), updated_by: "system",
          });
      }
    }
    const newDevice = devicesRef.doc();
    tx.set(newDevice, {
      user_id: userId, device_id: deviceId, device_name: deviceName, platform, os_version: osVersion,
      app_version: appVersion, last_login: FieldValue.serverTimestamp(), active_device: true, fcm_token: null,
      created_at: FieldValue.serverTimestamp(), updated_at: FieldValue.serverTimestamp(),
      created_by: "system", updated_by: "system", is_deleted: false, deleted_at: null, deleted_by: null,
    });
    tx.update(userRef, {current_device_id: newDevice.id, updated_at: FieldValue.serverTimestamp(), updated_by: "system"});
    return {kind: "created", deviceDocId: newDevice.id};
  });

  return {
    allowed: true, 
    status: outcome.kind === "existing" ? "existing_device" : "new_device", 
    maxDevices, 
    deviceDocumentId: outcome.deviceDocId
  };
});

export const approveStudent = onCall(SECURE_CALL_OPTS, async (request) => {
  const authorization = await requireStudentAccessManager(request);
  const studentId = getString(request.data?.studentId);
  const studentType = getString(request.data?.studentType);
  const rawAssignments = request.data?.subjectAccess;
  if (
    !studentId ||
    (studentType !== "public_student" && studentType !== "center_student") ||
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

export const convertStudentType = onCall(SECURE_CALL_OPTS, async (request) => {
  const authorization = await requireStudentAccessManager(request);
  const studentId = getString(request.data?.studentId);
  const targetStudentType = getString(request.data?.targetStudentType);
  if (
    !studentId ||
    (targetStudentType !== "public_student" && targetStudentType !== "center_student")
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

export const onStudentApproved = onDocumentUpdated("users/{userId}", async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (!before || !after) return;
  if (before.approval_status === "approved" || after.approval_status !== "approved") return;

  const userId = event.params.userId;
  const studentType = getString(after.student_type);
  if (studentType !== "public_student" && studentType !== "center_student") {
    throw new Error(`Invalid student_type for approved student: ${userId}`);
  }

  const settingsSnap = await db.collection("system_settings").limit(1).get();
  if (settingsSnap.empty) throw new Error("system_settings configuration was not found.");
  const settings = dataOf(settingsSnap.docs[0].data());
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
    lectureIds.push(...lecturesSnap.docs.map((doc: any) => doc.id));
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
        .filter((doc: any) => doc.data().is_completed === true)
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
  if (!before || !after || before.is_completed === after.is_completed) return;

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

  if (userId !== requesterId && callerRole(request) !== "teacher" && callerRole(request) !== "admin") {
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
  const actorId = requireAdminOrTeacher(request);
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

export const generateBunnySignedUrl = onCall(SECURE_CALL_OPTS, async (request) => {
  const userId = requireAuthenticated(request);
  const videoId = getString(request.data?.videoId);
  const requestedQuality = getString(request.data?.quality);
  const subjectId = getString(request.data?.subjectId);
  const deviceId = getString(request.data?.deviceId);

  if (!videoId) throw new HttpsError("invalid-argument", "videoId is required.");
  if (!deviceId) throw new HttpsError("invalid-argument", "deviceId is required.");
  await assertVideoRequestAllowed(userId, deviceId);

  const plan = await getUserPlan(userId);

  const resourceSnap = await db.collection("lecture_resources")
    .where("bunny_video_id", "==", videoId)
    .limit(1)
    .get();
  if (resourceSnap.empty) throw new HttpsError("not-found", "Video resource not found.");

  const resource = resourceSnap.docs[0].data();
  const lectureId = getString(resource.lecture_id);
  if (!lectureId) throw new HttpsError("failed-precondition", "Video resource is not linked to a lecture.");

  const lectureSnap = await db.collection("lectures").doc(lectureId).get();
  if (!lectureSnap.exists) throw new HttpsError("not-found", "Lecture not found.");
  const lecture = dataOf(lectureSnap.data());
  const linkedSubjectId = subjectId ?? getString(lecture.subject_id);

  let resolvedSubjectId = linkedSubjectId;
  if (!resolvedSubjectId) {
    const sectionId = getString(lecture.section_id);
    if (!sectionId) throw new HttpsError("failed-precondition", "Lecture section is missing.");
    const sectionSnap = await db.collection("subject_sections").doc(sectionId).get();
    resolvedSubjectId = getString(sectionSnap.data()?.subject_id);
  }
  if (!resolvedSubjectId) throw new HttpsError("failed-precondition", "Subject cannot be resolved.");
  await requireEnabledSubjectAccess(userId, resolvedSubjectId);

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
    subjectPlan.student_type !== plan.studentType
  ) {
    throw new HttpsError("permission-denied", "Subject subscription plan is not valid for this student.");
  }

  const accessFeature = await getPlanFeature(subjectPlanId, "video.access");
  if (accessFeature?.enabled !== true) {
    throw new HttpsError("permission-denied", "Video access is not enabled for this plan.");
  }

  const qualityFeatures = (await getPlanFeatures(subjectPlanId))
    .filter((feature) =>
      typeof feature.feature_key === "string" &&
      feature.feature_key.startsWith("video.quality.") &&
      feature.enabled === true,
    );
  const allowedQualities = new Set(
    qualityFeatures
      .map((feature) => getString(feature.feature_key)?.replace("video.quality.", ""))
      .filter((quality): quality is string => Boolean(quality)),
  );
  if (allowedQualities.size === 0) {
    throw new HttpsError("failed-precondition", "No video quality is configured for this plan.");
  }
  if (requestedQuality && !allowedQualities.has(requestedQuality)) {
    throw new HttpsError("permission-denied", "Requested video quality is not enabled for this plan.");
  }
  const selectedQuality = requestedQuality ??
    [...allowedQualities].sort((left, right) => qualityRank(right) - qualityRank(left))[0];

  const template = getEnv("BUNNY_PLAYBACK_URL_TEMPLATE");
  const secret = getEnv("BUNNY_TOKEN_KEY");
  const expires = Math.floor(Date.now() / 1000) + 300;
  const rawUrl = template.replace("{video_id}", encodeURIComponent(videoId)).replace("{quality}", encodeURIComponent(selectedQuality));
  const url = new URL(rawUrl);
  const token = hashPathToken(secret, url.pathname, expires);
  url.searchParams.set("token", token);
  url.searchParams.set("expires", String(expires));

  await writeAnalyticsEvent(userId, "Open Video", videoId, {subject_id: resolvedSubjectId, quality: selectedQuality});
  return {url: url.toString(), expiresAt: expires, quality: selectedQuality};
});

export const getVideoWatchWindow = onCall(SECURE_CALL_OPTS, async (request) => {
  const userId = requireAuthenticated(request);
  const windowSnap = await db.collection("video_watch_windows").doc(userId).get();
  if (!windowSnap.exists) return { active: false };
  const window = windowSnap.data() as any;
  if (!window.window_expires_at) return { active: false };
  
  const now = Date.now();
  const expiresAtMs = window.window_expires_at.toMillis();
  if (now >= expiresAtMs) return { active: false };
  
  return {
    active: true,
    activeLectureId: window.active_lecture_id,
    windowExpiresAtMs: expiresAtMs
  };
});

export const revalidateOfflineAccess = onCall(SECURE_CALL_OPTS, async (request) => {
  const userId = requireAuthenticated(request);
  const subjectIds = Array.isArray(request.data?.subjectIds) ? request.data.subjectIds.filter((id: unknown): id is string => typeof id === "string" && id.length > 0) : [];
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
 * Shared helper: resolves document resource → subject → subscription → plan,
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

  return {planId, subjectId, lectureId, storagePath, resourceTitle: getString(resource.title), resourceType: type};
}

/**
 * Generate a short-lived signed URL for **viewing** a document in-app.
 * Requires corresponding plan feature.
 */
export const generateProtectedPdfUrl = onCall(SECURE_CALL_OPTS, async (request) => {
  const userId = requireAuthenticated(request);
  const resourceId = getString(request.data?.resourceId);
  if (!resourceId) throw new HttpsError("invalid-argument", "resourceId is required.");

  const ctx = await resolveDocumentAccess(userId, resourceId);
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
  if (!resourceId) throw new HttpsError("invalid-argument", "resourceId is required.");

  const ctx = await resolveDocumentAccess(userId, resourceId);
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

export const getLectureResources = onCall(SECURE_CALL_OPTS, async (request) => {
  const userId = requireAuthenticated(request);
  const lectureId = getString(request.data?.lectureId);
  if (!lectureId) throw new HttpsError("invalid-argument", "lectureId is required.");

  const lectureSnap = await db.collection("lectures").doc(lectureId).get();
  if (!lectureSnap.exists) throw new HttpsError("not-found", "Lecture not found.");
  const lecture = dataOf(lectureSnap.data());
  const subjectId = getString(lecture.subject_id);
  if (!subjectId) throw new HttpsError("failed-precondition", "Lecture subject is missing.");
  await requireEnabledSubjectAccess(userId, subjectId);

  const subscriptionSnap = await db.collection("subscriptions")
    .where("student_id", "==", userId)
    .where("subject_id", "==", subjectId)
    .where("status", "==", "active")
    .limit(1)
    .get();
  if (subscriptionSnap.empty) throw new HttpsError("permission-denied", "Active subject subscription is required.");
  assertSubjectAccess(subscriptionSnap.docs[0].data());

  const resourcesSnap = await db.collection("lecture_resources")
    .where("lecture_id", "==", lectureId)
    .where("is_visible", "==", true)
    .orderBy("display_order")
    .get();

  return {
    resources: resourcesSnap.docs.map((doc) => {
      const resource = dataOf(doc.data());
      return {
        id: doc.id,
        resourceType: getString(resource.resource_type) ?? "attachment",
        title: getString(resource.title) ?? getString(resource.resource_title) ?? "Ù…ÙˆØ±Ø¯ ØªØ¹Ù„ÙŠÙ…ÙŠ",
        bunnyVideoId: getString(resource.bunny_video_id),
        storagePath: getString(resource.storage_path),
        thumbnail: getString(resource.thumbnail),
        duration: resource.duration,
        displayOrder: typeof resource.display_order === "number" ? resource.display_order : 0,
      };
    }),
  };
});

export const onDeviceChangeRequest = onCall(SECURE_CALL_OPTS, async (request) => {
  const approverId = requireAdminOrTeacher(request);
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

  if (oldDeviceId) {
    const oldDeviceSnap = await db.collection("devices").doc(oldDeviceId).get();
    if (oldDeviceSnap.exists) {
      await oldDeviceSnap.ref.update({active_device: false, updated_at: FieldValue.serverTimestamp(), updated_by: approverId});
    }
  }

  await requestRef.update({status: "approved", resolved_by: approverId, resolved_at: FieldValue.serverTimestamp(), updated_at: FieldValue.serverTimestamp()});
  await db.collection("users").doc(studentId).update({current_device_id: null, updated_at: FieldValue.serverTimestamp(), updated_by: approverId});
  await createNotification(studentId, "system", "Device Change Approved", "Your new device has been approved. Please sign in again from the new device.", {priority: "critical"});
  await writeAnalyticsEvent(studentId, "Device Replaced", requestId, {old_device_id: oldDeviceId, new_device_id: newDeviceId, resolved_by: approverId});

  return {approved: true};
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
  if (newPassword.length < 6) throw new HttpsError("invalid-argument", "Password must contain at least 6 characters.");

  const requestRef = db.collection("password_reset_requests").doc(requestId);
  const requestSnap = await requestRef.get();
  if (!requestSnap.exists) throw new HttpsError("not-found", "Password reset request not found.");
  const resetRequest = dataOf(requestSnap.data());
  if (resetRequest.status !== "pending") throw new HttpsError("failed-precondition", "Password reset request is not pending.");

  const studentId = getString(resetRequest.student_id);
  if (!studentId) throw new HttpsError("failed-precondition", "Student ID is missing.");

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
    await notifyUsersByRole("teacher", "system", "Security Alert", `A security event was detected: ${eventType}`, {priority: "critical", deep_link: `/admin/security-events/${securityRef.id}`});
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

  const settingsSnap = await db.collection("system_settings").limit(1).get();
  if (settingsSnap.empty) throw new HttpsError("failed-precondition", "System settings configuration was not found.");
  const settings = dataOf(settingsSnap.docs[0].data());
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

  const existingSnap = await db.collection("subscriptions")
    .where("student_id", "==", studentId)
    .where("subject_id", "==", subjectId)
    .where("status", "==", "active")
    .limit(1)
    .get();
  if (!existingSnap.empty) return {subscriptionId: existingSnap.docs[0].id, alreadyActive: true};

  const binding = await resolveSubscriptionPeriodBinding();
  const subscriptionRef = db.collection("subscriptions").doc();
  await subscriptionRef.set({
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

  await writeAnalyticsEvent(studentId, "Free Plan Activated", subscriptionRef.id, {subject_id: subjectId, plan_id: planSnap.docs[0].id, activated_by: authorization.actorId});

  const entitlements = await getActiveEntitlements(planSnap.docs[0].id);
  await db.collection("subject_access_assignments").doc(`${studentId}_${subjectId}`).update({
    entitlements,
    subscription_expires_at: binding.endDate,
  });

  return {subscriptionId: subscriptionRef.id, alreadyActive: false};
});

export const onPaymentLogged = onCall(SECURE_CALL_OPTS, async (request) => {
  const authorization = await requirePaymentManager(request);
  const studentId = getString(request.data?.studentId);
  const subjectId = getString(request.data?.subjectId);
  const amount = getNumber(request.data?.amount);
  const receiptNumber = getString(request.data?.receiptNumber);
  const notes = getString(request.data?.notes);

  if (!studentId || !subjectId || amount === null || amount < 0 || !receiptNumber) {
    throw new HttpsError("invalid-argument", "studentId, subjectId, amount and receiptNumber are required.");
  }

  const now = FieldValue.serverTimestamp();
  const paymentRef = await db.collection("payment_logs").add({
    student_id: studentId,
    subject_id: subjectId,
    amount,
    payment_date: now,
    collected_by: authorization.actorId,
    receipt_number: receiptNumber,
    notes: notes ?? null,
    created_at: now,
    updated_at: now,
    created_by: authorization.actorId,
    updated_by: authorization.actorId,
    is_deleted: false,
    deleted_at: null,
    deleted_by: null,
  });

  await db.collection("admin_audit_log").add({
    action: "payment_logged",
    entity: "payment_logs",
    target_id: paymentRef.id,
    student_id: studentId,
    subject_id: subjectId,
    amount,
    receipt_number: receiptNumber,
    actor_id: authorization.actorId,
    actor_role: authorization.actorRole,
    permission_basis: authorization.permissionBasis,
    created_at: now,
    timestamp: now,
  });

  await createNotification(studentId, "payment", "Payment Confirmed", "Your payment has been confirmed.", {priority: "critical", subject_id: subjectId});
  await writeAnalyticsEvent(studentId, "Payment Logged", paymentRef.id, {subject_id: subjectId, amount, receipt_number: receiptNumber, collected_by: authorization.actorId});

  return {logged: true, paymentId: paymentRef.id};
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

export const cleanupInvalidDeviceTokens = onSchedule("every 24 hours", async () => {
  const devicesSnap = await db.collection("devices").where("active_device", "==", false).limit(200).get();
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
  await membership.ref.update({
    academic_period_id: binding.academicPeriodId,
    end_date: binding.endDate,
    status: "active",
    renewal_count: (typeof membership.data.renewal_count === "number" ? membership.data.renewal_count : 0) + 1,
    updated_at: FieldValue.serverTimestamp(),
    updated_by: authorization.actorId,
  });
  await writeAnalyticsEvent(studentId, "Membership Renewed", membership.ref.id, {subject_id: subjectId, renewed_by: authorization.actorId});
  return {subscriptionId: membership.ref.id};
});

export const setSubscriptionDisciplinaryStatus = onCall(SECURE_CALL_OPTS, async (request) => {
  const teacherId = requireTeacher(request);
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
      disabled_by: disabled ? teacherId : null,
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
      actor_id: teacherId,
      created_at: FieldValue.serverTimestamp(),
    });
  });

  return {success: true};
});

/* ============================================================
 * ACADEMIC PERIODS
 * Teacher (Platform Owner) ONLY - no delegated admin permission.
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
  const teacherId = requireTeacher(request);

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
        created_by: teacherId,
        created_at: FieldValue.serverTimestamp(),
        updated_at: FieldValue.serverTimestamp(),
        updated_by: teacherId,
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
        patch.updated_by = teacherId;
        batch.set(ref, patch, {merge: true});
      }
    }
  }

  await batch.commit();

  await db.collection("admin_audit_log").add({
    action: "academic_periods_initialized",
    actor_id: teacherId,
    actor_role: "teacher",
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
  requireTeacher(request);

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
  const teacherId = requireTeacher(request);

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
    created_by: teacherId,
    created_at: FieldValue.serverTimestamp(),
    updated_at: FieldValue.serverTimestamp(),
    updated_by: teacherId,
    is_deleted: false,
  });

  await db.collection("admin_audit_log").add({
    action: "academic_period_created",
    actor_id: teacherId,
    actor_role: "teacher",
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
  const teacherId = requireTeacher(request);

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
      updated_by: teacherId,
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
      actor_id: teacherId,
      actor_role: "teacher",
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
        updated_by: teacherId,
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
 * Same permission pattern as setSubjectAccess: Teacher always,
 * delegated admin only with the matching admin_permissions key.
 * ============================================================ */

async function requireContentManager(request: CallableRequest<unknown>): Promise<{
  actorId: string;
  actorRole: "teacher" | "admin";
  permissionBasis: "teacher" | "delegated:admin_content";
}> {
  const actorId = requireAuthenticated(request);
  const role = callerRole(request);
  if (role === "teacher") {
    return {actorId, actorRole: "teacher", permissionBasis: "teacher"};
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
 * Teacher (Platform Owner) ONLY - no delegated permission.
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
  "password.reset",
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
  const teacherId = requireTeacher(request);
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
    if (user.role === "teacher") {
      throw new HttpsError("failed-precondition", "The Teacher role cannot be reassigned.");
    }

    transaction.update(userRef, {
      role: "admin",
      approval_status: "approved",
      updated_at: FieldValue.serverTimestamp(),
      updated_by: teacherId,
    });
    transaction.set(permissionRef, {
      admin_id: userId,
      is_active: true,
      permissions,
      created_at: FieldValue.serverTimestamp(),
      created_by: teacherId,
      updated_at: FieldValue.serverTimestamp(),
      updated_by: teacherId,
    }, {merge: true});
    transaction.set(db.collection("admin_audit_log").doc(), {
      action: "admin_added",
      entity: "admin_permissions",
      target_id: userId,
      permissions,
      actor_id: teacherId,
      actor_role: "teacher",
      created_at: FieldValue.serverTimestamp(),
      timestamp: FieldValue.serverTimestamp(),
    });
  });

  await auth.setCustomUserClaims(userId, {role: "admin", approved: true});
  return {success: true, userId};
});

export const removeAdmin = onCall(SECURE_CALL_OPTS, async (request) => {
  const teacherId = requireTeacher(request);
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
      updated_by: teacherId,
    });
    transaction.set(permissionRef, {
      is_active: false,
      permissions: sanitizeAdminPermissions(null),
      updated_at: FieldValue.serverTimestamp(),
      updated_by: teacherId,
    }, {merge: true});
    transaction.set(db.collection("admin_audit_log").doc(), {
      action: "admin_removed",
      entity: "admin_permissions",
      target_id: userId,
      actor_id: teacherId,
      actor_role: "teacher",
      created_at: FieldValue.serverTimestamp(),
      timestamp: FieldValue.serverTimestamp(),
    });
  });

  await auth.setCustomUserClaims(userId, {role: "student", approved: false});
  return {success: true, userId};
});

export const setAdminPermissions = onCall(SECURE_CALL_OPTS, async (request) => {
  const teacherId = requireTeacher(request);
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
      updated_by: teacherId,
    }, {merge: true});
    transaction.set(db.collection("admin_audit_log").doc(), {
      action: "admin_permissions_updated",
      entity: "admin_permissions",
      target_id: userId,
      permissions,
      actor_id: teacherId,
      actor_role: "teacher",
      created_at: FieldValue.serverTimestamp(),
      timestamp: FieldValue.serverTimestamp(),
    });
  });

  return {success: true, userId};
});

/* ============================================================
 * PLATFORM FEATURE MATRIX (Dashboard)
 * Platform-wide feature toggles, independent from plan features.
 * Teacher (Platform Owner) ONLY.
 * ============================================================ */

export const setPlatformFeature = onCall(SECURE_CALL_OPTS, async (request) => {
  const teacherId = requireTeacher(request);
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
      updated_by: teacherId,
      ...(previous ? {} : {
        created_at: FieldValue.serverTimestamp(),
        created_by: teacherId,
      }),
    }, {merge: true});
    transaction.set(db.collection("admin_audit_log").doc(), {
      action: "platform_feature_toggled",
      entity: "platform_feature",
      target_id: featureKey,
      previous_enabled: previous?.enabled ?? null,
      new_enabled: enabled,
      actor_id: teacherId,
      actor_role: "teacher",
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
  while (true) {
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

  const result: any = { score, totalMarks, hasEssay };
  if (missingQuestions > 0) {
    result.missingQuestions = missingQuestions;
  }
  return result;
}

// Phase 2 Storage Delivery Security
export function isDocumentResourceType(type: any): boolean {
  return type === "pdf" || type === "attachment";
}

export function documentFeatureKeys(type: string) {
  return {
    view: `${type}.access`,
    download: `${type}.download`
  };
}

export function isDirectThumbnailUrl(url: any): boolean {
  if (typeof url !== "string") return false;
  const lower = url.toLowerCase();
  return lower.startsWith("http://") || lower.startsWith("https://");
}

