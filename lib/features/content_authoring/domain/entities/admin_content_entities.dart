import '../../../lecture/domain/entities/lecture.dart' show LectureStatus;
import '../../../lecture/domain/entities/lecture_resource.dart'
    show LectureResourceType;

/// Which physical backend stores a resource's bytes
/// (FINAL_DECISIONS §15). Domain-level because it is part of the authoring
/// model; ONLY the Data layer ever branches on it (gateways/repository).
enum ResourceStorageProvider {
  bunny('bunny'),
  firebase('firebase');

  final String wireValue;
  const ResourceStorageProvider(this.wireValue);

  static ResourceStorageProvider fromWire(String? value) =>
      value == ResourceStorageProvider.bunny.wireValue
          ? ResourceStorageProvider.bunny
          : ResourceStorageProvider.firebase;
}

/// Admin-facing section entity per the `subject_sections` schema
/// (05 Database §16): subject_id, section_key, is_system_section, title,
/// display_order, is_visible (+ common audit fields).
class AdminSection {
  final String id;
  final String subjectId;

  /// `explanation` / `revision` / `final_review` for system sections;
  /// null for custom ones (05 Database §17 Section Type).
  final String? sectionKey;
  final bool isSystemSection;
  final String title;
  final int displayOrder;
  final bool isVisible;

  /// Soft-delete metadata (Archive System, Part B): populated only in the
  /// archived-sections query.
  final DateTime? deletedAt;
  final String? deletedBy;

  const AdminSection({
    required this.id,
    required this.subjectId,
    required this.sectionKey,
    required this.isSystemSection,
    required this.title,
    required this.displayOrder,
    required this.isVisible,
    this.deletedAt,
    this.deletedBy,
  });

  AdminSection copyWith({String? title, bool? isVisible}) {
    return AdminSection(
      id: id,
      subjectId: subjectId,
      // section_key / is_system_section are immutable (Feature 03):
      // system identity can never be edited into — or out of — a section.
      sectionKey: sectionKey,
      isSystemSection: isSystemSection,
      title: title ?? this.title,
      displayOrder: displayOrder,
      isVisible: isVisible ?? this.isVisible,
      deletedAt: deletedAt,
      deletedBy: deletedBy,
    );
  }
}

/// Student row for the per-lecture Access UI. Read from the existing
/// `users` collection (`full_name` + `grade` are approved schema fields);
/// no new collection is introduced here.
class LectureStudent {
  final String id;
  final String name;
  final String? grade;

  const LectureStudent({
    required this.id,
    required this.name,
    this.grade,
  });
}
/// Staged per-lecture allow/deny decision, persisted to
/// `lecture_access_grants/{lectureId_studentId}` (deterministic id —
/// duplicates are structurally impossible). Missing grant = no override.
/// Revocation is represented by `allowed: false`; the soft-delete audit
/// fields exist for architectural consistency (client delete stays
/// prohibited — revocation never deletes the document).
class LectureAccessGrant {
  final String lectureId;
  final String studentId;
  final bool allowed;

  /// Soft-delete audit state. Managed server-side only; clients always
  /// write `false`/null (enforced by Security Rules).
  final bool isDeleted;
  final DateTime? deletedAt;
  final String? deletedBy;

  const LectureAccessGrant({
    required this.lectureId,
    required this.studentId,
    required this.allowed,
    this.isDeleted = false,
    this.deletedAt,
    this.deletedBy,
  });
}
/// Read model for the Archive view: an archived lecture with its
/// soft-delete metadata and origin context ("archived-from which subject").
/// Kept separate from the shared student-facing [Lecture] aggregate so the
/// consumption code never carries authoring-only fields.
class ArchivedLecture {
  final String id;
  final String subjectId;
  final String sectionId;
  final String title;
  final LectureStatus statusAtArchive;
  final DateTime? deletedAt;
  final String? deletedBy;

  const ArchivedLecture({
    required this.id,
    required this.subjectId,
    required this.sectionId,
    required this.title,
    required this.statusAtArchive,
    this.deletedAt,
    this.deletedBy,
  });
}

/// Admin-facing lecture-resource entity per the `lecture_resources` schema
/// (05 Database §16/§17). Kept separate from the student-facing
/// [LectureResource] so the admin aggregate can carry authoring fields
/// (title, display_order, storage_path, soft-delete) without touching the
/// shared student consumption code.
class AdminLectureResource {
  final String id;
  final String lectureId;
  final LectureResourceType resourceType;
  final String title;
  final int displayOrder;

  /// Bunny video id for `video` resources — NEVER a raw URL (06 §6.4 /
  /// 11 Assets §4.3: Admin enters only the video_id in the Dashboard).
  final String? bunnyVideoId;

  /// Storage path of the uploaded file for pdf/attachment resources, per
  /// 11 Assets §4.2: /lecture_resources/{lecture_id}/{resource_id}/{file}.
  final String? storagePath;

  /// Which backend stores [storagePath] (FINAL_DECISIONS §15):
  /// "bunny" | "firebase". Null/absent → firebase (legacy default).
  final ResourceStorageProvider? storageProvider;

  /// Provider used for the uploaded thumbnail bytes of a video resource;
  /// kept separate so pure video resources stay implicitly Bunny with no
  /// provider field (05 Database v1.9).
  final ResourceStorageProvider? thumbnailProvider;

  /// External link target for `external_link` resources (stored in the
  /// schema's resource_url field; media types leave it empty).
  final String? externalUrl;

  final String? thumbnail;
  final int? duration;
  final bool isVisible;
  final bool isDeleted;
  final DateTime? deletedAt;
  final String? deletedBy;

  const AdminLectureResource({
    required this.id,
    required this.lectureId,
    required this.resourceType,
    required this.title,
    required this.displayOrder,
    this.bunnyVideoId,
    this.storagePath,
    this.storageProvider,
    this.thumbnailProvider,
    this.externalUrl,
    this.thumbnail,
    this.duration,
    required this.isVisible,
    required this.isDeleted,
    this.deletedAt,
    this.deletedBy,
  });

  AdminLectureResource copyWith({
    String? title,
    int? displayOrder,
    bool? isVisible,
    bool? isDeleted,
    String? bunnyVideoId,
    String? thumbnail,
    int? duration,
    ResourceStorageProvider? storageProvider,
    ResourceStorageProvider? thumbnailProvider,
  }) {
    return AdminLectureResource(
      id: id,
      lectureId: lectureId,
      resourceType: resourceType,
      title: title ?? this.title,
      displayOrder: displayOrder ?? this.displayOrder,
      bunnyVideoId: bunnyVideoId ?? this.bunnyVideoId,
      storagePath: storagePath,
      externalUrl: externalUrl,
      thumbnail: thumbnail ?? this.thumbnail,
      duration: duration ?? this.duration,
      isVisible: isVisible ?? this.isVisible,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedAt: deletedAt,
      deletedBy: deletedBy,
      storageProvider: storageProvider ?? this.storageProvider,
      thumbnailProvider: thumbnailProvider ?? this.thumbnailProvider,
    );
  }
}

/// Deterministic grant document id: `lecture_access_grants` uses
/// `{lectureId}_{studentId}` so the same pair can never produce two
/// documents (repeat-safe saves by construction).
String lectureAccessGrantDocId(String lectureId, String studentId) =>
    '${lectureId}_$studentId';

/// Displayed/saved default for one student: an explicit staged toggle
/// wins, then the stored grant, otherwise ON — meaning "no override",
/// i.e. the student follows normal lecture eligibility. Default ON is
/// behavior-preserving: nothing is denied until the Teacher acts.
bool resolveEffectiveAccess({bool? staged, bool? grantAllowed}) =>
    staged ?? grantAllowed ?? true;

/// Backend fallback predicate (mirrors the Cloud Functions + Rules
/// enforcement): only an explicit stored `allowed == false` denies.
/// Missing grant (null) or `allowed == true` defers to the normal
/// eligibility model.
bool isLectureAccessDeniedByGrant(bool? grantAllowed) =>
    grantAllowed == false;
