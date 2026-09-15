import 'package:dio/dio.dart';

import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/features/tasks/domain/task.dart';
import 'package:supanotes/features/tasks/domain/task_operation.dart';

/// The server snapshot returned by the task bootstrap endpoint.
final class TaskBootstrapResponse {
  const TaskBootstrapResponse({required this.watermark, required this.tasks});

  factory TaskBootstrapResponse.fromJson(Map<String, dynamic> json) {
    final rawWatermark = json['watermark'];
    final rawTasks = json['tasks'];
    if (rawWatermark is! num || rawWatermark < 0 || rawTasks is! List) {
      throw const FormatException('Invalid task bootstrap response');
    }
    try {
      return TaskBootstrapResponse(
        watermark: rawWatermark.toInt(),
        tasks: List.unmodifiable(
          rawTasks.map((value) => Task.fromJson(_asMap(value))),
        ),
      );
    } on FormatException {
      rethrow;
    } catch (error) {
      throw FormatException('Invalid task bootstrap task: $error');
    }
  }

  final int watermark;
  final List<Task> tasks;
}

/// The idempotent result returned by a task mutation.
final class TaskMutationResponse {
  const TaskMutationResponse({
    required this.operationId,
    required this.revision,
    required this.task,
  });

  factory TaskMutationResponse.fromJson(Map<String, dynamic> json) {
    final operationId = json['operationId'];
    final revision = json['revision'];
    final task = json['task'];
    if (operationId is! String ||
        operationId.isEmpty ||
        revision is! num ||
        revision < 0 ||
        task is! Map) {
      throw const FormatException('Invalid task mutation response');
    }
    try {
      return TaskMutationResponse(
        operationId: operationId,
        revision: revision.toInt(),
        task: Task.fromJson(_asMap(task)),
      );
    } on FormatException {
      rethrow;
    } catch (error) {
      throw FormatException('Invalid task mutation task: $error');
    }
  }

  final String operationId;
  final int revision;
  final Task task;
}

/// HTTP contract for independently-owned tasks.
///
/// Feature code depends on this class rather than Dio. Transport failures are
/// translated to the app's typed [ApiException] hierarchy at this boundary.
class TaskApi {
  TaskApi(this._client);

  final ApiClient _client;

  Future<TaskBootstrapResponse> bootstrap() async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/tasks/bootstrap',
      );
      return TaskBootstrapResponse.fromJson(_requireMap(response.data));
    } on DioException catch (error) {
      throw fromDioError(error);
    }
  }

  Future<Task> fetch(String taskId) async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/tasks/$taskId',
      );
      return _parseTask(_requireMap(response.data));
    } on DioException catch (error) {
      throw fromDioError(error);
    }
  }

  Future<TaskMutationResponse> mutate(TaskOperation operation) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        '/tasks/${operation.taskId}/mutations',
        data: operation.toJson(),
      );
      return TaskMutationResponse.fromJson(_requireMap(response.data));
    } on DioException catch (error) {
      throw fromDioError(error);
    }
  }

  static Task _parseTask(Map<String, dynamic>? data) {
    if (data == null) throw const FormatException('Empty task response');
    try {
      return Task.fromJson(data);
    } on FormatException {
      rethrow;
    } catch (error) {
      throw FormatException('Invalid task response: $error');
    }
  }

  static Map<String, dynamic> _requireMap(Object? value) {
    if (value is! Map) {
      throw const FormatException('Response must be an object');
    }
    try {
      return Map<String, dynamic>.from(value);
    } on TypeError {
      throw const FormatException('Response object has invalid keys');
    }
  }
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is! Map) throw const FormatException('Response must be an object');
  try {
    return Map<String, dynamic>.from(value);
  } on TypeError {
    throw const FormatException('Response object has invalid keys');
  }
}
