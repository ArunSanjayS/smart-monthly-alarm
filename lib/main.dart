import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/alarm_storage.dart';
import 'services/alarm_scheduler.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait for a cleaner alarm UI.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Open Hive box.
  await AlarmStorage.initialize();

  // Reschedule any alarms that may have been cleared (e.g. after OS update).
  await AlarmScheduler.rescheduleAll();

  runApp(const SmartMonthlyAlarmApp());
}

class SmartMonthlyAlarmApp extends StatelessWidget {
  const SmartMonthlyAlarmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Monthly Alarm',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final base = ColorScheme.fromSeed(
      seedColor: const Color(0xFF5C6BC0), // Indigo-400
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: base,
      fontFamily: 'Roboto',
      appBarTheme: AppBarTheme(
        titleTextStyle: TextStyle(
          color: base.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
