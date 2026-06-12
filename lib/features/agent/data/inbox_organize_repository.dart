/// HTTP repository for inbox-organization endpoints.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/core/di/providers.dart';

import '../domain/organization_plan.dart';

class InboxOrganizeRepository {
  InboxOrganizeRepository({required ApiClient apiClient}) : _api = apiClient;

  final ApiClient _api;

  static const _planPath = '/notes/inbox/organize/plan';
  static const _applyPath = '/notes/inbox/organize/apply';

  Future<OrganizationPlan> planInboxOrganization() async {
    try {
      final response = await _api.post<Map<String, dynamic>>(_planPath);
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

  Future<void> applyOrganizationPlan(
    OrganizationPlan plan,
  ) async {
    try {
      final response = await _api.post<Map<String, dynamic>>(
        _applyPath,
        data: plan.toJson(),
      );
      final data = response.data;
      if (data == null) {
        throw const ServerException(
          message: 'Resposta vazia do servidor',
          statusCode: 500,
        );
      }
    } on DioException catch (e) {
      throw fromDioError(e);
    }
  }
}

final inboxOrganizeRepositoryProvider = Provider.autoDispose<InboxOrganizeRepository>((ref) {
  return InboxOrganizeRepository(apiClient: ref.watch(apiClientProvider));
});
