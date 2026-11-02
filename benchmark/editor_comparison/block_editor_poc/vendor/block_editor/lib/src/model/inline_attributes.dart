library;

import 'package:meta/meta.dart';

@immutable
final class InlineAttributes {
  const InlineAttributes({
    this.bold,
    this.italic,
    this.underline,
    this.strikethrough,
    this.inlineCode,
    this.link,
    this.color,
    this.backgroundColor,
  });

  factory InlineAttributes.fromJson(Map<String, dynamic> json) {
    return InlineAttributes(
      bold: json['bold'] as bool?,
      italic: json['italic'] as bool?,
      underline: json['underline'] as bool?,
      strikethrough: json['strikethrough'] as bool?,
      inlineCode: json['inlineCode'] as bool?,
      link: json['link'] as String?,
      color: json['color'] as String?,
      backgroundColor: json['backgroundColor'] as String?,
    );
  }

  final bool? bold;
  final bool? italic;
  final bool? underline;
  final bool? strikethrough;
  final bool? inlineCode;
  final String? link;
  final String? color;
  final String? backgroundColor;

  bool get isEmpty =>
      bold == null &&
      italic == null &&
      underline == null &&
      strikethrough == null &&
      inlineCode == null &&
      link == null &&
      color == null &&
      backgroundColor == null;

  Map<String, dynamic> toJson() {
    return {
      if (bold != null) 'bold': bold,
      if (italic != null) 'italic': italic,
      if (underline != null) 'underline': underline,
      if (strikethrough != null) 'strikethrough': strikethrough,
      if (inlineCode != null) 'inlineCode': inlineCode,
      if (link != null) 'link': link,
      if (color != null) 'color': color,
      if (backgroundColor != null) 'backgroundColor': backgroundColor,
    };
  }

  InlineAttributes copyWith({
    bool? bold,
    bool? italic,
    bool? underline,
    bool? strikethrough,
    bool? inlineCode,
    String? link,
    String? color,
    String? backgroundColor,
  }) {
    return InlineAttributes(
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      underline: underline ?? this.underline,
      strikethrough: strikethrough ?? this.strikethrough,
      inlineCode: inlineCode ?? this.inlineCode,
      link: link ?? this.link,
      color: color ?? this.color,
      backgroundColor: backgroundColor ?? this.backgroundColor,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is InlineAttributes &&
        other.bold == bold &&
        other.italic == italic &&
        other.underline == underline &&
        other.strikethrough == strikethrough &&
        other.inlineCode == inlineCode &&
        other.link == link &&
        other.color == color &&
        other.backgroundColor == backgroundColor;
  }

  @override
  int get hashCode => Object.hash(
    bold,
    italic,
    underline,
    strikethrough,
    inlineCode,
    link,
    color,
    backgroundColor,
  );

  @override
  String toString() => 'InlineAttributes(${toJson()})';
}
