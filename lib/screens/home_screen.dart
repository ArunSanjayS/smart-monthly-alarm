import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/alarm_model.dart';
import '../services/alarm_storage.dart';
import '../services/alarm_scheduler.dart';
import 'add_alarm_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<AlarmModel> _alarms = [];

  @override
  void initState() {
    super.initState();
    _refresh();
    _checkPermissions();
  }

  void _refresh() => setState(() => _alarms = AlarmStorage.getAll());

  Future<void> _checkPermissions() async {
    final exact = await AlarmScheduler.canScheduleExactAlarms();
    final notif = await AlarmScheduler.hasNotificationPermission();
    if (!mounted) return;
    if (!exact) _showExactAlarmBanner();
    if (!notif) await AlarmScheduler.requestNotificationPermission();
  }

  void _showExactAlarmBanner() {
    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        content: const Text(
          'Exact alarm permission is required for reliable alarms.',
        ),
        leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
        actions: [
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
              AlarmScheduler.openExactAlarmSettings();
            },
            child: const Text('GRANT'),
          ),
          TextButton(
            onPressed: () =>
                ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
            child: const Text('DISMISS'),
          ),
        ],
      ),
    );
  }

  // ─── Alarm actions ────────────────────────────────────────────────────────

  Future<void> _toggleEnabled(AlarmModel alarm) async {
    alarm.isEnabled = !alarm.isEnabled;
    await AlarmStorage.save(alarm);
    if (alarm.isEnabled) {
      await AlarmScheduler.scheduleAlarm(alarm);
    } else {
      await AlarmScheduler.cancelAlarm(alarm.id);
    }
    _refresh();
  }

  Future<void> _deleteAlarm(AlarmModel alarm) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Alarm?'),
        content: Text('Delete "${alarm.label}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    await AlarmScheduler.cancelAlarm(alarm.id);
    await AlarmStorage.delete(alarm.id);
    _refresh();
  }

  Future<void> _editAlarm(AlarmModel alarm) async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AddAlarmScreen(existing: alarm)),
    );
    if (updated == true) _refresh();
  }

  Future<void> _addAlarm() async {
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddAlarmScreen()),
    );
    if (added == true) _refresh();
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerHighest,
        elevation: 0,
        title: Row(
          children: [
            Icon(Icons.alarm, color: cs.primary),
            const SizedBox(width: 10),
            const Text('Smart Monthly Alarm',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            tooltip: 'Re-check permissions',
            onPressed: _checkPermissions,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addAlarm,
        icon: const Icon(Icons.add_alarm),
        label: const Text('New Alarm'),
      ),
      body: _alarms.isEmpty ? _buildEmpty() : _buildList(cs),
    );
  }

  Widget _buildEmpty() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.alarm_off_outlined, size: 80, color: cs.outlineVariant),
          const SizedBox(height: 16),
          Text(
            'No alarms yet',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(color: cs.outline),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap + to create your first monthly alarm',
            style: TextStyle(color: cs.outline),
          ),
        ],
      ),
    );
  }

  Widget _buildList(ColorScheme cs) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: _alarms.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _AlarmCard(
        alarm: _alarms[i],
        onToggle: () => _toggleEnabled(_alarms[i]),
        onEdit: () => _editAlarm(_alarms[i]),
        onDelete: () => _deleteAlarm(_alarms[i]),
      ),
    );
  }
}

// ─── Alarm card widget ───────────────────────────────────────────────────────

class _AlarmCard extends StatelessWidget {
  final AlarmModel alarm;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _AlarmCard({
    required this.alarm,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  String _nextFireText() {
    final d = alarm.nextTriggerDate;
    if (d == null) return 'Not scheduled';
    if (!alarm.isEnabled) return 'Disabled';
    final fmt = DateFormat('EEE, MMM d, yyyy – h:mm a');
    return 'Fires: ${fmt.format(d)}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = alarm.isEnabled;

    return Card(
      elevation: enabled ? 2 : 0,
      color: enabled ? cs.surfaceContainerLow : cs.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Clock icon ──────────────────────────────────────────
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color:
                      enabled ? cs.primaryContainer : cs.surfaceContainerHigh,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.alarm,
                  color: enabled ? cs.onPrimaryContainer : cs.outline,
                ),
              ),
              const SizedBox(width: 14),

              // ── Text info ───────────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      alarm.label,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: enabled ? null : cs.outline,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      alarm.ruleDescription,
                      style: TextStyle(
                        color: enabled ? cs.primary : cs.outline,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _nextFireText(),
                      style: TextStyle(
                        color: cs.outline,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Actions ─────────────────────────────────────────────
              Column(
                children: [
                  Switch(value: enabled, onChanged: (_) => onToggle()),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                          value: 'edit',
                          child: ListTile(
                              leading: Icon(Icons.edit_outlined),
                              title: Text('Edit'),
                              dense: true)),
                      const PopupMenuItem(
                          value: 'delete',
                          child: ListTile(
                              leading:
                                  Icon(Icons.delete_outline, color: Colors.red),
                              title: Text('Delete',
                                  style: TextStyle(color: Colors.red)),
                              dense: true)),
                    ],
                    onSelected: (v) {
                      if (v == 'edit') onEdit();
                      if (v == 'delete') onDelete();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
