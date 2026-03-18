import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/alarm_model.dart';

/// Thin wrapper around the Hive box that persists [AlarmModel] objects.
/// All writes are synchronous from the caller's perspective; Hive flushes
/// asynchronously to disk.
class AlarmStorage {
  static const String _boxName = 'alarms';
  static Box<AlarmModel>? _box;

  // ─── Initialisation ──────────────────────────────────────────────────────

  /// Must be called once during app start-up (before [runApp]).
  static Future<void> initialize() async {
    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(AlarmModelAdapter());
    }
    _box = await Hive.openBox<AlarmModel>(_boxName);
  }

  static Box<AlarmModel> get _safeBox {
    assert(_box != null, 'AlarmStorage.initialize() has not been called');
    return _box!;
  }

  // ─── CRUD ─────────────────────────────────────────────────────────────────

  static List<AlarmModel> getAll() =>
      _safeBox.values.toList()..sort((a, b) => a.id.compareTo(b.id));

  static AlarmModel? getById(int id) => _safeBox.get(id);

  static Future<void> save(AlarmModel alarm) async =>
      _safeBox.put(alarm.id, alarm);

  static Future<void> delete(int id) async => _safeBox.delete(id);

  /// Generates a monotonically increasing ID.
  static int nextId() {
    if (_safeBox.isEmpty) return 1;
    return _safeBox.values.map((a) => a.id).reduce((a, b) => a > b ? a : b) + 1;
  }

  /// ValueListenable for reactive UI updates.
  static ValueListenable<Box<AlarmModel>> get listenable =>
      _safeBox.listenable();
}
