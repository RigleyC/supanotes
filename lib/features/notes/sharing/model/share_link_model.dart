class ShareLinkModel {
  const ShareLinkModel({required this.active, this.url});

  final bool active;
  final String? url;

  factory ShareLinkModel.fromJson(Map<String, dynamic> json) {
    final active = json['active'];
    if (active is! bool) {
      throw const FormatException('Share link response is missing active');
    }

    final rawUrl = json['url'];
    if (rawUrl != null && rawUrl is! String) {
      throw const FormatException('Share link response has an invalid url');
    }
    final url = rawUrl as String?;
    if (active && (url == null || url.isEmpty)) {
      throw const FormatException('Active share link response is missing url');
    }
    return ShareLinkModel(active: active, url: url);
  }

  @override
  bool operator ==(Object other) {
    return other is ShareLinkModel &&
        other.active == active &&
        other.url == url;
  }

  @override
  int get hashCode => Object.hash(active, url);
}
