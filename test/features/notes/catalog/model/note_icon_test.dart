import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/catalog/model/note_icon.dart';
import 'package:supanotes/features/notes/catalog/presentation/widgets/note_icon_catalog.dart';

void main() {
  test('round trips emoji metadata', () {
    final icon = NoteIcon.emoji('🙂');

    expect(NoteIcon.fromJson(icon.toJson()).toJson(), icon.toJson());
  });

  test('accepts long ZWJ emoji sequences from the picker catalog', () {
    final icon = NoteIcon.emoji('👨🏼‍❤️‍💋‍👨🏽');

    expect(NoteIcon.fromJson(icon.toJson()).toJson(), icon.toJson());
  });

  test('round trips colored catalog metadata', () {
    final icon = NoteIcon.catalog(id: 'star', colorKey: 'blue');

    expect(NoteIcon.fromJson(icon.toJson()).toJson(), icon.toJson());
  });

  test('rejects malformed catalog metadata', () {
    expect(
      () => NoteIcon.fromJson({'kind': 'catalog', 'value': 'star'}),
      throwsFormatException,
    );
    expect(
      () => NoteIcon.fromJson({
        'kind': 'catalog',
        'value': 'unknown',
        'color_key': 'blue',
      }),
      throwsFormatException,
    );
  });

  test('rejects plain text as emoji metadata', () {
    expect(() => NoteIcon.emoji('abc'), throwsArgumentError);
    expect(
      () => NoteIcon.fromJson({'kind': 'emoji', 'value': 'abc'}),
      throwsFormatException,
    );
  });

  test('rejects a color on emoji metadata', () {
    expect(
      () => NoteIcon.fromJson({
        'kind': 'emoji',
        'value': '🙂',
        'color_key': null,
      }),
      throwsFormatException,
    );
  });

  test('keeps the presentation catalog aligned with the wire contract', () {
    final contract =
        jsonDecode(
              File('test/fixtures/note_icon_contract.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    final catalogIconFixture = (contract['catalog_icons'] as List)
        .cast<String>();
    final colorKeyFixture = (contract['color_keys'] as List).cast<String>();

    expect(contract['max_emoji_bytes'], maxNoteIconBytes);
    expect(catalogIconIds, catalogIconFixture.toSet());
    expect(noteIconColorKeys, colorKeyFixture.toSet());
    expect(catalogIcons.keys.toList(), catalogIconFixture);
    expect(catalogIconLabels.keys.toList(), catalogIconFixture);
    expect(noteIconColors.keys.toList(), colorKeyFixture);
  });
}
