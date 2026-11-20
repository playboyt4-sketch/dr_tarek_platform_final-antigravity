/**
 * ADR-010 — Firestore-backed read path for the server-managed Bunny catalog.
 *
 * This module is the ONLY place the platform turns `bunny_libraries` documents
 * into a client-safe list. It builds on the pure contract in
 * `bunny_library_catalog.ts` (validation + activation gate + projection) and
 * adds exactly two things:
 *
 * 1. The emergency deny-list from Mission 8 §F.3.7: when
 *    `BUNNY_ACTIVE_LIBRARY_IDS` is set to a non-empty value, a library is
 *    eligible ONLY if it is listed there. The list can only REDUCE
 *    eligibility, never expand it.
 * 2. A deterministic, de-duplicated ordering so the Dashboard and the tests
 *    observe a stable list.
 *
 * Security contract:
 * - The projection is exactly `{libraryId, displayName}`. Pull zone ids,
 *   playback hosts, credential references, verification stamps and error
 *   codes are never returned to a client.
 * - A document is eligible only when the pure activation gate passes
 *   (`status: active`, token auth enabled AND probe-verified, valid ids/host,
 *   credential NAMES). Anything unknown, disabled, pending, incomplete or
 *   malformed is dropped — there is no fallback library.
 * - The document id must equal `library_id` (Mission 8 §H.1); a mismatched
 *   document is treated as malformed and dropped.
 */

import {
  toEligibleLibraryOption,
} from "./bunny_library_catalog";

/** Client-visible, non-secret projection of one eligible library. */
export interface EligibleBunnyLibrary {
  libraryId: string;
  displayName: string;
}

/** One catalog document as read from Firestore (id + raw data). */
export interface BunnyCatalogDocument {
  id: string;
  data: unknown;
}

/**
 * Minimal Firestore surface this module needs.
 *
 * Structural typing keeps the reader unit-testable without the Admin SDK and
 * lets `FirebaseFirestore.Firestore` satisfy it directly at the call site.
 */
export interface BunnyCatalogStore {
  collection(name: string): {
    get(): Promise<{docs: ReadonlyArray<{id: string; data(): unknown}>}>;
  };
}

/** Env variable that acts as an emergency deny-list (Mission 8 §F.3.7). */
export const BUNNY_ACTIVE_LIBRARY_IDS_VAR = "BUNNY_ACTIVE_LIBRARY_IDS";

const NUMERIC_LIBRARY_ID = /^\d{1,20}$/;

/**
 * Parse the emergency deny-list.
 *
 * Semantics (fail closed):
 * - unset or blank → `null` (the kill switch is not engaged);
 * - non-empty → the set of valid numeric ids it names. A non-empty value that
 *   names no valid id yields an EMPTY set, which denies every library. That is
 *   deliberate: a malformed emergency control must not silently disable the
 *   safety it exists to provide.
 * @param {Readonly<Record<string, string | undefined>>} env Env snapshot.
 * @return {ReadonlySet<string> | null} Allowed ids, or null when not engaged.
 */
export function parseBunnyEmergencyDenyList(
  env: Readonly<Record<string, string | undefined>>,
): ReadonlySet<string> | null {
  const raw = env[BUNNY_ACTIVE_LIBRARY_IDS_VAR];
  if (typeof raw !== "string") return null;
  if (raw.trim() === "") return null;
  const ids = raw
    .split(",")
    .map((entry) => entry.trim())
    .filter((entry) => NUMERIC_LIBRARY_ID.test(entry));
  return new Set(ids);
}

/**
 * Deterministic numeric ordering for digit-only library ids.
 * @param {string} left First library id.
 * @param {string} right Second library id.
 * @return {number} Negative, zero or positive sort result.
 */
function compareLibraryIds(left: string, right: string): number {
  if (left.length !== right.length) return left.length - right.length;
  if (left === right) return 0;
  return left < right ? -1 : 1;
}

/**
 * Filter catalog documents down to the eligible, client-safe list.
 *
 * Pure: no Firestore, no `process.env` reads (the env snapshot is explicit).
 * @param {ReadonlyArray<BunnyCatalogDocument>} documents Catalog documents.
 * @param {Readonly<Record<string, string | undefined>>} env Env snapshot.
 * @return {EligibleBunnyLibrary[]} Eligible libraries, sorted, de-duplicated.
 */
export function selectEligibleBunnyLibraries(
  documents: ReadonlyArray<BunnyCatalogDocument>,
  env: Readonly<Record<string, string | undefined>>,
): EligibleBunnyLibrary[] {
  const denyList = parseBunnyEmergencyDenyList(env);
  const seen = new Set<string>();
  const eligible: EligibleBunnyLibrary[] = [];

  for (const document of documents) {
    const option = toEligibleLibraryOption(document.data);
    if (!option) continue;
    // Mission 8 §H.1: the document id is the canonical library id.
    if (document.id !== option.libraryId) continue;
    if (denyList && !denyList.has(option.libraryId)) continue;
    if (seen.has(option.libraryId)) continue;
    seen.add(option.libraryId);
    eligible.push({
      libraryId: option.libraryId,
      displayName: option.displayName,
    });
  }

  eligible.sort((left, right) =>
    compareLibraryIds(left.libraryId, right.libraryId));
  return eligible;
}

/**
 * Read `bunny_libraries` and return the eligible, client-safe projection.
 *
 * The collection is server-only (Firestore Rules deny all client access); the
 * Dashboard reaches it exclusively through `listEligibleBunnyLibraries`.
 * @param {BunnyCatalogStore} store Firestore handle (or a test double).
 * @param {Readonly<Record<string, string | undefined>>} env Env snapshot.
 * @return {Promise<EligibleBunnyLibrary[]>} Eligible libraries.
 */
export async function loadEligibleBunnyLibraries(
  store: BunnyCatalogStore,
  env: Readonly<Record<string, string | undefined>>,
): Promise<EligibleBunnyLibrary[]> {
  const snapshot = await store.collection("bunny_libraries").get();
  const documents: BunnyCatalogDocument[] = snapshot.docs.map((doc) => ({
    id: doc.id,
    data: doc.data(),
  }));
  return selectEligibleBunnyLibraries(documents, env);
}
