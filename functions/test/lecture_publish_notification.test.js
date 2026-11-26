/**
 * Pure unit tests for lecture publish notification gating and payload construction.
 */
const assert = require("node:assert/strict");
const {
  shouldSendLecturePublishNotification,
  buildLecturePublishNotificationPayload,
  buildLecturePublishInAppNotificationDoc,
  resolveNextUnreadBadgeCount,
} = require("../lib/index.js");

// 1. Draft -> published triggers notification when not already sent.
assert.equal(
  shouldSendLecturePublishNotification(
    {status: "draft", is_deleted: false},
    {status: "published", is_deleted: false},
  ),
  true,
);

// 2. Direct creation with status == published triggers notification.
assert.equal(
  shouldSendLecturePublishNotification(
    null,
    {status: "published", is_deleted: false},
  ),
  true,
);

// 3. Subsequent edit on an already-published lecture does NOT re-trigger.
assert.equal(
  shouldSendLecturePublishNotification(
    {status: "published", is_deleted: false},
    {status: "published", is_deleted: false, title: "Updated title"},
  ),
  false,
);

// 4. Idempotency guard: publish_notification_sent === true blocks notification
// even if before state was draft or missing.
assert.equal(
  shouldSendLecturePublishNotification(
    {status: "draft"},
    {status: "published", is_deleted: false, publish_notification_sent: true},
  ),
  false,
);

// 5. Draft or soft-deleted lectures never trigger notification.
assert.equal(
  shouldSendLecturePublishNotification(
    null,
    {status: "draft", is_deleted: false},
  ),
  false,
);
assert.equal(
  shouldSendLecturePublishNotification(
    {status: "draft"},
    {status: "published", is_deleted: true},
  ),
  false,
);

// 6. APNs & FCM payload includes full iOS alert, sound, badge, and apns-priority 10.
const payload = buildLecturePublishNotificationPayload({
  lectureId: "lec_123",
  subjectId: "subj_456",
  subjectTitle: "Anatomy",
  lectureTitle: "Upper Limb 1",
});
assert.equal(payload.title, "محاضرة جديدة في Anatomy");
assert.equal(payload.body, "تم نشر محاضرة: Upper Limb 1");
assert.equal(payload.apns.headers["apns-priority"], "10");
assert.equal(payload.apns.headers["apns-push-type"], "alert");
assert.equal(payload.apns.payload.aps.sound, "default");
assert.equal(payload.apns.payload.aps.badge, 1);
assert.deepEqual(payload.apns.payload.aps.alert, {
  title: "محاضرة جديدة في Anatomy",
  body: "تم نشر محاضرة: Upper Limb 1",
});
assert.equal(payload.data.lecture_id, "lec_123");
assert.equal(payload.data.subject_id, "subj_456");

// 7. Dynamic unread badge helpers preserve caller badge counts and increment safely.
const customBadgePayload = buildLecturePublishNotificationPayload({
  lectureId: "lec_124",
  subjectId: "subj_456",
  subjectTitle: "Anatomy",
  lectureTitle: "Upper Limb 2",
  badge: 3,
});
assert.equal(customBadgePayload.apns.payload.aps.badge, 3);
assert.equal(resolveNextUnreadBadgeCount(undefined), 1);
assert.equal(resolveNextUnreadBadgeCount(0), 1);
assert.equal(resolveNextUnreadBadgeCount(2), 3);
assert.equal(resolveNextUnreadBadgeCount(4, 0), 4);

// 8. In-app notification doc carries exact UI fields and skip_push guard.
const inAppDoc = buildLecturePublishInAppNotificationDoc({
  studentId: "stu_1",
  lectureId: "lec_124",
  subjectId: "subj_456",
  title: "محاضرة جديدة في Anatomy",
  body: "تم نشر محاضرة: Upper Limb 2",
  deepLink: "/subject/subj_456",
  hasTokens: true,
  sentTimestamp: "__NOW__",
  nowTimestamp: "__NOW__",
});
assert.equal(inAppDoc.user_id, "stu_1");
assert.equal(inAppDoc.lecture_id, "lec_124");
assert.equal(inAppDoc.subject_id, "subj_456");
assert.equal(inAppDoc.type, "Lecture");
assert.equal(inAppDoc.notification_type, "lecture");
assert.equal(inAppDoc.is_read, false);
assert.equal(inAppDoc.skip_push, true);
assert.equal(inAppDoc.delivery_status, "sent");

console.log("lecture_publish_notification.test.js: all assertions passed");
