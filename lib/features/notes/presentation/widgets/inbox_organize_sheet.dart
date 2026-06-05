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
/// `showModalBottomSheet` and resolves to `true` when the user actually
/// applied a plan so the caller knows to reload the inbox.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/features/agent/data/agent_repository.dart';
import 'package:supanotes/features/agent/domain/organization_plan.dart';
import 'package:supanotes/shared/theme/app_colors.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/theme/app_typography.dart';

Future<bool> showInboxOrganizeSheet(BuildContext context) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const InboxOrganizeSheet(),
  );
  return result ?? false;
}

class InboxOrganizeSheet extends ConsumerStatefulWidget {
  const InboxOrganizeSheet({super.key});

  @override
  ConsumerState<InboxOrganizeSheet> createState() => _InboxOrganizeSheetState();
}

class _InboxOrganizeSheetState extends ConsumerState<InboxOrganizeSheet> {
  OrganizationPlan? _plan;
  String? _error;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _plan = null;
      _error = null;
    });
    try {
      final plan = await ref.read(agentRepositoryProvider).planInboxOrganization();
      if (!mounted) return;
      setState(() => _plan = plan);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _apply() async {
    final plan = _plan;
    if (plan == null) return;
    final accepted = plan.items
        .where((i) => i.accepted)
        .map((i) => i.itemId)
        .toList(growable: false);
    if (accepted.isEmpty) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() => _applying = true);
    try {
      await ref.read(agentRepositoryProvider).applyOrganizationPlan(
            planId: plan.planId,
            acceptedItemIds: accepted,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _applying = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _applying = false;
        _error = e.toString();
      });
    }
  }

  void _toggle(int index, bool? value) {
    final plan = _plan;
    if (plan == null) return;
    setState(() {
      _plan = OrganizationPlan(
        planId: plan.planId,
        items: List<OrganizationPlanItem>.generate(plan.items.length, (i) {
          return i == index
              ? plan.items[i].copyWith(accepted: value ?? false)
              : plan.items[i];
        }),
      );
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
    if (_error != null && _plan == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: colorScheme.error, size: 32),
            const SizedBox(height: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: AppTypography.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.tonal(
              onPressed: _applying ? null : _fetch,
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      );
    }
    if (_plan == null) {
      return Column(
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
      );
    }
    final items = _plan!.items;
    if (items.isEmpty) {
      return Center(
        child: Text(
          'Nada para organizar no momento.',
          style: AppTypography.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: items.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: colorScheme.outlineVariant,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        return _PlanItemTile(
          item: item,
          onChanged: (v) => _toggle(index, v),
        );
      },
    );
  }

  Widget _buildFooter(ColorScheme colorScheme) {
    final plan = _plan;
    final acceptedCount =
        plan == null ? 0 : plan.items.where((i) => i.accepted).length;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        children: [
          TextButton(
            onPressed:
                _applying ? null : () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          const Spacer(),
          FilledButton(
            onPressed: (_applying || plan == null || acceptedCount == 0)
                ? null
                : _apply,
            child: Text('Aplicar $acceptedCount selecionados'),
          ),
        ],
      ),
    );
  }
}

class _PlanItemTile extends StatelessWidget {
  const _PlanItemTile({required this.item, required this.onChanged});

  final OrganizationPlanItem item;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final destination = _destinationLabel();

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
            Icon(_destinationIcon(),
                size: 14, color: _destinationColor(colorScheme)),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                destination,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.textTheme.labelSmall?.copyWith(
                  color: _destinationColor(colorScheme),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _destinationLabel() {
    switch (item.destinationType) {
      case 'new_note':
        return 'Nova nota: ${item.destinationTitle ?? "sem título"}';
      case 'existing_note':
        return 'Mover para: ${item.destinationTitle ?? "nota existente"}';
      case 'keep':
      default:
        return 'Manter no rascunho';
    }
  }

  IconData _destinationIcon() {
    switch (item.destinationType) {
      case 'new_note':
        return Icons.note_add_outlined;
      case 'existing_note':
        return Icons.drive_file_move_outline;
      case 'keep':
      default:
        return Icons.inbox_outlined;
    }
  }

  Color _destinationColor(ColorScheme colorScheme) {
    switch (item.destinationType) {
      case 'new_note':
        return AppColors.info;
      case 'existing_note':
        return colorScheme.primary;
      case 'keep':
      default:
        return colorScheme.onSurfaceVariant;
    }
  }
}
