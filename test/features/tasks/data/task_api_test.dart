import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/features/tasks/data/task_api.dart';
import 'package:supanotes/features/tasks/domain/task.dart';
import 'package:supanotes/features/tasks/domain/task_operation.dart';

class _MockApiClient extends Mock implements ApiClient {}

class _MockResponse<T> extends Mock implements Response<T> {}

class _FakeTaskOperation extends Fake implements TaskOperation {}

Map<String, dynamic> _taskJson({
  String id = 'task-1',
  String title = 'Review',
}) {
  return {
    'id': id,
    'ownerUserId': 'user-a',
    'title': title,
    'dueDate': null,
    'hasTime': false,
    'recurrenceRule': null,
    'reminder': null,
    'completions': <String, String>{},
    'isCompleted': false,
    'lastCompletedAt': null,
    'revision': 1,
    'scheduleGeneration': 0,
    'createdAt': '2026-09-15T12:00:00Z',
    'updatedAt': '2026-09-15T12:00:00Z',
    'deletedAt': null,
  };
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeTaskOperation());
  });

  test('parses bootstrap watermark and tasks', () async {
    final client = _MockApiClient();
    final response = _MockResponse<Map<String, dynamic>>();
    when(() => response.data).thenReturn({
      'watermark': 42,
      'tasks': [_taskJson()],
    });
    when(
      () => client.get<Map<String, dynamic>>(
        '/tasks/bootstrap',
        queryParameters: any(named: 'queryParameters'),
        options: any(named: 'options'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) async => response);

    final result = await TaskApi(client).bootstrap();

    expect(result.watermark, 42);
    expect(result.tasks.single.id, 'task-1');
  });

  test('parses mutation response and sends operation payload', () async {
    final client = _MockApiClient();
    final response = _MockResponse<Map<String, dynamic>>();
    when(() => response.data).thenReturn({
      'operationId': 'op-1',
      'revision': 2,
      'task': _taskJson(title: 'Updated'),
    });
    final operation = TaskOperation.upsert(
      operationId: 'op-1',
      taskId: 'task-1',
      payload: {'title': 'Updated'},
    );
    when(
      () => client.post<Map<String, dynamic>>(
        '/tasks/task-1/mutations',
        data: operation.toJson(),
        queryParameters: any(named: 'queryParameters'),
        options: any(named: 'options'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) async => response);

    final result = await TaskApi(client).mutate(operation);

    expect(result.operationId, 'op-1');
    expect(result.revision, 2);
    expect(result.task.title, 'Updated');
    verify(
      () => client.post<Map<String, dynamic>>(
        '/tasks/task-1/mutations',
        data: operation.toJson(),
        queryParameters: any(named: 'queryParameters'),
        options: any(named: 'options'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).called(1);
  });

  test('maps schedule conflict and deleted task protocol responses', () async {
    final client = _MockApiClient();
    final operation = TaskOperation.delete(
      operationId: 'op-1',
      taskId: 'task-1',
    );
    final conflict = DioException(
      requestOptions: RequestOptions(path: '/tasks/task-1/mutations'),
      response: Response(
        requestOptions: RequestOptions(path: '/tasks/task-1/mutations'),
        statusCode: 409,
        data: {'error': 'SCHEDULE_CHANGED'},
      ),
    );
    when(
      () => client.post<Map<String, dynamic>>(
        '/tasks/task-1/mutations',
        data: operation.toJson(),
        queryParameters: any(named: 'queryParameters'),
        options: any(named: 'options'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenThrow(conflict);

    await expectLater(
      () => TaskApi(client).mutate(operation),
      throwsA(
        isA<ConflictException>()
            .having((error) => error.statusCode, 'statusCode', 409)
            .having((error) => error.message, 'message', 'SCHEDULE_CHANGED'),
      ),
    );

    final deleted = DioException(
      requestOptions: RequestOptions(path: '/tasks/task-1/mutations'),
      response: Response(
        requestOptions: RequestOptions(path: '/tasks/task-1/mutations'),
        statusCode: 410,
        data: {'error': 'TASK_DELETED'},
      ),
    );
    when(
      () => client.post<Map<String, dynamic>>(
        '/tasks/task-1/mutations',
        data: operation.toJson(),
        queryParameters: any(named: 'queryParameters'),
        options: any(named: 'options'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenThrow(deleted);

    await expectLater(
      () => TaskApi(client).mutate(operation),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'statusCode', 410)
            .having((error) => error.message, 'message', 'TASK_DELETED'),
      ),
    );
  });

  test('maps malformed payload and network failure', () async {
    final client = _MockApiClient();
    final malformed = _MockResponse<Map<String, dynamic>>();
    when(() => malformed.data).thenReturn({
      'watermark': 1,
      'tasks': [{}],
    });
    when(
      () => client.get<Map<String, dynamic>>(
        '/tasks/bootstrap',
        queryParameters: any(named: 'queryParameters'),
        options: any(named: 'options'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) async => malformed);
    await expectLater(
      () => TaskApi(client).bootstrap(),
      throwsA(isA<FormatException>()),
    );

    when(
      () => client.get<Map<String, dynamic>>(
        '/tasks/bootstrap',
        queryParameters: any(named: 'queryParameters'),
        options: any(named: 'options'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/tasks/bootstrap'),
        type: DioExceptionType.connectionError,
        message: 'offline',
      ),
    );
    await expectLater(
      () => TaskApi(client).bootstrap(),
      throwsA(isA<NetworkException>()),
    );
  });
}
