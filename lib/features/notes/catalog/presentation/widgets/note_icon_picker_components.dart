part of 'note_icon_picker.dart';

const _pickerGridMinTileExtent = 48.0;
const _pickerGridMaxColumns = 8;
const _pickerGridSpacing = 8.0;
const _pickerGridCrossAxisSpacing = 4.0;

class _PickerGridContent extends StatelessWidget {
  const _PickerGridContent({
    required this.headerChildren,
    required this.itemCount,
    required this.itemBuilder,
  });

  final List<Widget> headerChildren;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: headerChildren,
          ),
        ),
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final crossAxisCount = math
                        .max(
                          1,
                          ((constraints.crossAxisExtent +
                                      _pickerGridCrossAxisSpacing) /
                                  (_pickerGridMinTileExtent +
                                      _pickerGridCrossAxisSpacing))
                              .floor(),
                        )
                        .clamp(1, _pickerGridMaxColumns)
                        .toInt();
                    return SliverGrid(
                      delegate: SliverChildBuilderDelegate(
                        itemBuilder,
                        childCount: itemCount,
                      ),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        mainAxisSpacing: _pickerGridSpacing,
                        crossAxisSpacing: _pickerGridCrossAxisSpacing,
                        childAspectRatio: 1,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PickerAction extends StatelessWidget {
  const _PickerAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        leading: Icon(icon, size: 20),
        title: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w500),
        ),
        onTap: onTap,
      ),
    );
  }
}
