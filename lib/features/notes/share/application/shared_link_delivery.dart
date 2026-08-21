import 'package:supanotes/core/api/api_client.dart';

final class SharedLinkDelivery {
  const SharedLinkDelivery(this._api);

  final ApiClient _api;

  /// Extracts the first http(s) URL from shared text, trimming trailing
  /// punctuation that share targets tend to append. The server re-validates
  /// the result; this is a UX-level pre-filter only.
  static Uri? extractUrlFromText(String text) {
    final match = RegExp(
      r'https?://[^\s<>"“”]+',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) return null;
    var value = match.group(0)!;
    while (value.isNotEmpty && '.,;:!?)]}'.contains(value[value.length - 1])) {
      value = value.substring(0, value.length - 1);
    }
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return uri;
  }

  Future<void> appendToNote({
    required String noteId,
    required Uri url,
    required String shareId,
  }) async {
    await _api.post<void>(
      '/notes/$noteId/shared-links',
      data: {
        'shareId': shareId,
        'url': url.toString(),
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }
}
