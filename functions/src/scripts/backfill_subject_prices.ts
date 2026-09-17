/**
 * Backfill script: ensures every document in the "subjects" collection
 * carries valid numeric "price_egp" and "discount_egp" fields (consumed by
 * the Dashboard Student Profile Payments ledger).
 *
 * Usage (from functions/):
 *   npm run backfill:prices
 *
 * Requires Application Default Credentials for the target project, e.g.:
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
 */
import {initializeApp, getApps} from "firebase-admin/app";
import {getFirestore, FieldValue} from "firebase-admin/firestore";

const DEFAULT_PRICE_EGP = 500;
const DEFAULT_DISCOUNT_EGP = 50;
const BATCH_LIMIT = 400;

function asValidNumber(value: unknown): number | null {
  if (typeof value !== "number" || !Number.isFinite(value)) return null;
  return value;
}

async function backfillSubjectPrices(): Promise<void> {
  if (getApps().length === 0) {
    initializeApp();
  }
  const db = getFirestore();

  console.log("[Backfill] Scanning subjects collection for price fields...");
  const subjectsSnap = await db.collection("subjects").get();
  const total = subjectsSnap.size;

  let updatedCount = 0;
  let batch = db.batch();
  let batchOps = 0;

  const commitBatch = async (): Promise<void> => {
    if (batchOps === 0) return;
    await batch.commit();
    batch = db.batch();
    batchOps = 0;
  };

  for (const doc of subjectsSnap.docs) {
    const data = doc.data() ?? {};
    const priceEgp = asValidNumber(data.price_egp) ?? DEFAULT_PRICE_EGP;
    const discountEgp =
      asValidNumber(data.discount_egp) ?? DEFAULT_DISCOUNT_EGP;

    const needsUpdate =
      asValidNumber(data.price_egp) === null ||
      asValidNumber(data.discount_egp) === null;
    if (!needsUpdate) continue;

    batch.update(doc.ref, {
      price_egp: priceEgp,
      discount_egp: discountEgp,
      updated_at: FieldValue.serverTimestamp(),
    });
    batchOps++;
    updatedCount++;
    console.log(
      `[Backfill] Queued ${doc.id}: price_egp=${priceEgp}, ` +
      `discount_egp=${discountEgp}.`
    );
    if (batchOps >= BATCH_LIMIT) {
      await commitBatch();
    }
  }

  await commitBatch();
  console.log(
    `[Backfill] Scanned ${total} subjects, ` +
    `updated ${updatedCount} subjects with prices.`
  );
}

backfillSubjectPrices().catch((error) => {
  console.error("[Backfill] Failed:", error);
  process.exitCode = 1;
});
