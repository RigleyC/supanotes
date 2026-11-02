import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:supanotes/core/utils/app_haptics.dart';
import 'package:supanotes/core/utils/recurrence.dart';
import 'package:supanotes/features/notes/editor/appflowy/note_appflowy_codec.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/task_text_style_resolver.dart';
import 'package:supanotes/features/tasks/domain/task_completion_state.dart';
import 'package:supanotes/features/tasks/domain/task_occurrence.dart';
import 'package:supanotes/features/tasks/presentation/controllers/task_metadata_draft.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_metadata_badges.dart';
import 'package:supanotes/shared/theme/app_colors.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';
import 'package:supanotes/shared/widgets/app_task_checkbox.dart';
import 'package:supanotes/shared/widgets/task_exit_animator.dart';

const _occurrencePolicy = TaskOccurrencePolicy();

/// What the note editor does when the user acts on a task block.
final class NoteTaskActions {
  const NoteTaskActions({
    this.onComplete,
    this.onReopen,
    this.onOpenDetails,
  });

  /// Completes the current occurrence of task [blockId].
  final Future<void> Function(String blockId)? onComplete;

  /// Reopens task [blockId], or its occurrence at [scheduledAt].
  final Future<void> Function(String blockId, DateTime? scheduledAt)? onReopen;

  /// Opens the task's date, recurrence and reminder sheet.
  final void Function(String blockId)? onOpenDetails;
}

/// Whether a task block currently counts as done: for a recurring task, its
/// current occurrence is completed.
({bool isComplete, DateTime? occurrence}) resolveTaskCompletion(Node node) {
  final metadata = TaskMetadataDraft.fromMetadata(
    Map<String, dynamic>.from(
      node.attributes[NoteNodeKeys.metadata] as Map? ?? const {},
    ),
  );
  final occurrence = _occurrencePolicy.resolveCurrent(
    taskId: node.id,
    anchor: metadata.scheduleAnchor,
    recurrence: metadata.recurrence,
    hasTime: metadata.hasTime,
    completedAtByScheduledAt: metadata.completions,
  );
  return (
    isComplete: isTaskOccurrenceCompleted(
      isComplete: node.attributes[TodoListBlockKeys.checked] as bool? ?? false,
      recurrence: metadata.recurrence,
      occurrence: occurrence,
    ),
    occurrence: occurrence?.scheduledAt,
  );
}

/// Renders a note task the way SupaNotes always has: rounded checkbox,
/// struck-through text when done and a metadata row (date, repeat, reminder).
final class NoteTaskBlockComponentBuilder extends BlockComponentBuilder {
  NoteTaskBlockComponentBuilder({
    required this.actions,
    required this.readOnly,
    required this.hideCompleted,
    super.configuration,
  });

  final NoteTaskActions actions;
  final bool readOnly;
  final bool hideCompleted;

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return NoteTaskBlockComponent(
      key: node.key,
      node: node,
      configuration: configuration,
      actions: actions,
      readOnly: readOnly,
      hideCompleted: hideCompleted,
    );
  }

  @override
  BlockComponentValidate get validate =>
      (node) => node.delta != null;
}

class NoteTaskBlockComponent extends BlockComponentStatefulWidget {
  const NoteTaskBlockComponent({
    required super.node,
    required this.actions,
    required this.readOnly,
    required this.hideCompleted,
    super.key,
    super.configuration = const BlockComponentConfiguration(),
  });

  final NoteTaskActions actions;
  final bool readOnly;
  final bool hideCompleted;

  @override
  State<NoteTaskBlockComponent> createState() => _NoteTaskBlockState();
}

class _NoteTaskBlockState extends State<NoteTaskBlockComponent>
    with
        SelectableMixin,
        DefaultSelectableMixin,
        BlockComponentConfigurable,
        BlockComponentBackgroundColorMixin,
        NestedBlockComponentStatefulWidgetMixin,
        BlockComponentTextDirectionMixin,
        BlockComponentAlignMixin {
  static const _checkboxSize = 20.0;
  static const _checkboxGap = 8.0;
  // With the 14 px spacing above each task (block padding) this keeps the
  // previous 44 px touch target without making short tasks taller.
  static const _touchHeight = 30.0;

  @override
  final forwardKey = GlobalKey(debugLabel: 'note_task_text');

  @override
  GlobalKey<State<StatefulWidget>> get containerKey => widget.node.key;

  @override
  GlobalKey<State<StatefulWidget>> blockComponentKey = GlobalKey(
    debugLabel: TodoListBlockKeys.type,
  );

  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  late bool _isComplete;
  DateTime? _occurrence;
  bool _updating = false;
  bool _animatingOut = false;
  Timer? _boundaryTimer;

  String get _blockId =>
      node.attributes[NoteNodeKeys.blockId] as String? ?? node.id;

  TaskMetadataDraft get _metadata => TaskMetadataDraft.fromMetadata(
    Map<String, dynamic>.from(
      node.attributes[NoteNodeKeys.metadata] as Map? ?? const {},
    ),
  );

  @override
  void initState() {
    super.initState();
    _readCompletion();
  }

  @override
  void didUpdateWidget(covariant NoteTaskBlockComponent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_updating) _readCompletion();
  }

  @override
  void dispose() {
    _boundaryTimer?.cancel();
    super.dispose();
  }

  void _readCompletion() {
    final state = resolveTaskCompletion(node);
    _isComplete = state.isComplete;
    _occurrence = state.occurrence;
    _scheduleOccurrenceRefresh();
  }

  /// A recurring occurrence changes at the next local day boundary (or its
  /// scheduled time); refresh then without waiting for an edit.
  void _scheduleOccurrenceRefresh() {
    _boundaryTimer?.cancel();
    final metadata = _metadata;
    final anchor = metadata.scheduleAnchor;
    final recurrence = metadata.recurrence;
    final scheduledAt = _occurrence;
    if (anchor == null || recurrence == null || scheduledAt == null) return;
    final next = nextDueDate(
      from: scheduledAt,
      recurrence: recurrence,
      anchorDay: anchor.day,
    );
    if (next == null) return;
    final now = DateTime.now();
    final boundaries = [
      scheduledAt,
      DateTime(scheduledAt.year, scheduledAt.month, scheduledAt.day),
      DateTime(next.year, next.month, next.day),
    ].where((boundary) => boundary.isAfter(now));
    if (boundaries.isEmpty) return;
    final boundary = boundaries.reduce((a, b) => b.isBefore(a) ? b : a);
    _boundaryTimer = Timer(boundary.difference(now), () {
      if (!mounted) return;
      setState(_readCompletion);
    });
  }

  Future<void> _toggle() async {
    if (widget.readOnly || _updating) return;
    final previous = _isComplete;
    final complete = !_isComplete;
    setState(() {
      _isComplete = complete;
      _updating = true;
      _animatingOut = widget.hideCompleted && complete;
    });
    unawaited(AppHaptics.taskCompletion());
    try {
      if (complete) {
        await widget.actions.onComplete?.call(_blockId);
      } else {
        await widget.actions.onReopen?.call(_blockId, _occurrence);
      }
    } catch (error, stackTrace) {
      if (mounted) {
        setState(() {
          _isComplete = previous;
          _animatingOut = false;
        });
        AppMessenger.showError('Não foi possível atualizar a tarefa');
      }
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'supanotes note editor',
          context: ErrorDescription('while changing note task completion'),
        ),
      );
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  void _openDetails() {
    if (widget.readOnly) return;
    widget.actions.onOpenDetails?.call(_blockId);
  }

  @override
  Widget buildComponent(
    BuildContext context, {
    bool withBackgroundColor = true,
  }) {
    final scheme = Theme.of(context).colorScheme;
    // Center the checkbox on the first text line.
    final textStyle = textStyleWithTextSpan();
    final lineHeight = (textStyle.fontSize ?? 17) * (textStyle.height ?? 1.4);
    final checkboxTop = ((lineHeight - _checkboxSize) / 2).clamp(0.0, 12.0);
    final taskColor =
        Theme.of(context).extension<AppSemanticColors>()?.task ??
        AppColors.taskAccent;
    final metadata = _metadata;
    final textDirection = calculateTextDirection(
      layoutDirection: Directionality.maybeOf(context),
    );

    Widget child = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      textDirection: textDirection,
      children: [
        Semantics(
          button: true,
          checked: _isComplete,
          enabled: !widget.readOnly && !_updating,
          label: _isComplete
              ? 'Marcar tarefa como pendente'
              : 'Concluir tarefa',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.readOnly ? null : _toggle,
            onLongPress: widget.readOnly ? null : _openDetails,
            child: SizedBox(
              width: _checkboxSize + _checkboxGap,
              height: _touchHeight,
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: EdgeInsets.only(top: checkboxTop),
                  child: AppTaskCheckbox(
                    size: _checkboxSize,
                    value: _isComplete,
                    accentColor: taskColor,
                    inactiveColor: scheme.outline,
                    shape: AppTaskCheckboxShape.rounded,
                  ),
                ),
              ),
            ),
          ),
        ),
        Flexible(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onLongPress: widget.readOnly ? null : _openDetails,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                AppFlowyRichText(
                  key: forwardKey,
                  delegate: this,
                  node: widget.node,
                  editorState: editorState,
                  textAlign: alignment?.toTextAlign ?? textAlign,
                  placeholderText: placeholderText,
                  textDirection: textDirection,
                  textSpanDecorator: (textSpan) => textSpan.updateTextStyle(
                    resolveTaskTextStyle(
                      textStyleWithTextSpan(textSpan: textSpan),
                      scheme.onSurface,
                      _isComplete,
                    ),
                  ),
                  placeholderTextSpanDecorator: (textSpan) =>
                      textSpan.updateTextStyle(
                        placeholderTextStyleWithTextSpan(textSpan: textSpan),
                      ),
                  cursorColor: editorState.editorStyle.cursorColor,
                  selectionColor: editorState.editorStyle.selectionColor,
                  cursorWidth: editorState.editorStyle.cursorWidth,
                ),
                if (metadata.scheduleAnchor != null ||
                    metadata.recurrence != null ||
                    metadata.reminder != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 4),
                    child: TaskMetadataBadges(
                      dueDate: metadata.scheduleAnchor,
                      resolvedOccurrenceDate: _occurrence,
                      recurrence: metadata.recurrence,
                      hasReminder: metadata.reminder != null,
                      hasTime: metadata.hasTime,
                      completions: metadata.completions,
                      isCompleted: _isComplete,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );

    child = Container(
      key: blockComponentKey,
      decoration: withBackgroundColor ? decoration : null,
      padding: padding,
      width: double.infinity,
      alignment: alignment,
      child: child,
    );

    child = BlockSelectionContainer(
      node: node,
      delegate: this,
      listenable: editorState.selectionNotifier,
      remoteSelection: editorState.remoteSelections,
      blockColor: editorState.editorStyle.selectionColor,
      supportTypes: const [BlockSelectionType.block],
      child: child,
    );

    final hidden = widget.hideCompleted && _isComplete;
    return TaskExitAnimator(
      hideCompleted: widget.hideCompleted,
      isComplete: _isComplete,
      onAnimationComplete: _animatingOut
          ? () => setState(() => _animatingOut = false)
          : null,
      child: ExcludeSemantics(
        excluding: hidden,
        child: IgnorePointer(ignoring: hidden, child: child),
      ),
    );
  }
}
