part of 'note_icon_picker.dart';

const _pickerGridMinTileExtent = 48.0;
const _pickerGridMaxColumns = 8;
const _pickerGridSpacing = 8.0;
const _pickerGridCrossAxisSpacing = 4.0;

class _PickerScrollPage extends StatelessWidget {
  const _PickerScrollPage({
    required this.title,
    required this.headerChildren,
    required this.itemCount,
    required this.itemBuilder,
    this.onBack,
  });

  final String title;
  final List<Widget> headerChildren;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PickerHeader(title: title, onBack: onBack),
                const SizedBox(height: AppSpacing.md),
                ...headerChildren,
              ],
            ),
          ),
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
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
      ),
    );
  }
}

class _PickerPage extends StatelessWidget {
  const _PickerPage({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PickerHeader(title: title),
              const SizedBox(height: AppSpacing.md),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _PickerHeader extends StatelessWidget {
  const _PickerHeader({required this.title, this.onBack});

  final String title;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (onBack != null)
          AppIconButton(
            onPressed: onBack,
            tooltip: 'Voltar',
            icon: const Icon(Icons.arrow_back),
          ),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
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
