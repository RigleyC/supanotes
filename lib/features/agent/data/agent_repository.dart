/// HTTP repository for inbox-organization endpoints exposed by the
/// agent backend.
///
/// The agent currently advertises its inbox-organize capability through
/// tool calls (see `backend/internal/agent/tools.go`), but the FE-5
/// feature surfaces a dedicated `POST /api/v1/agent/inbox/organize/plan`
/// + `POST /api/v1/agent/inbox/organize/apply` flow so the UI does not
/// have to ride the agent chat loop.
///
/// The endpoints are not yet implemented on the backend (no handler
/// exists under `backend/internal/agent` or `backend/internal/notes`
/// matching this path). When called, the backend returns 404 and the
/// repository surfaces an [ApiException] so the UI can degrade
/// gracefully — see `inbox_organize_sheet.dart` for the error state.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/core/di/providers.dart';

import '../domain/organization_plan.dart';

class AgentRepository {
  AgentRepository({required ApiClient apiClient}) : _dio = apiClient.dio;

  final Dio _dio;

  /// `POST /agent/inbox/organize/plan` → ask the agent to draft a plan
  /// from the user's current inbox note.
  Future<OrganizationPlan> planInboxOrganization() async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/agent/inbox/organize/plan',
      );
      final data = response.data;
      if (data == null) {
        throw const ServerException(
          message: 'Resposta vazia do servidor',
          statusCode: 500,
        );
      }
      return OrganizationPlan.fromJson(data);
    } on DioException catch (e) {
      throw fromDioError(e);
    }
  }

  /// `POST /agent/inbox/organize/apply` → push the user-curated subset
  /// of plan items back to the agent so it can perform the moves.
  Future<void> applyOrganizationPlan({
    required String planId,
    required List<String> acceptedItemIds,
  }) async {
    try {
      await _dio.post<dynamic>(
        '/agent/inbox/organize/apply',
        data: {
          'plan_id': planId,
          'accepted_item_ids': acceptedItemIds,
        },
      );
    } on DioException catch (e) {
      throw fromDioError(e);
    }
  }
}

/// Single shared [AgentRepository] wired to the app-wide [apiClientProvider].
final agentRepositoryProvider = Provider<AgentRepository>((ref) {
  return AgentRepository(apiClient: ref.watch(apiClientProvider));
});
