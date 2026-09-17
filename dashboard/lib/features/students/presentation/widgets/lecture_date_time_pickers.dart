import 'package:flutter/material.dart';

/// Figma-style pickers for the Add New Lecture form.
///
/// - Date: calendar popup (month navigation, year selection, day grid,
///   selected-day state). Tapping a day selects and closes; Cancel or
///   outside-tap preserves the previous value; reopening starts from the
///   current selection.
/// - Time: wheel picker (hour 1–12, minute 00–59, AM/PM) with explicit
///   Cancel/Set — dismissing without Set never overwrites the previous
///   value; reopening starts from the current selection.
///
/// Pure presentation: no Firestore, no business rules. Date and time are
/// independent values combined only at save time by the caller.

const List<String> _monthNames = <String>[
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

const List<String> _monthShort = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

const List<String> _weekdayHeaders = <String>[
  'Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa',
];

String formatLectureDate(DateTime date) =>
    '${date.day} ${_monthShort[date.month - 1]} ${date.year}';

/// 12-hour clock value picked by [showLectureTimePicker].
class LectureTime {
  final int hour; // 1–12
  final int minute; // 0–59
  final bool isAm;

  const LectureTime({
    required this.hour,
    required this.minute,
    required this.isAm,
  });

  String format() {
    final String hh = hour.toString().padLeft(2, '0');
    final String mm = minute.toString().padLeft(2, '0');
    return '$hh:$mm ${isAm ? 'AM' : 'PM'}';
  }
}

/// Calendar dialog. Returns the picked day, or null when canceled or
/// dismissed (caller keeps the previous value).
Future<DateTime?> showLectureDatePicker({
  required BuildContext context,
  DateTime? initialDate,
  required Color gradeColor,
}) {
  final DateTime now = DateTime.now();
  return showDialog<DateTime>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.25),
    builder: (BuildContext context) => Center(
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: _CalendarPicker(
          initialDate: initialDate ?? now,
          gradeColor: gradeColor,
        ),
      ),
    ),
  );
}

class _CalendarPicker extends StatefulWidget {
  final DateTime initialDate;
  final Color gradeColor;

  const _CalendarPicker({
    required this.initialDate,
    required this.gradeColor,
  });

  @override
  State<_CalendarPicker> createState() => _CalendarPickerState();
}

class _CalendarPickerState extends State<_CalendarPicker> {
  late int _year = widget.initialDate.year;
  late int _month = widget.initialDate.month;

  static const int _minYear = 2024;
  static const int _maxYear = 2100;

  void _shiftMonth(int delta) {
    int month = _month + delta;
    int year = _year;
    while (month < 1) {
      month += 12;
      year -= 1;
    }
    while (month > 12) {
      month -= 12;
      year += 1;
    }
    if (year < _minYear || year > _maxYear) return;
    setState(() {
      _month = month;
      _year = year;
    });
  }

  @override
  Widget build(BuildContext context) {
    final int daysInMonth = DateTime(_year, _month + 1, 0).day;
    // Sunday-first offset: DateTime.weekday is Mon=1..Sun=7.
    final int leading =
        DateTime(_year, _month, 1).weekday % 7;
    final DateTime today = DateTime.now();
    final bool isCurrentMonth =
        today.year == _year && today.month == _month;

    return Container(
      width: 340,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 30,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => _shiftMonth(-1),
                icon: const Icon(Icons.chevron_left),
                tooltip: 'Previous month',
              ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        _monthNames[_month - 1],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Google Sans Flex',
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF111827),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _year,
                        isDense: true,
                        icon: const Icon(Icons.arrow_drop_down, size: 18),
                        style: const TextStyle(
                          fontFamily: 'Google Sans Flex',
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF111827),
                        ),
                        items: [
                          for (int y = _minYear; y <= _maxYear; y++)
                            DropdownMenuItem<int>(
                              value: y,
                              child: Text('$y'),
                            ),
                        ],
                        onChanged: (int? y) {
                          if (y != null) setState(() => _year = y);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _shiftMonth(1),
                icon: const Icon(Icons.chevron_right),
                tooltip: 'Next month',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final String d in _weekdayHeaders)
                Expanded(
                  child: Text(
                    d,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Google Sans Flex',
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
            ),
            itemCount: leading + daysInMonth,
            itemBuilder: (BuildContext context, int index) {
              if (index < leading) return const SizedBox.shrink();
              final int day = index - leading + 1;
              final bool selected =
                  widget.initialDate.year == _year &&
                      widget.initialDate.month == _month &&
                      widget.initialDate.day == day;
              final bool isToday =
                  isCurrentMonth && today.day == day;
              return GestureDetector(
                onTap: () => Navigator.of(context)
                    .pop(DateTime(_year, _month, day)),
                child: Container(
                  alignment: Alignment.center,
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: selected
                        ? widget.gradeColor
                        : Colors.transparent,
                    shape: BoxShape.circle,
                    border: isToday && !selected
                        ? Border.all(color: widget.gradeColor)
                        : null,
                  ),
                  child: Text(
                    '$day',
                    style: TextStyle(
                      fontFamily: 'Google Sans Flex',
                      fontSize: 14,
                      color: selected
                          ? Colors.white
                          : const Color(0xFF111827),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Wheel time-picker dialog. Returns the confirmed value, or null when
/// canceled or dismissed (caller keeps the previous value).
Future<LectureTime?> showLectureTimePicker({
  required BuildContext context,
  LectureTime? initialTime,
  required Color gradeColor,
}) {
  return showDialog<LectureTime>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.25),
    builder: (BuildContext context) => Center(
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: _WheelTimePicker(
          initialTime: initialTime ??
              const LectureTime(hour: 9, minute: 0, isAm: true),
          gradeColor: gradeColor,
        ),
      ),
    ),
  );
}

class _WheelTimePicker extends StatefulWidget {
  final LectureTime initialTime;
  final Color gradeColor;

  const _WheelTimePicker({
    required this.initialTime,
    required this.gradeColor,
  });

  @override
  State<_WheelTimePicker> createState() => _WheelTimePickerState();
}

class _WheelTimePickerState extends State<_WheelTimePicker> {
  late FixedExtentScrollController _hourController;
  late FixedExtentScrollController _minuteController;
  late FixedExtentScrollController _periodController;

  @override
  void initState() {
    super.initState();
    _hourController =
        FixedExtentScrollController(initialItem: widget.initialTime.hour - 1);
    _minuteController = FixedExtentScrollController(
        initialItem: widget.initialTime.minute);
    _periodController = FixedExtentScrollController(
        initialItem: widget.initialTime.isAm ? 0 : 1);
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    _periodController.dispose();
    super.dispose();
  }

  LectureTime _current() => LectureTime(
        hour: _hourController.selectedItem + 1,
        minute: _minuteController.selectedItem,
        isAm: _periodController.selectedItem == 0,
      );

  @override
  Widget build(BuildContext context) {
    TextStyle itemStyle(bool selected) => TextStyle(
          fontFamily: 'Google Sans Flex',
          fontSize: selected ? 22 : 16,
          fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
          color: selected ? widget.gradeColor : const Color(0xFF6B7280),
        );

    Widget wheel({
      required FixedExtentScrollController controller,
      required int itemCount,
      required String Function(int) label,
      required Key key,
    }) {
      return Expanded(
        child: SizedBox(
          height: 150,
          child: ListWheelScrollView.useDelegate(
            key: key,
            controller: controller,
            itemExtent: 40,
            perspective: 0.005,
            physics: const FixedExtentScrollPhysics(),
            onSelectedItemChanged: (_) => setState(() {}),
            childDelegate: ListWheelChildBuilderDelegate(
              childCount: itemCount,
              builder: (BuildContext context, int index) {
                final bool selected =
                    controller.selectedItem == index;
                return Center(
                    child: Text(label(index),
                        style: itemStyle(selected)));
              },
            ),
          ),
        ),
      );
    }

    return Container(
      width: 320,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 30,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Publish Time',
            style: TextStyle(
              fontFamily: 'Google Sans Flex',
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              wheel(
                key: const Key('hourWheel'),
                controller: _hourController,
                itemCount: 12,
                label: (int i) =>
                    (i + 1).toString().padLeft(2, '0'),
              ),
              const Text(':',
                  style: TextStyle(
                      fontSize: 22, color: Color(0xFF111827))),
              wheel(
                key: const Key('minuteWheel'),
                controller: _minuteController,
                itemCount: 60,
                label: (int i) => i.toString().padLeft(2, '0'),
              ),
              wheel(
                key: const Key('periodWheel'),
                controller: _periodController,
                itemCount: 2,
                label: (int i) => i == 0 ? 'AM' : 'PM',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () =>
                    Navigator.of(context).pop(_current()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.gradeColor,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9999),
                  ),
                ),
                child: const Text('Set'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
