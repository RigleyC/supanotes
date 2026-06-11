/// Bottom sheet that shows the agent's proposed organization plan for
/// the inbox and lets the user accept / reject each move before
/// applying.
///
/// Three states cycle inside the sheet:
///   * loading — `CircularProgressIndicator` while the plan is fetched
///   * error   — message + "Tentar novamente" button
///   * plan    — scrollable list of plan items with toggles and footer
///
/// `showInboxOrganizeSheet` is a convenience that wraps the sheet in a
/// `showModalBottomSheet` and resolves to the `OrganizationPlan` (with
/// final accepted flags) when the user successfully applied a plan, or
/// `null` if they cancelled.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/features/agent/data/inbox_organize_repository.dart';
import 'package:supanotes/features/agent/domain/organization_plan.dart';
import 'package:supanotes/features/agent/domain/destination_type.dart';
import 'package:supanotes/shared/theme/app_colors.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/theme/app_typography.dart';

// ---------------------------------------------------------------------------
// Sheet state – sealed class for exhaustive handling
// ---------------------------------------------------------------------------

sealed class _SheetState {}

class _Loading extends _SheetState {}

class _Error extends _SheetState {
  final String message;
  _Error(this.message);
}

class _PlanReady extends _SheetState {
  final OrganizationPlan plan;
  _PlanReady(this.plan);
}

class _Applying extends _SheetState {
  final OrganizationPlan plan;
  _Applying(this.plan);
}

// ---------------------------------------------------------------------------
// Convenience entry-point
// ---------------------------------------------------------------------------

Future<OrganizationPlan?> showInboxOrganizeSheet(
    BuildContext context) async {
  final result = await showModalBottomSheet<OrganizationPlan>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const InboxOrganizeSheet(),
  );
  return result;
}

// ---------------------------------------------------------------------------
// Sheet widget
// ---------------------------------------------------------------------------

class InboxOrganizeSheet extends ConsumerStatefulWidget {
  const InboxOrganizeSheet({super.key});

  @override
  ConsumerState<InboxOrganizeSheet> createState() => _InboxOrganizeSheetState();
}

class _InboxOrganizeSheetState extends ConsumerState<InboxOrganizeSheet> {
  _SheetState _state = _Loading();

  OrganizationPlan? _currentPlan() => switch (_state) {
    _PlanReady(:final plan) => plan,
    _Applying(:final plan) => plan,
    _ => null,
  };

  bool get _canApply => switch (_state) {
    _PlanReady(plan: final p) => p.items.any((i) => i.accepted),
    _ => false,
  };

  int get _acceptedCount => switch (_state) {
    _PlanReady(plan: final p) => p.items.where((i) => i.accepted).length,
    _Applying(plan: final p) => p.items.where((i) => i.accepted).length,
    _ => 0,
  };

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _state = _Loading());
    try {
      final plan =
          await ref.read(inboxOrganizeRepositoryProvider).planInboxOrganization();
      if (!mounted) return;
      setState(() => _state = _PlanReady(plan));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _state = _Error(e.message));
    } catch (e) {
      if (!mounted) return;
      setState(() => _state = _Error(e.toString()));
    }
  }

  Future<void> _apply() async {
    final plan = _currentPlan();
    if (plan == null) return;
    setState(() => _state = _Applying(plan));
    try {
      await ref.read(inboxOrganizeRepositoryProvider).applyOrganizationPlan(plan);
      if (!mounted) return;
      Navigator.of(context).pop(_currentPlan());
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _state = _Error(e.message));
    } catch (e) {
      if (!mounted) return;
      setState(() => _state = _Error(e.toString()));
    }
  }

  void _toggle(int index, bool? value) {
    final plan = _currentPlan();
    if (plan == null) return;
    setState(() {
      _state = _PlanReady(OrganizationPlan(
        planId: plan.planId,
        items: List<OrganizationPlanItem>.generate(plan.items.length, (i) {
          return i == index
              ? plan.items[i].copyWith(accepted: value ?? false)
              : plan.items[i];
        }),
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(
                  left: AppSpacing.xs,
                  top: AppSpacing.xs,
                  bottom: AppSpacing.md,
                ),
                child: Text(
                  'Organizar rascunho',
                  style: AppTypography.textTheme.titleLarge?.copyWith(
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              Expanded(child: _buildBody(colorScheme)),
              _buildFooter(colorScheme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ColorScheme colorScheme) {
    return switch (_state) {
      _Loading() => Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Analisando rascunho…',
              style: AppTypography.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      _Error(:final message) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: colorScheme.error, size: 32),
              const SizedBox(height: AppSpacing.sm),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: AppTypography.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton.tonal(
                onPressed: _fetch,
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      _PlanReady(:final plan) => _buildPlanItems(plan, colorScheme),
      _Applying(:final plan) => _buildPlanItems(plan, colorScheme),
    };
  }

  Widget _buildPlanItems(OrganizationPlan plan, ColorScheme colorScheme) {
    if (plan.items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined,
                size: 48, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Nada para organizar no momento.',
              style: AppTypography.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: plan.items.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        color: colorScheme.outlineVariant,
      ),
      itemBuilder: (context, index) {
        final item = plan.items[index];
        return _PlanItemTile(
          item: item,
          onChanged: (v) => _toggle(index, v),
        );
      },
    );
  }

  Widget _buildFooter(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        children: [
          TextButton(
            onPressed: _state is _Applying ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          const Spacer(),
          FilledButton(
            onPressed: _canApply ? _apply : null,
            child: Text('Aplicar $_acceptedCount selecionados'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Plan item tile
// ---------------------------------------------------------------------------

class _PlanItemTile extends StatelessWidget {
  const _PlanItemTile({required this.item, required this.onChanged});

  final OrganizationPlanItem item;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final style = _destinationStyle(colorScheme);

    return SwitchListTile(
      value: item.accepted,
      onChanged: onChanged,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xs,
      ),
      title: Text(
        item.originalSnippet,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurface,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Row(
          children: [
            Icon(style.icon, size: 14, color: style.color),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                style.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.textTheme.labelSmall?.copyWith(
                  color: style.color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  ({String label, IconData icon, Color color}) _destinationStyle(
      ColorScheme s) {
    return switch (item.destinationType) {
      DestinationType.newNote => (
        label: 'Nova nota: ${item.destinationTitle ?? "sem título"}',
        icon: Icons.note_add_outlined,
        color: AppColors.info,
      ),
      DestinationType.existingNote => (
        label: 'Mover para: ${item.destinationTitle ?? "nota existente"}',
        icon: Icons.drive_file_move_outline,
        color: s.primary,
      ),
      DestinationType.keep => (
        label: 'Manter no rascunho',
        icon: Icons.inbox_outlined,
        color: s.onSurfaceVariant,
      ),
    };
  }
}
