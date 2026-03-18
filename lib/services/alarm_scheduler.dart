import 'package:flutter/services.dart';
import '../models/alarm_model.dart';
import '../services/alarm_storage.dart';
import '../utils/date_calculator.dart';

/// Bridges Flutter ↔ Android native AlarmManager via a [MethodChannel].
///
/// The channel name must match [CHANNEL] in MainActivity.kt exactly.
class AlarmScheduler {
  static const MethodChannel _ch =
      MethodChannel('com.example.smart_monthly_alarm/alarm');

  // ─── Permissions ──────────────────────────────────────────────────────────

  /// Returns `true` if the app already has SCHEDULE_EXACT_ALARM permission.
  static Future<bool> canScheduleExactAlarms() async {
    final result = await _ch.invokeMethod<bool>('canScheduleExactAlarms');
    return result ?? false;
  }

  /// Opens the exact-alarm permission settings screen (Android 12+).
  static Future<void> openExactAlarmSettings() =>
      _ch.invokeMethod('openExactAlarmSettings');

  /// Returns `true` if POST_NOTIFICATIONS permission is granted (Android 13+).
  static Future<bool> hasNotificationPermission() async {
    final result = await _ch.invokeMethod<bool>('hasNotificationPermission');
    return result ?? true;
  }

  /// Requests POST_NOTIFICATIONS at runtime (Android 13+).
  static Future<void> requestNotificationPermission() =>
      _ch.invokeMethod('requestNotificationPermission');

  // ─── Scheduling ───────────────────────────────────────────────────────────

  /// Calculates the next trigger date, persists it in Hive, and asks the
  /// native layer to call [AlarmManager.setExactAndAllowWhileIdle].
  ///
  /// Returns the computed trigger [DateTime] or `null` if none could be found
  /// within 13 months (e.g. "5th Monday" in months that only have 4).
  static Future<DateTime?> scheduleAlarm(AlarmModel alarm) async {
    if (!alarm.isEnabled) return null;

    final DateTime now = DateTime.now();
    final DateTime? trigger = DateCalculator.getNextTriggerDate(
      now: now,
      weekOfMonth: alarm.weekOfMonth,
      dayOfWeek: alarm.dayOfWeek,
      hour: alarm.hour,
      minute: alarm.minute,
    );

    if (trigger == null) return null;

    // Persist the computed trigger so native code can read it on reboot.
    alarm.nextTriggerDate = trigger;
    await AlarmStorage.save(alarm);

    await _ch.invokeMethod('scheduleAlarm', {
      'id': alarm.id,
      'label': alarm.label,
      'triggerMillis': trigger.millisecondsSinceEpoch,
      // Pass rule params so native BootReceiver can reschedule independently.
      'weekOfMonth': alarm.weekOfMonth,
      'dayOfWeek': alarm.dayOfWeek,
      'hour': alarm.hour,
      'minute': alarm.minute,
    });

    return trigger;
  }

  /// Cancels a pending alarm in AlarmManager.
  static Future<void> cancelAlarm(int id) async =>
      _ch.invokeMethod('cancelAlarm', {'id': id});

  /// Re-schedules every enabled alarm – called on cold start and after reboot.
  static Future<void> rescheduleAll() async {
    final alarms = AlarmStorage.getAll();
    for (final alarm in alarms) {
      if (alarm.isEnabled) await scheduleAlarm(alarm);
    }
  }
}
