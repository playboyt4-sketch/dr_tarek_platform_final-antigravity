/**
 * Pure lifecycle builders and validation helpers for archiving, restoring,
 * and permanently deleting students, subjects, and lectures.
 */

export interface ArchiveFieldActor {
  actorId: string;
  nowSentinel: unknown;
}

export function isStudentArchiveEligibleRole(role: unknown): boolean {
  return role === "student" || role === "new_student";
}

export function isArchivedRecord(data: Record<string, unknown> | undefined): boolean {
  if (!data) return false;
  return data.is_archived === true || data.is_deleted === true;
}

export function buildStudentArchiveFields(params: ArchiveFieldActor & {
  previousAccountStatus?: string | null;
}): Record<string, unknown> {
  const previousStatus =
    typeof params.previousAccountStatus === "string" &&
    params.previousAccountStatus.trim().length > 0
      ? params.previousAccountStatus.trim()
      : "active";

  return {
    is_archived: true,
    is_deleted: true,
    deleted_at: params.nowSentinel,
    archived_at: params.nowSentinel,
    archived_by: params.actorId,
    archived_previous_account_status: previousStatus,
    account_status: "disabled",
    updated_at: params.nowSentinel,
    updated_by: params.actorId,
  };
}

export function buildStudentRestoreFields(params: ArchiveFieldActor & {
  previousAccountStatus?: string | null;
}): Record<string, unknown> {
  const prev =
    typeof params.previousAccountStatus === "string"
      ? params.previousAccountStatus.trim()
      : "";
  const restoredStatus =
    prev.length > 0 && prev !== "disabled" ? prev : "active";

  return {
    is_archived: false,
    is_deleted: false,
    deleted_at: null,
    archived_at: null,
    archived_by: null,
    archived_previous_account_status: null,
    account_status: restoredStatus,
    updated_at: params.nowSentinel,
    updated_by: params.actorId,
  };
}

export function buildSubjectArchiveFields(
  params: ArchiveFieldActor,
): Record<string, unknown> {
  return {
    is_archived: true,
    is_deleted: true,
    deleted_at: params.nowSentinel,
    deleted_by: params.actorId,
    archived_by: params.actorId,
    updated_at: params.nowSentinel,
    updated_by: params.actorId,
  };
}

export function buildSubjectRestoreFields(
  params: ArchiveFieldActor,
): Record<string, unknown> {
  return {
    is_archived: false,
    is_deleted: false,
    deleted_at: null,
    deleted_by: null,
    archived_by: null,
    updated_at: params.nowSentinel,
    updated_by: params.actorId,
  };
}

export function buildLectureRestoreFields(params: ArchiveFieldActor & {
  previousStatus?: string | null;
}): Record<string, unknown> {
  const prev =
    typeof params.previousStatus === "string"
      ? params.previousStatus.trim()
      : "";
  const restoredStatus =
    prev.length > 0 && prev !== "archived" ? prev : "draft";

  return {
    is_archived: false,
    is_deleted: false,
    deleted_at: null,
    archived_by: null,
    status: restoredStatus,
    updated_at: params.nowSentinel,
    updated_by: params.actorId,
  };
}
