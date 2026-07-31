import 'dart:convert';

import 'package:supanotes/core/constants/api_constants.dart';

const _mcpServerType = 'http';
const _mcpServersKey = 'mcpServers';
const _mcpServerName = 'supanotes';
const _mcpHeadersKey = 'headers';
const _authorizationHeader = 'Authorization';

/// The single Streamable HTTP endpoint exposed by the backend.
String mcpEndpointUrl() => '${ApiConstants.baseUrl}/mcp';

/// Builds the JSON format accepted by Claude Code and compatible MCP clients.
///
/// The token is intentionally embedded only when it has just been generated;
/// the screen never persists it locally.
String buildClaudeMcpConfigJson({required String url, String? token}) {
  final server = <String, dynamic>{
    'type': _mcpServerType,
    'url': url,
    if (token != null && token.isNotEmpty)
      _mcpHeadersKey: <String, String>{_authorizationHeader: 'Bearer $token'},
  };

  return const JsonEncoder.withIndent('  ').convert({
    _mcpServersKey: <String, dynamic>{_mcpServerName: server},
  });
}
