class ShareLinkModel {
  const ShareLinkModel({required this.active, this.url});

  final bool active;
  final String? url;

  factory ShareLinkModel.fromJson(Map<String, dynamic> json) => ShareLinkModel(
    active: json['active'] as bool? ?? false,
    url: json['url'] as String?,
  );
}
