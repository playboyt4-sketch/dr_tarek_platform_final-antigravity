export type PlanResolutionDoc<
  T extends Record<string, unknown> = Record<string, unknown>,
> = {
  id: string;
  data: T;
};

const CANONICAL_PLAN_IDS = new Set(["guest", "free", "pro", "max"]);

function normalizedString(value: unknown): string {
  return typeof value === "string" ? value.trim().toLowerCase() : "";
}

function timestampMillis(value: unknown): number {
  if (!value) return 0;
  if (typeof value === "object") {
    const maybe = value as {toMillis?: unknown; seconds?: unknown; _seconds?: unknown};
    if (typeof maybe.toMillis === "function") {
      try {
        return Number((maybe.toMillis as () => number)());
      } catch {
        return 0;
      }
    }
    const seconds =
      typeof maybe.seconds === "number" ?
        maybe.seconds :
        typeof maybe._seconds === "number" ?
          maybe._seconds :
          null;
    if (seconds !== null) return seconds * 1000;
  }
  if (typeof value === "string") {
    const parsed = Date.parse(value);
    return Number.isNaN(parsed) ? 0 : parsed;
  }
  if (value instanceof Date) return value.getTime();
  return 0;
}

/**
 * Maps a plan doc ID or plan_key to a sortable tier rank so higher tiers
 * deterministically win when multiple active subscriptions exist.
 */
export function planTierRank(planIdOrKey: unknown): number {
  const key = normalizedString(planIdOrKey);
  if (!key) return -1;
  if (key === "max" || key.endsWith("_max")) return 3;
  if (key === "pro" || key.endsWith("_pro")) return 2;
  if (key === "free" || key.endsWith("_free")) return 1;
  if (key === "guest" || key.endsWith("_guest")) return 0;
  return -1;
}

function isLegacyStubPlanId(planId: string): boolean {
  const normalized = planId.trim().toLowerCase();
  return (
    normalized.startsWith("plan_center_") ||
    normalized.startsWith("plan_public_") ||
    normalized.startsWith("e2e_")
  );
}

/**
 * Selects the canonical active plan document for `(studentType, plan)`.
 * Exact canonical IDs (`free`, `pro`, `max`, `guest`) and exact `plan_key`
 * matches strictly outrank prefixed/legacy stub docs (`plan_center_*`, `e2e_*`)
 * regardless of Firestore lexicographical document ordering.
 */
export function selectCanonicalPlanDoc<T extends PlanResolutionDoc>(
  docs: readonly T[],
  input: {
    studentType: string;
    plan: string;
    preferredPlanKey?: string | null;
  },
): T | null {
  const targetTier = normalizedString(input.plan);
  const preferredKey = normalizedString(input.preferredPlanKey) || targetTier;

  let best: T | null = null;
  let bestScore = Number.NEGATIVE_INFINITY;

  for (const doc of docs) {
    if (doc.data.is_active !== true) continue;
    if (doc.data.student_type !== input.studentType) continue;

    const docId = normalizedString(doc.id);
    const planKey = normalizedString(doc.data.plan_key);
    const matchesTarget =
      docId === targetTier ||
      docId === preferredKey ||
      planKey === preferredKey ||
      planKey === targetTier ||
      (targetTier !== "" && planKey.endsWith(`_${targetTier}`));

    if (!matchesTarget) continue;

    let score = 0;
    if (docId === targetTier || docId === preferredKey) {
      score += 1000;
    } else if (CANONICAL_PLAN_IDS.has(docId)) {
      score += 800;
    }
    if (planKey === preferredKey || planKey === targetTier) {
      score += 200;
    } else if (targetTier !== "" && planKey.endsWith(`_${targetTier}`)) {
      score += 50;
    }
    if (isLegacyStubPlanId(docId)) {
      score -= 500;
    }

    if (score > bestScore) {
      best = doc;
      bestScore = score;
    }
  }

  return best;
}

/**
 * Separates non-deleted active subscription docs for `(studentId, subjectId)`
 * into the authoritative `primary` record (highest tier, non-frozen/disabled,
 * canonical plan ID, most recently updated) and any `extras` that should be
 * deactivated as `replaced`.
 */
export function partitionSubscriptionsForSubject<T extends PlanResolutionDoc>(
  docs: readonly T[],
): {primary: T | null; extras: T[]} {
  const active = docs.filter(
    (doc) =>
      doc.data.is_deleted !== true &&
      doc.data.is_archived !== true &&
      doc.data.status === "active",
  );

  if (active.length === 0) {
    return {primary: null, extras: []};
  }

  const sorted = [...active].sort((a, b) => {
    const usableA =
      a.data.is_frozen !== true && a.data.manually_disabled !== true ? 1 : 0;
    const usableB =
      b.data.is_frozen !== true && b.data.manually_disabled !== true ? 1 : 0;
    if (usableB !== usableA) return usableB - usableA;

    const rankDiff = planTierRank(b.data.plan_id) - planTierRank(a.data.plan_id);
    if (rankDiff !== 0) return rankDiff;

    const canonicalA = CANONICAL_PLAN_IDS.has(normalizedString(a.data.plan_id)) ? 1 : 0;
    const canonicalB = CANONICAL_PLAN_IDS.has(normalizedString(b.data.plan_id)) ? 1 : 0;
    if (canonicalB !== canonicalA) return canonicalB - canonicalA;

    const timeA = Math.max(
      timestampMillis(a.data.updated_at),
      timestampMillis(a.data.created_at),
    );
    const timeB = Math.max(
      timestampMillis(b.data.updated_at),
      timestampMillis(b.data.created_at),
    );
    if (timeB !== timeA) return timeB - timeA;

    return a.id.localeCompare(b.id);
  });

  return {
    primary: sorted[0],
    extras: sorted.slice(1),
  };
}
