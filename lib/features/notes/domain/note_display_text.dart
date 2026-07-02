import 'package:supanotes/core/constants/app_constants.dart';
import 'package:supanotes/features/notes/domain/note_strings.dart';

String deriveNoteTitle(String content) {
  if (content.trim().isEmpty) return NoteStrings.fallbackTitle;
  final lines = content.split('\n');
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isNotEmpty) {
      var clean = trimmed.replaceFirst(RegExp(r'^#+\s*'), '');
      clean = clean.replaceFirst(RegExp(r'^[-*]\s*\[[ xX]\]\s*'), '');
      clean = clean.replaceFirst(RegExp(r'^[-*]\s*'), '');
      clean = clean.replaceFirst(RegExp(r'^\d+\.\s*'), '');
      return clean.trim().isNotEmpty ? clean.trim() : NoteStrings.fallbackTitle;
    }
  }
  return NoteStrings.fallbackTitle;
}

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
  final flat = restOfLines.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (flat.isEmpty) return null;
  if (flat.length <= maxLength) return flat;
  return '${flat.substring(0, maxLength)}…';
}
