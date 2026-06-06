/// `SegmentedButton` for picking the active [SearchMode].
///
/// Three options, each with a tooltip that explains how the strategy
/// works so the user can pick deliberately. The default surfaced to the
/// screen is [SearchMode.hybrid] — it gives the best recall on this
/// backend (RRF fusion of FTS + semantic, see
/// `backend/internal/db/sqlcgen/search.sql.go`).
library;

import 'package:flutter/material.dart';

import 'package:supanotes/features/search/domain/search_result_model.dart';

class SearchModeToggle extends StatelessWidget {
  const SearchModeToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final SearchMode value;
  final ValueChanged<SearchMode> onChanged;

  static const _ftsTooltip =
      'Texto: busca exata por palavras (rápida e literal).';
  static const _semanticTooltip =
      'Semântica: busca por significado usando embeddings.';
  static const _hybridTooltip =
      'Híbrida: combina texto e semântica (recomendado).';

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<SearchMode>(
      segments: const [
        ButtonSegment<SearchMode>(
          value: SearchMode.fts,
          label: Tooltip(message: _ftsTooltip, child: Text('Texto')),
          icon: Tooltip(message: _ftsTooltip, child: Icon(Icons.title)),
        ),
        ButtonSegment<SearchMode>(
          value: SearchMode.semantic,
          label: Tooltip(message: _semanticTooltip, child: Text('Semântica')),
          icon: Tooltip(
            message: _semanticTooltip,
            child: Icon(Icons.psychology_outlined),
          ),
        ),
        ButtonSegment<SearchMode>(
          value: SearchMode.hybrid,
          label: Tooltip(message: _hybridTooltip, child: Text('Híbrida')),
          icon: Tooltip(
            message: _hybridTooltip,
            child: Icon(Icons.auto_awesome),
          ),
        ),
      ],
      selected: <SearchMode>{value},
      showSelectedIcon: false,
      onSelectionChanged: (selection) {
        if (selection.isEmpty) return;
        onChanged(selection.first);
      },
    );
  }
}
