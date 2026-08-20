const admin = require("firebase-admin");

admin.initializeApp({
  projectId: "dr-tarek-platform",
});

const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;

// Approved schema: id, period_type, label, is_core, status (active|ended),
// started_at, ended_at, created_by, created_at.
const periods = [
  {
    id: "term_1",
    period_type: "term_1",
    label: "الترم الأول",
    display_order: 1,
  },
  {
    id: "term_2",
    period_type: "term_2",
    label: "الترم الثاني",
    display_order: 2,
  },
  {
    id: "summer_course",
    period_type: "summer_course",
    label: "السمر كورس",
    display_order: 3,
  },
];

(async () => {
  const batch = db.batch();

  for (const period of periods) {
    const ref = db.collection("academic_periods").doc(period.id);
    const snapshot = await ref.get();

    if (!snapshot.exists) {
      batch.set(ref, {
        id: period.id,
        period_type: period.period_type,
        label: period.label,
        is_core: true,
        status: "ended",
        display_order: period.display_order,
        started_at: null,
        ended_at: null,
        created_at: FieldValue.serverTimestamp(),
        updated_at: FieldValue.serverTimestamp(),
        created_by: "migration",
        updated_by: "migration",
        is_deleted: false,
      });
    } else {
      // Backfill the approved schema without touching lifecycle state.
      batch.set(
        ref,
        {
          period_type: period.period_type,
          label: period.label,
          is_core: true,
          display_order: period.display_order,
          updated_at: FieldValue.serverTimestamp(),
          updated_by: "migration",
        },
        { merge: true },
      );
    }
  }

  await batch.commit();

  console.log("ACADEMIC PERIODS BASE CREATED");
  console.log("term_1");
  console.log("term_2");
  console.log("summer_course");
  console.log("Exceptional periods are created dynamically by Teacher.");
})().catch((error) => {
  console.error("ACADEMIC PERIOD MIGRATION FAILED");
  console.error(error);
  process.exit(1);
});
