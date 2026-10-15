# 🔍 Interactive Component Specification: Scoped Search Bar (`Scoped Search Bar`)

---

## 1. 📋 Component Overview (نظرة عامة والهدف)
مكون تفاعلي ذو 8 حالات (8-Variant Interactive Component Set) يمثل شريط البحث الذكي محدد النطاق (Scoped Search Bar) في لوحة تحكم المنصة التعليمية (Tarek el araby Platform - Dashboard).
يتيح الشريط للمستخدم البحث في جداول وقوائم الطلاب من خلال نقطة إدخال واحدة موحدة ومرنة، مع إمكانية تبديل نطاق وفلترة البحث بنقرة واحدة بين 4 معايير أساسية:
1. الاسم (`Name`): للبحث باسم الطالب أو كوده.
2. النوع (`Type`): لتصفية طلاب السنتر أو الأونلاين (Center vs Public).
3. الباقة (`Plan`): لتصفية الطلاب حسب باقات الاشتراك (FREE / PRO / MAX).
4. الحالة (`Status`): لتصفية الطلاب النشطين أو غير المفعلين (Active vs Inactive / Des Action).

---

## 2. 📐 Master Component Anatomy & Tokens (الهيكل العام والأبعاد)

### أ) شريط الإدخال الأساسي (Input Bar Container):
* اسم المكون في Figma: `❖ Scoped Search Bar`
* الأبعاد (في الحالة المقفولة): العرض 420px × الارتفاع 44px.
* انحناء الحواف (Corner Radius): 16px كبسولة ناعمة.
* الخلفية (Fill): أبيض نقي #FFFFFF (100%).
* الحدود (Stroke): 1px solid #E5E7EB (رمادي ناعم محايد).
* التوزيع الداخلي (Auto Layout Row):
  * الجهة اليسرى (محدد النطاق Scope Selector):
    * السهم التفاعلي: أيقونة سهم (في المقفول keyboard_arrow_down وفي المفتوح keyboard_arrow_up) بمقاس 18px × 18px ولون #374151.
    * نص النطاق النشط: خط Google Sans Flex Regular 14px ولون أسود داكن #111827.
  * الخط الفاصل (Vertical Divider Line 15):
    * خط رأسي بسمك 1px، ارتفاع 20px، ولون رمادي فاتح #E5E7EB بمسافة هامش 12px يميناً ويساراً.
  * الجهة اليمنى (حقل النص الإرشادي Placeholder):
    * نص متغير حسب النطاق: خط Google Sans Flex Regular 14px، ولون رمادي هادئ #9CA3AF.

---

### ب) القائمة المنسدلة المرفقة (Dropdown Menu Card):
* الأبعاد: العرض 160px × الارتفاع 180px.
* الموقع: تتمركز أسفل محدد النطاق مباشرة بمسافة رأسية 4px (داخل الحالات المفتوحة open).
* انحناء الحواف (Corner Radius): 16px.
* الخلفية والحدود: خلفية بيضاء #FFFFFF، إطار ناعم 1px solid #E5E7EB.
* الظل (Drop Shadow): Y: 8px, Blur: 20px, Opacity: 8% (rgba(0, 0, 0, 0.08)).
* العناصر الداخلية الأربعة (Auto Layout Vertical, Gap: 4px):
  * كل عنصر عبارة عن شريط أفقي بأبعاد Width: 100%, Height: 36px بحواف 8px وبادينج أيسر 12px.
  * العنصر النشط/المحدد (Active / Hover State): يكتسب خلفية رمادية ناعمة #F3F4F6 لتمييز النطاق الحالي.
  * العناصر غير النشطة: خلفية شفافة ونصوص بلون #374151.

---

## 3. 🧩 All 8 Component Variants (تفصيل الحالات الثمانية)

| اسم الـ Variant | الحالة (State) | اتجاه السهم | النص المعروض في الصندوق | التظليل الرمادي في القائمة المنسدلة |
| :--- | :---: | :---: | :--- | :---: |
| **`name`** | مقفول (44px) | أسفل `▾` | `Name` \| `Search by Name...` | - |
| **`name open`** | مفتوح (230px) | أعلى `▴` | `Name` \| `Search by Name...` | مظلل على كلمة **`Name`** |
| **`type`** | مقفول (44px) | أسفل `▾` | `Type` \| `Search by Type...` | - |
| **`type open`** | مفتوح (230px) | أعلى `▴` | `Type` \| `Search by Type...` | مظلل على كلمة **`Type`** |
| **`plan`** | مقفول (44px) | أسفل `▾` | `Plan` \| `Search by Plan...` | - |
| **`plan open`** | مفتوح (230px) | أعلى `▴` | `Plan` \| `Search by Plan...` | مظلل على كلمة **`Plan`** |
| **`status`** | مقفول (44px) | أسفل `▾` | `Status` \| `Search by Status...` | - |
| **`status open`** | مفتوح (230px) | أعلى `▴` | `Status` \| `Search by Status...` | مظلل على كلمة **`Status`** |

---

## 4. 🎬 Interactive Prototype Wiring Matrix (مصفوفة التوصيل البرمجي)

### 1. أسهم الفتح (Open Triggers):
من أي صندوق مقفول، النقر على كلمة النطاق أو السهم لأسفل يفتح الحالة المطابقة:
* من `name` ➔ On click ➔ Change to: name open (Smart animate, 150ms).
* من `type` ➔ On click ➔ Change to: type open (Smart animate, 150ms).
* من `plan` ➔ On click ➔ Change to: plan open (Smart animate, 150ms).
* من `status` ➔ On click ➔ Change to: status open (Smart animate, 150ms).

### 2. أسهم الإغلاق (Close Triggers):
من أي صندوق مفتوح، النقر على كلمة النطاق أو السهم لأعلى يغلق القائمة ويعود لنفس الحالة المقفولة:
* من `name open` (النقر على الرأس) ➔ Change to: name.
* من `type open` (النقر على الرأس) ➔ Change to: type.
* من `plan open` (النقر على الرأس) ➔ Change to: plan.
* من `status open` (النقر على الرأس) ➔ Change to: status.

### 3. أسهم الاختيار والتحويل (Selection Triggers):
من داخل القائمة المنسدلة في أي حالة مفتوحة، النقر على أي خيار يغير الصندوق للحالة المقفولة المختارة فوراً:
* النقر على سطر `Name` ➔ Change to: name.
* النقر على سطر `Type` ➔ Change to: type.
* النقر على سطر `Plan` ➔ Change to: plan.
* النقر على سطر `Status` ➔ Change to: status.

---

## 5. 💻 Flutter Production Code Reference (مرجع الكود الجاهز للتنفيذ)

```dart
// lib/features/students/presentation/widgets/scoped_search_bar.dart
import 'package:flutter/material.dart';

enum SearchScope {
  name('Name', 'Search by Name...'),
  type('Type', 'Search by Type (Center / Public)...'),
  plan('Plan', 'Search by Plan (FREE / PRO / MAX)...'),
  status('Status', 'Search by Status (Active / Inactive)...');

  final String label;
  final String placeholder;
  const SearchScope(this.label, this.placeholder);
}

class ScopedSearchBar extends StatefulWidget {
  final ValueChanged<String>? onSearchChanged;
  final ValueChanged<SearchScope>? onScopeChanged;

  const ScopedSearchBar({
    super.key,
    this.onSearchChanged,
    this.onScopeChanged,
  });

  @override
  State<ScopedSearchBar> createState() => _ScopedSearchBarState();
}

class _ScopedSearchBarState extends State<ScopedSearchBar> {
  SearchScope _currentScope = SearchScope.name;
  bool _isOpen = false;
  final TextEditingController _textController = TextEditingController();
  final OverlayPortalController _overlayController = OverlayPortalController();
  final LayerLink _layerLink = LayerLink();

  void _selectScope(SearchScope scope) {
    setState(() {
      _currentScope = scope;
      _isOpen = false;
      _overlayController.hide();
    });
    widget.onScopeChanged?.call(scope);
  }

  void _toggleDropdown() {
    setState(() {
      _isOpen = !_isOpen;
      if (_isOpen) {
        _overlayController.show();
      } else {
        _overlayController.hide();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: OverlayPortal(
        controller: _overlayController,
        overlayChildBuilder: (context) {
          return CompositedTransformFollower(
            link: _layerLink,
            targetAnchor: Alignment.bottomLeft,
            followerAnchor: Alignment.topLeft,
            offset: const Offset(0, 6),
            child: Align(
              alignment: Alignment.topLeft,
              child: _buildDropdownMenu(),
            ),
          );
        },
        child: Container(
          width: 420,
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(
            children: [
              // Scope Selector Button
              InkWell(
                onTap: _toggleDropdown,
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isOpen
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: const Color(0xFF374151),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _currentScope.label,
                      style: const TextStyle(
                        fontFamily: 'GoogleSansFlex',
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF111827),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Vertical Divider
              Container(
                width: 1,
                height: 20,
                color: const Color(0xFFE5E7EB),
              ),
              const SizedBox(width: 12),
              // Search Input Text Field
              Expanded(
                child: TextField(
                  controller: _textController,
                  onChanged: widget.onSearchChanged,
                  style: const TextStyle(
                    fontFamily: 'GoogleSansFlex',
                    fontSize: 14,
                    color: Color(0xFF111827),
                  ),
                  decoration: InputDecoration(
                    hintText: _currentScope.placeholder,
                    hintStyle: const TextStyle(
                      fontFamily: 'GoogleSansFlex',
                      fontSize: 14,
                      color: Color(0xFF9CA3AF),
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDropdownMenu() {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: SearchScope.values.map((scope) {
          final isSelected = scope == _currentScope;
          return InkWell(
            onTap: () => _selectScope(scope),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: double.infinity,
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFF3F4F6) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.centerLeft,
              child: Text(
                scope.label,
                style: TextStyle(
                  fontFamily: 'GoogleSansFlex',
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? const Color(0xFF111827) : const Color(0xFF374151),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}