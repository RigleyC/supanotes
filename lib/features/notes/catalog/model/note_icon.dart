import 'package:flutter/material.dart';

enum NoteIconKind { emoji, catalog }

class NoteIcon {
  const NoteIcon._({
    required this.kind,
    required this.value,
    this.colorKey,
  });

  factory NoteIcon.emoji(String value) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(value, 'value', 'Emoji cannot be empty');
    }
    return NoteIcon._(kind: NoteIconKind.emoji, value: value, colorKey: null);
  }

  factory NoteIcon.catalog({required String id, required String colorKey}) {
    if (!catalogIconIds.contains(id)) {
      throw ArgumentError.value(id, 'id', 'Unknown catalog icon');
    }
    if (!noteIconColors.containsKey(colorKey)) {
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
      'emoji' => NoteIcon.emoji(value),
      'catalog' => NoteIcon.catalog(
        id: value,
        colorKey: json['color_key'] as String? ?? '',
      ),
      _ => throw FormatException('Unknown note icon kind: $kind'),
    };
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

  IconData? get catalogIcon => kind == NoteIconKind.catalog
      ? catalogIcons[value]
      : null;

  Color colorFor(ColorScheme scheme) {
    final color = noteIconColors[colorKey];
    if (color == null) return scheme.onSurfaceVariant;
    return color.resolve(scheme.brightness);
  }
}

const catalogIcons = <String, IconData>{
  'wallet': Icons.account_balance_wallet_outlined,
  'arrow_down': Icons.arrow_downward_rounded,
  'star': Icons.star_rounded,
  'lock': Icons.lock_outline_rounded,
  'home': Icons.home_outlined,
  'calendar': Icons.calendar_month_outlined,
  'basket': Icons.shopping_basket_outlined,
  'travel': Icons.flight_takeoff_rounded,
  'book': Icons.menu_book_outlined,
  'bookmark': Icons.bookmark_outline_rounded,
  'code': Icons.code_rounded,
  'braces': Icons.data_object_rounded,
  'building': Icons.business_outlined,
  'sparkles': Icons.auto_awesome_rounded,
  'camera': Icons.camera_alt_outlined,
  'car': Icons.directions_car_outlined,
  'cart': Icons.shopping_cart_outlined,
  'warning': Icons.warning_amber_rounded,
  'chart': Icons.bar_chart_rounded,
  'chat': Icons.chat_bubble_outline_rounded,
  'cloud': Icons.cloud_outlined,
  'settings': Icons.settings_outlined,
  'crown': Icons.workspace_premium_outlined,
  'monitor': Icons.desktop_windows_outlined,
  'money': Icons.attach_money_rounded,
  'globe': Icons.language_rounded,
  'eye': Icons.visibility_outlined,
  'fire': Icons.local_fire_department_outlined,
  'flag': Icons.flag_outlined,
  'game': Icons.sports_esports_outlined,
};

const catalogIconLabels = <String, String>{
  'wallet': 'Carteira',
  'arrow_down': 'Baixar',
  'star': 'Estrela',
  'lock': 'Privado',
  'home': 'Casa',
  'calendar': 'Calendário',
  'basket': 'Compras',
  'travel': 'Viagem',
  'book': 'Livro',
  'bookmark': 'Marcador',
  'code': 'Código',
  'braces': 'Dados',
  'building': 'Empresa',
  'sparkles': 'Ideias',
  'camera': 'Fotos',
  'car': 'Carro',
  'cart': 'Carrinho',
  'warning': 'Atenção',
  'chart': 'Gráfico',
  'chat': 'Conversa',
  'cloud': 'Nuvem',
  'settings': 'Configurações',
  'crown': 'Importante',
  'monitor': 'Computador',
  'money': 'Dinheiro',
  'globe': 'Internet',
  'eye': 'Visualização',
  'fire': 'Urgente',
  'flag': 'Projeto',
  'game': 'Jogo',
};

final catalogIconIds = catalogIcons.keys.toSet();

class NoteIconColor {
  const NoteIconColor(this.light, this.dark);

  final Color light;
  final Color dark;

  Color resolve(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}

const noteIconColors = <String, NoteIconColor>{
  'red': NoteIconColor(Color(0xFFB3261E), Color(0xFFFFB4AB)),
  'orange': NoteIconColor(Color(0xFF8A4B00), Color(0xFFFFB870)),
  'yellow': NoteIconColor(Color(0xFF6B5200), Color(0xFFFFD95A)),
  'green': NoteIconColor(Color(0xFF146C2E), Color(0xFF7BE495)),
  'teal': NoteIconColor(Color(0xFF006A6A), Color(0xFF5DDADA)),
  'blue': NoteIconColor(Color(0xFF2455A4), Color(0xFFA8C7FA)),
  'indigo': NoteIconColor(Color(0xFF5146A5), Color(0xFFC5BEFF)),
  'purple': NoteIconColor(Color(0xFF7B3FA0), Color(0xFFE2B7FF)),
  'pink': NoteIconColor(Color(0xFFA03467), Color(0xFFFFB0D0)),
  'brown': NoteIconColor(Color(0xFF6F4A32), Color(0xFFE6BFA3)),
  'gray': NoteIconColor(Color(0xFF5F6368), Color(0xFFD0D3D8)),
  'black': NoteIconColor(Color(0xFF202124), Color(0xFFF4F4F4)),
};
