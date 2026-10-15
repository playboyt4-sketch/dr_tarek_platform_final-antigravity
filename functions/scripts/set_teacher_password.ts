/**
 * QUARANTINE NOTICE (post ADR-005 Doctor migration) — documentation only,
 * no behavior change.
 *
 * This script writes the LEGACY role "teacher" to users/{uid} (merge) plus a
 * password hash to user_secrets/{uid}. Production authorization (Firestore /
 * Storage Rules, Cloud Functions ADMIN_ROLES / requireDoctor, mobile +
 * dashboard gates) accepts only "doctor" / "admin" / "student" /
 * "new_student": a "teacher" account is inert (denied everywhere), so
 * running this script post-migration REGRESSES the owner account instead of
 * repairing it. DO NOT RUN without explicit Project Owner approval. Changing
 * the role string, the pinned UID/phone, or deleting this file all require
 * an owner decision — do not do them silently.
 */
import { randomBytes, scrypt as scryptCallback } from "node:crypto";
import { initializeApp, getApps } from "firebase-admin/app";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { getAuth } from "firebase-admin/auth";

if (getApps().length === 0) {
  initializeApp({
    projectId:
      process.env.GCLOUD_PROJECT ??
      process.env.GOOGLE_CLOUD_PROJECT ??
      "dr-tarek-platform",
  });
}

const db = getFirestore();
const auth = getAuth();

const TEACHER_UID = "2B1pvLZ0p5W3hwoXlBi1rUtp0Iy2";
const TEACHER_PHONE = "01115800180";

function deriveScryptKey(
  password: string,
  salt: Buffer,
  keyLength: number,
  options: { N: number; r: number; p: number },
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
  const derived = await deriveScryptKey(password, salt, 64, { N: cost, r: 8, p: 1 });
  return `scrypt$${salt.toString("hex")}$${derived.toString("hex")}$${cost}`;
}

export async function setTeacherPassword(newPassword?: string): Promise<void> {
  const password = newPassword ?? process.argv[2] ?? "12345678";

  if (!password || password.length < 6) {
    throw new Error("Password must be at least 6 characters (Firebase Auth requirement).");
  }

  console.log(`=== Setting teacher password (phone: ${TEACHER_PHONE}, uid: ${TEACHER_UID}) ===`);

  // Verify the user exists (by uid, then by phone as a safety check).
  const userRef = db.collection("users").doc(TEACHER_UID);
  const userSnap = await userRef.get();
  if (!userSnap.exists) {
    throw new Error(`users/${TEACHER_UID} not found. Aborting.`);
  }
  const userData = userSnap.data() ?? {};
  if (userData.phone_number && userData.phone_number !== TEACHER_PHONE) {
    console.warn(
      `[WARN] Phone mismatch: doc has phone_number=${userData.phone_number}, expected ${TEACHER_PHONE}. Continuing with uid.`,
    );
  }

  // 1. Hash with the same server-side scrypt algorithm.
  const passwordHash = await hashPassword(password);

  // 2. Save hash in user_secrets/<uid>.
  await db.collection("user_secrets").doc(TEACHER_UID).set(
    {
      password_hash: passwordHash,
      updated_at: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  console.log(`[user_secrets/${TEACHER_UID}] password_hash updated.`);

  // 3. Ensure teacher doc flags.
  await userRef.set(
    {
      role: "teacher",
      approval_status: "approved",
      account_status: "active",
      is_active: true,
      updated_at: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  console.log(`[users/${TEACHER_UID}] role/approval/account flags ensured.`);

  // 4. Update Firebase Auth password so dashboard login works immediately.
  await auth.updateUser(TEACHER_UID, { password });
  console.log(`[Auth ${TEACHER_UID}] password updated in Firebase Auth.`);

  console.log("=== Done: teacher can now log in to the dashboard. ===");
}

if (require.main === module) {
  setTeacherPassword()
    .then(() => process.exit(0))
    .catch((err) => {
      console.error("setTeacherPassword failed:", err);
      process.exit(1);
    });
}
