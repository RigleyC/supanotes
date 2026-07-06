import 'package:supanotes/core/constants/app_constants.dart';

String? deriveNoteExcerpt(
  String content, {
  int maxLength = AppConstants.noteExcerptMaxLength,
}) {
  if (content.isEmpty) return null;
  final lines = content.split('\n');
  int firstNonEmptyIdx = -1;
  for (int i = 0; i < lines.length; i++) {
    if (lines[i].trim().isNotEmpty) {
      firstNonEmptyIdx = i;
      break;
    }
  }
  if (firstNonEmptyIdx == -1) return null;
  final restOfLines = lines.skip(firstNonEmptyIdx + 1).join('\n');
  final cleanContent = restOfLines.replaceAll(RegExp(r'[#*`\[\]_>]'), '');
  final flat = cleanContent.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (flat.isEmpty) return null;
  if (flat.length <= maxLength) return flat;
  return '${flat.substring(0, maxLength)}…';
}
