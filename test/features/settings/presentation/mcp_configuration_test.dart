import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/settings/presentation/mcp_configuration.dart';

void main() {
  test('builds valid Streamable HTTP configuration with authorization', () {
    final json = buildClaudeMcpConfigJson(
      url: 'https://example.test/api/v1/mcp',
      token: 'sn_mcp_test-token',
    );

    final config = jsonDecode(json) as Map<String, dynamic>;
    final server =
        (config['mcpServers'] as Map<String, dynamic>)['supanotes']
            as Map<String, dynamic>;

    expect(server['type'], 'http');
    expect(server['url'], 'https://example.test/api/v1/mcp');
    expect(
      (server['headers'] as Map<String, dynamic>)['Authorization'],
      'Bearer sn_mcp_test-token',
    );
  });

  test('does not add an empty authorization header', () {
    final config =
        jsonDecode(
              buildClaudeMcpConfigJson(url: 'https://example.test/api/v1/mcp'),
            )
            as Map<String, dynamic>;
    final server =
        (config['mcpServers'] as Map<String, dynamic>)['supanotes']
            as Map<String, dynamic>;

    expect(server.containsKey('headers'), isFalse);
  });
}
