import type {CallableOptions} from "firebase-functions/v2/https";

export const APP_CHECK_ENFORCEMENT_VAR = "APP_CHECK_ENFORCEMENT";

/**
 * Parsed `APP_CHECK_ENFORCEMENT` state.
 *
 * `mode` is one of:
 * - `enforced`  — the variable is exactly `"true"`.
 * - `disabled`  — the variable is exactly `"false"`, absent or empty.
 * - `malformed` — anything else. Enforcement is treated as disabled (the
 *   unchanged historical behaviour) and the boot diagnostic reports it.
 */
export interface AppCheckEnforcementState {
  enabled: boolean;
  malformed: boolean;
  mode: "enforced" | "disabled" | "malformed";
  /**
   * Length of the raw value when malformed, so an operator can tell a stray
   * newline from a flattened multi-line `.env` blob. Never the value itself.
   */
  rawLength?: number;
}

/**
 * Parse the App Check enforcement switch.
 *
 * Production incident (2026-11-16, ADR-010 Mission 21): three `.env` lines were
 * flattened into one, so `APP_CHECK_ENFORCEMENT` held a 97-character blob.
 * `=== "true"` silently evaluated to `false`, and enforcement was off on every
 * callable while the deployment was believed to have enabled it. Only the exact
 * literals count; anything else stays disabled but is now *visible*.
 * @param {string|undefined} raw Raw environment value.
 * @return {AppCheckEnforcementState} Parsed state.
 */
export function describeAppCheckEnforcement(
  raw: string | undefined,
): AppCheckEnforcementState {
  if (raw === "true") {
    return {enabled: true, malformed: false, mode: "enforced"};
  }
  if (raw === "false" || raw === undefined || raw === "") {
    return {enabled: false, malformed: false, mode: "disabled"};
  }
  return {
    enabled: false,
    malformed: true,
    mode: "malformed",
    rawLength: raw.length,
  };
}

/** Parsed state of the live process environment. */
export const APP_CHECK_ENFORCEMENT_STATE = describeAppCheckEnforcement(
  process.env[APP_CHECK_ENFORCEMENT_VAR],
);

export const SECURE_CALL_OPTS: CallableOptions = {
  enforceAppCheck: APP_CHECK_ENFORCEMENT_STATE.enabled,
};
