import 'dart:async';
import 'package:dio/dio.dart';
import 'package:supanotes/core/api/api_client.dart';

class NoteDocumentResponse {

  NoteDocumentResponse({
    required this.noteId,
    required this.revision,
    required this.document,
    required this.serverTime,
  });

  factory NoteDocumentResponse.fromJson(Map<String, dynamic> json) {
    return NoteDocumentResponse(
      noteId: json['noteId'] as String,
      revision: json['revision'] as int,
      document: json['document'] as Map<String, dynamic>,
      serverTime: DateTime.parse(json['serverTime'] as String),
    );
  }
  final String noteId;
  final int revision;
  final Map<String, dynamic> document;
  final DateTime serverTime;
}

class OperationRequest {

  OperationRequest({
    required this.operationId,
    required this.baseRevision,
    required this.kind,
    required this.payload, this.blockId,
  });
  final String operationId;
  final int baseRevision;
  final String kind;
  final String? blockId;
  final Map<String, dynamic> payload;

  Map<String, dynamic> toJson() => {
    'operationId': operationId,
    'baseRevision': baseRevision,
    'kind': kind,
    if (blockId != null) 'blockId': blockId,
    'payload': payload,
  };
}

class SyncRequest {

  SyncRequest({
    required this.knownRevision,
    required this.operations,
    required this.clientId,
  });
  final int knownRevision;
  final List<OperationRequest> operations;
  final String clientId;

  Map<String, dynamic> toJson() => {
    'knownRevision': knownRevision,
    'operations': operations.map((o) => o.toJson()).toList(),
    'clientId': clientId,
  };
}

class AcceptedOperation {

  AcceptedOperation({
    required this.operationId,
    required this.revision,
    required this.kind,
    this.blockId,
  });

  factory AcceptedOperation.fromJson(Map<String, dynamic> json) {
    return AcceptedOperation(
      operationId: json['operationId'] as String,
      revision: json['revision'] as int,
      kind: json['kind'] as String,
      blockId: json['blockId'] as String?,
    );
  }
  final String operationId;
  final int revision;
  final String kind;
  final String? blockId;
}

class Operation {

  Operation({
    required this.operationId,
    required this.noteId,
    required this.revision,
    required this.baseRevision,
    required this.actorId,
    required this.kind,
    required this.payload, required this.createdAt, this.blockId,
  });

  factory Operation.fromJson(Map<String, dynamic> json) {
    return Operation(
      operationId: json['operationId'] as String,
      noteId: json['noteId'] as String,
      revision: json['revision'] as int,
      baseRevision: json['baseRevision'] as int,
      actorId: json['actorId'] as String,
      kind: json['kind'] as String,
      blockId: json['blockId'] as String?,
      payload: json['payload'] as Map<String, dynamic>,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
  final String operationId;
  final String noteId;
  final int revision;
  final int baseRevision;
  final String actorId;
  final String kind;
  final String? blockId;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
}

class SyncResponse {

  SyncResponse({
    required this.accepted,
    required this.finalRevision,
    required this.remoteOperations,
    required this.serverTime, this.canonicalDocument,
  });

  factory SyncResponse.fromJson(Map<String, dynamic> json) {
    return SyncResponse(
      accepted:
          (json['accepted'] as List?)
              ?.map(
                (e) => AcceptedOperation.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          [],
      finalRevision: json['finalRevision'] as int,
      remoteOperations:
          (json['remoteOperations'] as List?)
              ?.map((e) => Operation.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      canonicalDocument: json['canonicalDocument'] as Map<String, dynamic>?,
      serverTime: DateTime.parse(json['serverTime'] as String),
    );
  }
  final List<AcceptedOperation> accepted;
  final int finalRevision;
  final List<Operation> remoteOperations;
  final Map<String, dynamic>? canonicalDocument;
  final DateTime serverTime;
}

class OperationsListResponse {

  OperationsListResponse({
    required this.operations,
    this.document,
    this.revision,
  });

  factory OperationsListResponse.fromJson(Map<String, dynamic> json) {
    return OperationsListResponse(
      operations:
          (json['operations'] as List?)
              ?.map((e) => Operation.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      document: json['document'] as Map<String, dynamic>?,
      revision: json['revision'] as int?,
    );
  }
  final List<Operation> operations;
  final Map<String, dynamic>? document;
  final int? revision;
}

class NoteOperationsException implements Exception {

  NoteOperationsException({
    required this.errorCode,
    required this.message,
    this.statusCode,
  });
  final String errorCode;
  final String message;
  final int? statusCode;

  @override
  String toString() => 'NoteOperationsException($errorCode): $message';
}

class NotePreferencesResponse {
  const NotePreferencesResponse({
    required this.favorite,
    required this.archived,
    required this.hideCompleted,
    required this.collapseImages,
    required this.updatedAt,
  });

  factory NotePreferencesResponse.fromJson(Map<String, dynamic> json) {
    return NotePreferencesResponse(
      favorite: json['favorite'] as bool,
      archived: json['archived'] as bool,
      hideCompleted: json['hide_completed'] as bool,
      collapseImages: json['collapse_images'] as bool,
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  final bool favorite;
  final bool archived;
  final bool hideCompleted;
  final bool collapseImages;
  final DateTime updatedAt;
}

class NoteSyncClient {

  NoteSyncClient({required ApiClient client}) : _client = client;
  final ApiClient _client;

  Future<NoteDocumentResponse> getDocument(String noteId) async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/notes/$noteId/document',
      );
      return NoteDocumentResponse.fromJson(
        response.data!,
      );
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<NoteDocumentResponse?> fetchDocument(String noteId) async {
    return getDocument(noteId);
  }

  Future<List<Map<String, dynamic>>> listNotes({
    int limit = 100,
    DateTime? cursorUpdatedAt,
    String? cursorId,
  }) async {
    try {
      final queryParameters = <String, dynamic>{'limit': limit};
      if (cursorUpdatedAt case final cursor?) {
        queryParameters['cursor_updated_at'] = cursor.toUtc().toIso8601String();
      }
      if (cursorId case final id?) {
        queryParameters['cursor_id'] = id;
      }
      final response = await _client.get<List<dynamic>>(
        '/notes',
        queryParameters: queryParameters,
      );
      return (response.data ?? const [])
          .map((note) => Map<String, dynamic>.from(note as Map))
          .toList();
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<void> deleteNote(String noteId) async {
    try {
      await _client.delete<void>('/notes/$noteId');
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<NotePreferencesResponse> updatePreferences({
    required String noteId,
    required bool favorite,
    required bool archived,
    required bool hideCompleted,
    required bool collapseImages,
  }) async {
    try {
      final response = await _client.patch<Map<String, dynamic>>(
        '/notes/$noteId/preferences',
        data: {
          'favorite': favorite,
          'archived': archived,
          'hide_completed': hideCompleted,
          'collapse_images': collapseImages,
        },
      );
      return NotePreferencesResponse.fromJson(response.data!);
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }


  Future<OperationsListResponse> getOperationsSince(
    String noteId,
    int afterRevision,
  ) async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/notes/$noteId/operations',
        queryParameters: {'afterRevision': afterRevision},
      );
      return OperationsListResponse.fromJson(
        response.data!,
      );
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<SyncResponse> syncOperations(
    String noteId,
    SyncRequest request,
  ) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        '/notes/$noteId/operations:sync',
        data: request.toJson(),
      );
      return SyncResponse.fromJson(response.data!);
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  NoteOperationsException _mapError(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      return NoteOperationsException(
        errorCode: data['error'] as String? ?? 'UNKNOWN',
        message: data['message'] as String? ?? e.message ?? 'Unknown error',
        statusCode: e.response?.statusCode,
      );
    }
    return NoteOperationsException(
      errorCode: 'NETWORK_ERROR',
      message: e.message ?? 'Network error',
      statusCode: e.response?.statusCode,
    );
  }
}
