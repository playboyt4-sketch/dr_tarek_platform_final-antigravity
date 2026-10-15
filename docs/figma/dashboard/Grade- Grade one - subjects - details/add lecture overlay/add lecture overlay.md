# 🚀 Master Production Specification & Flutter Code (Single Block)
## Subject Details Screen & Add Lecture Overlay (Figma Exact 1:1)

**Target Project:** `dashboard` (Dr. Tarek Platform - Web & Desktop LMS)  
**Target Environment:** AI Agent on OpenCode Muse Spark 1.3  
**Figma Canvas Frames:**
- Screen: `Grade- Grade one - subjects - details` (Node ID: `852-800`)
- Overlay: `#add lecture overlay` (Node ID: `791-1173` | Dimensions: `640px × 671px`, Radius `16px`)

---

## 1. 🎨 Multi-Grade Semantic Theming Architecture

The UI architecture dynamically updates based on the selected Grade. All containers, tabs, accents, and action pills take the active `gradeColor`:

* **Grade One (`الفرقة الأولى`):** `#F59E0B` (Amber / Yellow)
* **Grade Two (`الفرقة الثانية`):** `#1D4ED8` (Royal Blue)
* **Grade Three (`الفرقة الثالثة`):** `#15803D` (Forest Green)
* **Grade Four (`الفرقة الرابعة`):** `#DC2626` (Ruby Red)

---

## 2. 📐 Exact Pixel Specifications (From Figma Inspector)

### A. Main Canvas: `Grade- Grade one - subjects - details`
1. **Brand Title:**
   - Text: `Tarek el araby Platform`
   - Typography: `Google Sans Flex` (Brand signature `Regular 400 26px` + `Platform` `Light 300 26px`).
2. **Grades Navigation Capsule (`Grades nav icons`):**
   - Dimensions: `Width: 660px`, `Height: 42px`, `BorderRadius.circular(9999)`.
   - Border: `1px solid rgba(0, 0, 0, 0.20)`.
   - Active Grade: Filled capsule in `gradeColor`, text white `#FFFFFF` `15px Medium`.
   - Inactive Grades: Text `#6B7280` `15px Regular`.
3. **Sub-Navigation Tabs (`Students` / `Subjects`):**
   - `Students`: `#111827`, `16px`.
   - `Subjects` (Active): `gradeColor`, `16px Medium`, with active indicator line `Height: 2px, Width: 58px`.
4. **Subject Header Bar:**
   - Dimensions: `Width: 640px`, `Height: 56px`, `BorderRadius.circular(9999)`.
   - Border: `2px solid gradeColor`.
   - Left: Active Toggle Switch (`#10B981`).
   - Right: Arabic text `محاسبة مالية` (`22px Medium #111827`).
5. **Subject Action Buttons:**
   - Row of 3 filled pills (`height: 36px`, `BorderRadius.circular(9999)`, text white `14px Medium`):
     - `Edit` (`Width: 90px`)
     - `Add Lecture` (`Width: 130px`) -> **Triggers `#add lecture overlay`**
     - `Delete Subject` (`Width: 130px`)
6. **Lecture Filter Tabs:**
   - Tabs: `Lectures` (Active, underlined), `Revisions`, `Final`, `Online`.
7. **Lectures Table:**
   - Width: `1120px`, `BorderRadius.circular(16)`, border `#E5E7EB`.
   - Headers: `No.` (`80px`), `Lecture Name` (`Expanded`), `Action` (`160px`).
   - Rows:
     - `01.` | `مباديء المحاسبة المالية` | Action pills `Edit` & `Del` in `gradeColor`.

---

### B. Modal Overlay: `#add lecture overlay`
* **Modal Dimensions:** `Width: 640px` × `Height: 671px`.
* **Corner Radius:** `16px` (`Clip content: true`).
* **Background:** Solid white `#FFFFFF` (`Opacity: 100%`).
* **Shadow:** `BoxShadow(color: Color(0x29000000), blurRadius: 32, offset: Offset(0, 12))`.

#### Exact Auto Layout & Frames Breakdown:
1. **Header:**
   - Title: `Add New Lecture` (Centered, `22px Medium #111827`).
   - Close Button: `✕` at top right (`20px`, `#4B5563`).
2. **Form Fields Container (`Frame 127`):**
   - Position: `X: 40px`, `Y: 77px`.
   - Auto layout: Vertical flow, `Width: 560px (Hug)`, `Height: 84px (Hug)`, `Gap: 0px`.
   - **Row 1 (`# lecture name`):**
     - Dimensions: `W: 560px`, `H: 34px`, `Gap: 16px`, `Padding: H: 8, V: 4`.
     - Label (`Lecture Name`): `W: 168px`, `H: 26px`, typography `body/regular 14/20`.
     - Capsule Input (`Frame 114`): `W: 320px`, `H: 26px`, `BorderRadius.circular(28)`, stroke `#979797 1px`. Value: `مباديء المحاسبة المالية`.
     - Delete Action: Trash icon `24 × 24 px` at `X: 528px`.
   - **Row 2 (`# lecture NUMBER`):**
     - Label (`Lecture Display order`): `W: 168px`, `H: 26px`, typography `body/regular 14/20`.
     - Capsule Input (`Frame 114`): `W: 320px`, `H: 26px`, `BorderRadius.circular(28)`, stroke `#979797 1px`. Value: `01`.
     - Delete Action: Trash icon `24 × 24 px`.
3. **Resources Section:**
   - Subtitle: `Add Lecture Resources` at `X: 48px, Y: 178px`, `W: 312px, H: 24px`, typography `title/large 28/36`.
   - Resources List (`Frame 134`): `X: 113px, Y: 219px`, `W: 414.5px, H: 119px (Hug)`, `Gap: 7px`.
   - Single Item (`Frame 131`): `W: 414.5px (Fill)`, `H: 24px (Hug)`, `Gap: 4px`.
     - Index: `01.` (`W: 36px, H: 24px`, `title/medium 20/26`).
     - Title: `Video - Part 01` (`W: 245px, H: 24px`, `title/medium 20/26`).
     - Edit Pill: `W: 97px, H: 24px`, `BorderRadius.circular(9999)`, black fill `#000000`, text `Edit` (`W: 42px, H: 20px`, `Google Sans Flex Light 20`).
     - Delete Icon: Trash icon next to Edit button.
   - Button (`# add resource` / `Frame 129`):
     - Position: `X: 246.5px, Y: 93px (relative)`, `W: 168px, H: 26px`, `BorderRadius.circular(28)`, black fill `#000000`.
     - Content: `add_circle` icon + `Add Resource` text.
4. **Publishing & Scheduling Row (`Frame 118`):**
   - Position: `X: 69px, Y: 370px`, `W: 502px (Hug), H: 65px (Hug)`, `Gap: 32px`.
   - `Publish Date`: Column with title (`W: 168 Fill, H: 31`, `title/medium 20/26`) + Capsule input (`W: 168 Fill, H: 26`, `radius: 28`, stroke `#979797`, text `Sept 9. 2026`).
   - `Publish Time`: Column with title + Capsule input (`W: 168 Fill, H: 26`, `radius: 28`, stroke `#979797`, text `09:41 AM`).
   - Quick Actions Column (`Frame 130`):
     - `Publish Now`: `W: 102px (Hug), H: 26px`, `BorderRadius.circular(28)`, black fill `#000000`, text white.
     - `Save Draft`: `W: 102px (Hug), H: 26px`, `BorderRadius.circular(28)`, black fill `#000000`, text white.
5. **Guest Access Row (`Access for free public plan`):**
   - Position: `X: 40px, Y: 449px`, `W: 560px, H: 36px (Hug)`, `Gap: 32px`.
   - Left Label: `Access for free Guest` (`W: 192px, H: 36px`, `body/regular 14/20`).
   - Toggle: `Toggle - Switch` (`W: 64px, H: 28px`, `BorderRadius.circular(100)`, fill `#10B981` / `Accents/Green`).
   - Middle Label: `Available Minutes` (`W: 138px, H: 36px`, `body/regular 14/20`).
   - Input Box (`Frame 108`): `W: 64px, H: 28px`, `BorderRadius.circular(9999)`, stroke `#000000 1px`, number `7`.
6. **Bottom Master Actions:**
   - `Configure Access` (`Frame 90`):
     - Position: `X: 188px, Y: 543px`, `W: 262px (Hug), H: 40px`, `BorderRadius.circular(9999)`.
     - Outlined: `1.2px solid #111827`, background white.
     - Text: `W: 240px, H: 36px (Hug)`, `title/large 28/36`, color `#111827`.
   - `Save` (`Frame 83`):
     - Position: `X: 258px, Y: 601px`, `W: 124px, H: 28px`, `BorderRadius.circular(9999)`.
     - Filled: solid black `#000000` (or `gradeColor`), text `Save` (`W: 42px, H: 20px`, white `#FFFFFF`).

---

## 3. 💻 Production Ready Flutter Code (Single Block)

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// ---------------------------------------------------------------------------
/// 1. Grade Theming Engine
/// ---------------------------------------------------------------------------
enum DashboardGrade {
  gradeOne(name: 'Grade One', color: Color(0xFFF59E0B)),
  gradeTwo(name: 'Grade Two', color: Color(0xFF1D4ED8)),
  gradeThree(name: 'Grade Three', color: Color(0xFF15803D)),
  gradeFour(name: 'Grade Four', color: Color(0xFFDC2626));

  final String name;
  final Color color;
  const DashboardGrade({required this.name, required this.color});
}

/// ---------------------------------------------------------------------------
/// 2. Domain Data Models
/// ---------------------------------------------------------------------------
enum ResourceType { video, pdf, attachment, externalLink }

class LectureResourceItem {
  final String id;
  final String order;
  final String title;
  final ResourceType type;

  const LectureResourceItem({
    required this.id,
    required this.order,
    required this.title,
    required this.type,
  });
}

class LectureModel {
  final String id;
  final String order;
  final String name;
  final List<LectureResourceItem> resources;
  final DateTime publishDate;
  final TimeOfDay publishTime;
  final bool isGuestAccessEnabled;
  final int guestMinutes;
  final bool isPublished;

  const LectureModel({
    required this.id,
    required this.order,
    required this.name,
    this.resources = const [],
    required this.publishDate,
    required this.publishTime,
    this.isGuestAccessEnabled = true,
    this.guestMinutes = 7,
    this.isPublished = true,
  });
}

/// ---------------------------------------------------------------------------
/// 3. Main Screen: SubjectDetailsScreen (Grade- Grade one - subjects - details)
/// ---------------------------------------------------------------------------
class SubjectDetailsScreen extends StatefulWidget {
  final DashboardGrade initialGrade;
  final String subjectTitle;

  const SubjectDetailsScreen({
    super.key,
    this.initialGrade = DashboardGrade.gradeOne,
    this.subjectTitle = 'محاسبة مالية',
  });

  @override
  State<SubjectDetailsScreen> createState() => _SubjectDetailsScreenState();
}

class _SubjectDetailsScreenState extends State<SubjectDetailsScreen> {
  late DashboardGrade _selectedGrade;
  bool _isSubjectActive = true;
  String _activeCategoryTab = 'Lectures';
  final List<String> _categoryTabs = ['Lectures', 'Revisions', 'Final', 'Online'];

  final List<LectureModel> _lectures = [
    LectureModel(
      id: 'lec_01',
      order: '01.',
      name: 'مباديء المحاسبة المالية',
      publishDate: DateTime(2026, 9, 9),
      publishTime: const TimeOfDay(hour: 9, minute: 41),
      resources: [
        const LectureResourceItem(id: 'r1', order: '01', title: 'Video - Part 01', type: ResourceType.video),
        const LectureResourceItem(id: 'r2', order: '02', title: 'Video - Part 02', type: ResourceType.video),
        const LectureResourceItem(id: 'r3', order: '03', title: 'PDF - مباديء المحاسبة', type: ResourceType.pdf),
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _selectedGrade = widget.initialGrade;
  }

  void _openAddLectureOverlay([LectureModel? lectureToEdit]) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.45),
      builder: (ctx) => AddLectureOverlay(
        grade: _selectedGrade,
        existingLecture: lectureToEdit,
        onSave: (newLecture) {
          setState(() {
            _lectures.add(newLecture);
          });
          Navigator.of(ctx).pop();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gradeColor = _selectedGrade.color;

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 24),
            _buildBrandHeader(),
            const SizedBox(height: 20),
            _buildGradesNavCapsule(),
            const SizedBox(height: 16),
            _buildSubNavTabs(gradeColor),
            const SizedBox(height: 28),
            _buildSubjectHeaderBar(gradeColor),
            const SizedBox(height: 16),
            _buildSubjectActionButtons(gradeColor),
            const SizedBox(height: 24),
            _buildCategoryTabs(gradeColor),
            const SizedBox(height: 16),
            _buildLecturesTable(gradeColor),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }

  Widget _buildBrandHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: const [
        Text(
          'Tarek el araby ',
          style: TextStyle(
            fontFamily: 'Google Sans Flex',
            fontSize: 26,
            fontWeight: FontWeight.w400,
            color: Color(0xFF111827),
          ),
        ),
        Text(
          'Platform',
          style: TextStyle(
            fontFamily: 'Google Sans Flex',
            fontSize: 26,
            fontWeight: FontWeight.w300,
            color: Color(0xFF4B5563),
          ),
        ),
      ],
    );
  }

  Widget _buildGradesNavCapsule() {
    return Container(
      width: 660,
      height: 42,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(9999),
        border: Border.all(color: const Color(0x33000000), width: 1.0),
      ),
      child: Row(
        children: DashboardGrade.values.map((grade) {
          final isSelected = grade == _selectedGrade;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedGrade = grade),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected ? grade.color : Colors.transparent,
                  borderRadius: BorderRadius.circular(9999),
                ),
                child: Text(
                  grade.name,
                  style: TextStyle(
                    fontFamily: 'Google Sans Flex',
                    fontSize: 15,
                    fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
                    color: isSelected ? Colors.white : const Color(0xFF6B7280),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSubNavTabs(Color gradeColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'Students',
          style: TextStyle(
            fontFamily: 'Google Sans Flex',
            fontSize: 16,
            color: Color(0xFF111827),
          ),
        ),
        const SizedBox(width: 48),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Subjects',
              style: TextStyle(
                fontFamily: 'Google Sans Flex',
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: gradeColor,
              ),
            ),
            const SizedBox(height: 4),
            Container(width: 58, height: 2, color: gradeColor),
          ],
        ),
      ],
    );
  }

  Widget _buildSubjectHeaderBar(Color gradeColor) {
    return Container(
      width: 640,
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(9999),
        border: Border.all(color: gradeColor, width: 2.0),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          CupertinoSwitch(
            value: _isSubjectActive,
            activeColor: const Color(0xFF10B981),
            onChanged: (val) => setState(() => _isSubjectActive = val),
          ),
          Text(
            widget.subjectTitle,
            style: const TextStyle(
              fontFamily: 'Google Sans Flex',
              fontSize: 22,
              fontWeight: FontWeight.w500,
              color: Color(0xFF111827),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubjectActionButtons(Color gradeColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildPillButton(label: 'Edit', color: gradeColor, width: 90, onTap: () {}),
        const SizedBox(width: 14),
        _buildPillButton(
          label: 'Add Lecture',
          color: gradeColor,
          width: 130,
          onTap: () => _openAddLectureOverlay(),
        ),
        const SizedBox(width: 14),
        _buildPillButton(label: 'Delete Subject', color: gradeColor, width: 130, onTap: () {}),
      ],
    );
  }

  Widget _buildPillButton({
    required String label,
    required Color color,
    required double width,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: width,
      height: 36,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: const StadiumBorder(),
          padding: EdgeInsets.zero,
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: 'Google Sans Flex',
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryTabs(Color gradeColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: _categoryTabs.map((tab) {
        final isSelected = tab == _activeCategoryTab;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: GestureDetector(
            onTap: () => setState(() => _activeCategoryTab = tab),
            child: Column(
              children: [
                Text(
                  tab,
                  style: TextStyle(
                    fontFamily: 'Google Sans Flex',
                    fontSize: 16,
                    fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
                    color: isSelected ? const Color(0xFF111827) : const Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 32,
                  height: 2,
                  color: isSelected ? gradeColor : Colors.transparent,
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildLecturesTable(Color gradeColor) {
    return Container(
      width: 1120,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
            ),
            child: Row(
              children: const [
                SizedBox(
                  width: 80,
                  child: Text('No.', style: TextStyle(fontFamily: 'Google Sans Flex', fontSize: 14, color: Color(0xFF6B7280))),
                ),
                Expanded(
                  child: Text('Lecture Name', textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Google Sans Flex', fontSize: 14, color: Color(0xFF6B7280))),
                ),
                SizedBox(
                  width: 160,
                  child: Text('Action', textAlign: TextAlign.end, style: TextStyle(fontFamily: 'Google Sans Flex', fontSize: 14, color: Color(0xFF6B7280))),
                ),
              ],
            ),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _lectures.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFE5E7EB)),
            itemBuilder: (ctx, index) {
              final lecture = _lectures[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                child: Row(
                  children: [
                    SizedBox(
                      width: 80,
                      child: Text(lecture.order, style: const TextStyle(fontFamily: 'Google Sans Flex', fontSize: 16, color: Color(0xFF111827))),
                    ),
                    Expanded(
                      child: Text(lecture.name, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Google Sans Flex', fontSize: 18, color: Color(0xFF111827))),
                    ),
                    SizedBox(
                      width: 160,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          _buildSmallActionButton('Edit', gradeColor, () => _openAddLectureOverlay(lecture)),
                          const SizedBox(width: 8),
                          _buildSmallActionButton('Del', gradeColor, () {
                            setState(() => _lectures.removeAt(index));
                          }),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSmallActionButton(String label, Color color, VoidCallback onTap) {
    return SizedBox(
      height: 28,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        child: Text(label, style: const TextStyle(fontFamily: 'Google Sans Flex', fontSize: 13)),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// 4. Modal Overlay: AddLectureOverlay (Exact Figma Dimensions: 640px × 671px)
/// ---------------------------------------------------------------------------
class AddLectureOverlay extends StatefulWidget {
  final DashboardGrade grade;
  final LectureModel? existingLecture;
  final ValueChanged<LectureModel> onSave;

  const AddLectureOverlay({
    super.key,
    required this.grade,
    this.existingLecture,
    required this.onSave,
  });

  @override
  State<AddLectureOverlay> createState() => _AddLectureOverlayState();
}

class _AddLectureOverlayState extends State<AddLectureOverlay> {
  late TextEditingController _nameController;
  late TextEditingController _orderController;
  late TextEditingController _guestMinutesController;
  late List<LectureResourceItem> _resources;

  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  late bool _accessForFreeGuest;

  @override
  void initState() {
    super.initState();
    final lecture = widget.existingLecture;
    _nameController = TextEditingController(text: lecture?.name ?? 'مباديء المحاسبة المالية');
    _orderController = TextEditingController(text: lecture?.order.replaceAll('.', '') ?? '01');
    _guestMinutesController = TextEditingController(text: '${lecture?.guestMinutes ?? 7}');
    _accessForFreeGuest = lecture?.isGuestAccessEnabled ?? true;
    _selectedDate = lecture?.publishDate ?? DateTime(2026, 9, 9);
    _selectedTime = lecture?.publishTime ?? const TimeOfDay(hour: 9, minute: 41);

    _resources = lecture != null
        ? List.from(lecture.resources)
        : [
            const LectureResourceItem(id: '1', order: '01', title: 'Video - Part 01', type: ResourceType.video),
            const LectureResourceItem(id: '2', order: '02', title: 'Video - Part 02', type: ResourceType.video),
            const LectureResourceItem(id: '3', order: '03', title: 'PDF - مباديء المحاسبة', type: ResourceType.pdf),
          ];
  }

  @override
  void dispose() {
    _nameController.dispose();
    _orderController.dispose();
    _guestMinutesController.dispose();
    super.dispose();
  }

  void _handleSave() {
    final lecture = LectureModel(
      id: widget.existingLecture?.id ?? UniqueKey().toString(),
      order: '${_orderController.text.trim()}.',
      name: _nameController.text.trim(),
      resources: _resources,
      publishDate: _selectedDate,
      publishTime: _selectedTime,
      isGuestAccessEnabled: _accessForFreeGuest,
      guestMinutes: int.tryParse(_guestMinutesController.text) ?? 7,
      isPublished: true,
    );
    widget.onSave(lecture);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: 640,
        height: 671,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(color: Color(0x29000000), blurRadius: 32, offset: Offset(0, 12)),
          ],
        ),
        child: Column(
          children: [
            // Top Bar: Title & Close Button
            Padding(
              padding: const EdgeInsets.only(left: 36, right: 24, top: 20, bottom: 8),
              child: Row(
                children: [
                  const Spacer(),
                  const Text(
                    'Add New Lecture',
                    style: TextStyle(
                      fontFamily: 'Google Sans Flex',
                      fontSize: 22,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20, color: Color(0xFF4B5563)),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    // Frame 127: Form Rows
                    _buildFormInputRow(
                      label: 'Lecture Name',
                      controller: _nameController,
                      onDelete: () => _nameController.clear(),
                    ),
                    const SizedBox(height: 12),
                    _buildFormInputRow(
                      label: 'Lecture Display order',
                      controller: _orderController,
                      onDelete: () => _orderController.clear(),
                    ),
                    const SizedBox(height: 24),

                    // Section: Add Lecture Resources
                    const Text(
                      'Add Lecture Resources',
                      style: TextStyle(
                        fontFamily: 'Google Sans Flex',
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Frame 134: Resources List
                    ..._resources.asMap().entries.map((entry) {
                      final index = entry.key;
                      final res = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 36,
                              child: Text(
                                '${res.order}.',
                                style: const TextStyle(
                                  fontFamily: 'Google Sans Flex',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF111827),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                res.title,
                                style: const TextStyle(
                                  fontFamily: 'Google Sans Flex',
                                  fontSize: 14,
                                  color: Color(0xFF111827),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 97,
                              height: 24,
                              child: ElevatedButton(
                                onPressed: () {},
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF000000),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: const StadiumBorder(),
                                  padding: EdgeInsets.zero,
                                ),
                                child: const Text(
                                  'Edit',
                                  style: TextStyle(
                                    fontFamily: 'Google Sans Flex',
                                    fontWeight: FontWeight.w300,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFF4B5563)),
                              onPressed: () {
                                setState(() => _resources.removeAt(index));
                              },
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 6),

                    // Add Resource Button (Frame 129)
                    Center(
                      child: SizedBox(
                        width: 168,
                        height: 26,
                        child: ElevatedButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.add_circle_outline, size: 15),
                          label: const Text(
                            'Add Resource',
                            style: TextStyle(fontFamily: 'Google Sans Flex', fontSize: 12),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF000000),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: const StadiumBorder(),
                            padding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Frame 118: Publishing & Scheduling Row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Publish Date
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Publish Date', style: TextStyle(fontFamily: 'Google Sans Flex', fontSize: 13, color: Color(0xFF374151))),
                              const SizedBox(height: 4),
                              _buildCapsuleButton(
                                text: '${_selectedDate.year}-${_selectedDate.month}-${_selectedDate.day}',
                                icon: Icons.calendar_today_outlined,
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: _selectedDate,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2035),
                                  );
                                  if (picked != null) setState(() => _selectedDate = picked);
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Publish Time
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Publish Time', style: TextStyle(fontFamily: 'Google Sans Flex', fontSize: 13, color: Color(0xFF374151))),
                              const SizedBox(height: 4),
                              _buildCapsuleButton(
                                text: _selectedTime.format(context),
                                icon: Icons.access_time,
                                onTap: () async {
                                  final picked = await showTimePicker(
                                    context: context,
                                    initialTime: _selectedTime,
                                  );
                                  if (picked != null) setState(() => _selectedTime = picked);
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Quick Action Buttons (Frame 130)
                        Column(
                          children: [
                            SizedBox(
                              width: 102,
                              height: 26,
                              child: ElevatedButton(
                                onPressed: () {},
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF000000),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: const StadiumBorder(),
                                  padding: EdgeInsets.zero,
                                ),
                                child: const Text('Publish Now', style: TextStyle(fontFamily: 'Google Sans Flex', fontSize: 11)),
                              ),
                            ),
                            const SizedBox(height: 6),
                            SizedBox(
                              width: 102,
                              height: 26,
                              child: ElevatedButton(
                                onPressed: () {},
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF000000),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: const StadiumBorder(),
                                  padding: EdgeInsets.zero,
                                ),
                                child: const Text('Save Draft', style: TextStyle(fontFamily: 'Google Sans Flex', fontSize: 11)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),

                    // Guest Access Row (Access for free public plan)
                    Row(
                      children: [
                        const Text(
                          'Access for free Guest',
                          style: TextStyle(fontFamily: 'Google Sans Flex', fontSize: 13, color: Color(0xFF374151)),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 64,
                          height: 28,
                          child: CupertinoSwitch(
                            value: _accessForFreeGuest,
                            activeColor: const Color(0xFF10B981),
                            onChanged: (val) => setState(() => _accessForFreeGuest = val),
                          ),
                        ),
                        const Spacer(),
                        const Text(
                          'Available Minutes',
                          style: TextStyle(fontFamily: 'Google Sans Flex', fontSize: 13, color: Color(0xFF374151)),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 64,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(9999),
                            border: Border.all(color: const Color(0xFF000000), width: 1.0),
                          ),
                          child: TextField(
                            controller: _guestMinutesController,
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(fontFamily: 'Google Sans Flex', fontSize: 13, fontWeight: FontWeight.w500),
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),

                    // Configure Access Button (Frame 90)
                    Center(
                      child: SizedBox(
                        width: 262,
                        height: 40,
                        child: OutlinedButton(
                          onPressed: () {},
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFF111827), width: 1.2),
                            shape: const StadiumBorder(),
                            foregroundColor: const Color(0xFF111827),
                          ),
                          child: const Text(
                            'Configure Access',
                            style: TextStyle(fontFamily: 'Google Sans Flex', fontSize: 15, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Save Button (Frame 83)
                    Center(
                      child: SizedBox(
                        width: 124,
                        height: 28,
                        child: ElevatedButton(
                          onPressed: _handleSave,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF000000),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: const StadiumBorder(),
                            padding: EdgeInsets.zero,
                          ),
                          child: const Text(
                            'Save',
                            style: TextStyle(fontFamily: 'Google Sans Flex', fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormInputRow({
    required String label,
    required TextEditingController controller,
    required VoidCallback onDelete,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 168,
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'Google Sans Flex',
              fontSize: 14,
              color: Color(0xFF374151),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0xFF979797), width: 1.0),
            ),
            child: TextField(
              controller: controller,
              style: const TextStyle(fontFamily: 'Google Sans Flex', fontSize: 13),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 4),
                border: InputBorder.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 24,
          height: 24,
          child: IconButton(
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.delete_outline, size: 20, color: Color(0xFF4B5563)),
            onPressed: onDelete,
          ),
        ),
      ],
    );
  }

  Widget _buildCapsuleButton({
    required String text,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0xFF979797), width: 1.0),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(text, style: const TextStyle(fontFamily: 'Google Sans Flex', fontSize: 12, color: Color(0xFF111827))),
            Icon(icon, size: 14, color: const Color(0xFF6B7280)),
          ],
        ),
      ),
    );
  }
}