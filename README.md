# Smart Monthly Alarm

A Flutter Android application that schedules recurring alarms for a specific
weekday occurrence in every month (e.g. *"First Tuesday at 10:00 AM"*).
The alarm fires **2 days before** the computed rule date, handles cross-month
triggers, survives reboots, and rings continuously until manually dismissed.

---

## Table of Contents

1. [Features](#features)
2. [Architecture Overview](#architecture-overview)
3. [Date Calculation Logic](#date-calculation-logic)
4. [Cross-Month Handling](#cross-month-handling)
5. [Alarm Lifecycle](#alarm-lifecycle)
6. [Project Structure](#project-structure)
7. [Setup & Installation](#setup--installation)
8. [Android Permissions](#android-permissions)
9. [OEM-Specific Notes](#oem-specific-notes)
10. [Troubleshooting](#troubleshooting)

---

## Features

| Feature | Implementation |
|---|---|
| Nth weekday rule (First–Last, Mon–Sun) | `DateCalculator` (Dart) + `AlarmHelper` (Kotlin) |
| Trigger = rule date − 2 days | Both implementations; Dart for scheduling, Kotlin for native reschedule |
| Cross-month trigger dates | Scan window starts at currentMonth − 1 |
| Rings continuously until dismissed | `AlarmService` foreground service + looping `MediaPlayer` |
| Works when app is killed | `START_STICKY` foreground service |
| Works on lock screen | `FLAG_SHOW_WHEN_LOCKED` + `FLAG_TURN_SCREEN_ON` |
| Full-screen UI | `AlarmActivity` shown via `setFullScreenIntent` |
| Vibration | `VibrationEffect.createWaveform` (looping) |
| Persists after reboot | `BootReceiver` reads SharedPreferences, reschedules via AlarmManager |
| Doze-mode safe | `setExactAndAllowWhileIdle` |
| Duplicate alarm prevention | `FLAG_UPDATE_CURRENT` on every `PendingIntent` |
| Leap year / varying months | `DateTime(year, month+1, 0)` for correct last-day |
| Missing Nth occurrence (e.g. 5th Mon) | Scanner skips month and tries the next |
| Data persistence | Hive (Flutter) + SharedPreferences (native) |

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                        Flutter Layer                        │
│                                                             │
│  HomeScreen ──► AddAlarmScreen                              │
│       │               │                                     │
│  AlarmStorage     DateCalculator                            │
│  (Hive box)       (Dart math)                               │
│       │               │                                     │
│  AlarmScheduler ◄──────┘                                    │
│  (MethodChannel bridge)                                     │
└──────────────────────┬──────────────────────────────────────┘
                       │  MethodChannel
                       │  "com.example.smart_monthly_alarm/alarm"
┌──────────────────────▼──────────────────────────────────────┐
│                     Android Native Layer                    │
│                                                             │
│  MainActivity                                               │
│  (MethodChannel handler)                                    │
│       │                                                     │
│  AlarmHelper ──► AlarmManager.setExactAndAllowWhileIdle()   │
│  (SharedPrefs + date math)                                  │
│                                                             │
│  [at trigger time]                                          │
│  AlarmReceiver ──► AlarmService (ForegroundService)         │
│                         │                                   │
│                    MediaPlayer (looping)                    │
│                    Vibrator (looping)                       │
│                    WakeLock (10 min)                        │
│                    Full-screen notification                 │
│                         │                                   │
│                    AlarmActivity (over lock screen)         │
│                         │                                   │
│                    [user taps DISMISS]                      │
│                    ACTION_STOP_ALARM broadcast              │
│                    AlarmService.stopSelf()                  │
│                                                             │
│  [on reboot]                                                │
│  BootReceiver ──► AlarmHelper.computeNextTriggerMillis()    │
│                ──► AlarmHelper.scheduleExactAlarm()         │
└─────────────────────────────────────────────────────────────┘
```

---

## Date Calculation Logic

### Nth Weekday Algorithm

Given `weekOfMonth` (0=First…4=Last) and `dayOfWeek` (ISO: 1=Mon…7=Sun):

**For First–Fourth:**
```
firstOfMonth = DateTime(year, month, 1)
daysToAdd    = (targetWeekday - firstOfMonth.weekday + 7) % 7
firstOccur   = firstOfMonth + daysToAdd days
nthOccur     = firstOccur  + (weekOfMonth × 7) days

Guard: nthOccur.month must equal month  →  return null if not
```

**For Last:**
```
lastOfMonth  = DateTime(year, month+1, 0)   // day-0 trick
daysToSub    = (lastOfMonth.weekday - targetWeekday + 7) % 7
lastOccur    = lastOfMonth - daysToSub days
```

### Trigger Date
```
triggerDate = nthOccur − 2 days
triggerTime = triggerDate at [hour]:[minute]
```

### Examples

| Rule | Rule date (Jan 2025) | Trigger date |
|---|---|---|
| First Tuesday | Jan 7, 2025 | Jan 5, 2025 |
| Last Friday | Jan 31, 2025 | Jan 29, 2025 |
| First Monday | Jan 6, 2025 | Jan 4, 2025 |
| Third Wednesday | Jan 15, 2025 | Jan 13, 2025 |

---

## Cross-Month Handling

The trigger for "First Monday of February" could be **January 29** if the
first Monday of February is January 31+2=Feb 2 → trigger Jan 31… or the
first Monday of January is Jan 6 → trigger Jan 4 (previous month).

**Solution:** The search window for the *next* trigger starts at
`currentMonth − 1` and spans 14 months:

```dart
for (int offset = -1; offset <= 12; offset++) {
  final probe = addMonths(now, offset);
  final trigger = computeTriggerDate(probe.year, probe.month, ...);
  if (trigger != null && trigger.isAfter(now)) return trigger;
}
```

This guarantees a trigger whose rule date is in month M but whose
trigger date falls in month M−1 is never skipped.

---

## Alarm Lifecycle

```
1. User saves alarm
   └─► AlarmStorage.save()           // Hive
   └─► AlarmScheduler.scheduleAlarm()
         └─► DateCalculator.getNextTriggerDate()
         └─► MethodChannel → MainActivity
               └─► AlarmHelper.saveAlarmData()   // SharedPreferences
               └─► AlarmHelper.scheduleExactAlarm()  // AlarmManager

2. Trigger fires (device may be in Doze / screen off)
   └─► AlarmReceiver.onReceive()
         └─► context.startForegroundService(AlarmService)
         └─► AlarmHelper.computeNextTriggerMillis() + scheduleExactAlarm()
               ↑ Reschedules NEXT month without Flutter

3. AlarmService.onStartCommand()
   └─► acquireWakeLock()             // Keeps CPU alive
   └─► startForeground(notification) // High-priority + full-screen intent
   └─► MediaPlayer.start()           // Default alarm ringtone, looping
   └─► Vibrator.vibrate(pattern, 0)  // Looping wave

4. AlarmActivity shown (even on lock screen)
   └─► Live clock ticking every second
   └─► User taps DISMISS
         └─► sendBroadcast(ACTION_STOP_ALARM)
         └─► AlarmService.stopSelf()
               └─► stopSound() + stopVibration() + releaseWakeLock()
               └─► stopForeground(true)  // Removes notification

5. On device reboot
   └─► BootReceiver.onReceive(BOOT_COMPLETED)
         └─► AlarmHelper.loadAllAlarmData()   // Reads SharedPreferences
         └─► For each enabled alarm:
               AlarmHelper.computeNextTriggerMillis()
               AlarmHelper.scheduleExactAlarm()
```

---

## Project Structure

```
smart_monthly_alarm/
├── pubspec.yaml
│
├── lib/
│   ├── main.dart                       App entry, Hive init, reschedule on start
│   │
│   ├── models/
│   │   ├── alarm_model.dart            Hive @HiveType entity
│   │   └── alarm_model.g.dart          TypeAdapter (hand-written, no build_runner needed)
│   │
│   ├── utils/
│   │   └── date_calculator.dart        Pure Dart: Nth weekday + trigger math
│   │
│   ├── services/
│   │   ├── alarm_storage.dart          Hive box CRUD
│   │   └── alarm_scheduler.dart        MethodChannel → Android bridge
│   │
│   └── screens/
│       ├── home_screen.dart            Alarm list with toggle / edit / delete
│       └── add_alarm_screen.dart       Form: week/day/time dropdowns + live preview
│
└── android/app/src/main/
    ├── AndroidManifest.xml             All permissions + 5 component declarations
    │
    ├── kotlin/com/example/smart_monthly_alarm/
    │   ├── MainActivity.kt             FlutterActivity + MethodChannel handler
    │   ├── AlarmHelper.kt              SharedPrefs I/O + date math + AlarmManager
    │   ├── AlarmReceiver.kt            BroadcastReceiver: service + reschedule
    │   ├── AlarmService.kt             ForegroundService: sound + vibration + WakeLock
    │   ├── AlarmActivity.kt            Full-screen alarm UI (lock screen safe)
    │   └── BootReceiver.kt             BOOT_COMPLETED → reschedule all alarms
    │
    └── res/
        ├── layout/activity_alarm.xml   Dark alarm screen layout
        ├── values/colors.xml           Alarm color palette
        ├── values/styles.xml           LaunchTheme / NormalTheme / AlarmTheme
        ├── values-night/styles.xml     Dark-mode overrides
        └── drawable/launch_background.xml
```

---

## Setup & Installation

### Prerequisites

| Tool | Minimum version |
|---|---|
| Flutter SDK | 3.10.0 |
| Dart SDK | 3.0.0 |
| Android Studio | Hedgehog (2023.1.1) |
| Kotlin | 1.9.22 |
| Android Gradle Plugin | 8.2.2 |
| Gradle | 8.4 |
| `compileSdk` | 34 |
| `minSdk` | 21 |

### Step-by-step

```bash
# 1. Clone / copy the project
cd smart_monthly_alarm

# 2. Install Flutter dependencies
flutter pub get

# 3. Create android/local.properties (Flutter does this automatically on first build,
#    but you can also create it manually)
echo "flutter.sdk=/path/to/flutter" > android/local.properties
echo "sdk.dir=/path/to/android-sdk" >> android/local.properties

# 4. Enable View Binding (already in android/app/build.gradle)
#    buildFeatures { viewBinding true }

# 5. Run on a connected device (not emulator – alarm audio works better on real device)
flutter run

# 6. Build release APK
flutter build apk --release
```

### Enable View Binding (verify)

Open `android/app/build.gradle` and confirm:

```groovy
android {
    buildFeatures {
        viewBinding true
    }
}
```

---

## Android Permissions

| Permission | Why needed |
|---|---|
| `WAKE_LOCK` | Keep CPU alive while alarm rings |
| `RECEIVE_BOOT_COMPLETED` | Re-register alarms after reboot |
| `SCHEDULE_EXACT_ALARM` | Exact alarm on Android 12 (user grants via Settings) |
| `USE_EXACT_ALARM` | Unrestricted exact alarm on Android 13+ |
| `FOREGROUND_SERVICE` | Run AlarmService in foreground |
| `FOREGROUND_SERVICE_SPECIAL_USE` | Declare foreground service type on Android 14 |
| `USE_FULL_SCREEN_INTENT` | Show full-screen alarm UI over lock screen |
| `VIBRATE` | Vibration during alarm |
| `POST_NOTIFICATIONS` | Show alarm notification (Android 13+, runtime request) |
| `SYSTEM_ALERT_WINDOW` | Overlay window on some OEM devices |

### Granting `SCHEDULE_EXACT_ALARM` (Android 12+)

The app shows a Material Banner on first launch:

1. Tap **GRANT** in the banner.
2. The OS opens **Settings → Apps → Smart Monthly Alarm → Alarms & Reminders**.
3. Toggle **Allow setting alarms and reminders** ON.

Without this permission, `AlarmManager.setExactAndAllowWhileIdle()` is silently
ignored on Android 12+ and alarms will not fire.

---

## OEM-Specific Notes

Many Chinese OEM Android builds (Xiaomi, OPPO, Vivo, Huawei) aggressively kill
background services. Do the following on those devices:

| OEM | Setting |
|---|---|
| **Xiaomi / MIUI** | Settings → Battery & Performance → App Battery Saver → Smart Monthly Alarm → No Restrictions; also enable Autostart |
| **OPPO / ColorOS** | Settings → Battery → Power Saving → Smart Monthly Alarm → Allow background activity |
| **Vivo / FuntouchOS** | Settings → Battery → High background power consumption → Add app |
| **Huawei / EMUI** | Settings → Battery → App Launch → Smart Monthly Alarm → Manage manually → enable all three |
| **Samsung / OneUI** | Settings → Battery → Background usage limits → Never sleeping apps → Add |

**Universal:** Settings → Battery → Battery Optimization → All Apps →
**Smart Monthly Alarm → Don't Optimize**

---

## Troubleshooting

### Alarm did not fire

1. Check `SCHEDULE_EXACT_ALARM` is granted (see above).
2. Check battery optimization is disabled for the app.
3. On Android 14, confirm the `<service android:foregroundServiceType="specialUse">` entry and `<property>` tag are present in the Manifest.
4. Confirm `AlarmService.stopWithTask="false"` is set in the Manifest (means the service survives task removal).

### Sound plays but no full-screen activity

1. The `USE_FULL_SCREEN_INTENT` permission must be granted. On Android 14+, go to **Settings → Apps → Special App Access → Display over other apps**.
2. Check `AlarmActivity` has `android:showWhenLocked="true"` and `android:turnScreenOn="true"` in the Manifest.

### Alarm not rescheduled after reboot

1. Confirm `BootReceiver` is declared with the `BOOT_COMPLETED` intent filter in the Manifest.
2. Some OEMs delay `BOOT_COMPLETED` by several minutes. Test by waiting after reboot.
3. Check `android:exported="true"` on `BootReceiver`.

### Build error: "Cannot find symbol ActivityAlarmBinding"

View Binding is not enabled. Add to `android/app/build.gradle`:
```groovy
buildFeatures { viewBinding true }
```
Then run `./gradlew clean` and rebuild.

### Kotlin compilation error on AlarmActivity

Ensure `androidx.appcompat:appcompat` is in dependencies (needed for `AppCompatActivity`).

---

## License

MIT – free to use and modify for personal and commercial projects.
