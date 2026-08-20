# 04_FEATURES

Version: 1.4
Status: Approved

## Version History

- **1.4** (2026-08-04): Rewrote Registration Main Flow and Business Rules to match the approved Figma onboarding sequence (Student Type → Full Name → Phone Number → Photo → Grade selection → Password), replacing the earlier "phone number and password only" flow. Added self-selected `grade` (Frqa) as a new student-owned attribute, distinct from the existing admin-only "Academic Year/Term" (subject-scheduling metadata), which is unchanged. See 05 Database v1.6 for the new field and 11 Assets for the per-grade color tokens.
- **1.3** and earlier: see prior revisions.

# Feature 01 — Authentication & Registration

## Purpose

Provide a secure registration and authentication process while enforcing manual approval, single-device access, and role-based permissions.

---

## Actors

- New Student
- Student
- Admin
- Teacher

---

## Entry Point

- Registration Screen
- Login Screen

---

## Preconditions

### Registration

- Registration is enabled.
- The phone number is not already registered.

### Login

- The account exists.
- The account has been approved.
- The account is active.

---

## Main Flow

### Registration

Per the approved Figma onboarding flow (2026-08-04):

1. The user selects their type on the "I am a" screen: **New Student** (طالب جديد) or **Current Student** (طالب حالي).
    - Selecting **Current Student** routes directly to the Login screen (see First Login below) — this is a UI router, not a separate registration path.
    - Selecting **New Student** proceeds to step 2.
2. The user enters their **Full Name**.
3. The user enters their **Phone Number** (Egypt format, per 08 Development Standards Section 2.1).
4. The user optionally adds a **Profile Photo**.
5. The user selects their **Grade** (الفرقة — Grade one / two / three / four; the specific set of grades is configurable per 08 Development Standards' "no hardcoded business rule" principle).
6. The user sets and confirms a **Password**.
7. A new account is created with the role **New Student**, storing `full_name`, `phone_number`, `profile_photo` (if provided), and `grade`.
8. The account is placed in the **Waiting for Approval** state ("Application under review" screen).
9. The student cannot access the platform.
10. The registration request is sent to the Admin Dashboard for review.

### Manual Approval

1. The Admin reviews the registration request.
2. If approved:
    - The account role changes to **Student**.
    - The **Free Plan** is activated automatically.
    - An approval notification is sent.
3. If rejected:
    - A rejection notification is sent.
    - The student remains unable to access the platform.

### First Login

1. The student logs in using the registered phone number and password.
2. The current device is registered as the student’s primary device.
3. The device becomes the only authorized device.
4. The student is redirected to the Student Dashboard.

---

## Alternative Flow

### Invalid Credentials

- Login is rejected.
- An error message is displayed.

### Waiting for Approval

- Login is rejected.
- The student is informed that the account is awaiting approval.

### Rejected Account

- Login is rejected.
- The rejection message is displayed.

### Disabled Account

- Login is rejected.

### Login From Another Device

1. The login request is rejected.
2. The previously registered device remains active.
3. An Analytics event is created.
4. A warning notification is sent to the student.
5. A security alert becomes available to the Admin for review.

---

## Business Rules

- Registration collects: full name, phone number, optional profile photo, grade (الفرقة), and password — per the approved Figma onboarding flow.
- The student's `grade` is self-selected at registration and is never assigned or overridden by Admin/Teacher in V1. It is distinct from "Academic Year/Term," which remains subject-scheduling metadata controlled by Admin/Teacher and is never shown to students (see 05 Database Section 10, 23).
- Every newly registered user is created as **New Student**.
- Platform access is prohibited until manual approval.
- Approval automatically activates the Free Plan.
- The first successful login permanently binds the account to the current device.
- The number of devices allowed is determined by the student's membership plan (default 1 device; see "Device Limits per Plan" below for the full table).
- Students cannot change their registered device.
- Only Admin and Teacher may replace the registered device.
- Login attempts from unauthorized devices are rejected.
- Every successful and failed login attempt generates an Analytics event.
- Security actions are administrative decisions and are never applied automatically.

---

## Permissions

### New Student

- Register.
- Login to check approval status only.

### Student

- Login from the authorized device only.
- Access features allowed by the assigned membership plan.

### Admin

- Review registration requests.
- Approve or reject students.
- Replace registered devices.
- Review unauthorized device attempts.

### Teacher

- Full administrative permissions.

---

## Success Criteria

- The student account is approved.
- The Free Plan is activated automatically.
- The first device is successfully bound.
- Login succeeds only from the authorized device.
- The correct permissions are loaded.
- The student is redirected to the Student Dashboard.

# Feature 02 — Student Dashboard

## Purpose

Provide a centralized entry point that allows students to access their subscribed subjects, important notifications, and communication channels.

---

## Actors

- Student

---

## Entry Point

- Successful login.

---

## Preconditions

- Student account is approved.
- Student is logged in.
- Student has access to at least the Free Plan.

---

## Main Flow

1. The Student Dashboard is displayed after login.
2. A personalized greeting is shown.
3. The student’s subscribed subjects are displayed as a horizontal carousel.
4. The student selects a subject to continue learning.
5. Two quick-access icons are always available:
    - Notifications
    - Messages

---

## Alternative Flow

### No Active Subjects

- The dashboard is displayed.
- An empty state is shown.
- The student is encouraged to subscribe to a subject.

---

## Business Rules

- Students only see subjects they can access.
- Subjects are displayed according to the configured display order.
- Academic Year and Term are never displayed.
- Selecting a subject opens the Subject page.
- The Notifications Center contains all platform notifications.
- Each notification opens its related feature directly.
- The Messages Center contains:
    - Admin Chat (two-way communication).
    - Doctor Announcements (read-only communication).

---

## Permissions

### Student

- View subscribed subjects.
- Open notifications.
- Chat with Admin.
- Read Doctor announcements.
- Enter accessible subjects.

---

## Success Criteria

- The student reaches the dashboard after login.
- Available subjects are displayed correctly.
- Notifications are accessible.
- Communication channels are available.
- The student can enter a subject with a single action.

# Feature 03 — Subject Navigation

## Purpose

Provide a structured learning experience by organizing each subject into configurable learning sections while allowing students to seamlessly continue their learning journey from where they previously stopped.

---

## Actors

- Student
- Admin
- Teacher

---

## Entry Point

- Student selects a subject from the Student Dashboard.

---

## Preconditions

- The student is authenticated.
- The student has access to the selected subject.
- The selected subject is published and available.

---

## Main Flow

1. The student opens a subject.
2. The subject title is displayed.
3. A horizontal section navigator is displayed.
4. The first available section is automatically selected.
5. The lectures of the selected section are displayed in a vertical list.
6. Each lecture displays its title and current learning status.
7. Selecting a lecture opens the lecture from the last saved position.
8. Returning to the subject restores the last opened section automatically.

---

## Alternative Flow

### Locked Section

- The section remains visible.
- Locked content is identified visually.
- Selecting the section displays the available preview or upgrade option according to the student’s membership permissions.

### Empty Section

- The section is displayed.
- An empty state is shown until lectures become available.

### Hidden Section

- Hidden sections are not displayed to students.

---

## Business Rules

### Subject Structure

- Every subject contains one or more learning sections.
- Sections are displayed horizontally.
- Lectures inside a section are displayed vertically.
- Sections are ordered by their configured display order.
- Sections can be enabled, disabled, added, or removed by Admin without requiring application updates.

### System Sections

The platform provides predefined learning sections, including:

- Explanation
- Revision
- Final Review

These sections behave like normal sections and may be published independently.

### Custom Sections

Administrators may create additional sections for any educational purpose, including but not limited to:

- Online Sessions
- Important Announcements
- Special Videos
- Exam Instructions
- Bonus Lectures

Custom sections follow the same behavior as system sections.

### Resume Learning

The platform remembers the student’s progress on three levels:

#### Subject Level

- The last opened section is restored automatically.

#### Section Level

- The last opened lecture is restored automatically.

#### Lecture Level

- Video playback resumes from the last watched timestamp.
- PDF resources reopen at the last saved reading position when supported.

### Lecture Information

Each section displays:

- Total number of lectures.
- Student learning progress when available.

Example:

- 12 Lectures
- 8 Completed

### Membership Visibility

Content availability is completely controlled by the assigned membership profile.

A section or lecture may be:

- Fully available.
- Preview only.
- Locked.

Locked content remains visible whenever permitted by the membership configuration.

### Preview Mode

Membership configuration determines preview behavior.

Examples include:

- No preview.
- First 3 minutes.
- First 5 minutes.
- First 10 minutes.
- Full access.

When the preview limit is reached:

- Playback stops automatically.
- The student is prompted to upgrade or activate the appropriate membership.

All preview limits are configurable without application updates.

---

## Permissions

### Student

- View accessible sections.
- View lecture list.
- Resume previous learning.
- Access content allowed by the assigned membership.

### Admin

- Create sections.
- Edit sections.
- Delete custom sections.
- Publish or hide sections.
- Configure section order.
- Configure preview behavior.

### Teacher

- Full administrative permissions.

---

## Success Criteria

- The student opens the selected subject successfully.
- The correct learning section is restored automatically.
- The correct lecture resumes from the previous progress.
- Only authorized content is accessible.
- Preview restrictions are enforced according to membership configuration.
- New learning sections can be introduced without modifying the application.

# Feature 04 — Lecture

## Purpose

Provide a complete learning experience by delivering educational resources inside a lecture while supporting resume learning, offline access, configurable membership permissions, and multiple content types.

---

## Actors

- Student
- Admin
- Teacher

---

## Entry Point

- Student selects a lecture from a subject section.

---

## Preconditions

- Student has access to the subject.
- Lecture is published.
- Required permissions are granted by the assigned membership profile.

---

## Main Flow

1. The student opens a lecture.
2. The lecture displays all available learning resources.
3. Resources are displayed in their configured order.
4. The student may switch between resources without leaving the lecture.
5. Progress is saved continuously.
6. Leaving and reopening the lecture restores the previous learning position automatically.

---

## Alternative Flow

### Locked Lecture

- The lecture remains visible.
- Preview is provided if enabled.
- Upgrade options are displayed when required.

### Offline Mode

- Previously downloaded resources remain available according to membership permissions.
- Offline resources are accessible only inside the application.

### Updated Lecture

- If new learning resources are added after completion, the lecture status changes from Completed to Updated.
- Students are informed that new content is available.

---

## Business Rules

### Lecture Structure

A lecture may contain one or more learning resources.

Supported resources include:

- Video
- PDF
- Attachments
- External Links
- Timeline Quizzes

Resources are independent and may be combined in any order.

---

### Multiple Videos

A lecture may contain multiple video parts.

Example:

- Part 1
- Part 2
- Part 3

Each video part carries an explicit sequence number that determines its playback order within the lecture.

Video parts are played sequentially while remaining part of the same lecture.

---

### Resume Learning

The platform automatically remembers:

- Last opened lecture.
- Last watched video.
- Last watched video timestamp.
- Last opened PDF page when supported.
- Last completed learning resource.

---

### Learning Progress

Lecture progress is calculated using all available learning resources.

A lecture is considered completed only after all required resources have been completed according to the lecture configuration.

---

### PDF Reading Mode

The lecture supports simultaneous video and PDF viewing.

Available viewing modes include:

- Video Mode
- Reading Mode
- Focus Mode

Reading Mode displays the PDF while the video continues in a mini player.

---

### Membership Permissions

Every lecture feature is controlled by the assigned membership profile.

Configurable permissions include but are not limited to:

- Video access
- PDF access
- Attachments
- External links
- Timeline quizzes
- Notes
- Chat
- Offline mode
- PDF download
- Video download
- Preview mode
- Playback speed
- Picture in Picture
- Cast to TV
- Available video qualities

No feature is hardcoded to a specific membership plan.

---

### Video Preview

Preview duration is configurable.

Examples:

- Disabled
- 3 Minutes
- 5 Minutes
- 10 Minutes
- Unlimited

When the preview limit is reached:

- Playback stops automatically.
- The student is prompted to upgrade or activate the required membership.

---

### Video Quality

Available qualities are configurable.

Supported qualities include:

- 144p
- 240p
- 360p
- 480p
- 720p
- 1080p
- 1440p
- 4K

Membership profiles determine which qualities are available.

---

### Offline Mode

Offline mode is fully configurable.

Configuration includes:

- Enable or Disable
- Maximum downloaded videos
- Offline storage limit
- Download quality
- Offline expiration policy

Downloaded resources:

- Are encrypted.
- Are stored inside the application only.
- Cannot be accessed by external applications.
- Cannot be copied outside the application.

If membership permissions are removed, downloaded resources immediately become unavailable.

---

### Download Policy

Video and PDF downloads are controlled independently.

Examples:

- Allow Video Download
- Allow PDF Download
- Allow Attachments Download

Each permission is managed separately.

---

### Feature Configuration

All lecture capabilities are controlled by configurable Feature Flags.

Examples include:

- Offline Mode
- Video Download
- PDF Download
- Playback Speed
- Picture in Picture
- Cast to TV
- Preview Duration
- Video Quality
- Notes
- Chat
- Timeline Quiz

No application update is required to enable or disable these features.

---

## Permissions

### Student

- Access permitted lecture resources.
- Resume previous learning.
- Download resources when permitted.
- Use offline mode when permitted.

### Admin

- Create lectures.
- Edit lectures.
- Publish or unpublish lectures.
- Configure lecture resources.
- Configure preview behavior.
- Configure offline permissions.
- Configure feature availability.

### Teacher

- Full administrative permissions.

---

## Success Criteria

- The lecture loads successfully.
- Learning resumes from the previous position.
- All membership permissions are enforced correctly.
- Preview restrictions operate correctly.
- Offline resources function according to permissions.
- Multiple video parts behave as a single lecture.
- New resources automatically update lecture completion status.

# Feature 05 — Video Player

## Purpose

Provide a secure, high-performance video learning experience with intelligent progress tracking, configurable playback capabilities, advanced content protection, and membership-driven feature control.

---

## Actors

- Student
- Admin
- Teacher

---

## Entry Point

- Student opens a video resource inside a lecture.

---

## Preconditions

- Student has permission to watch the selected video.
- Video is published.
- Required membership permissions are available.

---

## Main Flow

1. The selected video starts from the previously saved position.
2. The highest permitted video quality is selected automatically.
3. Playback progress is saved continuously.
4. Students may use available playback features according to their membership permissions.
5. If the lecture contains multiple video parts, playback automatically continues to the next part.
6. Lecture progress is updated continuously.

---

## Alternative Flow

### Preview Mode

- Playback starts normally.
- Playback automatically stops when the configured preview duration is reached.
- The student is prompted to activate or upgrade the required membership.

### Offline Playback

- Previously downloaded videos play without an internet connection.
- Videos remain encrypted inside the application.

### Security Violation

When a security violation is detected, the configured security policy is executed.

Possible actions include:

- Display warning.
- Pause playback.
- Stop playback.
- End session.
- Log security event.
- Notify administrators.

---

## Business Rules

### Resume Playback

The player automatically restores:

- Last watched video.
- Last video part.
- Last playback timestamp.
- Last selected playback quality.
- Last playback speed.
- Previous viewing mode.

---

### Multiple Video Parts

A lecture may contain multiple video parts.

Example:

- Part 1
- Part 2
- Part 3

The player automatically continues to the next part after the current part finishes.

---

### Adaptive Video Quality

The player automatically selects the highest quality allowed by both:

- Membership permissions.
- Current network conditions.

Available qualities may include:

- 144p
- 240p
- 360p
- 480p
- 720p
- 1080p
- 1440p
- 4K

Visible qualities are completely configurable.

---

### Playback Speed

Playback speed is controlled by membership permissions.

Available values are configurable.

Examples include:

- 0.5x
- 0.75x
- 1x
- 1.25x
- 1.5x
- 1.75x
- 2x
- 3x

---

### Picture in Picture

Picture in Picture is controlled by membership permissions.

The feature may be enabled or disabled without application updates.

---

### Offline Playback

Offline playback is fully configurable.

Configuration includes:

- Enable or Disable.
- Maximum downloaded videos.
- Download quality.
- Storage limits.
- Expiration policy.

Offline videos:

- Are encrypted.
- Are stored only inside the application.
- Cannot be exported.
- Cannot be shared.
- Cannot be opened by external applications.

If access permissions are removed, downloaded videos immediately become unavailable.

---

### Interactive Learning

While watching a video, students may access available lecture resources without leaving the lecture.

Supported actions include:

- Open PDF.
- Create Notes.
- Ask Questions.
- Open Timeline Quiz.
- View Attachments.

Available actions depend on membership permissions.

---

### Content Protection

The player applies multiple protection layers.

Protection includes:

- Screenshot prevention where supported.
- Screen recording detection where supported.
- Dynamic forensic watermark.
- Encrypted video streaming.
- Secure offline storage.
- Device binding validation.
- Membership validation.

---

### Dynamic Watermark

The watermark is generated dynamically during playback.

It may include:

- Student name.
- Phone number.
- User ID.
- Device identifier.
- Current date and time.

The watermark continuously changes position during playback.

---

### Security Policy

When supported by the operating system, security events may include:

- Screenshot attempt.
- Screen recording detection.
- Rooted device.
- Jailbroken device.
- Emulator detection.
- Unauthorized device.
- Other security violations.

Each detected event is processed according to the configured security policy.

---

### Security Score

Every student has a security score.

Each detected security violation (Section: Security Policy) is recorded as an independent **Security Event** — a distinct record type separate from general learning analytics.

Security events increase the score.

The score is visible to administrators and may be used when reviewing suspicious activity.

No automatic punishment is applied by default.

Administrative actions remain configurable.

---

### Analytics

The player records learning analytics including:

- Video started.
- Video completed.
- Watch duration.
- Resume count.
- Pause count.
- Seek forward count.
- Seek backward count.
- Playback quality.
- Playback speed.
- Network quality.
- Completion percentage.
- Most replayed moments.
- Most abandoned moments.

Security violations are tracked separately as Security Events (see Security Score above) and are not part of general learning analytics.

---

### Feature Configuration

Every player capability is controlled by Feature Flags.

Examples include:

- Video Quality
- Playback Speed
- Preview Duration
- Offline Mode
- Offline Limits
- Picture in Picture
- Download
- Notes
- Timeline Quiz
- Dynamic Watermark
- Security Policies

No capability is hardcoded to any membership plan.

---

## Permissions

### Student

- Watch permitted videos.
- Resume playback.
- Download videos when permitted.
- Use offline playback when permitted.
- Access available interactive features.

### Admin

- Configure playback permissions.
- Configure preview rules.
- Configure offline policies.
- Configure security policies.
- View analytics.
- Review security events.

### Teacher

- Full administrative permissions.

---

## Success Criteria

- Videos start successfully.
- Resume playback functions correctly.
- Multiple video parts play seamlessly.
- Membership permissions are enforced correctly.
- Offline playback follows configured policies.
- Security policies execute correctly.
- Analytics are recorded accurately.
- Content protection remains active throughout playback.

# Feature 06 — PDF Viewer

## Purpose

Provide a secure and interactive PDF reading experience fully integrated with the learning process while supporting synchronized navigation, progress tracking, offline reading, and configurable membership permissions.

---

## Actors

- Student
- Admin
- Teacher

---

## Entry Point

- Student opens a PDF resource from a lecture.
- Student switches from Video to PDF inside the lecture.

---

## Preconditions

- Student has permission to access the PDF.
- PDF is published.
- Required membership permissions are granted.

---

## Main Flow

1. The student opens the PDF.
2. The PDF opens at the previously saved reading position.
3. The student can navigate between pages without leaving the lecture.
4. The student may switch between Video, PDF, and other lecture resources at any time.
5. Reading progress is saved continuously.
6. Returning to the lecture restores the previous reading position automatically.

---

## Alternative Flow

### Preview Mode

- Only the configured preview pages are accessible.
- Remaining pages remain locked.
- Upgrade options are displayed when required.

### Offline Reading

- Previously downloaded PDFs remain available according to membership permissions.
- PDFs remain encrypted inside the application.

### Updated PDF

- When a new version of the PDF is published, students are notified.
- Reading progress is preserved whenever possible.

---

## Business Rules

### Integrated Learning

The PDF Viewer is part of the lecture experience.

Students can switch instantly between:

- Video
- PDF
- Attachments
- Timeline Quiz

without leaving the lecture.

---

### Resume Reading

The system automatically restores:

- Last opened page.
- Last zoom level.
- Last reading position.
- Previous viewing mode.

---

### Reading Progress

The platform tracks:

- Last opened page.
- Total pages read.
- Reading percentage.
- Reading completion status.

Reading progress contributes to the overall lecture progress.

---

### Synchronized Learning

The platform supports synchronization between video and PDF.

Examples include:

- Video Timestamp → PDF Page
- PDF Page → Video Timestamp

Students can instantly move between related explanations in the video and their corresponding pages in the PDF.

---

### Viewing Modes

Supported viewing modes include:

- Standard Reading Mode.
- Video + Mini Player Mode.
- Full Screen PDF Mode.

Students may switch between modes without interrupting their learning progress.

---

### PDF Features

Available features may include:

- Zoom
- Search
- Table of Contents
- Bookmarks
- Page Thumbnails
- Page Navigation

Each feature is controlled independently through Feature Matrix.

---

### Membership Permissions

PDF capabilities are fully configurable.

Permissions include but are not limited to:

- PDF Access
- Preview Pages
- PDF Download
- Offline Reading
- Search
- Zoom
- Bookmarks
- Table of Contents
- Print
- Copy Text
- Share
- Open In

No capability is hardcoded to any membership plan.

---

### Offline Reading

Offline reading is fully configurable.

Configuration includes:

- Enable or Disable.
- Maximum downloaded PDFs.
- Storage limits.
- Expiration policy.

Downloaded PDFs:

- Are encrypted.
- Are stored only inside the application.
- Cannot be exported.
- Cannot be shared.
- Cannot be opened by external applications.

If membership permissions are removed, downloaded PDFs immediately become unavailable.

---

### Content Protection

The PDF Viewer applies multiple protection layers.

Protection includes:

- Screenshot prevention where supported.
- Screen recording detection where supported.
- Dynamic forensic watermark.
- Secure encrypted storage.
- Device binding validation.
- Membership validation.

Each detected violation is recorded as an independent Security Event (see Feature 05 — Security Score), not as general reading analytics.

---

### Dynamic Watermark

The watermark is generated dynamically while reading.

It may include:

- Student Name
- Phone Number
- User ID
- Device Identifier
- Current Date and Time

The watermark changes position continuously during reading.

---

### Notes Integration

Students may create notes linked to:

- PDF Page
- Lecture
- Video Timestamp (when applicable)

Notes remain associated with the lecture rather than the PDF file itself.

---

### Analytics

The platform records PDF analytics including:

- PDF Opened
- Reading Duration
- Pages Visited
- Reading Completion
- Search Usage
- Bookmark Usage
- Download Events
- Offline Reading

Security violations are tracked separately as Security Events (see Content Protection above) and are not part of general reading analytics.

---

### Feature Configuration

Every PDF capability is controlled by Feature Flags.

Examples include:

- PDF Access
- Preview Pages
- Offline Reading
- PDF Download
- Search
- Zoom
- Bookmarks
- Table of Contents
- Copy Text
- Print
- Share
- Dynamic Watermark
- Security Policies

No application update is required to enable or disable these capabilities.

---

## Permissions

### Student

- Read permitted PDFs.
- Resume previous reading.
- Download PDFs when permitted.
- Use offline reading when permitted.
- Create notes linked to PDF pages.

### Admin

- Upload PDFs.
- Replace PDF versions.
- Configure preview rules.
- Configure offline permissions.
- Configure PDF features.
- View reading analytics.

### Teacher

- Full administrative permissions.

---

## Success Criteria

- PDFs open successfully.
- Reading resumes from the previous position.
- Video and PDF synchronization functions correctly.
- Membership permissions are enforced correctly.
- Offline reading follows configured policies.
- Reading analytics are recorded accurately.
- Content protection remains active throughout the reading session.

# Feature 07 — Timeline Quizzes & Learning Access

## Purpose

Provide continuous assessment throughout the learning journey while giving administrators complete control over lecture availability, viewing limits, and student access.

---

## Actors

- Student
- Admin
- Teacher

---

## Entry Point

- Student reaches a quiz trigger during a lecture.
- Student manually opens an available quiz.
- Admin manages lecture access.

---

## Preconditions

- The lecture is available to the student.
- Quiz is published.
- Student satisfies all access requirements.

---

## Main Flow

### Timeline Quiz

1. The student reaches a configured quiz trigger.
2. The quiz becomes available.
3. The student completes the quiz.
4. The result is recorded.
5. Lecture progress is updated.
6. The learning journey continues according to quiz settings.

### Lecture Access Management

1. Admin opens a lecture.
2. Admin views all eligible students.
3. Admin grants or removes lecture access individually or in bulk.
4. Access changes become effective immediately.

---

## Alternative Flow

### Optional Quiz

- Student may postpone the quiz.
- The quiz remains available until completed or expired.

### Mandatory Quiz

- Student must complete the quiz before continuing when configured.

### Lecture Locked

- Lecture remains visible.
- Student cannot access its content.
- Access is granted only after administrator approval or when automatic access conditions are satisfied.

---

## Business Rules

### Quiz Triggers

A quiz may become available after:

- Specific video timestamp.
- Specific video part.
- Specific PDF page.
- Lecture completion.
- Manual release.
- Any configurable learning milestone.

---

### Supported Question Types

The platform supports:

- Multiple Choice
- Multiple Response
- True / False
- Fill in the Blank
- Ordering
- Matching
- Essay

Additional question types may be introduced without changing application logic.

---

### Quiz Configuration

Each quiz may define:

- Mandatory or Optional.
- Time limit.
- Number of attempts.
- Passing score.
- Review policy.
- Explanation visibility.
- Randomized questions.
- Randomized answers.

---

### Quiz Attempt History

Every Timeline Quiz completion is recorded as an independent quiz attempt, tracked separately from Exam attempts (Feature 08).

Each attempt stores its own score, time spent, and attempt number, allowing “Number of attempts” and “Attempt count” (see Analytics) to be enforced and reported per quiz.

---

### Review Learning

After incorrect answers the platform may:

- Display the explanation.
- Jump directly to the related video timestamp.
- Open the related PDF page.
- Recommend reviewing the lecture.
- Allow another attempt according to quiz settings.

---

## Lecture Viewing Policy

Each lecture has its own configurable viewing policy.

Configuration includes:

- Published or Hidden.
- Available From.
- Available Until.
- Membership Permissions.
- Student Permissions.
- Group Permissions.
- Required Previous Lecture.
- Required Quiz Completion.
- Required Exam Completion.
- Required Minimum Score.
- Preview Policy.
- Maximum Watch Attempts.

No viewing policy is hardcoded.

---

## Maximum Watch Attempts

Each lecture may define its own maximum number of completed views.

Examples:

- Unlimited
- 1
- 2
- 3
- 5
- 10

A completed view is counted only after the configured completion percentage has been reached.

Opening and closing the video without meaningful watching does not consume an attempt.

---

## Watch Limit Reached

When the student reaches the maximum allowed views:

- Playback is blocked.
- The lecture remains visible.
- The student is informed that the viewing limit has been reached.

Administrators and Teachers may restore viewing access at any time.

Restoring access may include:

- Resetting the watch counter.
- Granting additional viewing attempts.
- Removing the viewing limit completely.

---

## Student Access Management

Administrators may manage lecture access at multiple levels.

> TODO (Version 2): Group Access and per-lecture Individual Access grants below depend on Student Groups and Lecture Access Grants, both postponed to Version 2. For Version 1, lecture access is governed by Membership, Subject Subscription, and the other availability rules in this document (Available From/Until, Prerequisites).
> 

### Global Access

Available for all eligible students.

### Group Access

Available only for selected groups.

Examples:

- Group A
- Group B
- Online Students
- VIP Students

### Individual Access

Available only for selected students.

Administrators may:

- Grant access.
- Remove access.
- Select all students.
- Remove all selections.
- Perform bulk operations.

Changes are applied immediately.

---

## Availability Rules

Lecture access may depend on:

- Membership.
- Student.
- Group.
- Date and time.
- Previous lecture completion.
- Quiz completion.
- Exam completion.
- Administrator approval.

---

## Analytics

The platform records:

- Quiz opened.
- Quiz completed.
- Quiz score.
- Time spent.
- Attempt count.
- Success rate.
- Incorrect answers.
- Most difficult questions.
- Review actions.
- Lecture unlock events.
- Lecture lock events.
- Watch attempt consumption.
- Watch limit reached.
- Access granted.
- Access revoked.

---

## Permissions

### Student

- Complete available quizzes.
- Review explanations when permitted.
- Access lectures according to assigned permissions.
- Watch lectures within allowed viewing limits.

### Admin

- Create quizzes.
- Configure quiz rules.
- Configure lecture access.
- Grant or revoke lecture permissions.
- Reset viewing attempts.
- Grant additional viewing attempts.
- Remove viewing limits.
- View quiz analytics.

### Teacher

- Full administrative permissions.

---

## Success Criteria

- Quizzes appear according to configured triggers.
- Quiz rules are enforced correctly.
- Lecture access follows configured policies.
- Viewing limits operate correctly.
- Administrators can instantly restore or modify lecture access.
- Learning progress and analytics are recorded accurately.

# Feature 08 — Exams

## Purpose

Provide a configurable examination system that supports learning, practice, and formal assessment while maintaining security, fairness, and detailed analytics.

---

## Actors

- Student
- Admin
- Teacher

---

## Entry Point

- Student opens an available exam.

---

## Preconditions

- Student has permission to access the exam.
- Exam is published.
- All access conditions are satisfied.

---

## Main Flow

1. Student opens the exam.
2. Exam instructions are displayed.
3. Student starts the attempt.
4. Answers are saved automatically throughout the exam.
5. Student submits the exam or the exam is submitted automatically when time expires.
6. Results are processed according to exam configuration.

---

## Alternative Flow

### Practice Mode

- Immediate feedback is available.
- Multiple attempts may be allowed.

### Learning Mode

- Explanations may be displayed.
- Related lecture and PDF references may be available.

### Exam Mode

- Security rules are enforced.
- Results are published according to administrator settings.

---

## Business Rules

### Exam Types

The platform supports:

- Practice Exam
- Assignment
- Chapter Exam
- Revision Exam
- Mock Exam
- Final Exam

Additional exam types may be introduced without application updates.

---

### Question Bank

Exams are generated from the Question Bank.

Configuration includes:

- Fixed Questions.
- Random Questions.
- Question Pools.
- Random Answers.

---

### Supported Question Types

- Multiple Choice
- Multiple Response
- True / False
- Fill in the Blank
- Matching
- Ordering
- Essay

---

### Question Configuration

Each question may define:

- Marks.
- Difficulty.
- Explanation.
- Reference Lecture.
- Reference PDF.
- Reference Video Timestamp.

---

### Exam Configuration

Each exam defines:

- Duration.
- Passing Score.
- Attempt Limit.
- Randomization.
- Availability Window.
- Result Visibility.
- Review Policy.
- Security Policy.

---

### Automatic Saving

All answers are saved continuously.

Students may resume interrupted attempts according to exam configuration.

---

### Exam Security

Supported security options include:

- Full Screen Mode.
- Screenshot Prevention where supported.
- Screen Recording Detection where supported.
- Device Validation.
- Time Enforcement.
- Question Randomization.
- Answer Randomization.
- Back Navigation Control.
- Skip Question Control.

Each option is configurable.

Each detected violation is recorded as an independent Security Event (see Feature 05 — Security Score), not as general exam analytics.

---

### Result Processing

Result calculation supports:

- Automatic Grading.
- Manual Grading.
- Mixed Grading.

---

### Result Visibility

Results may include:

- Final Score.
- Percentage.
- Correct Answers.
- Incorrect Answers.
- Explanations.
- Ranking.
- Feedback.

Visibility is fully configurable.

---

### Attempt History

Students may have multiple attempts.

Administrators determine how the final result is calculated.

Supported policies include:

- Highest Score.
- Latest Attempt.
- First Attempt.
- Average Score.

---

### Exam Availability

An exam may become available based on:

- Membership.
- Student.
- Group.
- Subject.
- Section.
- Lecture.
- Previous Lecture Completion.
- Quiz Completion.
- Previous Exam Score.
- Date and Time.
- Administrator Approval.

> TODO (Version 2): Group-based availability depends on Student Groups, which are postponed to Version 2. For Version 1, exam availability is configured by Membership, Student, Subject, Section, Lecture, and the remaining criteria above.
> 

---

### Learning References

Questions may contain learning references including:

- Lecture.
- Video Timestamp.
- PDF Page.

Students may review these references when permitted.

---

### Analytics

The platform records:

- Exam Started.
- Exam Submitted.
- Exam Duration.
- Attempt Count.
- Question Statistics.
- Success Rate.
- Average Score.
- Highest Score.
- Lowest Score.
- Most Difficult Questions.
- Most Skipped Questions.
- Most Incorrect Questions.

Security violations are tracked separately as Security Events (see Exam Security above) and are not part of general exam analytics.

---

## Permissions

### Student

- Take available exams.
- Resume interrupted attempts when permitted.
- Review results according to exam configuration.

### Admin

- Create exams.
- Configure exams.
- Publish exams.
- Grade essay questions.
- Configure security policies.
- Configure result policies.
- View analytics.

### Teacher

- Full administrative permissions.

---

## Success Criteria

- Exams are delivered according to configured rules.
- Answers are saved automatically.
- Security policies are enforced.
- Results are calculated correctly.
- Analytics are recorded accurately.
- Learning references function correctly.

# Feature 09 — Notes

## Purpose

Provide an integrated note-taking system that allows students to capture, organize, search, and revisit learning notes while linking them directly to educational content.

---

## Actors

- Student
- Admin
- Teacher

---

## Entry Point

- Student selects **Add Note** from any supported learning resource.
- Student opens the Notes Center.

---

## Preconditions

- Student is authenticated.
- Student has permission to use Notes.
- The related learning resource is accessible.

---

## Main Flow

1. Student creates a new note.
2. The note is automatically linked to the current learning context.
3. The note is saved instantly.
4. The student may edit, organize, search, or revisit the note at any time.
5. Selecting a note returns the student directly to its related learning resource.

---

## Alternative Flow

### Offline Mode

- Notes remain available offline.
- Changes synchronize automatically when connectivity is restored.

### Read-Only Notes

- Some system-generated notes may be read-only.
- Students may save them to their personal notebooks.

---

## Business Rules

### Supported Note Types

The platform supports:

- Text Notes
- Checklist Notes
- Image Notes
- Voice Notes (Future Extension)
- Highlight Notes (Future Extension)

Additional note types may be introduced without application updates.

---

### Learning Context

Every note may be linked to one or more learning resources.

Supported references include:

- Subject
- Section
- Lecture
- Video
- Video Timestamp
- PDF Page
- Timeline Quiz
- Exam

Selecting a note automatically opens its related learning location.

---

### Smart Notes

Administrators may create predefined learning notes.

Examples include:

- Important Formula
- Common Mistake
- Important Definition
- Exam Tip

Students may save these notes directly into their personal notebooks.

---

### Personal Notebooks

Students may organize notes into notebooks.

Examples include:

- Financial Accounting
- Cost Accounting
- Revision Notes
- Important Concepts

Students may create, rename and delete personal notebooks.

---

### Favorites

Students may mark notes as favorites.

Favorite notes are available through a dedicated section.

---

### Categories

Notes may be categorized.

Examples include:

- Important
- Review Later
- Question
- Definition
- Formula
- Reminder

Categories are configurable.

---

### Search

Students may search notes by:

- Title
- Content
- Subject
- Section
- Lecture
- Tags
- Notebook
- Category

---

### Review Reminders

Students may schedule reminders for any note.

Examples include:

- Tomorrow
- Next Week
- Next Month
- Custom Date

Reminder notifications are generated automatically.

---

### Export

Export permissions are configurable.

Supported export formats may include:

- PDF
- Word
- Print

Export availability depends on membership permissions.

---

### Synchronization

Notes are synchronized with the student’s account.

Changing the authorized device does not affect saved notes.

---

### Content Protection

Personal notes remain private.

Students cannot access notes belonging to other students.

System-generated notes are managed separately from personal notes.

---

### Analytics

The platform records:

- Notes Created
- Notes Updated
- Notes Deleted
- Favorite Notes
- Reminder Usage
- Search Usage
- Notebook Usage
- Most Referenced Subjects
- Most Referenced Lectures
- Review Activity

---

### Feature Configuration

Every Notes capability is controlled by Feature Flags.

Examples include:

- Notes
- Voice Notes
- Image Notes
- Favorites
- Notebooks
- Search
- Export
- Reminders
- Smart Notes

No capability is hardcoded to any membership plan.

---

## Permissions

### Student

- Create notes.
- Edit personal notes.
- Delete personal notes.
- Organize notebooks.
- Search notes.
- Schedule reminders.
- Export notes when permitted.

### Admin

- Create Smart Notes.
- Configure Notes features.
- Configure export permissions.
- Configure reminder settings.

### Teacher

- Full administrative permissions.

---

## Success Criteria

- Notes are saved successfully.
- Every note is linked to the correct learning resource.
- Students can instantly return to the related lecture, video, or PDF.
- Search operates accurately.
- Reminders are generated correctly.
- Synchronization functions correctly.
- Membership permissions are enforced.
- Analytics are recorded accurately.

# Feature 10— Bookmarks

## Purpose

Provide students with a fast and organized way to save important learning locations across the platform, allowing them to return to specific content instantly without affecting learning progress.

---

## Actors

- Student
- Admin
- Teacher

---

## Entry Point

- Student taps the Bookmark button while viewing learning content.
- Student opens My Bookmarks.

---

## Preconditions

- Student is authenticated.
- Student has permission to access the related content.
- Bookmark feature is enabled for the assigned membership.

---

## Main Flow

### Create Bookmark

1. The student opens a lecture resource.
2. The student selects **Add Bookmark**.
3. The current location is detected automatically.
4. The student may enter an optional title.
5. The bookmark is saved immediately.
6. The bookmark becomes available in **My Bookmarks**.

### Open Bookmark

1. The student opens **My Bookmarks**.
2. The saved bookmarks are displayed.
3. The student selects a bookmark.
4. The related content opens directly at the saved location.

---

## Alternative Flow

### Feature Disabled

- Bookmark option is hidden or disabled according to Membership permissions.

### Deleted Content

- The bookmark remains visible.
- It is marked as **Unavailable**.
- Opening the bookmark displays an appropriate message.

### Lost Access

- The bookmark remains in the list.
- Protected content cannot be opened until access is restored.

---

## Business Rules

### Supported Bookmark Types

Bookmarks may be created for:

- Video Timestamp
- PDF Page
- Lecture

---

### Bookmark Information

Each bookmark stores:

- Bookmark Title
- Bookmark Type
- Subject
- Section
- Lecture
- Video Timestamp (when applicable)
- PDF Page (when applicable)
- Creation Date

---

### My Bookmarks

Students can:

- View all bookmarks.
- Search bookmarks.
- Filter by Subject.
- Filter by Bookmark Type.
- Rename bookmarks.
- Delete bookmarks.

---

### Resume Behavior

Bookmarks never replace Resume Learning.

Resume Learning always restores the last learning position.

Bookmarks are manual reference points created by the student.

---

### Membership Permissions

The Bookmark feature is fully configurable.

Permissions include:

- Enable Bookmark Feature
- Maximum Number of Bookmarks
- Bookmark Search
- Bookmark Rename
- Bookmark Delete

No capability is hardcoded to any membership plan.

---

### Analytics

The platform records bookmark analytics including:

- Bookmark Created
- Bookmark Opened
- Bookmark Renamed
- Bookmark Deleted

---

### Feature Configuration

Every bookmark capability is controlled by Feature Flags.

Examples include:

- Bookmark Enabled
- Maximum Bookmarks
- Search
- Rename
- Delete

No application update is required to enable or disable these capabilities.

---

## Permissions

### Student

- Create bookmarks.
- View bookmarks.
- Open bookmarks.
- Rename bookmarks.
- Delete bookmarks.

### Admin

- View bookmark analytics.

### Teacher

- Full administrative permissions.

---

## Success Criteria

- Students can save important learning locations.
- Bookmarks open directly at the correct location.
- Bookmark limits are enforced according to Membership permissions.
- Resume Learning operates independently from Bookmarks.
- All bookmark activities are recorded for analytics.

# Feature 11— Questions to Admin

## Purpose

Provide a structured communication system that enables students to submit academic, technical, and administrative questions while giving administrators efficient tools to manage, classify, answer, and track requests.

---

## Actors

- Student
- Admin
- Teacher

---

## Entry Point

- Student selects **Ask Question** from anywhere within the platform.
- Student asks a question while watching a lecture or reading a PDF.

---

## Preconditions

- Student is authenticated.
- Student has permission to submit questions.
- Related learning content is accessible when applicable.

---

## Main Flow

1. Student opens the Ask Question form.
2. The platform automatically detects the current learning context whenever possible.
3. Student selects the question category.
4. Student writes the question.
5. Student optionally attaches supporting files.
6. The question is submitted.
7. The system creates a support ticket.
8. Administrators receive a notification.
9. An administrator reviews and answers the ticket.
10. The student receives a notification when a response is available.

---

## Alternative Flow

### General Question

The student may submit a question without linking it to any learning content.

---

### Contextual Question

The platform automatically links the question to the current learning resource.

Supported references include:

- Subject
- Section
- Lecture
- Video
- Video Timestamp
- PDF Page
- Timeline Quiz
- Exam

---

### Reopened Ticket

Students may reopen previously answered tickets when additional clarification is required.

---

## Business Rules

### Question Categories

Supported categories include:

- Academic
- Technical Support
- Payment
- Account
- Report Problem
- Suggestion

Additional categories may be introduced without application updates.

---

### Ticket Lifecycle

Every question follows a configurable workflow.

Supported statuses include:

- Open
- In Review
- Answered
- Closed

Additional statuses may be introduced when required.

---

### Priority

Each ticket may define a priority level.

Examples include:

- Low
- Normal
- High
- Urgent

Priority may be assigned automatically or manually.

---

### Attachments

Students may attach supporting files.

Supported attachment types include:

- Images
- Screenshots
- PDF Files
- Documents

Attachment permissions are configurable.

---

### Administrator Responses

Administrators may respond using:

- Text
- Image
- File
- PDF
- Short Video
- External Link

Multiple responses may be added to the same ticket.

---

### Duplicate Detection

Before creating a new ticket, the platform searches for similar previously answered questions.

If similar answers exist:

- Suggested answers are presented.
- The student may read them before submitting a new ticket.

Students may still create a new ticket if the suggested answers are insufficient.

---

### Broadcast Answer

Administrators may publish an answer to multiple students.

Broadcasts may target:

- Entire Platform
- Subject
- Section
- Lecture
- Student Group
- Individual Students

Published answers may also generate notifications.

---

### Search

Administrators may search tickets using:

- Student
- Subject
- Section
- Lecture
- Question Category
- Status
- Priority
- Date
- Keywords

---

### Analytics

The platform records:

- Submitted Questions
- Answered Questions
- Closed Questions
- Reopened Questions
- Average Response Time
- Average Resolution Time
- Most Asked Subjects
- Most Asked Lectures
- Most Common Categories
- Duplicate Detection Usage
- Broadcast Answer Usage

---

### Feature Configuration

Every Questions capability is controlled by Feature Flags.

Examples include:

- Ask Question
- Attachments
- Short Video Replies
- Duplicate Detection
- Broadcast Answers
- Question Categories
- Reopen Ticket
- Search

No capability is hardcoded to any membership plan.

---

## Permissions

### Student

- Submit questions.
- Attach supporting files.
- View personal tickets.
- Reopen answered tickets.
- View administrator responses.

### Admin

- View assigned tickets.
- Answer questions.
- Change ticket status.
- Change priority.
- Publish broadcast answers.
- Configure question categories.
- View analytics.

### Teacher

- Full administrative permissions.

---

## Success Criteria

- Questions are submitted successfully.
- Learning context is linked automatically whenever available.
- Administrators receive new ticket notifications.
- Students receive response notifications.
- Duplicate detection reduces repeated questions.
- Broadcast answers function correctly.
- Analytics are recorded accurately.

# Feature 12— Chat

## Purpose

Provide an integrated communication system that enables direct communication with administrators and one-way educational announcements from instructors while maintaining structured, scalable, and secure communication.

---

## Actors

- Student
- Admin
- Teacher (referred to as “Doctor” throughout this feature — see note below)

> Architecture Note: “Doctor” refers to the Teacher (Platform Owner, Dr. Tarek) acting in the instructor/content-publisher capacity. It is not a separate system role. Every “Doctor” action in this feature is performed under the `teacher` role.
> 

---

## Entry Point

- Student opens the Chat Center.
- Student selects a conversation.
- Doctor (Teacher) or Admin creates a new message.

---

## Preconditions

- User is authenticated.
- User has permission to access Chat.
- Related subject is accessible when applicable.

---

## Main Flow

### Admin Chat

1. Student opens the Admin Chat.
2. Student sends a message.
3. Administrator receives the message.
4. Administrator replies.
5. Student receives a notification.
6. Conversation continues until completed.

---

### Doctor Channel

1. Doctor publishes a message.
2. The message is delivered to eligible students.
3. Students receive a notification.
4. Students open and read the announcement.

Students cannot reply to Doctor Channels.

---

## Alternative Flow

### Rich Educational Message

A message may contain direct educational actions.

Students may open linked resources directly from the message.

---

### Scheduled Message

Messages may be scheduled for future delivery.

Delivery occurs automatically at the configured time.

---

### Temporary Message

Messages may expire automatically after a configured period.

Expired messages are hidden automatically.

---

## Business Rules

### Chat Types

The platform supports:

- Admin Chat
- Doctor Channel

Additional communication channels may be introduced without application updates.

---

### Admin Chat

Admin Chat supports two-way communication.

Supported message types include:

- Text
- Image
- PDF
- File

Voice and Video messages may be introduced in future versions.

Administrators may convert conversations into support tickets when required.

---

### Doctor Channel

Doctor Channel is a one-way communication channel.

Only authorized users may publish messages.

Students:

- Can read messages.
- Cannot reply.
- Cannot edit.
- Cannot delete.

Each subject has its own independent Doctor Channel.

Students only see channels for subjects they are enrolled in.

---

### Rich Messages

Messages may contain direct actions.

Supported actions include:

- Open Subject
- Open Section
- Open Lecture
- Open Video
- Open Video Timestamp
- Open PDF
- Open PDF Page
- Open Quiz
- Open Exam
- Open External Link

Selecting an action opens the related learning resource immediately.

---

### Message Priority

Messages may define priority.

Examples include:

- Normal
- Important
- High Priority

Priority affects notification behavior.

---

### Silent Messages

Messages may be delivered silently without generating push notifications.

---

### Pinned Messages

Important messages may be pinned.

Pinned messages remain visible at the top of the conversation until removed.

---

### Scheduled Messages

Messages may be scheduled for automatic publication.

Publication occurs without administrator intervention.

---

### Temporary Messages

Messages may automatically expire.

Expiration rules are configurable.

---

### Polls

Doctor Channels may include polls.

Examples include:

- Select Revision Date
- Choose Online Session Time
- General Student Feedback

Poll results are available to administrators.

---

### Read Status

Administrators and Doctors may view message statistics.

Examples include:

- Delivered Count
- Read Count

Individual student read tracking is not displayed by default.

---

### Search

Users may search messages by:

- Subject
- Conversation
- Keywords
- Date
- Attachments

---

### Analytics

The platform records:

- Messages Sent
- Messages Delivered
- Messages Read
- Attachment Usage
- Rich Message Usage
- Poll Participation
- Scheduled Messages
- Temporary Messages
- Pinned Messages
- Average Read Rate

---

### Feature Configuration

Every Chat capability is controlled by Feature Flags.

Examples include:

- Admin Chat
- Doctor Channel
- Rich Messages
- Attachments
- Polls
- Scheduled Messages
- Temporary Messages
- Pinned Messages
- Search
- Read Statistics

No capability is hardcoded to any membership plan.

---

## Permissions

### Student

- Send messages to Admin.
- Receive Admin replies.
- Read Doctor Channels.
- Participate in polls.
- Open linked educational resources.

---

### Admin

- Reply to students.
- Manage conversations.
- Convert conversations into tickets.
- Pin messages.
- Schedule messages.
- Publish announcements.
- View analytics.

---

### Teacher — Doctor Capabilities

(Teacher role, acting as Doctor — see Architecture Note above)

- Publish announcements.
- Schedule announcements.
- Create polls.
- Pin announcements.
- Send rich educational messages.
- View delivery statistics.

---

### Teacher

- Full administrative permissions.

---

## Success Criteria

- Students communicate successfully with administrators.
- Doctor announcements reach the correct students.
- Rich educational messages open the correct learning resources.
- Polls function correctly.
- Scheduled and temporary messages operate according to configuration.
- Analytics are recorded accurately.
- Membership permissions are enforced correctly.

# Feature 13— Notifications

## Purpose

Provide a centralized notification system that delivers academic, administrative, membership, payment, and security events while enabling students to take immediate action from every notification.

---

## Actors

- Student
- Admin
- Teacher (referred to as “Doctor” throughout this feature — see Architecture Note in Feature 12)
- System

---

## Entry Point

- A platform event generates a notification.
- Student opens the Notification Center.

---

## Preconditions

- The notification event is valid.
- The recipient has permission to receive the notification.

---

## Main Flow

1. A platform event occurs.
2. The notification engine evaluates all notification rules.
3. Eligible recipients are determined.
4. The notification is generated.
5. The notification is delivered through the configured delivery channels.
6. The student receives the notification.
7. The student opens the notification.
8. Selecting the notification opens the related platform resource.

---

## Alternative Flow

### Scheduled Notification

Notifications are delivered automatically at the configured date and time.

---

### Conditional Notification

Notifications are generated automatically when configured business conditions are satisfied.

---

### Silent Notification

Notifications may be delivered without push alerts.

---

## Business Rules

### Notification Categories

Supported notification categories include:

- Academic
- Communication
- Membership
- Payment
- Security
- System

Additional categories may be introduced without application updates.

---

### Academic Notifications

Examples include:

- New Lecture
- New Revision
- New Final Review
- New Quiz
- New Exam
- Exam Result
- Lecture Updated
- New PDF
- New Attachment

---

### Communication Notifications

Examples include:

- Doctor Announcement
- Admin Reply
- Ticket Answered
- New Broadcast

---

### Membership Notifications

Examples include:

- Trial Activated
- Membership Activated
- Membership Upgraded
- Membership Expiring
- Membership Expired

---

### Payment Notifications

Examples include:

- Payment Received
- Payment Approved
- Payment Rejected
- Payment Pending Review

---

### Security Notifications

Examples include:

- New Login
- Unauthorized Device Attempt
- Device Changed
- Security Warning
- Suspicious Activity

---

### System Notifications

Examples include:

- Maintenance
- Platform Update
- New Feature
- Scheduled Downtime

---

### Action Notifications

Every notification may contain one or more actions.

Examples include:

- Open Subject
- Open Section
- Open Lecture
- Open Video
- Open PDF
- Open Quiz
- Start Exam
- Open Membership
- Open Payment
- Open Chat
- Open Ticket

Selecting an action immediately opens the related platform resource.

Each action defines an action type (e.g. “Open Lecture”) and a reference to the specific target resource (e.g. the Lecture ID), so the correct destination can be resolved and opened.

---

### Notification Priority

Notifications support configurable priorities.

Examples include:

- Low
- Normal
- High
- Critical

Priority affects delivery behavior.

---

### Smart Reminders

The platform may generate automatic reminders.

Examples include:

- Continue your last lecture.
- You have unfinished quizzes.
- Your exam starts tomorrow.
- Your membership expires soon.
- You have unread announcements.
- You have unanswered administrator replies.

Reminder rules are fully configurable.

---

### Notification Rules

Notifications may be generated automatically by business events.

Examples include:

- Lecture Published
- Quiz Published
- Exam Released
- Payment Approved
- Membership Activated
- Ticket Answered
- Student Inactive
- Lecture Updated

No notification rule is hardcoded.

---

### Scheduled Notifications

Notifications may be scheduled for future delivery.

---

### Quiet Hours

Students may configure Quiet Hours.

During Quiet Hours:

- Normal notifications are delayed.
- Critical notifications may still be delivered according to platform policy.

---

### Notification Grouping

Similar notifications may be grouped.

Examples include:

- 5 New Lectures
- 3 New Announcements
- 4 Unread Messages

Grouping rules are configurable.

---

### Delivery Channels

Supported delivery channels include:

- In-App Notifications
- Push Notifications

Future extensions may include:

- Email
- SMS
- WhatsApp

Each channel is controlled independently.

---

### Notification Templates

Administrators may define reusable templates.

Templates support dynamic placeholders.

Examples include:

- Student Name
- Subject Name
- Lecture Name
- Exam Name
- Membership Name

---

### Delivery Tracking

The platform records:

- Generated
- Sent
- Delivered
- Opened
- Action Clicked

Delivery status is available for analytics.

---

### Analytics

The platform records:

- Notification Count
- Delivery Rate
- Open Rate
- Action Rate
- Reminder Usage
- Most Opened Notifications
- Most Ignored Notifications
- Delivery Failures
- Notification Channel Usage

---

### Feature Configuration

Every notification capability is controlled by Feature Flags.

Examples include:

- Push Notifications
- In-App Notifications
- Quiet Hours
- Smart Reminders
- Scheduled Notifications
- Notification Templates
- Notification Grouping
- Delivery Tracking
- Delivery Channels

No capability is hardcoded to any membership plan.

---

## Permissions

### Student

- Receive notifications.
- Open notifications.
- Execute available notification actions.
- Configure Quiet Hours.
- Mark notifications as read.

---

### Admin

- Create notification templates.
- Schedule notifications.
- Publish broadcasts.
- Configure notification rules.
- View notification analytics.

---

### Teacher — Doctor Capabilities

(Teacher role, acting as Doctor — see Architecture Note in Feature 12)

- Publish academic notifications.
- Schedule announcements.
- View delivery statistics.

---

### Teacher

- Full administrative permissions.

---

## Success Criteria

- Notifications are generated automatically according to business rules.
- Notifications are delivered through the configured channels.
- Students are redirected to the correct platform resource.
- Quiet Hours operate correctly.
- Smart reminders are generated accurately.
- Notification analytics are recorded correctly.
- Feature Matrix controls all notification capabilities.

# Feature 14— Membership Plans

## Purpose

Manage student access using Student Types and Membership Plans while allowing complete control over platform capabilities through the Feature Matrix.

---

## Actors

- Student
- Admin
- Teacher

---

## Entry Point

- Registration Approval
- Membership Assignment
- Membership Upgrade
- Membership Renewal

---

## Preconditions

- Student account is approved.
- Student Type is assigned.
- Membership Plan is assigned.

---

## Main Flow

### Registration

1. Student submits a registration request.
2. Admin or Teacher reviews the request.
3. Student Type is assigned.
4. Initial Membership Plan is assigned.
5. Platform permissions become active immediately.

---

### Membership Upgrade

1. Admin or Teacher selects a student.
2. Membership Plan is changed.
3. New permissions become effective immediately.
4. Student progress and history remain unchanged.

---

## Alternative Flow

### Public Student

The student receives the Public Free membership.

Only Public Free is available.

---

### Center Student

The student may receive:

- Center Free
- Center Pro
- Center Max

Membership may be upgraded or downgraded at any time.

---

## Business Rules

### Student Types

The platform supports only two Student Types.

- Public Student
- Center Student

Student Type is assigned only by Admin or Teacher.

Students cannot change their own Student Type.

---

### Public Student

Public Students are intended for marketing and student acquisition.

Available Membership:

- Public Free

Examples of configurable capabilities include:

- Preview only.
- Limited video duration.
- Limited lecture access.
- Limited video quality.
- No Offline Mode.
- No Downloads.

All capabilities are controlled by Feature Matrix.

---

### Center Student

Center Students are official enrolled students.

Available Membership Plans:

- Center Free
- Center Pro
- Center Max

Each plan enables a different Feature Matrix configuration.

---

### Public Free

Examples include:

- Configurable preview duration.
- Configurable preview lectures.
- Configurable video quality.
- Marketing upgrade screens.

All limits are configurable.

---

### Center Free

Examples include:

- Full lecture access.
- Configurable video quality.
- Limited premium features.

Permissions are controlled entirely by Feature Matrix.

---

### Center Pro

Provides additional learning capabilities according to Feature Matrix.

---

### Center Max

Provides the highest available learning capabilities according to Feature Matrix.

---

### Device Limits per Plan

The platform enforces device binding limits based on the assigned membership plan:

| Plan | Max Devices | Configurable |
|------|-------------|--------------|
| Public Free | 1 | No |
| Center Free | 1 | No |
| Center Pro | 1 | No |
| Center Max | 2+ | Yes (from Dashboard) |

Device limits are enforced via the Feature Matrix (`plan_features`) and validated at login time by the `onLoginAttempt` Cloud Function. Changing the limit for Center Max requires Teacher (Platform Owner) approval.

---

### Feature Matrix

Membership Plans never contain hardcoded permissions.

Every capability is enabled or disabled through Feature Matrix.

Examples include:

- Video Preview Duration
- Video Quality
- Offline Mode
- Video Download
- PDF Access
- Quiz Access
- Exam Access
- Notes
- Chat
- Picture in Picture
- Export
- Notifications
- Security Features

Every capability is independently configurable.

---

### Student Type Conversion

Admin or Teacher may convert:

- Public Student → Center Student
- Center Student → Public Student

The conversion:

- Preserves learning progress.
- Preserves notes.
- Preserves quizzes.
- Preserves exams.
- Preserves analytics.
- Preserves history.

Only permissions change.

---

### Membership Upgrade

Supported operations include:

- Upgrade
- Downgrade
- Renewal
- Gift Membership
- Freeze
- Resume

No student data is lost.

---

### Membership Validity

Membership duration is configurable.

Examples include:

- Weekly
- Monthly
- Semester
- Annual
- Lifetime

---

### Marketing Configuration

Public memberships support configurable marketing content.

Examples include:

- Upgrade Messages
- Promotional Videos
- Discount Campaigns
- Registration Links
- WhatsApp Contact
- Coupon Campaigns

---

### Membership Analytics

The platform records:

- Public Students
- Center Students
- Public to Center Conversions
- Membership Distribution
- Upgrade Rate
- Downgrade Rate
- Renewal Rate
- Expired Memberships
- Active Memberships

---

### Feature Configuration

All Membership capabilities are controlled through Feature Matrix.

No capability is hardcoded.

---

## Permissions

### Student

- View current membership.
- View available upgrades.
- Access permitted features.

---

### Admin

- Assign Student Type.
- Change Student Type.
- Assign Membership Plans.
- Upgrade Membership.
- Downgrade Membership.
- Renew Membership.
- Freeze Membership.
- Resume Membership.

---

### Teacher

- Full administrative permissions.

---

## Success Criteria

- Student Type controls available Membership Plans.
- Membership Plans correctly activate Feature Matrix.
- Membership changes preserve all student data.
- Feature Matrix enforces every platform capability.
- Membership analytics are recorded accurately.

# Feature 15 — Student Profile

## Purpose

Provide students with a centralized profile management system that allows them to manage their personal information, account settings, and membership details while maintaining platform security and administrative restrictions.

---

## Actors

- Student
- Admin
- Teacher

---

## Entry Point

- Student selects **Profile** from the main navigation.
- Student taps the profile avatar.

---

## Preconditions

- Student is authenticated.
- Student account is active.

---

## Main Flow

1. Student opens the Profile page.
2. Personal account information is displayed.
3. Student updates permitted information.
4. Changes are validated.
5. Changes are saved immediately.
6. Updated information becomes available across the platform.

---

## Alternative Flow

### Read-Only Fields

Some account information cannot be modified by the student.

The platform displays these fields as read-only.

---

### Membership Restrictions

Some profile capabilities may be unavailable according to the assigned membership.

---

### Invalid Data

If submitted information is invalid:

- Changes are rejected.
- Validation messages are displayed.

---

## Business Rules

### Personal Information

Students may view:

- Profile Photo
- Full Name
- Phone Number
- Student ID (if assigned)
- Academic Year
- Membership Plan
- Account Status

---

### Editable Information

Students may edit:

- Full Name
- Profile Photo
- Password

Editable fields are fully configurable.

---

### Read-Only Information

Students cannot modify:

- Phone Number
- Registered Device
- Membership Plan
- Account Status

Only Admin and Teacher may modify restricted information.

---

### Membership Information

The profile displays:

- Current Membership
- Membership Expiration (when applicable)
- Available Features

---

### Device Information

Students may view:

- Current Authorized Device
- Device Registration Date

Students cannot replace or remove the registered device.

---

### Password Management

Students may:

- Change Password

Password policy is controlled by System Settings.

---

### Profile Photo

Students may:

- Upload Profile Photo
- Replace Profile Photo
- Remove Profile Photo

Supported formats and maximum file size are configurable.

---

### Feature Configuration

Every Profile capability is controlled by Feature Flags.

Examples include:

- Profile Photo
- Change Password
- Edit Name
- Device Information
- Membership Information

No capability is hardcoded to any membership plan.

---

## Permissions

### Student

- View profile.
- Edit permitted information.
- Change password.
- Manage profile photo.

### Admin

- View student profile.
- Edit restricted information.
- Reset student password.
- Replace registered device.

### Teacher

- Full administrative permissions.

---

## Success Criteria

- Students can manage permitted profile information.
- Restricted fields remain protected.
- Membership information is displayed correctly.
- Device information is displayed accurately.
- All profile changes are validated and saved successfully.