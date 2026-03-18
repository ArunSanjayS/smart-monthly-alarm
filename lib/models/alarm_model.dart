import 'package:hive/hive.dart';

part 'alarm_model.g.dart';

/// Supported week positions within a month.
enum WeekOfMonth { first, second, third, fourth, last }

/// Supported days of the week (ISO weekday: Mon=1 … Sun=7).
enum DayOfWeek { monday, tuesday, wednesday, thursday, friday, saturday, sunday }

extension WeekOfMonthExt on WeekOfMonth {
  String get label => ['First', 'Second', 'Third', 'Fourth', 'Last'][index];
  int get value => index; // 0-4
}

extension DayOfWeekExt on DayOfWeek {
  String get label =>
      ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][index];
  /// ISO weekday number (Mon=1, Sun=7).
  int get isoWeekday => index + 1;
}

@HiveType(typeId: 0)
class AlarmModel extends HiveObject {
  /// Unique alarm ID – used as AlarmManager request code on Android.
  @HiveField(0)
  int id;

  /// User-supplied label shown on the alarm screen.
  @HiveField(1)
  String label;

  /// 0=First … 3=Fourth, 4=Last
  @HiveField(2)
  int weekOfMonth;

  /// ISO weekday: 1=Monday … 7=Sunday
  @HiveField(3)
  int dayOfWeek;

  @HiveField(4)
  int hour;

  @HiveField(5)
  int minute;

  @HiveField(6)
  bool isEnabled;

  /// The pre-computed "2 days before" trigger date/time for the NEXT occurrence.
  @HiveField(7)
  DateTime? nextTriggerDate;

  AlarmModel({
    required this.id,
    required this.label,
    required this.weekOfMonth,
    required this.dayOfWeek,
    required this.hour,
    required this.minute,
    this.isEnabled = true,
    this.nextTriggerDate,
  });

  String get weekOfMonthLabel => WeekOfMonth.values[weekOfMonth].label;
  String get dayOfWeekLabel => DayOfWeek.values[dayOfWeek - 1].label;

  String get timeLabel {
    final h = hour.toString().padLeft(2, '0');
    final m = minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String get ruleDescription =>
      '$weekOfMonthLabel $dayOfWeekLabel of every month at $timeLabel';

  AlarmModel copyWith({
    String? label,
    int? weekOfMonth,
    int? dayOfWeek,
    int? hour,
    int? minute,
    bool? isEnabled,
    DateTime? nextTriggerDate,
  }) {
    return AlarmModel(
      id: id,
      label: label ?? this.label,
      weekOfMonth: weekOfMonth ?? this.weekOfMonth,
      dayOfWeek: dayOfWeek ?? this.dayOfWeek,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      isEnabled: isEnabled ?? this.isEnabled,
      nextTriggerDate: nextTriggerDate ?? this.nextTriggerDate,
    );
  }
}
