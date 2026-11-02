library;

import 'package:flutter/material.dart';
import 'package:block_editor/block_editor.dart';

/// [BlockPlugin] for [BlockTypes.code].
///
/// Stores code content in [BlockNode.attributes]:
///
/// - `code` — the code string to display.
/// - `language` — the language identifier (e.g. `'dart'`, `'python'`).
///
/// Renders the code in a monospace container. When [CodeBlockConfig.showLineNumbers]
/// is true, line numbers are shown to the left of each line. When
/// [CodeBlockConfig.showLanguageSelector] is true, a tappable language label
/// is shown in the top-right corner — tapping it emits a [CustomBlockEvent]
/// with `eventType: 'code_language_change_requested'` carrying the current
/// language as payload.
///
/// Configuration is read from [CodeBlockConfig] via [BlockEditorScope].
final class CodeBlock extends BlockPlugin {
  /// Creates a [CodeBlock].
  CodeBlock();

  @override
  String get blockType => BlockTypes.code;

  @override
  Widget build(
    BlockNode node,
    EditorSelection selection,
    void Function(BlockEvent) onEvent,
  ) {
    return _CodeBlockWidget(node: node, onEvent: onEvent);
  }

  @override
  Map<String, dynamic> serialize(BlockNode node) => node.toJson();

  @override
  BlockNode deserialize(Map<String, dynamic> json) => BlockNode.fromJson(json);

  @override
  SlashCommandConfig slashCommandItem() => SlashCommandConfig(
    label: 'Code',
    group: 'Basic',
    icon: const Icon(Icons.code),
    onSelected: () {},
  );

  @override
  String slashCommandGroup() => 'Basic';
}

class _CodeBlockWidget extends StatelessWidget {
  const _CodeBlockWidget({required this.node, required this.onEvent});

  final BlockNode node;
  final void Function(BlockEvent) onEvent;

  static const Color _background = Color(0xFF1E1E1E);
  static const Color _codeColor = Color(0xFFD4D4D4);
  static const Color _lineNumberColor = Color(0xFF858585);
  static const Color _languageLabelColor = Color(0xFF858585);
  static const String _defaultFont = 'monospace';

  String get _code => node.attributes['code'] as String? ?? '';
  String get _language => node.attributes['language'] as String? ?? 'plaintext';

  @override
  Widget build(BuildContext context) {
    final config = BlockEditorScope.maybeOf(context)?.codeConfig;
    final fontSize = config?.fontSize ?? 14.0;
    final showLineNumbers = config?.showLineNumbers ?? true;
    final showLanguageSelector = config?.showLanguageSelector ?? true;

    final lines = _code.split('\n');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: _background,
        borderRadius: BorderRadius.all(Radius.circular(6)),
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showLanguageSelector) const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showLineNumbers)
                    Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: List.generate(
                          lines.length,
                          (i) => Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontFamily: _defaultFont,
                              fontSize: fontSize,
                              color: _lineNumberColor,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: Text(
                      _code,
                      style: TextStyle(
                        fontFamily: _defaultFont,
                        fontSize: fontSize,
                        color: _codeColor,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (showLanguageSelector)
            Positioned(
              top: 0,
              right: 0,
              child: GestureDetector(
                onTap: () => onEvent(
                  CustomBlockEvent(
                    blockId: node.id,
                    eventType: 'code_language_change_requested',
                    payload: _language,
                  ),
                ),
                child: Text(
                  _language,
                  style: const TextStyle(
                    fontFamily: _defaultFont,
                    fontSize: 12,
                    color: _languageLabelColor,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
