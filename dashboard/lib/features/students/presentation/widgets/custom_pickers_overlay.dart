import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// ---------------------------------------------------------------------------
/// 1. Custom Calendar Date Overlay (Exact Figma 318px Width)
/// ---------------------------------------------------------------------------
class CalendarDateOverlay extends StatefulWidget {
  final DateTime initialDate;
  final ValueChanged<DateTime>? onSaveDate;

  const CalendarDateOverlay({
    super.key,
    required this.initialDate,
    this.onSaveDate,
  });

  static Future<DateTime?> show(BuildContext context, {required DateTime initialDate}) {
    return showDialog<DateTime>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.25),
      builder: (context) => CalendarDateOverlay(initialDate: initialDate),
    );
  }

  @override
  State<CalendarDateOverlay> createState() => _CalendarDateOverlayState();
}

class _CalendarDateOverlayState extends State<CalendarDateOverlay> {
  late DateTime _selectedDate;
  late int _currentMonth;
  late int _currentYear;

  final List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  final List<String> _weekdays = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
    _currentMonth = _selectedDate.month;
    _currentYear = _selectedDate.year;
  }

  void _prevMonth() {
    setState(() {
      if (_currentMonth == 1) {
        _currentMonth = 12;
        _currentYear--;
      } else {
        _currentMonth--;
      }
    });
  }

  void _nextMonth() {
    setState(() {
      if (_currentMonth == 12) {
        _currentMonth = 1;
        _currentYear++;
      } else {
        _currentMonth++;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateUtils.getDaysInMonth(_currentYear, _currentMonth);
    final firstDayOffset = DateTime(_currentYear, _currentMonth, 1).weekday % 7;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 318,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color(0x29000000),
                blurRadius: 32,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header: < Month Year >
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left, size: 20),
                    onPressed: _prevMonth,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  Row(
                    children: [
                      Text(
                        _months[_currentMonth - 1],
                        style: const TextStyle(
                          fontFamily: 'Google Sans Flex',
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$_currentYear',
                        style: const TextStyle(
                          fontFamily: 'Google Sans Flex',
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF111827),
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right, size: 20),
                    onPressed: _nextMonth,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Weekdays Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: _weekdays.map((day) {
                  return SizedBox(
                    width: 36,
                    child: Text(
                      day,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Google Sans Flex',
                        fontSize: 12,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),

              // Days Grid
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: firstDayOffset + daysInMonth,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                ),
                itemBuilder: (context, index) {
                  if (index < firstDayOffset) {
                    return const SizedBox();
                  }
                  final day = index - firstDayOffset + 1;
                  final isSelected = _selectedDate.year == _currentYear &&
                      _selectedDate.month == _currentMonth &&
                      _selectedDate.day == day;

                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedDate = DateTime(_currentYear, _currentMonth, day);
                      });
                    },
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.black : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$day',
                        style: TextStyle(
                          fontFamily: 'Google Sans Flex',
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
                          color: isSelected ? Colors.white : const Color(0xFF111827),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),

              // Save Button
              Center(
                child: SizedBox(
                  width: 124,
                  height: 28,
                  child: ElevatedButton(
                    onPressed: () {
                      if (widget.onSaveDate != null) widget.onSaveDate!(_selectedDate);
                      Navigator.of(context).pop(_selectedDate);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: const StadiumBorder(),
                      padding: EdgeInsets.zero,
                    ),
                    child: const Text(
                      'Save',
                      style: TextStyle(
                        fontFamily: 'Google Sans Flex',
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// 2. Time Picker Wheels Overlay (Exact Figma 254x236 Glassmorphism Radius 32)
/// ---------------------------------------------------------------------------
class TimePickerWheelsOverlay extends StatefulWidget {
  final TimeOfDay initialTime;
  final ValueChanged<TimeOfDay>? onSaveTime;

  const TimePickerWheelsOverlay({
    super.key,
    required this.initialTime,
    this.onSaveTime,
  });

  static Future<TimeOfDay?> show(BuildContext context, {required TimeOfDay initialTime}) {
    return showDialog<TimeOfDay>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.25),
      builder: (context) => TimePickerWheelsOverlay(initialTime: initialTime),
    );
  }

  @override
  State<TimePickerWheelsOverlay> createState() => _TimePickerWheelsOverlayState();
}

class _TimePickerWheelsOverlayState extends State<TimePickerWheelsOverlay> {
  late int _selectedHour;
  late int _selectedMinute;
  late bool _isAm;

  late final FixedExtentScrollController _hourController;
  late final FixedExtentScrollController _minuteController;
  late final FixedExtentScrollController _periodController;

  @override
  void initState() {
    super.initState();
    final hourOfPeriod = widget.initialTime.hourOfPeriod;
    _selectedHour = hourOfPeriod == 0 ? 12 : hourOfPeriod;
    _selectedMinute = widget.initialTime.minute;
    _isAm = widget.initialTime.period == DayPeriod.am;

    _hourController = FixedExtentScrollController(initialItem: _selectedHour - 1);
    _minuteController = FixedExtentScrollController(initialItem: _selectedMinute);
    _periodController = FixedExtentScrollController(initialItem: _isAm ? 0 : 1);
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    _periodController.dispose();
    super.dispose();
  }

  void _handleSave() {
    int hour24 = _selectedHour;
    if (_isAm) {
      if (hour24 == 12) hour24 = 0;
    } else {
      if (hour24 != 12) hour24 += 12;
    }
    final result = TimeOfDay(hour: hour24, minute: _selectedMinute);
    if (widget.onSaveTime != null) widget.onSaveTime!(result);
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              width: 254,
              height: 250,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1.5),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1F000000),
                    blurRadius: 28,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Hours Wheel
                        SizedBox(
                          width: 50,
                          child: CupertinoPicker(
                            scrollController: _hourController,
                            itemExtent: 36,
                            selectionOverlay: Container(),
                            onSelectedItemChanged: (index) => setState(() => _selectedHour = index + 1),
                            children: List.generate(12, (i) {
                              return Center(
                                child: Text(
                                  '${i + 1}',
                                  style: TextStyle(
                                    fontFamily: 'Google Sans Flex',
                                    fontSize: 18,
                                    fontWeight: _selectedHour == i + 1 ? FontWeight.w500 : FontWeight.w300,
                                    color: _selectedHour == i + 1 ? const Color(0xFF111827) : const Color(0xFF9CA3AF),
                                  ),
                                ),
                              );
                            }),
                          ),
                        ),

                        // Minutes Wheel
                        SizedBox(
                          width: 50,
                          child: CupertinoPicker(
                            scrollController: _minuteController,
                            itemExtent: 36,
                            selectionOverlay: Container(),
                            onSelectedItemChanged: (index) => setState(() => _selectedMinute = index),
                            children: List.generate(60, (i) {
                              return Center(
                                child: Text(
                                  i.toString().padLeft(2, '0'),
                                  style: TextStyle(
                                    fontFamily: 'Google Sans Flex',
                                    fontSize: 18,
                                    fontWeight: _selectedMinute == i ? FontWeight.w500 : FontWeight.w300,
                                    color: _selectedMinute == i ? const Color(0xFF111827) : const Color(0xFF9CA3AF),
                                  ),
                                ),
                              );
                            }),
                          ),
                        ),

                        // AM / PM Wheel
                        SizedBox(
                          width: 50,
                          child: CupertinoPicker(
                            scrollController: _periodController,
                            itemExtent: 36,
                            selectionOverlay: Container(),
                            onSelectedItemChanged: (index) => setState(() => _isAm = index == 0),
                            children: ['AM', 'PM'].map((p) {
                              final isSelected = (p == 'AM') == _isAm;
                              return Center(
                                child: Text(
                                  p,
                                  style: TextStyle(
                                    fontFamily: 'Google Sans Flex',
                                    fontSize: 16,
                                    fontWeight: isSelected ? FontWeight.w500 : FontWeight.w300,
                                    color: isSelected ? const Color(0xFF111827) : const Color(0xFF9CA3AF),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Save Button
                  SizedBox(
                    width: 124,
                    height: 28,
                    child: ElevatedButton(
                      onPressed: _handleSave,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: const StadiumBorder(),
                        padding: EdgeInsets.zero,
                      ),
                      child: const Text(
                        'Save',
                        style: TextStyle(
                          fontFamily: 'Google Sans Flex',
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
