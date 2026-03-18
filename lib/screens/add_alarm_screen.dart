import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/alarm_model.dart';
import '../services/alarm_storage.dart';
import '../services/alarm_scheduler.dart';
import '../utils/date_calculator.dart';

class AddAlarmScreen extends StatefulWidget {
  /// Pass an existing [AlarmModel] to edit; `null` creates a new alarm.
  final AlarmModel? existing;

  const AddAlarmScreen({super.key, this.existing});

  @override
  State<AddAlarmScreen> createState() => _AddAlarmScreenState();
}

class _AddAlarmScreenState extends State<AddAlarmScreen> {
  final _labelCtrl = TextEditingController();

  int _weekOfMonth = 0; // 0=First … 4=Last
  int _dayOfWeek = 2; // ISO weekday: Mon=1 … Sun=7  (default: Tuesday)
  TimeOfDay _time = const TimeOfDay(hour: 10, minute: 0);

  bool _saving = false;

  static const _weekLabels = ['First', 'Second', 'Third', 'Fourth', 'Last'];
  static const _dayLabels = [
    'Monday', 'Tuesday', 'Wednesday',
    'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];

  @override
  void initState() {
    super.initState();
    final a = widget.existing;
    if (a != null) {
      _labelCtrl.text = a.label;
      _weekOfMonth = a.weekOfMonth;
      _dayOfWeek = a.dayOfWeek;
      _time = TimeOfDay(hour: a.hour, minute: a.minute);
    }
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

  // ─── Computed preview ───────────────────────────────────────────────────

  /// Shows what the next trigger date will be given the current selections.
  String get _previewText {
    final trigger = DateCalculator.getNextTriggerDate(
      now: DateTime.now(),
      weekOfMonth: _weekOfMonth,
      dayOfWeek: _dayOfWeek,
      hour: _time.hour,
      minute: _time.minute,
    );
    if (trigger == null) return 'No upcoming date found';
    final ruleDate = trigger.add(const Duration(days: 2));
    final fmt = DateFormat('EEE, MMM d, yyyy');
    return 'Rule date: ${fmt.format(ruleDate)}\n'
        'Alarm fires: ${fmt.format(trigger)} at ${_time.format(context)}';
  }

  // ─── Actions ─────────────────────────────────────────────────────────────

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save() async {
    final label = _labelCtrl.text.trim();
    if (label.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Please enter an alarm label')));
      return;
    }

    setState(() => _saving = true);

    final alarm = AlarmModel(
      id: widget.existing?.id ?? AlarmStorage.nextId(),
      label: label,
      weekOfMonth: _weekOfMonth,
      dayOfWeek: _dayOfWeek,
      hour: _time.hour,
      minute: _time.minute,
      isEnabled: true,
    );

    await AlarmStorage.save(alarm);
    final trigger = await AlarmScheduler.scheduleAlarm(alarm);

    setState(() => _saving = false);

    if (!mounted) return;

    if (trigger != null) {
      final fmt = DateFormat('EEE, MMM d yyyy, h:mm a');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Alarm set! Will ring on ${fmt.format(trigger)}'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    }
    Navigator.of(context).pop(true);
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isEditing = widget.existing != null;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Alarm' : 'New Alarm'),
        centerTitle: true,
        backgroundColor: cs.surfaceContainerHighest,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Label ──────────────────────────────────────────────────
              _SectionLabel('Alarm Label'),
              const SizedBox(height: 8),
              TextField(
                controller: _labelCtrl,
                decoration: InputDecoration(
                  hintText: 'e.g. Monthly Team Meeting',
                  prefixIcon: const Icon(Icons.label_outline),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                textCapitalization: TextCapitalization.words,
                maxLength: 50,
              ),

              const SizedBox(height: 20),

              // ── Week of month ─────────────────────────────────────────
              _SectionLabel('Week of Month'),
              const SizedBox(height: 8),
              _DropdownCard<int>(
                value: _weekOfMonth,
                items: List.generate(
                  5,
                  (i) => DropdownMenuItem(value: i, child: Text(_weekLabels[i])),
                ),
                onChanged: (v) => setState(() => _weekOfMonth = v!),
                icon: Icons.calendar_view_week_outlined,
              ),

              const SizedBox(height: 16),

              // ── Day of week ───────────────────────────────────────────
              _SectionLabel('Day of Week'),
              const SizedBox(height: 8),
              _DropdownCard<int>(
                value: _dayOfWeek,
                items: List.generate(
                  7,
                  (i) => DropdownMenuItem(
                      value: i + 1, child: Text(_dayLabels[i])),
                ),
                onChanged: (v) => setState(() => _dayOfWeek = v!),
                icon: Icons.today_outlined,
              ),

              const SizedBox(height: 16),

              // ── Time ──────────────────────────────────────────────────
              _SectionLabel('Alarm Time'),
              const SizedBox(height: 8),
              _TimePickerCard(time: _time, onTap: _pickTime),

              const SizedBox(height: 24),

              // ── Preview ───────────────────────────────────────────────
              _PreviewCard(text: _previewText),

              const SizedBox(height: 28),

              // ── Save ─────────────────────────────────────────────────
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.alarm_add),
                label: Text(_saving ? 'Saving…' : (isEditing ? 'Update Alarm' : 'Save Alarm')),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Small reusable widgets ─────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
      );
}

class _DropdownCard<T> extends StatelessWidget {
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final IconData icon;

  const _DropdownCard({
    required this.value,
    required this.items,
    required this.onChanged,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: cs.primary),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                value: value,
                items: items,
                onChanged: onChanged,
                isExpanded: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimePickerCard extends StatelessWidget {
  final TimeOfDay time;
  final VoidCallback onTap;

  const _TimePickerCard({required this.time, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Row(
          children: [
            Icon(Icons.access_time, color: cs.primary),
            const SizedBox(width: 12),
            Text(
              time.format(context),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const Spacer(),
            Icon(Icons.chevron_right, color: cs.outline),
          ],
        ),
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  final String text;
  const _PreviewCard({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: cs.onPrimaryContainer, size: 18),
              const SizedBox(width: 8),
              Text(
                'Next Alarm Preview',
                style: TextStyle(
                  color: cs.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: TextStyle(color: cs.onPrimaryContainer, height: 1.5),
          ),
        ],
      ),
    );
  }
}
