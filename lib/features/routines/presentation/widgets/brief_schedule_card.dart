import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_exceptions.dart';
import '../../../../shared/theme/app_spacing.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../data/routines_repository.dart';
import '../../domain/routine_model.dart';
import 'day_selector.dart';
import 'time_picker_field.dart';

/// Stateful card for editing a single brief schedule. Owns the
/// in-flight schedule values (days + time + enabled) and persists
/// them via the [RoutinesRepository] on every change.
///
/// The "Testar" button issues a dry-run against the backend and shows
/// the LLM-produced markdown in a scrollable bottom sheet.
class BriefScheduleCard extends ConsumerStatefulWidget {
  const BriefScheduleCard({super.key, required this.routine});

  final RoutineModel routine;

  @override
  ConsumerState<BriefScheduleCard> createState() => _BriefScheduleCardState();
}

class _BriefScheduleCardState extends ConsumerState<BriefScheduleCard> {
  static const _labelAtivo = 'Ativo';
  static const _labelDias = 'Dias';
  static const _labelHorario = 'Horário';
  static const _labelTestar = 'Testar';
  static const _labelTestando = 'Testando…';
  static const _labelFechar = 'Fechar';
  static const _titleTestResult = 'Prévia do brief';
  static const _errorSaveFailed = 'Falha ao salvar rotina';
  static const _errorTestFailed = 'Falha ao testar brief';

  late bool _enabled;
  late List<int> _daysOfWeek;
  late TimeOfDay _time;
  bool _initialized = false;
  bool _saving = false;
  bool _testing = false;

  void _hydrateFromRoutine() {
    final schedule = widget.routine.schedule;
    if (schedule != null) {
      _daysOfWeek = List<int>.from(schedule.daysOfWeek);
      _time = schedule.timeOfDay;
    } else {
      // Sensible default for a routine whose cron the UI does not
      // understand: weekdays at 08:00.
      _daysOfWeek = const [1, 2, 3, 4, 5];
      _time = const TimeOfDay(hour: 8, minute: 0);
    }
    _enabled = widget.routine.enabled;
    _initialized = true;
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) _hydrateFromRoutine();

    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.routine.name,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                Text(
                  _labelAtivo,
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Switch.adaptive(
                  value: _enabled,
                  onChanged: _saving ? null : (v) => _onEnabledChanged(v),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              _labelDias,
              style: textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            IgnorePointer(
              ignoring: _saving,
              child: Opacity(
                opacity: _enabled ? 1.0 : 0.5,
                child: DaySelector(
                  selected: _daysOfWeek,
                  onChanged: _onDaysChanged,
                  mode: widget.routine.briefType == BriefType.weekly
                      ? DaySelectorMode.single
                      : DaySelectorMode.multi,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              _labelHorario,
              style: textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            IgnorePointer(
              ignoring: _saving,
              child: Opacity(
                opacity: _enabled ? 1.0 : 0.5,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TimePickerField(
                    value: _time,
                    onChanged: _onTimeChanged,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                if (_saving) ...[
                  const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
                const Spacer(),
                IntrinsicWidth(
                  child: AppButton(
                    text: _testing ? _labelTestando : _labelTestar,
                    variant: AppButtonVariant.tonal,
                    icon: const Icon(Icons.science_outlined, size: 18),
                    onPressed: (_testing || _saving) ? null : _onTestPressed,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  Future<void> _persist({bool? enabled, String? cronExpr}) async {
    setState(() => _saving = true);
    try {
      await ref.read(routinesRepositoryProvider).updateRoutine(
            widget.routine.id,
            enabled: enabled,
            cronExpr: cronExpr,
          );
    } on ApiException catch (e) {
      if (mounted) {
        AppMessenger.showError(context, '$_errorSaveFailed: ${e.message}');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _onEnabledChanged(bool value) async {
    setState(() => _enabled = value);
    await _persist(enabled: value);
  }

  Future<void> _onDaysChanged(List<int> days) async {
    if (days.isEmpty) return; // At least one day is required.
    setState(() => _daysOfWeek = days);
    await _persist(cronExpr: _currentCronExpr());
  }

  Future<void> _onTimeChanged(TimeOfDay time) async {
    setState(() => _time = time);
    await _persist(cronExpr: _currentCronExpr());
  }

  String _currentCronExpr() => buildCronExpr(
        daysOfWeek: _daysOfWeek,
        hour: _time.hour,
        minute: _time.minute,
      );

  // ---------------------------------------------------------------------------
  // Dry-run
  // ---------------------------------------------------------------------------

  Future<void> _onTestPressed() async {
    setState(() => _testing = true);
    try {
      final repo = ref.read(routinesRepositoryProvider);
      final content = switch (widget.routine.briefType) {
        BriefType.daily => await repo.testDaily(),
        BriefType.weekly => await repo.testWeekly(),
      };
      if (!mounted) return;
      await _showResultSheet(content);
    } on ApiException catch (e) {
      if (mounted) {
        AppMessenger.showError(context, '$_errorTestFailed: ${e.message}');
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _showResultSheet(String content) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _titleTestResult,
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 480),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      content.isEmpty ? '(vazio)' : content,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Align(
                  alignment: Alignment.centerRight,
                  child: IntrinsicWidth(
                    child: AppButton(
                      text: _labelFechar,
                      onPressed: () => Navigator.of(sheetContext).pop(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
