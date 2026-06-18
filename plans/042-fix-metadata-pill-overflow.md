# Plan 042: Prevent _MetadataPill overflow on narrow screens

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 34998f2..HEAD -- lib/features/tasks/presentation/widgets/task_metadata_badges.dart`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: UX
- **Planned at**: commit `34998f2`, 2026-06-18

## Why this matters

`_MetadataPill` uses `Row` with `mainAxisSize: MainAxisSize.min`. If the label is long (e.g., "Atrasada · 15 Jun" in a narrow task tile), the `Row` can overflow. Wrapping the `Text` in `Flexible` with `overflow: TextOverflow.ellipsis` prevents this.

## Current state

- File: `lib/features/tasks/presentation/widgets/task_metadata_badges.dart`
- Widget: `_MetadataPill` (lines 83–109)

Current code:

```dart
class _MetadataPill extends StatelessWidget {
  const _MetadataPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: color),
        ),
      ],
    );
  }
}
```

## Commands you will need

| Purpose   | Command                              | Expected on success    |
|-----------|--------------------------------------|------------------------|
| Analyze   | `dart analyze lib/features/tasks/presentation/widgets/task_metadata_badges.dart` | No issues found |

## Scope

**In scope**:
- `lib/features/tasks/presentation/widgets/task_metadata_badges.dart` (only `_MetadataPill`)

**Out of scope**:
- `TaskMetadataBadges` parent widget
- Other badge-related files

## Steps

### Step 1: Wrap Text in Flexible with ellipsis

Replace the `Text` widget with a `Flexible` + `Text` combination:

```dart
@override
Widget build(BuildContext context) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 4),
      Flexible(
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: color),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}
```

### Step 2: Verify

**Verify**: `dart analyze lib/features/tasks/presentation/widgets/task_metadata_badges.dart` → No issues found

## Test plan

No new tests required — this is a layout safety change.

## Done criteria

- [ ] `dart analyze lib/features/tasks/presentation/widgets/task_metadata_badges.dart` exits 0
- [ ] `Text` in `_MetadataPill` is wrapped in `Flexible` with `overflow: TextOverflow.ellipsis`
- [ ] No files outside scope modified

## STOP conditions

- The code at lines 96–107 doesn't match the "Current state" excerpt.
- A step's verification fails twice.

## Maintenance notes

- The `Flexible` wrapper ensures the pill never overflows, but on very narrow screens the text will be truncated with "…". This is acceptable for badge labels.
- If the icon + text minimum width exceeds the parent, the `Row` will still clip. The parent `Wrap` handles this by flowing to the next line.
