import 'package:dio/dio.dart';

import 'package:supanotes/core/api/api_client.dart';

class NoteDocumentResponse {
  final String noteId;
  final int revision;
  final Map<String, dynamic> document;
  final DateTime serverTime;

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
}

class OperationRequest {
  final String operationId;
  final int baseRevision;
  final String kind;
  final String? blockId;
  final Map<String, dynamic> payload;

  OperationRequest({
    required this.operationId,
    required this.baseRevision,
    required this.kind,
    this.blockId,
    required this.payload,
  });

  Map<String, dynamic> toJson() => {
    'operationId': operationId,
    'baseRevision': baseRevision,
    'kind': kind,
    if (blockId != null) 'blockId': blockId,
    'payload': payload,
  };
}

class SyncRequest {
  final int knownRevision;
  final List<OperationRequest> operations;
  final String clientId;

  SyncRequest({
    required this.knownRevision,
    required this.operations,
    required this.clientId,
  });

  Map<String, dynamic> toJson() => {
    'knownRevision': knownRevision,
    'operations': operations.map((o) => o.toJson()).toList(),
    'clientId': clientId,
  };
}

class AcceptedOperation {
  final String operationId;
  final int revision;
  final String kind;
  final String? blockId;

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
}

class Operation {
  final String operationId;
  final String noteId;
  final int revision;
  final int baseRevision;
  final String actorId;
  final String kind;
  final String? blockId;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  Operation({
    required this.operationId,
    required this.noteId,
    required this.revision,
    required this.baseRevision,
    required this.actorId,
    required this.kind,
    this.blockId,
    required this.payload,
    required this.createdAt,
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
}

class SyncResponse {
  final List<AcceptedOperation> accepted;
  final int finalRevision;
  final List<Operation> remoteOperations;
  final Map<String, dynamic>? canonicalDocument;
  final DateTime serverTime;

  SyncResponse({
    required this.accepted,
    required this.finalRevision,
    required this.remoteOperations,
    this.canonicalDocument,
    required this.serverTime,
  });

  factory SyncResponse.fromJson(Map<String, dynamic> json) {
    return SyncResponse(
      accepted: (json['accepted'] as List?)
          ?.map((e) => AcceptedOperation.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      finalRevision: json['finalRevision'] as int,
      remoteOperations: (json['remoteOperations'] as List?)
          ?.map((e) => Operation.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      canonicalDocument: json['canonicalDocument'] as Map<String, dynamic>?,
      serverTime: DateTime.parse(json['serverTime'] as String),
    );
  }
}

class OperationsListResponse {
  final List<Operation> operations;
  final Map<String, dynamic>? document;
  final int? revision;

  OperationsListResponse({
    required this.operations,
    this.document,
    this.revision,
  });

  factory OperationsListResponse.fromJson(Map<String, dynamic> json) {
    return OperationsListResponse(
      operations: (json['operations'] as List?)
          ?.map((e) => Operation.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      document: json['document'] as Map<String, dynamic>?,
      revision: json['revision'] as int?,
    );
  }
}

class NoteOperationsException implements Exception {
  final String errorCode;
  final String message;
  final int? statusCode;

  NoteOperationsException({
    required this.errorCode,
    required this.message,
    this.statusCode,
  });

  @override
  String toString() => 'NoteOperationsException($errorCode): $message';
}

class NoteOperationsApiClient {
  final ApiClient _client;

  NoteOperationsApiClient({required ApiClient client}) : _client = client;

  Future<NoteDocumentResponse> getDocument(String noteId) async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/notes/$noteId/document',
      );
      return NoteDocumentResponse.fromJson(
        response.data as Map<String, dynamic>,
      );
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
        response.data as Map<String, dynamic>,
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
      return SyncResponse.fromJson(response.data as Map<String, dynamic>);
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
