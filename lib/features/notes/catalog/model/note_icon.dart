import 'dart:convert';

// Covers the longest current Unicode emoji sequences, including ZWJ and skin
// tone modifiers, while keeping arbitrary payloads out of note metadata.
const maxNoteIconBytes = 64;

/// Identifiers accepted by the note-icon wire contract.
///
/// The values are deliberately presentation-neutral. Flutter resolves these
/// identifiers to glyphs in the catalog presentation layer.
const catalogIconIds = <String>{
  'wallet',
  'arrow_down',
  'star',
  'lock',
  'home',
  'calendar',
  'basket',
  'travel',
  'book',
  'bookmark',
  'code',
  'braces',
  'building',
  'sparkles',
  'camera',
  'car',
  'cart',
  'warning',
  'chart',
  'chat',
  'cloud',
  'settings',
  'crown',
  'monitor',
  'money',
  'globe',
  'eye',
  'fire',
  'flag',
  'game',
};

/// Color keys accepted by a catalog note icon.
const noteIconColorKeys = <String>{
  'red',
  'orange',
  'yellow',
  'green',
  'teal',
  'blue',
  'indigo',
  'purple',
  'pink',
  'brown',
  'gray',
  'black',
};

enum NoteIconKind { emoji, catalog }

class NoteIcon {
  const NoteIcon._({required this.kind, required this.value, this.colorKey});

  factory NoteIcon.emoji(String value) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(value, 'value', 'Emoji cannot be empty');
    }
    if (!value.runes.any(_isEmojiCodePoint)) {
      throw ArgumentError.value(value, 'value', 'Value must contain an emoji');
    }
    if (utf8.encode(value).length > maxNoteIconBytes) {
      throw ArgumentError.value(value, 'value', 'Emoji is too long');
    }
    return NoteIcon._(kind: NoteIconKind.emoji, value: value);
  }

  factory NoteIcon.catalog({required String id, required String colorKey}) {
    if (!catalogIconIds.contains(id)) {
      throw ArgumentError.value(id, 'id', 'Unknown catalog icon');
    }
    if (!noteIconColorKeys.contains(colorKey)) {
      throw ArgumentError.value(colorKey, 'colorKey', 'Unknown icon color');
    }
    return NoteIcon._(
      kind: NoteIconKind.catalog,
      value: id,
      colorKey: colorKey,
    );
  }

  factory NoteIcon.fromJson(Map<String, dynamic> json) {
    final kind = json['kind'];
    final value = json['value'];
    if (kind is! String || value is! String) {
      throw const FormatException('Invalid note icon');
    }
    return switch (kind) {
      'emoji' => _emojiFromJson(value, json),
      'catalog' => _catalogFromJson(value, json['color_key']),
      _ => throw FormatException('Unknown note icon kind: $kind'),
    };
  }

  static NoteIcon _emojiFromJson(String value, Map<String, dynamic> json) {
    if (json.containsKey('color_key')) {
      throw const FormatException('Emoji cannot have a color');
    }
    try {
      return NoteIcon.emoji(value);
    } on ArgumentError catch (error) {
      throw FormatException(error.message.toString());
    }
  }

  static NoteIcon _catalogFromJson(String id, Object? colorKey) {
    if (colorKey is! String) {
      throw const FormatException('Catalog icon color is required');
    }
    try {
      return NoteIcon.catalog(id: id, colorKey: colorKey);
    } on ArgumentError catch (error) {
      throw FormatException(error.message.toString());
    }
  }

  final NoteIconKind kind;
  final String value;
  final String? colorKey;

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'value': value,
    if (colorKey != null) 'color_key': colorKey,
  };

  bool get isEmoji => kind == NoteIconKind.emoji;
}

bool _isEmojiCodePoint(int rune) {
  return (rune >= 0x1F000 && rune <= 0x1FAFF) ||
      (rune >= 0x2300 && rune <= 0x23FF) ||
      (rune >= 0x2600 && rune <= 0x27BF) ||
      (rune >= 0x2B00 && rune <= 0x2BFF);
}
