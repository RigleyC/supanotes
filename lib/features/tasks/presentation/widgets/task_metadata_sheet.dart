import 'package:family_bottom_sheet/family_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supanotes/core/utils/date_time_extensions.dart';
import 'package:supanotes/features/tasks/domain/task_date_format.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/features/tasks/domain/task_reminder_option.dart';
import 'package:supanotes/features/tasks/presentation/controllers/task_metadata_draft.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_metadata_date_page.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_metadata_selection_page.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_metadata_time_page.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_icon_button.dart';
import 'package:supanotes/shared/widgets/app_tile.dart';
import 'package:supanotes/shared/widgets/global_sheet.dart';

Future<TaskMetadataDraft> showTaskMetadataSheet({
  required BuildContext context,
  required TaskMetadataDraft draft,
}) async {
  final draftNotifier = ValueNotifier(draft);
  var result = draft;
  try {
    await showGlobalSheet<void>(
      context: context,
      builder: (_) => GlobalSheetPage(
        title: 'Editar horário e frequência',
        child: TaskMetadataSheetBody(
          draft: draft,
          draftNotifier: draftNotifier,
          onChanged: (next) => result = next,
        ),
      ),
    );
  } finally {
    draftNotifier.dispose();
  }
  return result;
}

class TaskMetadataSheetBody extends StatefulWidget {
  const TaskMetadataSheetBody({
    required this.draft,
    this.draftNotifier,
    this.onChanged,
    super.key,
  });

  final TaskMetadataDraft draft;
  final ValueNotifier<TaskMetadataDraft>? draftNotifier;
  final ValueChanged<TaskMetadataDraft>? onChanged;

  @override
  State<TaskMetadataSheetBody> createState() => _TaskMetadataSheetBodyState();
}

class _TaskMetadataSheetBodyState extends State<TaskMetadataSheetBody> {
  late final ValueNotifier<TaskMetadataDraft> _draftNotifier;
  late final bool _ownsDraftNotifier;

  // `DateFormat` construction does locale-data lookup: far too expensive to
  // rebuild on every draft change.
  static final _timeFormat = DateFormat('h:mm a');

  @override
  void initState() {
    super.initState();
    _ownsDraftNotifier = widget.draftNotifier == null;
    _draftNotifier = widget.draftNotifier ?? ValueNotifier(widget.draft);
  }

  @override
  void dispose() {
    if (_ownsDraftNotifier) _draftNotifier.dispose();
    super.dispose();
  }

  void _update(TaskMetadataDraft next) {
    _draftNotifier.value = next;
    widget.onChanged?.call(next);
  }

  void _openPickerPage(BuildContext context, Widget page) {
    // Release text-field focus before the picker covers it. Otherwise the
    // keyboard fights the page transition and a stale selection lingers on
    // the title field after returning.
    FocusManager.instance.primaryFocus?.unfocus();
    FamilyModalSheet.of(context).pushPage(page);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TaskMetadataDraft>(
      valueListenable: _draftNotifier,
      builder: (context, state, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.sm,
        children: [
          AppTile(
            contentPadding: EdgeInsets.zero,
            selected: state.scheduleAnchor != null,
            title: state.scheduleAnchor == null
                ? 'Adicionar data'
                : formatDueDate(state.scheduleAnchor!, hasTime: state.hasTime),
            leading: const Icon(Icons.calendar_today_rounded, size: 20),
            trailing: state.scheduleAnchor == null
                ? null
                : AppIconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    tooltip: 'Remover data',
                    onPressed: () => _update(
                      state.copyWith(
                        scheduleAnchor: null,
                        hasTime: false,
                        recurrence: null,
                        reminder: null,
                      ),
                    ),
                  ),
            onTap: () {
              _openPickerPage(
                context,
                TaskMetadataDatePage(
                  selected: state.scheduleAnchor,
                  onSelected: (date) => _update(
                    state.copyWith(scheduleAnchor: _mergeDateAndTime(date)),
                  ),
                ),
              );
            },
          ),
          AppTile(
            contentPadding: EdgeInsets.zero,
            selected: state.hasTime,
            title: state.hasTime && state.scheduleAnchor != null
                ? _timeFormat.format(state.scheduleAnchor!)
                : 'Adicionar horário',
            leading: const Icon(Icons.access_time_rounded, size: 20),
            trailing: state.hasTime
                ? AppIconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    tooltip: 'Remover horário',
                    onPressed: () => _update(
                      state.copyWith(
                        hasTime: false,
                        scheduleAnchor: state.scheduleAnchor == null
                            ? null
                            : DateTime(
                                state.scheduleAnchor!.year,
                                state.scheduleAnchor!.month,
                                state.scheduleAnchor!.day,
                              ),
                        reminder: state.reminder?.toAllDayFallback(),
                      ),
                    ),
                  )
                : null,
            onTap: () {
              _openPickerPage(
                context,
                TaskMetadataTimePage(
                  currentDueDate: state.scheduleAnchor ?? DateTime.now(),
                  hasTime: state.hasTime,
                  onSelected: (date, {required hasTime}) => _update(
                    state.copyWith(scheduleAnchor: date, hasTime: hasTime),
                  ),
                ),
              );
            },
          ),
          AppTile(
            contentPadding: EdgeInsets.zero,
            selected: state.recurrence != null,
            title:
                state.recurrence?.getLocalizedLabel(state.scheduleAnchor) ??
                'Adicionar recorrência',
            leading: const Icon(Icons.refresh_rounded, size: 20),
            trailing: state.recurrence == null
                ? null
                : AppIconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    tooltip: 'Remover recorrência',
                    onPressed: () => _update(state.copyWith(recurrence: null)),
                  ),
            onTap: () {
              _openPickerPage(
                context,
                TaskMetadataSelectionPage<TaskRecurrence>(
                  title: 'Repetição',
                  selected: state.recurrence,
                  options: TaskRecurrence.values,
                  noneLabel: 'Nenhuma',
                  optionLabel: (value) =>
                      value.getLocalizedLabel(state.scheduleAnchor),
                  optionIcon: (value) => value.icon,
                  onSelected: (value) => _update(
                    state.copyWith(
                      recurrence: value,
                      scheduleAnchor:
                          state.scheduleAnchor ??
                          (value == null ? null : DateTime.now().startOfDay),
                    ),
                  ),
                ),
              );
            },
          ),
          AppTile(
            contentPadding: EdgeInsets.zero,
            selected: state.reminder != null,
            title: state.reminder?.label ?? 'Adicionar lembrete',
            leading: const Icon(Icons.notifications_outlined, size: 20),
            trailing: state.reminder == null
                ? null
                : AppIconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    tooltip: 'Remover lembrete',
                    onPressed: () => _update(state.copyWith(reminder: null)),
                  ),
            onTap: () {
              _openPickerPage(
                context,
                TaskMetadataSelectionPage<TaskReminderOption>(
                  title: 'Lembrete',
                  selected: state.reminder,
                  options: TaskReminderOption.values.where(
                    (option) => option.isRelative == state.hasTime,
                  ),
                  noneLabel: 'Nenhum',
                  optionLabel: (value) => value.label,
                  optionIcon: (_) => Icons.notifications_outlined,
                  onSelected: (value) => _update(
                    state.copyWith(
                      reminder: value,
                      scheduleAnchor:
                          state.scheduleAnchor ??
                          (value == null ? null : DateTime.now().startOfDay),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  DateTime _mergeDateAndTime(DateTime date) {
    final draft = _draftNotifier.value;
    final current = draft.scheduleAnchor;
    if (!draft.hasTime || current == null) return date;
    return DateTime(
      date.year,
      date.month,
      date.day,
      current.hour,
      current.minute,
      current.second,
      current.millisecond,
      current.microsecond,
    );
  }
}
