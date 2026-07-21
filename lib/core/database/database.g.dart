// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $NotesTable extends Notes with TableInfo<$NotesTable, NoteData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NotesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contextIdMeta = const VerificationMeta(
    'contextId',
  );
  @override
  late final GeneratedColumn<String> contextId = GeneratedColumn<String>(
    'context_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _excerptMeta = const VerificationMeta(
    'excerpt',
  );
  @override
  late final GeneratedColumn<String> excerpt = GeneratedColumn<String>(
    'excerpt',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _embeddingStatusMeta = const VerificationMeta(
    'embeddingStatus',
  );
  @override
  late final GeneratedColumn<String> embeddingStatus = GeneratedColumn<String>(
    'embedding_status',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isDirtyMeta = const VerificationMeta(
    'isDirty',
  );
  @override
  late final GeneratedColumn<bool> isDirty = GeneratedColumn<bool>(
    'is_dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _hasRemoteCopyMeta = const VerificationMeta(
    'hasRemoteCopy',
  );
  @override
  late final GeneratedColumn<bool> hasRemoteCopy = GeneratedColumn<bool>(
    'has_remote_copy',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("has_remote_copy" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _collapseImagesMeta = const VerificationMeta(
    'collapseImages',
  );
  @override
  late final GeneratedColumn<bool> collapseImages = GeneratedColumn<bool>(
    'collapse_images',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("collapse_images" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _permissionMeta = const VerificationMeta(
    'permission',
  );
  @override
  late final GeneratedColumn<String> permission = GeneratedColumn<String>(
    'permission',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sharedByEmailMeta = const VerificationMeta(
    'sharedByEmail',
  );
  @override
  late final GeneratedColumn<String> sharedByEmail = GeneratedColumn<String>(
    'shared_by_email',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sharedByNameMeta = const VerificationMeta(
    'sharedByName',
  );
  @override
  late final GeneratedColumn<String> sharedByName = GeneratedColumn<String>(
    'shared_by_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    contextId,
    content,
    excerpt,
    embeddingStatus,
    createdAt,
    updatedAt,
    deletedAt,
    isDirty,
    hasRemoteCopy,
    collapseImages,
    permission,
    sharedByEmail,
    sharedByName,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'notes';
  @override
  VerificationContext validateIntegrity(
    Insertable<NoteData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('context_id')) {
      context.handle(
        _contextIdMeta,
        contextId.isAcceptableOrUnknown(data['context_id']!, _contextIdMeta),
      );
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('excerpt')) {
      context.handle(
        _excerptMeta,
        excerpt.isAcceptableOrUnknown(data['excerpt']!, _excerptMeta),
      );
    }
    if (data.containsKey('embedding_status')) {
      context.handle(
        _embeddingStatusMeta,
        embeddingStatus.isAcceptableOrUnknown(
          data['embedding_status']!,
          _embeddingStatusMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('is_dirty')) {
      context.handle(
        _isDirtyMeta,
        isDirty.isAcceptableOrUnknown(data['is_dirty']!, _isDirtyMeta),
      );
    }
    if (data.containsKey('has_remote_copy')) {
      context.handle(
        _hasRemoteCopyMeta,
        hasRemoteCopy.isAcceptableOrUnknown(
          data['has_remote_copy']!,
          _hasRemoteCopyMeta,
        ),
      );
    }
    if (data.containsKey('collapse_images')) {
      context.handle(
        _collapseImagesMeta,
        collapseImages.isAcceptableOrUnknown(
          data['collapse_images']!,
          _collapseImagesMeta,
        ),
      );
    }
    if (data.containsKey('permission')) {
      context.handle(
        _permissionMeta,
        permission.isAcceptableOrUnknown(data['permission']!, _permissionMeta),
      );
    }
    if (data.containsKey('shared_by_email')) {
      context.handle(
        _sharedByEmailMeta,
        sharedByEmail.isAcceptableOrUnknown(
          data['shared_by_email']!,
          _sharedByEmailMeta,
        ),
      );
    }
    if (data.containsKey('shared_by_name')) {
      context.handle(
        _sharedByNameMeta,
        sharedByName.isAcceptableOrUnknown(
          data['shared_by_name']!,
          _sharedByNameMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NoteData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NoteData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      contextId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}context_id'],
      ),
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      excerpt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}excerpt'],
      ),
      embeddingStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}embedding_status'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      isDirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_dirty'],
      )!,
      hasRemoteCopy: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}has_remote_copy'],
      )!,
      collapseImages: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}collapse_images'],
      )!,
      permission: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}permission'],
      ),
      sharedByEmail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}shared_by_email'],
      ),
      sharedByName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}shared_by_name'],
      ),
    );
  }

  @override
  $NotesTable createAlias(String alias) {
    return $NotesTable(attachedDatabase, alias);
  }
}

class NoteData extends DataClass implements Insertable<NoteData> {
  final String id;
  final String userId;
  final String? contextId;
  final String content;
  final String? excerpt;
  final String? embeddingStatus;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final bool isDirty;
  final bool hasRemoteCopy;
  final bool collapseImages;
  final String? permission;
  final String? sharedByEmail;
  final String? sharedByName;
  const NoteData({
    required this.id,
    required this.userId,
    this.contextId,
    required this.content,
    this.excerpt,
    this.embeddingStatus,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.isDirty,
    required this.hasRemoteCopy,
    required this.collapseImages,
    this.permission,
    this.sharedByEmail,
    this.sharedByName,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    if (!nullToAbsent || contextId != null) {
      map['context_id'] = Variable<String>(contextId);
    }
    map['content'] = Variable<String>(content);
    if (!nullToAbsent || excerpt != null) {
      map['excerpt'] = Variable<String>(excerpt);
    }
    if (!nullToAbsent || embeddingStatus != null) {
      map['embedding_status'] = Variable<String>(embeddingStatus);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['is_dirty'] = Variable<bool>(isDirty);
    map['has_remote_copy'] = Variable<bool>(hasRemoteCopy);
    map['collapse_images'] = Variable<bool>(collapseImages);
    if (!nullToAbsent || permission != null) {
      map['permission'] = Variable<String>(permission);
    }
    if (!nullToAbsent || sharedByEmail != null) {
      map['shared_by_email'] = Variable<String>(sharedByEmail);
    }
    if (!nullToAbsent || sharedByName != null) {
      map['shared_by_name'] = Variable<String>(sharedByName);
    }
    return map;
  }

  NotesCompanion toCompanion(bool nullToAbsent) {
    return NotesCompanion(
      id: Value(id),
      userId: Value(userId),
      contextId: contextId == null && nullToAbsent
          ? const Value.absent()
          : Value(contextId),
      content: Value(content),
      excerpt: excerpt == null && nullToAbsent
          ? const Value.absent()
          : Value(excerpt),
      embeddingStatus: embeddingStatus == null && nullToAbsent
          ? const Value.absent()
          : Value(embeddingStatus),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      isDirty: Value(isDirty),
      hasRemoteCopy: Value(hasRemoteCopy),
      collapseImages: Value(collapseImages),
      permission: permission == null && nullToAbsent
          ? const Value.absent()
          : Value(permission),
      sharedByEmail: sharedByEmail == null && nullToAbsent
          ? const Value.absent()
          : Value(sharedByEmail),
      sharedByName: sharedByName == null && nullToAbsent
          ? const Value.absent()
          : Value(sharedByName),
    );
  }

  factory NoteData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NoteData(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      contextId: serializer.fromJson<String?>(json['contextId']),
      content: serializer.fromJson<String>(json['content']),
      excerpt: serializer.fromJson<String?>(json['excerpt']),
      embeddingStatus: serializer.fromJson<String?>(json['embeddingStatus']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      isDirty: serializer.fromJson<bool>(json['isDirty']),
      hasRemoteCopy: serializer.fromJson<bool>(json['hasRemoteCopy']),
      collapseImages: serializer.fromJson<bool>(json['collapseImages']),
      permission: serializer.fromJson<String?>(json['permission']),
      sharedByEmail: serializer.fromJson<String?>(json['sharedByEmail']),
      sharedByName: serializer.fromJson<String?>(json['sharedByName']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'contextId': serializer.toJson<String?>(contextId),
      'content': serializer.toJson<String>(content),
      'excerpt': serializer.toJson<String?>(excerpt),
      'embeddingStatus': serializer.toJson<String?>(embeddingStatus),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'isDirty': serializer.toJson<bool>(isDirty),
      'hasRemoteCopy': serializer.toJson<bool>(hasRemoteCopy),
      'collapseImages': serializer.toJson<bool>(collapseImages),
      'permission': serializer.toJson<String?>(permission),
      'sharedByEmail': serializer.toJson<String?>(sharedByEmail),
      'sharedByName': serializer.toJson<String?>(sharedByName),
    };
  }

  NoteData copyWith({
    String? id,
    String? userId,
    Value<String?> contextId = const Value.absent(),
    String? content,
    Value<String?> excerpt = const Value.absent(),
    Value<String?> embeddingStatus = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    bool? isDirty,
    bool? hasRemoteCopy,
    bool? collapseImages,
    Value<String?> permission = const Value.absent(),
    Value<String?> sharedByEmail = const Value.absent(),
    Value<String?> sharedByName = const Value.absent(),
  }) => NoteData(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    contextId: contextId.present ? contextId.value : this.contextId,
    content: content ?? this.content,
    excerpt: excerpt.present ? excerpt.value : this.excerpt,
    embeddingStatus: embeddingStatus.present
        ? embeddingStatus.value
        : this.embeddingStatus,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    isDirty: isDirty ?? this.isDirty,
    hasRemoteCopy: hasRemoteCopy ?? this.hasRemoteCopy,
    collapseImages: collapseImages ?? this.collapseImages,
    permission: permission.present ? permission.value : this.permission,
    sharedByEmail: sharedByEmail.present
        ? sharedByEmail.value
        : this.sharedByEmail,
    sharedByName: sharedByName.present ? sharedByName.value : this.sharedByName,
  );
  NoteData copyWithCompanion(NotesCompanion data) {
    return NoteData(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      contextId: data.contextId.present ? data.contextId.value : this.contextId,
      content: data.content.present ? data.content.value : this.content,
      excerpt: data.excerpt.present ? data.excerpt.value : this.excerpt,
      embeddingStatus: data.embeddingStatus.present
          ? data.embeddingStatus.value
          : this.embeddingStatus,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      isDirty: data.isDirty.present ? data.isDirty.value : this.isDirty,
      hasRemoteCopy: data.hasRemoteCopy.present
          ? data.hasRemoteCopy.value
          : this.hasRemoteCopy,
      collapseImages: data.collapseImages.present
          ? data.collapseImages.value
          : this.collapseImages,
      permission: data.permission.present
          ? data.permission.value
          : this.permission,
      sharedByEmail: data.sharedByEmail.present
          ? data.sharedByEmail.value
          : this.sharedByEmail,
      sharedByName: data.sharedByName.present
          ? data.sharedByName.value
          : this.sharedByName,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NoteData(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('contextId: $contextId, ')
          ..write('content: $content, ')
          ..write('excerpt: $excerpt, ')
          ..write('embeddingStatus: $embeddingStatus, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('isDirty: $isDirty, ')
          ..write('hasRemoteCopy: $hasRemoteCopy, ')
          ..write('collapseImages: $collapseImages, ')
          ..write('permission: $permission, ')
          ..write('sharedByEmail: $sharedByEmail, ')
          ..write('sharedByName: $sharedByName')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    contextId,
    content,
    excerpt,
    embeddingStatus,
    createdAt,
    updatedAt,
    deletedAt,
    isDirty,
    hasRemoteCopy,
    collapseImages,
    permission,
    sharedByEmail,
    sharedByName,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NoteData &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.contextId == this.contextId &&
          other.content == this.content &&
          other.excerpt == this.excerpt &&
          other.embeddingStatus == this.embeddingStatus &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.isDirty == this.isDirty &&
          other.hasRemoteCopy == this.hasRemoteCopy &&
          other.collapseImages == this.collapseImages &&
          other.permission == this.permission &&
          other.sharedByEmail == this.sharedByEmail &&
          other.sharedByName == this.sharedByName);
}

class NotesCompanion extends UpdateCompanion<NoteData> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String?> contextId;
  final Value<String> content;
  final Value<String?> excerpt;
  final Value<String?> embeddingStatus;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<bool> isDirty;
  final Value<bool> hasRemoteCopy;
  final Value<bool> collapseImages;
  final Value<String?> permission;
  final Value<String?> sharedByEmail;
  final Value<String?> sharedByName;
  final Value<int> rowid;
  const NotesCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.contextId = const Value.absent(),
    this.content = const Value.absent(),
    this.excerpt = const Value.absent(),
    this.embeddingStatus = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.isDirty = const Value.absent(),
    this.hasRemoteCopy = const Value.absent(),
    this.collapseImages = const Value.absent(),
    this.permission = const Value.absent(),
    this.sharedByEmail = const Value.absent(),
    this.sharedByName = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NotesCompanion.insert({
    required String id,
    required String userId,
    this.contextId = const Value.absent(),
    required String content,
    this.excerpt = const Value.absent(),
    this.embeddingStatus = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.isDirty = const Value.absent(),
    this.hasRemoteCopy = const Value.absent(),
    this.collapseImages = const Value.absent(),
    this.permission = const Value.absent(),
    this.sharedByEmail = const Value.absent(),
    this.sharedByName = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       content = Value(content),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<NoteData> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? contextId,
    Expression<String>? content,
    Expression<String>? excerpt,
    Expression<String>? embeddingStatus,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<bool>? isDirty,
    Expression<bool>? hasRemoteCopy,
    Expression<bool>? collapseImages,
    Expression<String>? permission,
    Expression<String>? sharedByEmail,
    Expression<String>? sharedByName,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (contextId != null) 'context_id': contextId,
      if (content != null) 'content': content,
      if (excerpt != null) 'excerpt': excerpt,
      if (embeddingStatus != null) 'embedding_status': embeddingStatus,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (isDirty != null) 'is_dirty': isDirty,
      if (hasRemoteCopy != null) 'has_remote_copy': hasRemoteCopy,
      if (collapseImages != null) 'collapse_images': collapseImages,
      if (permission != null) 'permission': permission,
      if (sharedByEmail != null) 'shared_by_email': sharedByEmail,
      if (sharedByName != null) 'shared_by_name': sharedByName,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NotesCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String?>? contextId,
    Value<String>? content,
    Value<String?>? excerpt,
    Value<String?>? embeddingStatus,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<bool>? isDirty,
    Value<bool>? hasRemoteCopy,
    Value<bool>? collapseImages,
    Value<String?>? permission,
    Value<String?>? sharedByEmail,
    Value<String?>? sharedByName,
    Value<int>? rowid,
  }) {
    return NotesCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      contextId: contextId ?? this.contextId,
      content: content ?? this.content,
      excerpt: excerpt ?? this.excerpt,
      embeddingStatus: embeddingStatus ?? this.embeddingStatus,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      isDirty: isDirty ?? this.isDirty,
      hasRemoteCopy: hasRemoteCopy ?? this.hasRemoteCopy,
      collapseImages: collapseImages ?? this.collapseImages,
      permission: permission ?? this.permission,
      sharedByEmail: sharedByEmail ?? this.sharedByEmail,
      sharedByName: sharedByName ?? this.sharedByName,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (contextId.present) {
      map['context_id'] = Variable<String>(contextId.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (excerpt.present) {
      map['excerpt'] = Variable<String>(excerpt.value);
    }
    if (embeddingStatus.present) {
      map['embedding_status'] = Variable<String>(embeddingStatus.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (isDirty.present) {
      map['is_dirty'] = Variable<bool>(isDirty.value);
    }
    if (hasRemoteCopy.present) {
      map['has_remote_copy'] = Variable<bool>(hasRemoteCopy.value);
    }
    if (collapseImages.present) {
      map['collapse_images'] = Variable<bool>(collapseImages.value);
    }
    if (permission.present) {
      map['permission'] = Variable<String>(permission.value);
    }
    if (sharedByEmail.present) {
      map['shared_by_email'] = Variable<String>(sharedByEmail.value);
    }
    if (sharedByName.present) {
      map['shared_by_name'] = Variable<String>(sharedByName.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NotesCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('contextId: $contextId, ')
          ..write('content: $content, ')
          ..write('excerpt: $excerpt, ')
          ..write('embeddingStatus: $embeddingStatus, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('isDirty: $isDirty, ')
          ..write('hasRemoteCopy: $hasRemoteCopy, ')
          ..write('collapseImages: $collapseImages, ')
          ..write('permission: $permission, ')
          ..write('sharedByEmail: $sharedByEmail, ')
          ..write('sharedByName: $sharedByName, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TasksTable extends Tasks with TableInfo<$TasksTable, TaskData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TasksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteIdMeta = const VerificationMeta('noteId');
  @override
  late final GeneratedColumn<String> noteId = GeneratedColumn<String>(
    'note_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<String> position = GeneratedColumn<String>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('a0'),
  );
  @override
  late final GeneratedColumnWithTypeConverter<TaskRecurrence?, String>
  recurrence = GeneratedColumn<String>(
    'recurrence',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  ).withConverter<TaskRecurrence?>($TasksTable.$converterrecurrencen);
  static const VerificationMeta _dueDateMeta = const VerificationMeta(
    'dueDate',
  );
  @override
  late final GeneratedColumn<DateTime> dueDate = GeneratedColumn<DateTime>(
    'due_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hasTimeMeta = const VerificationMeta(
    'hasTime',
  );
  @override
  late final GeneratedColumn<bool> hasTime = GeneratedColumn<bool>(
    'has_time',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("has_time" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _reminderMeta = const VerificationMeta(
    'reminder',
  );
  @override
  late final GeneratedColumn<String> reminder = GeneratedColumn<String>(
    'reminder',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _completedAtMeta = const VerificationMeta(
    'completedAt',
  );
  @override
  late final GeneratedColumn<DateTime> completedAt = GeneratedColumn<DateTime>(
    'completed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    noteId,
    title,
    status,
    position,
    recurrence,
    dueDate,
    hasTime,
    reminder,
    completedAt,
    createdAt,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tasks';
  @override
  VerificationContext validateIntegrity(
    Insertable<TaskData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('note_id')) {
      context.handle(
        _noteIdMeta,
        noteId.isAcceptableOrUnknown(data['note_id']!, _noteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_noteIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    }
    if (data.containsKey('due_date')) {
      context.handle(
        _dueDateMeta,
        dueDate.isAcceptableOrUnknown(data['due_date']!, _dueDateMeta),
      );
    }
    if (data.containsKey('has_time')) {
      context.handle(
        _hasTimeMeta,
        hasTime.isAcceptableOrUnknown(data['has_time']!, _hasTimeMeta),
      );
    }
    if (data.containsKey('reminder')) {
      context.handle(
        _reminderMeta,
        reminder.isAcceptableOrUnknown(data['reminder']!, _reminderMeta),
      );
    }
    if (data.containsKey('completed_at')) {
      context.handle(
        _completedAtMeta,
        completedAt.isAcceptableOrUnknown(
          data['completed_at']!,
          _completedAtMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TaskData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TaskData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      noteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}position'],
      )!,
      recurrence: $TasksTable.$converterrecurrencen.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}recurrence'],
        ),
      ),
      dueDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}due_date'],
      ),
      hasTime: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}has_time'],
      )!,
      reminder: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reminder'],
      ),
      completedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}completed_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $TasksTable createAlias(String alias) {
    return $TasksTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<TaskRecurrence, String, String>
  $converterrecurrence = const EnumNameConverter(TaskRecurrence.values);
  static JsonTypeConverter2<TaskRecurrence?, String?, String?>
  $converterrecurrencen = JsonTypeConverter2.asNullable($converterrecurrence);
}

class TaskData extends DataClass implements Insertable<TaskData> {
  final String id;
  final String userId;
  final String noteId;
  final String title;
  final String status;
  final String position;
  final TaskRecurrence? recurrence;
  final DateTime? dueDate;
  final bool hasTime;
  final String? reminder;
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const TaskData({
    required this.id,
    required this.userId,
    required this.noteId,
    required this.title,
    required this.status,
    required this.position,
    this.recurrence,
    this.dueDate,
    required this.hasTime,
    this.reminder,
    this.completedAt,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['note_id'] = Variable<String>(noteId);
    map['title'] = Variable<String>(title);
    map['status'] = Variable<String>(status);
    map['position'] = Variable<String>(position);
    if (!nullToAbsent || recurrence != null) {
      map['recurrence'] = Variable<String>(
        $TasksTable.$converterrecurrencen.toSql(recurrence),
      );
    }
    if (!nullToAbsent || dueDate != null) {
      map['due_date'] = Variable<DateTime>(dueDate);
    }
    map['has_time'] = Variable<bool>(hasTime);
    if (!nullToAbsent || reminder != null) {
      map['reminder'] = Variable<String>(reminder);
    }
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<DateTime>(completedAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  TasksCompanion toCompanion(bool nullToAbsent) {
    return TasksCompanion(
      id: Value(id),
      userId: Value(userId),
      noteId: Value(noteId),
      title: Value(title),
      status: Value(status),
      position: Value(position),
      recurrence: recurrence == null && nullToAbsent
          ? const Value.absent()
          : Value(recurrence),
      dueDate: dueDate == null && nullToAbsent
          ? const Value.absent()
          : Value(dueDate),
      hasTime: Value(hasTime),
      reminder: reminder == null && nullToAbsent
          ? const Value.absent()
          : Value(reminder),
      completedAt: completedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory TaskData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TaskData(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      noteId: serializer.fromJson<String>(json['noteId']),
      title: serializer.fromJson<String>(json['title']),
      status: serializer.fromJson<String>(json['status']),
      position: serializer.fromJson<String>(json['position']),
      recurrence: $TasksTable.$converterrecurrencen.fromJson(
        serializer.fromJson<String?>(json['recurrence']),
      ),
      dueDate: serializer.fromJson<DateTime?>(json['dueDate']),
      hasTime: serializer.fromJson<bool>(json['hasTime']),
      reminder: serializer.fromJson<String?>(json['reminder']),
      completedAt: serializer.fromJson<DateTime?>(json['completedAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'noteId': serializer.toJson<String>(noteId),
      'title': serializer.toJson<String>(title),
      'status': serializer.toJson<String>(status),
      'position': serializer.toJson<String>(position),
      'recurrence': serializer.toJson<String?>(
        $TasksTable.$converterrecurrencen.toJson(recurrence),
      ),
      'dueDate': serializer.toJson<DateTime?>(dueDate),
      'hasTime': serializer.toJson<bool>(hasTime),
      'reminder': serializer.toJson<String?>(reminder),
      'completedAt': serializer.toJson<DateTime?>(completedAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  TaskData copyWith({
    String? id,
    String? userId,
    String? noteId,
    String? title,
    String? status,
    String? position,
    Value<TaskRecurrence?> recurrence = const Value.absent(),
    Value<DateTime?> dueDate = const Value.absent(),
    bool? hasTime,
    Value<String?> reminder = const Value.absent(),
    Value<DateTime?> completedAt = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => TaskData(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    noteId: noteId ?? this.noteId,
    title: title ?? this.title,
    status: status ?? this.status,
    position: position ?? this.position,
    recurrence: recurrence.present ? recurrence.value : this.recurrence,
    dueDate: dueDate.present ? dueDate.value : this.dueDate,
    hasTime: hasTime ?? this.hasTime,
    reminder: reminder.present ? reminder.value : this.reminder,
    completedAt: completedAt.present ? completedAt.value : this.completedAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  TaskData copyWithCompanion(TasksCompanion data) {
    return TaskData(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      noteId: data.noteId.present ? data.noteId.value : this.noteId,
      title: data.title.present ? data.title.value : this.title,
      status: data.status.present ? data.status.value : this.status,
      position: data.position.present ? data.position.value : this.position,
      recurrence: data.recurrence.present
          ? data.recurrence.value
          : this.recurrence,
      dueDate: data.dueDate.present ? data.dueDate.value : this.dueDate,
      hasTime: data.hasTime.present ? data.hasTime.value : this.hasTime,
      reminder: data.reminder.present ? data.reminder.value : this.reminder,
      completedAt: data.completedAt.present
          ? data.completedAt.value
          : this.completedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TaskData(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('noteId: $noteId, ')
          ..write('title: $title, ')
          ..write('status: $status, ')
          ..write('position: $position, ')
          ..write('recurrence: $recurrence, ')
          ..write('dueDate: $dueDate, ')
          ..write('hasTime: $hasTime, ')
          ..write('reminder: $reminder, ')
          ..write('completedAt: $completedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    noteId,
    title,
    status,
    position,
    recurrence,
    dueDate,
    hasTime,
    reminder,
    completedAt,
    createdAt,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TaskData &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.noteId == this.noteId &&
          other.title == this.title &&
          other.status == this.status &&
          other.position == this.position &&
          other.recurrence == this.recurrence &&
          other.dueDate == this.dueDate &&
          other.hasTime == this.hasTime &&
          other.reminder == this.reminder &&
          other.completedAt == this.completedAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class TasksCompanion extends UpdateCompanion<TaskData> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> noteId;
  final Value<String> title;
  final Value<String> status;
  final Value<String> position;
  final Value<TaskRecurrence?> recurrence;
  final Value<DateTime?> dueDate;
  final Value<bool> hasTime;
  final Value<String?> reminder;
  final Value<DateTime?> completedAt;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const TasksCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.noteId = const Value.absent(),
    this.title = const Value.absent(),
    this.status = const Value.absent(),
    this.position = const Value.absent(),
    this.recurrence = const Value.absent(),
    this.dueDate = const Value.absent(),
    this.hasTime = const Value.absent(),
    this.reminder = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TasksCompanion.insert({
    required String id,
    required String userId,
    required String noteId,
    required String title,
    required String status,
    this.position = const Value.absent(),
    this.recurrence = const Value.absent(),
    this.dueDate = const Value.absent(),
    this.hasTime = const Value.absent(),
    this.reminder = const Value.absent(),
    this.completedAt = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       noteId = Value(noteId),
       title = Value(title),
       status = Value(status),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<TaskData> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? noteId,
    Expression<String>? title,
    Expression<String>? status,
    Expression<String>? position,
    Expression<String>? recurrence,
    Expression<DateTime>? dueDate,
    Expression<bool>? hasTime,
    Expression<String>? reminder,
    Expression<DateTime>? completedAt,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (noteId != null) 'note_id': noteId,
      if (title != null) 'title': title,
      if (status != null) 'status': status,
      if (position != null) 'position': position,
      if (recurrence != null) 'recurrence': recurrence,
      if (dueDate != null) 'due_date': dueDate,
      if (hasTime != null) 'has_time': hasTime,
      if (reminder != null) 'reminder': reminder,
      if (completedAt != null) 'completed_at': completedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TasksCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String>? noteId,
    Value<String>? title,
    Value<String>? status,
    Value<String>? position,
    Value<TaskRecurrence?>? recurrence,
    Value<DateTime?>? dueDate,
    Value<bool>? hasTime,
    Value<String?>? reminder,
    Value<DateTime?>? completedAt,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return TasksCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      noteId: noteId ?? this.noteId,
      title: title ?? this.title,
      status: status ?? this.status,
      position: position ?? this.position,
      recurrence: recurrence ?? this.recurrence,
      dueDate: dueDate ?? this.dueDate,
      hasTime: hasTime ?? this.hasTime,
      reminder: reminder ?? this.reminder,
      completedAt: completedAt ?? this.completedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (noteId.present) {
      map['note_id'] = Variable<String>(noteId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (position.present) {
      map['position'] = Variable<String>(position.value);
    }
    if (recurrence.present) {
      map['recurrence'] = Variable<String>(
        $TasksTable.$converterrecurrencen.toSql(recurrence.value),
      );
    }
    if (dueDate.present) {
      map['due_date'] = Variable<DateTime>(dueDate.value);
    }
    if (hasTime.present) {
      map['has_time'] = Variable<bool>(hasTime.value);
    }
    if (reminder.present) {
      map['reminder'] = Variable<String>(reminder.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<DateTime>(completedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TasksCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('noteId: $noteId, ')
          ..write('title: $title, ')
          ..write('status: $status, ')
          ..write('position: $position, ')
          ..write('recurrence: $recurrence, ')
          ..write('dueDate: $dueDate, ')
          ..write('hasTime: $hasTime, ')
          ..write('reminder: $reminder, ')
          ..write('completedAt: $completedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalTaskCompletionsTable extends LocalTaskCompletions
    with TableInfo<$LocalTaskCompletionsTable, LocalTaskCompletionData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalTaskCompletionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _taskIdMeta = const VerificationMeta('taskId');
  @override
  late final GeneratedColumn<String> taskId = GeneratedColumn<String>(
    'task_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _completedAtMeta = const VerificationMeta(
    'completedAt',
  );
  @override
  late final GeneratedColumn<DateTime> completedAt = GeneratedColumn<DateTime>(
    'completed_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scheduledAtMeta = const VerificationMeta(
    'scheduledAt',
  );
  @override
  late final GeneratedColumn<DateTime> scheduledAt = GeneratedColumn<DateTime>(
    'scheduled_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    taskId,
    userId,
    completedAt,
    scheduledAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_task_completions';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalTaskCompletionData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('task_id')) {
      context.handle(
        _taskIdMeta,
        taskId.isAcceptableOrUnknown(data['task_id']!, _taskIdMeta),
      );
    } else if (isInserting) {
      context.missing(_taskIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('completed_at')) {
      context.handle(
        _completedAtMeta,
        completedAt.isAcceptableOrUnknown(
          data['completed_at']!,
          _completedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_completedAtMeta);
    }
    if (data.containsKey('scheduled_at')) {
      context.handle(
        _scheduledAtMeta,
        scheduledAt.isAcceptableOrUnknown(
          data['scheduled_at']!,
          _scheduledAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_scheduledAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalTaskCompletionData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalTaskCompletionData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      taskId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}task_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      completedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}completed_at'],
      )!,
      scheduledAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}scheduled_at'],
      )!,
    );
  }

  @override
  $LocalTaskCompletionsTable createAlias(String alias) {
    return $LocalTaskCompletionsTable(attachedDatabase, alias);
  }
}

class LocalTaskCompletionData extends DataClass
    implements Insertable<LocalTaskCompletionData> {
  final String id;
  final String taskId;
  final String userId;
  final DateTime completedAt;
  final DateTime scheduledAt;
  const LocalTaskCompletionData({
    required this.id,
    required this.taskId,
    required this.userId,
    required this.completedAt,
    required this.scheduledAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['task_id'] = Variable<String>(taskId);
    map['user_id'] = Variable<String>(userId);
    map['completed_at'] = Variable<DateTime>(completedAt);
    map['scheduled_at'] = Variable<DateTime>(scheduledAt);
    return map;
  }

  LocalTaskCompletionsCompanion toCompanion(bool nullToAbsent) {
    return LocalTaskCompletionsCompanion(
      id: Value(id),
      taskId: Value(taskId),
      userId: Value(userId),
      completedAt: Value(completedAt),
      scheduledAt: Value(scheduledAt),
    );
  }

  factory LocalTaskCompletionData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalTaskCompletionData(
      id: serializer.fromJson<String>(json['id']),
      taskId: serializer.fromJson<String>(json['taskId']),
      userId: serializer.fromJson<String>(json['userId']),
      completedAt: serializer.fromJson<DateTime>(json['completedAt']),
      scheduledAt: serializer.fromJson<DateTime>(json['scheduledAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'taskId': serializer.toJson<String>(taskId),
      'userId': serializer.toJson<String>(userId),
      'completedAt': serializer.toJson<DateTime>(completedAt),
      'scheduledAt': serializer.toJson<DateTime>(scheduledAt),
    };
  }

  LocalTaskCompletionData copyWith({
    String? id,
    String? taskId,
    String? userId,
    DateTime? completedAt,
    DateTime? scheduledAt,
  }) => LocalTaskCompletionData(
    id: id ?? this.id,
    taskId: taskId ?? this.taskId,
    userId: userId ?? this.userId,
    completedAt: completedAt ?? this.completedAt,
    scheduledAt: scheduledAt ?? this.scheduledAt,
  );
  LocalTaskCompletionData copyWithCompanion(
    LocalTaskCompletionsCompanion data,
  ) {
    return LocalTaskCompletionData(
      id: data.id.present ? data.id.value : this.id,
      taskId: data.taskId.present ? data.taskId.value : this.taskId,
      userId: data.userId.present ? data.userId.value : this.userId,
      completedAt: data.completedAt.present
          ? data.completedAt.value
          : this.completedAt,
      scheduledAt: data.scheduledAt.present
          ? data.scheduledAt.value
          : this.scheduledAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalTaskCompletionData(')
          ..write('id: $id, ')
          ..write('taskId: $taskId, ')
          ..write('userId: $userId, ')
          ..write('completedAt: $completedAt, ')
          ..write('scheduledAt: $scheduledAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, taskId, userId, completedAt, scheduledAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalTaskCompletionData &&
          other.id == this.id &&
          other.taskId == this.taskId &&
          other.userId == this.userId &&
          other.completedAt == this.completedAt &&
          other.scheduledAt == this.scheduledAt);
}

class LocalTaskCompletionsCompanion
    extends UpdateCompanion<LocalTaskCompletionData> {
  final Value<String> id;
  final Value<String> taskId;
  final Value<String> userId;
  final Value<DateTime> completedAt;
  final Value<DateTime> scheduledAt;
  final Value<int> rowid;
  const LocalTaskCompletionsCompanion({
    this.id = const Value.absent(),
    this.taskId = const Value.absent(),
    this.userId = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.scheduledAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalTaskCompletionsCompanion.insert({
    required String id,
    required String taskId,
    required String userId,
    required DateTime completedAt,
    required DateTime scheduledAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       taskId = Value(taskId),
       userId = Value(userId),
       completedAt = Value(completedAt),
       scheduledAt = Value(scheduledAt);
  static Insertable<LocalTaskCompletionData> custom({
    Expression<String>? id,
    Expression<String>? taskId,
    Expression<String>? userId,
    Expression<DateTime>? completedAt,
    Expression<DateTime>? scheduledAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (taskId != null) 'task_id': taskId,
      if (userId != null) 'user_id': userId,
      if (completedAt != null) 'completed_at': completedAt,
      if (scheduledAt != null) 'scheduled_at': scheduledAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalTaskCompletionsCompanion copyWith({
    Value<String>? id,
    Value<String>? taskId,
    Value<String>? userId,
    Value<DateTime>? completedAt,
    Value<DateTime>? scheduledAt,
    Value<int>? rowid,
  }) {
    return LocalTaskCompletionsCompanion(
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      userId: userId ?? this.userId,
      completedAt: completedAt ?? this.completedAt,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (taskId.present) {
      map['task_id'] = Variable<String>(taskId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<DateTime>(completedAt.value);
    }
    if (scheduledAt.present) {
      map['scheduled_at'] = Variable<DateTime>(scheduledAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalTaskCompletionsCompanion(')
          ..write('id: $id, ')
          ..write('taskId: $taskId, ')
          ..write('userId: $userId, ')
          ..write('completedAt: $completedAt, ')
          ..write('scheduledAt: $scheduledAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NoteLinksTable extends NoteLinks
    with TableInfo<$NoteLinksTable, NoteLinkData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NoteLinksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES notes (id)',
    ),
  );
  static const VerificationMeta _targetIdMeta = const VerificationMeta(
    'targetId',
  );
  @override
  late final GeneratedColumn<String> targetId = GeneratedColumn<String>(
    'target_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES notes (id)',
    ),
  );
  static const VerificationMeta _relationMeta = const VerificationMeta(
    'relation',
  );
  @override
  late final GeneratedColumn<String> relation = GeneratedColumn<String>(
    'relation',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('related'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _isDirtyMeta = const VerificationMeta(
    'isDirty',
  );
  @override
  late final GeneratedColumn<bool> isDirty = GeneratedColumn<bool>(
    'is_dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sourceId,
    targetId,
    relation,
    createdAt,
    updatedAt,
    isDirty,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'note_links';
  @override
  VerificationContext validateIntegrity(
    Insertable<NoteLinkData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceIdMeta);
    }
    if (data.containsKey('target_id')) {
      context.handle(
        _targetIdMeta,
        targetId.isAcceptableOrUnknown(data['target_id']!, _targetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_targetIdMeta);
    }
    if (data.containsKey('relation')) {
      context.handle(
        _relationMeta,
        relation.isAcceptableOrUnknown(data['relation']!, _relationMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('is_dirty')) {
      context.handle(
        _isDirtyMeta,
        isDirty.isAcceptableOrUnknown(data['is_dirty']!, _isDirtyMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NoteLinkData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NoteLinkData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      )!,
      targetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_id'],
      )!,
      relation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}relation'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      isDirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_dirty'],
      )!,
    );
  }

  @override
  $NoteLinksTable createAlias(String alias) {
    return $NoteLinksTable(attachedDatabase, alias);
  }
}

class NoteLinkData extends DataClass implements Insertable<NoteLinkData> {
  final String id;
  final String sourceId;
  final String targetId;
  final String relation;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDirty;
  const NoteLinkData({
    required this.id,
    required this.sourceId,
    required this.targetId,
    required this.relation,
    required this.createdAt,
    required this.updatedAt,
    required this.isDirty,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['source_id'] = Variable<String>(sourceId);
    map['target_id'] = Variable<String>(targetId);
    map['relation'] = Variable<String>(relation);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['is_dirty'] = Variable<bool>(isDirty);
    return map;
  }

  NoteLinksCompanion toCompanion(bool nullToAbsent) {
    return NoteLinksCompanion(
      id: Value(id),
      sourceId: Value(sourceId),
      targetId: Value(targetId),
      relation: Value(relation),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      isDirty: Value(isDirty),
    );
  }

  factory NoteLinkData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NoteLinkData(
      id: serializer.fromJson<String>(json['id']),
      sourceId: serializer.fromJson<String>(json['sourceId']),
      targetId: serializer.fromJson<String>(json['targetId']),
      relation: serializer.fromJson<String>(json['relation']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      isDirty: serializer.fromJson<bool>(json['isDirty']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sourceId': serializer.toJson<String>(sourceId),
      'targetId': serializer.toJson<String>(targetId),
      'relation': serializer.toJson<String>(relation),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'isDirty': serializer.toJson<bool>(isDirty),
    };
  }

  NoteLinkData copyWith({
    String? id,
    String? sourceId,
    String? targetId,
    String? relation,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isDirty,
  }) => NoteLinkData(
    id: id ?? this.id,
    sourceId: sourceId ?? this.sourceId,
    targetId: targetId ?? this.targetId,
    relation: relation ?? this.relation,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    isDirty: isDirty ?? this.isDirty,
  );
  NoteLinkData copyWithCompanion(NoteLinksCompanion data) {
    return NoteLinkData(
      id: data.id.present ? data.id.value : this.id,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      targetId: data.targetId.present ? data.targetId.value : this.targetId,
      relation: data.relation.present ? data.relation.value : this.relation,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      isDirty: data.isDirty.present ? data.isDirty.value : this.isDirty,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NoteLinkData(')
          ..write('id: $id, ')
          ..write('sourceId: $sourceId, ')
          ..write('targetId: $targetId, ')
          ..write('relation: $relation, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isDirty: $isDirty')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sourceId,
    targetId,
    relation,
    createdAt,
    updatedAt,
    isDirty,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NoteLinkData &&
          other.id == this.id &&
          other.sourceId == this.sourceId &&
          other.targetId == this.targetId &&
          other.relation == this.relation &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.isDirty == this.isDirty);
}

class NoteLinksCompanion extends UpdateCompanion<NoteLinkData> {
  final Value<String> id;
  final Value<String> sourceId;
  final Value<String> targetId;
  final Value<String> relation;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<bool> isDirty;
  final Value<int> rowid;
  const NoteLinksCompanion({
    this.id = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.targetId = const Value.absent(),
    this.relation = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.isDirty = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NoteLinksCompanion.insert({
    required String id,
    required String sourceId,
    required String targetId,
    this.relation = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.isDirty = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       sourceId = Value(sourceId),
       targetId = Value(targetId);
  static Insertable<NoteLinkData> custom({
    Expression<String>? id,
    Expression<String>? sourceId,
    Expression<String>? targetId,
    Expression<String>? relation,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<bool>? isDirty,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sourceId != null) 'source_id': sourceId,
      if (targetId != null) 'target_id': targetId,
      if (relation != null) 'relation': relation,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (isDirty != null) 'is_dirty': isDirty,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NoteLinksCompanion copyWith({
    Value<String>? id,
    Value<String>? sourceId,
    Value<String>? targetId,
    Value<String>? relation,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<bool>? isDirty,
    Value<int>? rowid,
  }) {
    return NoteLinksCompanion(
      id: id ?? this.id,
      sourceId: sourceId ?? this.sourceId,
      targetId: targetId ?? this.targetId,
      relation: relation ?? this.relation,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDirty: isDirty ?? this.isDirty,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (targetId.present) {
      map['target_id'] = Variable<String>(targetId.value);
    }
    if (relation.present) {
      map['relation'] = Variable<String>(relation.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (isDirty.present) {
      map['is_dirty'] = Variable<bool>(isDirty.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NoteLinksCompanion(')
          ..write('id: $id, ')
          ..write('sourceId: $sourceId, ')
          ..write('targetId: $targetId, ')
          ..write('relation: $relation, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isDirty: $isDirty, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AttachmentsTable extends Attachments
    with TableInfo<$AttachmentsTable, AttachmentData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AttachmentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteIdMeta = const VerificationMeta('noteId');
  @override
  late final GeneratedColumn<String> noteId = GeneratedColumn<String>(
    'note_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES notes(id) ON DELETE CASCADE',
  );
  static const VerificationMeta _localPathMeta = const VerificationMeta(
    'localPath',
  );
  @override
  late final GeneratedColumn<String> localPath = GeneratedColumn<String>(
    'local_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _remoteUrlMeta = const VerificationMeta(
    'remoteUrl',
  );
  @override
  late final GeneratedColumn<String> remoteUrl = GeneratedColumn<String>(
    'remote_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fileNameMeta = const VerificationMeta(
    'fileName',
  );
  @override
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
    'file_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mimeTypeMeta = const VerificationMeta(
    'mimeType',
  );
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
    'mime_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileSizeMeta = const VerificationMeta(
    'fileSize',
  );
  @override
  late final GeneratedColumn<int> fileSize = GeneratedColumn<int>(
    'file_size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('local'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    noteId,
    localPath,
    remoteUrl,
    fileName,
    mimeType,
    fileSize,
    status,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'attachments';
  @override
  VerificationContext validateIntegrity(
    Insertable<AttachmentData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('note_id')) {
      context.handle(
        _noteIdMeta,
        noteId.isAcceptableOrUnknown(data['note_id']!, _noteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_noteIdMeta);
    }
    if (data.containsKey('local_path')) {
      context.handle(
        _localPathMeta,
        localPath.isAcceptableOrUnknown(data['local_path']!, _localPathMeta),
      );
    }
    if (data.containsKey('remote_url')) {
      context.handle(
        _remoteUrlMeta,
        remoteUrl.isAcceptableOrUnknown(data['remote_url']!, _remoteUrlMeta),
      );
    }
    if (data.containsKey('file_name')) {
      context.handle(
        _fileNameMeta,
        fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta),
      );
    } else if (isInserting) {
      context.missing(_fileNameMeta);
    }
    if (data.containsKey('mime_type')) {
      context.handle(
        _mimeTypeMeta,
        mimeType.isAcceptableOrUnknown(data['mime_type']!, _mimeTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_mimeTypeMeta);
    }
    if (data.containsKey('file_size')) {
      context.handle(
        _fileSizeMeta,
        fileSize.isAcceptableOrUnknown(data['file_size']!, _fileSizeMeta),
      );
    } else if (isInserting) {
      context.missing(_fileSizeMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AttachmentData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AttachmentData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      noteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note_id'],
      )!,
      localPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_path'],
      ),
      remoteUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remote_url'],
      ),
      fileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_name'],
      )!,
      mimeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime_type'],
      )!,
      fileSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}file_size'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $AttachmentsTable createAlias(String alias) {
    return $AttachmentsTable(attachedDatabase, alias);
  }
}

class AttachmentData extends DataClass implements Insertable<AttachmentData> {
  final String id;
  final String noteId;
  final String? localPath;
  final String? remoteUrl;
  final String fileName;
  final String mimeType;
  final int fileSize;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  const AttachmentData({
    required this.id,
    required this.noteId,
    this.localPath,
    this.remoteUrl,
    required this.fileName,
    required this.mimeType,
    required this.fileSize,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['note_id'] = Variable<String>(noteId);
    if (!nullToAbsent || localPath != null) {
      map['local_path'] = Variable<String>(localPath);
    }
    if (!nullToAbsent || remoteUrl != null) {
      map['remote_url'] = Variable<String>(remoteUrl);
    }
    map['file_name'] = Variable<String>(fileName);
    map['mime_type'] = Variable<String>(mimeType);
    map['file_size'] = Variable<int>(fileSize);
    map['status'] = Variable<String>(status);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  AttachmentsCompanion toCompanion(bool nullToAbsent) {
    return AttachmentsCompanion(
      id: Value(id),
      noteId: Value(noteId),
      localPath: localPath == null && nullToAbsent
          ? const Value.absent()
          : Value(localPath),
      remoteUrl: remoteUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(remoteUrl),
      fileName: Value(fileName),
      mimeType: Value(mimeType),
      fileSize: Value(fileSize),
      status: Value(status),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory AttachmentData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AttachmentData(
      id: serializer.fromJson<String>(json['id']),
      noteId: serializer.fromJson<String>(json['noteId']),
      localPath: serializer.fromJson<String?>(json['localPath']),
      remoteUrl: serializer.fromJson<String?>(json['remoteUrl']),
      fileName: serializer.fromJson<String>(json['fileName']),
      mimeType: serializer.fromJson<String>(json['mimeType']),
      fileSize: serializer.fromJson<int>(json['fileSize']),
      status: serializer.fromJson<String>(json['status']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'noteId': serializer.toJson<String>(noteId),
      'localPath': serializer.toJson<String?>(localPath),
      'remoteUrl': serializer.toJson<String?>(remoteUrl),
      'fileName': serializer.toJson<String>(fileName),
      'mimeType': serializer.toJson<String>(mimeType),
      'fileSize': serializer.toJson<int>(fileSize),
      'status': serializer.toJson<String>(status),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  AttachmentData copyWith({
    String? id,
    String? noteId,
    Value<String?> localPath = const Value.absent(),
    Value<String?> remoteUrl = const Value.absent(),
    String? fileName,
    String? mimeType,
    int? fileSize,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => AttachmentData(
    id: id ?? this.id,
    noteId: noteId ?? this.noteId,
    localPath: localPath.present ? localPath.value : this.localPath,
    remoteUrl: remoteUrl.present ? remoteUrl.value : this.remoteUrl,
    fileName: fileName ?? this.fileName,
    mimeType: mimeType ?? this.mimeType,
    fileSize: fileSize ?? this.fileSize,
    status: status ?? this.status,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  AttachmentData copyWithCompanion(AttachmentsCompanion data) {
    return AttachmentData(
      id: data.id.present ? data.id.value : this.id,
      noteId: data.noteId.present ? data.noteId.value : this.noteId,
      localPath: data.localPath.present ? data.localPath.value : this.localPath,
      remoteUrl: data.remoteUrl.present ? data.remoteUrl.value : this.remoteUrl,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
      fileSize: data.fileSize.present ? data.fileSize.value : this.fileSize,
      status: data.status.present ? data.status.value : this.status,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AttachmentData(')
          ..write('id: $id, ')
          ..write('noteId: $noteId, ')
          ..write('localPath: $localPath, ')
          ..write('remoteUrl: $remoteUrl, ')
          ..write('fileName: $fileName, ')
          ..write('mimeType: $mimeType, ')
          ..write('fileSize: $fileSize, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    noteId,
    localPath,
    remoteUrl,
    fileName,
    mimeType,
    fileSize,
    status,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AttachmentData &&
          other.id == this.id &&
          other.noteId == this.noteId &&
          other.localPath == this.localPath &&
          other.remoteUrl == this.remoteUrl &&
          other.fileName == this.fileName &&
          other.mimeType == this.mimeType &&
          other.fileSize == this.fileSize &&
          other.status == this.status &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class AttachmentsCompanion extends UpdateCompanion<AttachmentData> {
  final Value<String> id;
  final Value<String> noteId;
  final Value<String?> localPath;
  final Value<String?> remoteUrl;
  final Value<String> fileName;
  final Value<String> mimeType;
  final Value<int> fileSize;
  final Value<String> status;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const AttachmentsCompanion({
    this.id = const Value.absent(),
    this.noteId = const Value.absent(),
    this.localPath = const Value.absent(),
    this.remoteUrl = const Value.absent(),
    this.fileName = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.fileSize = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AttachmentsCompanion.insert({
    required String id,
    required String noteId,
    this.localPath = const Value.absent(),
    this.remoteUrl = const Value.absent(),
    required String fileName,
    required String mimeType,
    required int fileSize,
    this.status = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       noteId = Value(noteId),
       fileName = Value(fileName),
       mimeType = Value(mimeType),
       fileSize = Value(fileSize),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<AttachmentData> custom({
    Expression<String>? id,
    Expression<String>? noteId,
    Expression<String>? localPath,
    Expression<String>? remoteUrl,
    Expression<String>? fileName,
    Expression<String>? mimeType,
    Expression<int>? fileSize,
    Expression<String>? status,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (noteId != null) 'note_id': noteId,
      if (localPath != null) 'local_path': localPath,
      if (remoteUrl != null) 'remote_url': remoteUrl,
      if (fileName != null) 'file_name': fileName,
      if (mimeType != null) 'mime_type': mimeType,
      if (fileSize != null) 'file_size': fileSize,
      if (status != null) 'status': status,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AttachmentsCompanion copyWith({
    Value<String>? id,
    Value<String>? noteId,
    Value<String?>? localPath,
    Value<String?>? remoteUrl,
    Value<String>? fileName,
    Value<String>? mimeType,
    Value<int>? fileSize,
    Value<String>? status,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return AttachmentsCompanion(
      id: id ?? this.id,
      noteId: noteId ?? this.noteId,
      localPath: localPath ?? this.localPath,
      remoteUrl: remoteUrl ?? this.remoteUrl,
      fileName: fileName ?? this.fileName,
      mimeType: mimeType ?? this.mimeType,
      fileSize: fileSize ?? this.fileSize,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (noteId.present) {
      map['note_id'] = Variable<String>(noteId.value);
    }
    if (localPath.present) {
      map['local_path'] = Variable<String>(localPath.value);
    }
    if (remoteUrl.present) {
      map['remote_url'] = Variable<String>(remoteUrl.value);
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    if (mimeType.present) {
      map['mime_type'] = Variable<String>(mimeType.value);
    }
    if (fileSize.present) {
      map['file_size'] = Variable<int>(fileSize.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AttachmentsCompanion(')
          ..write('id: $id, ')
          ..write('noteId: $noteId, ')
          ..write('localPath: $localPath, ')
          ..write('remoteUrl: $remoteUrl, ')
          ..write('fileName: $fileName, ')
          ..write('mimeType: $mimeType, ')
          ..write('fileSize: $fileSize, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $UserNotePreferencesTable extends UserNotePreferences
    with TableInfo<$UserNotePreferencesTable, UserNotePreferenceData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UserNotePreferencesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteIdMeta = const VerificationMeta('noteId');
  @override
  late final GeneratedColumn<String> noteId = GeneratedColumn<String>(
    'note_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _favoriteMeta = const VerificationMeta(
    'favorite',
  );
  @override
  late final GeneratedColumn<bool> favorite = GeneratedColumn<bool>(
    'favorite',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("favorite" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _archivedMeta = const VerificationMeta(
    'archived',
  );
  @override
  late final GeneratedColumn<bool> archived = GeneratedColumn<bool>(
    'archived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("archived" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _hideCompletedMeta = const VerificationMeta(
    'hideCompleted',
  );
  @override
  late final GeneratedColumn<bool> hideCompleted = GeneratedColumn<bool>(
    'hide_completed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("hide_completed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _filtersMeta = const VerificationMeta(
    'filters',
  );
  @override
  late final GeneratedColumn<String> filters = GeneratedColumn<String>(
    'filters',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _isDirtyMeta = const VerificationMeta(
    'isDirty',
  );
  @override
  late final GeneratedColumn<bool> isDirty = GeneratedColumn<bool>(
    'is_dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    userId,
    noteId,
    favorite,
    archived,
    hideCompleted,
    filters,
    createdAt,
    updatedAt,
    isDirty,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'user_note_preferences';
  @override
  VerificationContext validateIntegrity(
    Insertable<UserNotePreferenceData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('note_id')) {
      context.handle(
        _noteIdMeta,
        noteId.isAcceptableOrUnknown(data['note_id']!, _noteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_noteIdMeta);
    }
    if (data.containsKey('favorite')) {
      context.handle(
        _favoriteMeta,
        favorite.isAcceptableOrUnknown(data['favorite']!, _favoriteMeta),
      );
    }
    if (data.containsKey('archived')) {
      context.handle(
        _archivedMeta,
        archived.isAcceptableOrUnknown(data['archived']!, _archivedMeta),
      );
    }
    if (data.containsKey('hide_completed')) {
      context.handle(
        _hideCompletedMeta,
        hideCompleted.isAcceptableOrUnknown(
          data['hide_completed']!,
          _hideCompletedMeta,
        ),
      );
    }
    if (data.containsKey('filters')) {
      context.handle(
        _filtersMeta,
        filters.isAcceptableOrUnknown(data['filters']!, _filtersMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('is_dirty')) {
      context.handle(
        _isDirtyMeta,
        isDirty.isAcceptableOrUnknown(data['is_dirty']!, _isDirtyMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {userId, noteId};
  @override
  UserNotePreferenceData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UserNotePreferenceData(
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      noteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note_id'],
      )!,
      favorite: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}favorite'],
      )!,
      archived: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}archived'],
      )!,
      hideCompleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}hide_completed'],
      )!,
      filters: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}filters'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      isDirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_dirty'],
      )!,
    );
  }

  @override
  $UserNotePreferencesTable createAlias(String alias) {
    return $UserNotePreferencesTable(attachedDatabase, alias);
  }
}

class UserNotePreferenceData extends DataClass
    implements Insertable<UserNotePreferenceData> {
  final String userId;
  final String noteId;
  final bool favorite;
  final bool archived;
  final bool hideCompleted;
  final String filters;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDirty;
  const UserNotePreferenceData({
    required this.userId,
    required this.noteId,
    required this.favorite,
    required this.archived,
    required this.hideCompleted,
    required this.filters,
    required this.createdAt,
    required this.updatedAt,
    required this.isDirty,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    map['note_id'] = Variable<String>(noteId);
    map['favorite'] = Variable<bool>(favorite);
    map['archived'] = Variable<bool>(archived);
    map['hide_completed'] = Variable<bool>(hideCompleted);
    map['filters'] = Variable<String>(filters);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['is_dirty'] = Variable<bool>(isDirty);
    return map;
  }

  UserNotePreferencesCompanion toCompanion(bool nullToAbsent) {
    return UserNotePreferencesCompanion(
      userId: Value(userId),
      noteId: Value(noteId),
      favorite: Value(favorite),
      archived: Value(archived),
      hideCompleted: Value(hideCompleted),
      filters: Value(filters),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      isDirty: Value(isDirty),
    );
  }

  factory UserNotePreferenceData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UserNotePreferenceData(
      userId: serializer.fromJson<String>(json['userId']),
      noteId: serializer.fromJson<String>(json['noteId']),
      favorite: serializer.fromJson<bool>(json['favorite']),
      archived: serializer.fromJson<bool>(json['archived']),
      hideCompleted: serializer.fromJson<bool>(json['hideCompleted']),
      filters: serializer.fromJson<String>(json['filters']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      isDirty: serializer.fromJson<bool>(json['isDirty']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'noteId': serializer.toJson<String>(noteId),
      'favorite': serializer.toJson<bool>(favorite),
      'archived': serializer.toJson<bool>(archived),
      'hideCompleted': serializer.toJson<bool>(hideCompleted),
      'filters': serializer.toJson<String>(filters),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'isDirty': serializer.toJson<bool>(isDirty),
    };
  }

  UserNotePreferenceData copyWith({
    String? userId,
    String? noteId,
    bool? favorite,
    bool? archived,
    bool? hideCompleted,
    String? filters,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isDirty,
  }) => UserNotePreferenceData(
    userId: userId ?? this.userId,
    noteId: noteId ?? this.noteId,
    favorite: favorite ?? this.favorite,
    archived: archived ?? this.archived,
    hideCompleted: hideCompleted ?? this.hideCompleted,
    filters: filters ?? this.filters,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    isDirty: isDirty ?? this.isDirty,
  );
  UserNotePreferenceData copyWithCompanion(UserNotePreferencesCompanion data) {
    return UserNotePreferenceData(
      userId: data.userId.present ? data.userId.value : this.userId,
      noteId: data.noteId.present ? data.noteId.value : this.noteId,
      favorite: data.favorite.present ? data.favorite.value : this.favorite,
      archived: data.archived.present ? data.archived.value : this.archived,
      hideCompleted: data.hideCompleted.present
          ? data.hideCompleted.value
          : this.hideCompleted,
      filters: data.filters.present ? data.filters.value : this.filters,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      isDirty: data.isDirty.present ? data.isDirty.value : this.isDirty,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UserNotePreferenceData(')
          ..write('userId: $userId, ')
          ..write('noteId: $noteId, ')
          ..write('favorite: $favorite, ')
          ..write('archived: $archived, ')
          ..write('hideCompleted: $hideCompleted, ')
          ..write('filters: $filters, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isDirty: $isDirty')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    userId,
    noteId,
    favorite,
    archived,
    hideCompleted,
    filters,
    createdAt,
    updatedAt,
    isDirty,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UserNotePreferenceData &&
          other.userId == this.userId &&
          other.noteId == this.noteId &&
          other.favorite == this.favorite &&
          other.archived == this.archived &&
          other.hideCompleted == this.hideCompleted &&
          other.filters == this.filters &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.isDirty == this.isDirty);
}

class UserNotePreferencesCompanion
    extends UpdateCompanion<UserNotePreferenceData> {
  final Value<String> userId;
  final Value<String> noteId;
  final Value<bool> favorite;
  final Value<bool> archived;
  final Value<bool> hideCompleted;
  final Value<String> filters;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<bool> isDirty;
  final Value<int> rowid;
  const UserNotePreferencesCompanion({
    this.userId = const Value.absent(),
    this.noteId = const Value.absent(),
    this.favorite = const Value.absent(),
    this.archived = const Value.absent(),
    this.hideCompleted = const Value.absent(),
    this.filters = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.isDirty = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UserNotePreferencesCompanion.insert({
    required String userId,
    required String noteId,
    this.favorite = const Value.absent(),
    this.archived = const Value.absent(),
    this.hideCompleted = const Value.absent(),
    this.filters = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.isDirty = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       noteId = Value(noteId);
  static Insertable<UserNotePreferenceData> custom({
    Expression<String>? userId,
    Expression<String>? noteId,
    Expression<bool>? favorite,
    Expression<bool>? archived,
    Expression<bool>? hideCompleted,
    Expression<String>? filters,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<bool>? isDirty,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (noteId != null) 'note_id': noteId,
      if (favorite != null) 'favorite': favorite,
      if (archived != null) 'archived': archived,
      if (hideCompleted != null) 'hide_completed': hideCompleted,
      if (filters != null) 'filters': filters,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (isDirty != null) 'is_dirty': isDirty,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UserNotePreferencesCompanion copyWith({
    Value<String>? userId,
    Value<String>? noteId,
    Value<bool>? favorite,
    Value<bool>? archived,
    Value<bool>? hideCompleted,
    Value<String>? filters,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<bool>? isDirty,
    Value<int>? rowid,
  }) {
    return UserNotePreferencesCompanion(
      userId: userId ?? this.userId,
      noteId: noteId ?? this.noteId,
      favorite: favorite ?? this.favorite,
      archived: archived ?? this.archived,
      hideCompleted: hideCompleted ?? this.hideCompleted,
      filters: filters ?? this.filters,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDirty: isDirty ?? this.isDirty,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (noteId.present) {
      map['note_id'] = Variable<String>(noteId.value);
    }
    if (favorite.present) {
      map['favorite'] = Variable<bool>(favorite.value);
    }
    if (archived.present) {
      map['archived'] = Variable<bool>(archived.value);
    }
    if (hideCompleted.present) {
      map['hide_completed'] = Variable<bool>(hideCompleted.value);
    }
    if (filters.present) {
      map['filters'] = Variable<String>(filters.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (isDirty.present) {
      map['is_dirty'] = Variable<bool>(isDirty.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UserNotePreferencesCompanion(')
          ..write('userId: $userId, ')
          ..write('noteId: $noteId, ')
          ..write('favorite: $favorite, ')
          ..write('archived: $archived, ')
          ..write('hideCompleted: $hideCompleted, ')
          ..write('filters: $filters, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isDirty: $isDirty, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalYjsStatesTable extends LocalYjsStates
    with TableInfo<$LocalYjsStatesTable, LocalYjsState> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalYjsStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _noteIdMeta = const VerificationMeta('noteId');
  @override
  late final GeneratedColumn<String> noteId = GeneratedColumn<String>(
    'note_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES notes (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<Uint8List> state = GeneratedColumn<Uint8List>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _syncedStateVectorMeta = const VerificationMeta(
    'syncedStateVector',
  );
  @override
  late final GeneratedColumn<Uint8List> syncedStateVector =
      GeneratedColumn<Uint8List>(
        'synced_state_vector',
        aliasedName,
        true,
        type: DriftSqlType.blob,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    noteId,
    state,
    syncedStateVector,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_yjs_states';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalYjsState> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('note_id')) {
      context.handle(
        _noteIdMeta,
        noteId.isAcceptableOrUnknown(data['note_id']!, _noteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_noteIdMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('synced_state_vector')) {
      context.handle(
        _syncedStateVectorMeta,
        syncedStateVector.isAcceptableOrUnknown(
          data['synced_state_vector']!,
          _syncedStateVectorMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {noteId};
  @override
  LocalYjsState map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalYjsState(
      noteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note_id'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}state'],
      )!,
      syncedStateVector: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}synced_state_vector'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $LocalYjsStatesTable createAlias(String alias) {
    return $LocalYjsStatesTable(attachedDatabase, alias);
  }
}

class LocalYjsState extends DataClass implements Insertable<LocalYjsState> {
  final String noteId;
  final Uint8List state;
  final Uint8List? syncedStateVector;
  final DateTime updatedAt;
  const LocalYjsState({
    required this.noteId,
    required this.state,
    this.syncedStateVector,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['note_id'] = Variable<String>(noteId);
    map['state'] = Variable<Uint8List>(state);
    if (!nullToAbsent || syncedStateVector != null) {
      map['synced_state_vector'] = Variable<Uint8List>(syncedStateVector);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  LocalYjsStatesCompanion toCompanion(bool nullToAbsent) {
    return LocalYjsStatesCompanion(
      noteId: Value(noteId),
      state: Value(state),
      syncedStateVector: syncedStateVector == null && nullToAbsent
          ? const Value.absent()
          : Value(syncedStateVector),
      updatedAt: Value(updatedAt),
    );
  }

  factory LocalYjsState.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalYjsState(
      noteId: serializer.fromJson<String>(json['noteId']),
      state: serializer.fromJson<Uint8List>(json['state']),
      syncedStateVector: serializer.fromJson<Uint8List?>(
        json['syncedStateVector'],
      ),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'noteId': serializer.toJson<String>(noteId),
      'state': serializer.toJson<Uint8List>(state),
      'syncedStateVector': serializer.toJson<Uint8List?>(syncedStateVector),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  LocalYjsState copyWith({
    String? noteId,
    Uint8List? state,
    Value<Uint8List?> syncedStateVector = const Value.absent(),
    DateTime? updatedAt,
  }) => LocalYjsState(
    noteId: noteId ?? this.noteId,
    state: state ?? this.state,
    syncedStateVector: syncedStateVector.present
        ? syncedStateVector.value
        : this.syncedStateVector,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  LocalYjsState copyWithCompanion(LocalYjsStatesCompanion data) {
    return LocalYjsState(
      noteId: data.noteId.present ? data.noteId.value : this.noteId,
      state: data.state.present ? data.state.value : this.state,
      syncedStateVector: data.syncedStateVector.present
          ? data.syncedStateVector.value
          : this.syncedStateVector,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalYjsState(')
          ..write('noteId: $noteId, ')
          ..write('state: $state, ')
          ..write('syncedStateVector: $syncedStateVector, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    noteId,
    $driftBlobEquality.hash(state),
    $driftBlobEquality.hash(syncedStateVector),
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalYjsState &&
          other.noteId == this.noteId &&
          $driftBlobEquality.equals(other.state, this.state) &&
          $driftBlobEquality.equals(
            other.syncedStateVector,
            this.syncedStateVector,
          ) &&
          other.updatedAt == this.updatedAt);
}

class LocalYjsStatesCompanion extends UpdateCompanion<LocalYjsState> {
  final Value<String> noteId;
  final Value<Uint8List> state;
  final Value<Uint8List?> syncedStateVector;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const LocalYjsStatesCompanion({
    this.noteId = const Value.absent(),
    this.state = const Value.absent(),
    this.syncedStateVector = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalYjsStatesCompanion.insert({
    required String noteId,
    required Uint8List state,
    this.syncedStateVector = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : noteId = Value(noteId),
       state = Value(state);
  static Insertable<LocalYjsState> custom({
    Expression<String>? noteId,
    Expression<Uint8List>? state,
    Expression<Uint8List>? syncedStateVector,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (noteId != null) 'note_id': noteId,
      if (state != null) 'state': state,
      if (syncedStateVector != null) 'synced_state_vector': syncedStateVector,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalYjsStatesCompanion copyWith({
    Value<String>? noteId,
    Value<Uint8List>? state,
    Value<Uint8List?>? syncedStateVector,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return LocalYjsStatesCompanion(
      noteId: noteId ?? this.noteId,
      state: state ?? this.state,
      syncedStateVector: syncedStateVector ?? this.syncedStateVector,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (noteId.present) {
      map['note_id'] = Variable<String>(noteId.value);
    }
    if (state.present) {
      map['state'] = Variable<Uint8List>(state.value);
    }
    if (syncedStateVector.present) {
      map['synced_state_vector'] = Variable<Uint8List>(syncedStateVector.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalYjsStatesCompanion(')
          ..write('noteId: $noteId, ')
          ..write('state: $state, ')
          ..write('syncedStateVector: $syncedStateVector, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalNoteDocumentsTable extends LocalNoteDocuments
    with TableInfo<$LocalNoteDocumentsTable, LocalNoteDocumentData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalNoteDocumentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _noteIdMeta = const VerificationMeta('noteId');
  @override
  late final GeneratedColumn<String> noteId = GeneratedColumn<String>(
    'note_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _documentJsonMeta = const VerificationMeta(
    'documentJson',
  );
  @override
  late final GeneratedColumn<String> documentJson = GeneratedColumn<String>(
    'document_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    noteId,
    revision,
    documentJson,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_note_documents';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalNoteDocumentData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('note_id')) {
      context.handle(
        _noteIdMeta,
        noteId.isAcceptableOrUnknown(data['note_id']!, _noteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_noteIdMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    } else if (isInserting) {
      context.missing(_revisionMeta);
    }
    if (data.containsKey('document_json')) {
      context.handle(
        _documentJsonMeta,
        documentJson.isAcceptableOrUnknown(
          data['document_json']!,
          _documentJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_documentJsonMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {noteId};
  @override
  LocalNoteDocumentData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalNoteDocumentData(
      noteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note_id'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      documentJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}document_json'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $LocalNoteDocumentsTable createAlias(String alias) {
    return $LocalNoteDocumentsTable(attachedDatabase, alias);
  }
}

class LocalNoteDocumentData extends DataClass
    implements Insertable<LocalNoteDocumentData> {
  final String noteId;
  final int revision;
  final String documentJson;
  final DateTime updatedAt;
  const LocalNoteDocumentData({
    required this.noteId,
    required this.revision,
    required this.documentJson,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['note_id'] = Variable<String>(noteId);
    map['revision'] = Variable<int>(revision);
    map['document_json'] = Variable<String>(documentJson);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  LocalNoteDocumentsCompanion toCompanion(bool nullToAbsent) {
    return LocalNoteDocumentsCompanion(
      noteId: Value(noteId),
      revision: Value(revision),
      documentJson: Value(documentJson),
      updatedAt: Value(updatedAt),
    );
  }

  factory LocalNoteDocumentData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalNoteDocumentData(
      noteId: serializer.fromJson<String>(json['noteId']),
      revision: serializer.fromJson<int>(json['revision']),
      documentJson: serializer.fromJson<String>(json['documentJson']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'noteId': serializer.toJson<String>(noteId),
      'revision': serializer.toJson<int>(revision),
      'documentJson': serializer.toJson<String>(documentJson),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  LocalNoteDocumentData copyWith({
    String? noteId,
    int? revision,
    String? documentJson,
    DateTime? updatedAt,
  }) => LocalNoteDocumentData(
    noteId: noteId ?? this.noteId,
    revision: revision ?? this.revision,
    documentJson: documentJson ?? this.documentJson,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  LocalNoteDocumentData copyWithCompanion(LocalNoteDocumentsCompanion data) {
    return LocalNoteDocumentData(
      noteId: data.noteId.present ? data.noteId.value : this.noteId,
      revision: data.revision.present ? data.revision.value : this.revision,
      documentJson: data.documentJson.present
          ? data.documentJson.value
          : this.documentJson,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalNoteDocumentData(')
          ..write('noteId: $noteId, ')
          ..write('revision: $revision, ')
          ..write('documentJson: $documentJson, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(noteId, revision, documentJson, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalNoteDocumentData &&
          other.noteId == this.noteId &&
          other.revision == this.revision &&
          other.documentJson == this.documentJson &&
          other.updatedAt == this.updatedAt);
}

class LocalNoteDocumentsCompanion
    extends UpdateCompanion<LocalNoteDocumentData> {
  final Value<String> noteId;
  final Value<int> revision;
  final Value<String> documentJson;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const LocalNoteDocumentsCompanion({
    this.noteId = const Value.absent(),
    this.revision = const Value.absent(),
    this.documentJson = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalNoteDocumentsCompanion.insert({
    required String noteId,
    required int revision,
    required String documentJson,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : noteId = Value(noteId),
       revision = Value(revision),
       documentJson = Value(documentJson),
       updatedAt = Value(updatedAt);
  static Insertable<LocalNoteDocumentData> custom({
    Expression<String>? noteId,
    Expression<int>? revision,
    Expression<String>? documentJson,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (noteId != null) 'note_id': noteId,
      if (revision != null) 'revision': revision,
      if (documentJson != null) 'document_json': documentJson,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalNoteDocumentsCompanion copyWith({
    Value<String>? noteId,
    Value<int>? revision,
    Value<String>? documentJson,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return LocalNoteDocumentsCompanion(
      noteId: noteId ?? this.noteId,
      revision: revision ?? this.revision,
      documentJson: documentJson ?? this.documentJson,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (noteId.present) {
      map['note_id'] = Variable<String>(noteId.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (documentJson.present) {
      map['document_json'] = Variable<String>(documentJson.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalNoteDocumentsCompanion(')
          ..write('noteId: $noteId, ')
          ..write('revision: $revision, ')
          ..write('documentJson: $documentJson, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PendingNoteOperationsTable extends PendingNoteOperations
    with TableInfo<$PendingNoteOperationsTable, PendingNoteOperationData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingNoteOperationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _operationIdMeta = const VerificationMeta(
    'operationId',
  );
  @override
  late final GeneratedColumn<String> operationId = GeneratedColumn<String>(
    'operation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteIdMeta = const VerificationMeta('noteId');
  @override
  late final GeneratedColumn<String> noteId = GeneratedColumn<String>(
    'note_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _baseRevisionMeta = const VerificationMeta(
    'baseRevision',
  );
  @override
  late final GeneratedColumn<int> baseRevision = GeneratedColumn<int>(
    'base_revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ordinalMeta = const VerificationMeta(
    'ordinal',
  );
  @override
  late final GeneratedColumn<int> ordinal = GeneratedColumn<int>(
    'ordinal',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _blockIdMeta = const VerificationMeta(
    'blockId',
  );
  @override
  late final GeneratedColumn<String> blockId = GeneratedColumn<String>(
    'block_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastAttemptAtMeta = const VerificationMeta(
    'lastAttemptAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastAttemptAt =
      GeneratedColumn<DateTime>(
        'last_attempt_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _attemptCountMeta = const VerificationMeta(
    'attemptCount',
  );
  @override
  late final GeneratedColumn<int> attemptCount = GeneratedColumn<int>(
    'attempt_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    operationId,
    noteId,
    baseRevision,
    ordinal,
    kind,
    blockId,
    payloadJson,
    createdAt,
    lastAttemptAt,
    attemptCount,
    status,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_note_operations';
  @override
  VerificationContext validateIntegrity(
    Insertable<PendingNoteOperationData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('operation_id')) {
      context.handle(
        _operationIdMeta,
        operationId.isAcceptableOrUnknown(
          data['operation_id']!,
          _operationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_operationIdMeta);
    }
    if (data.containsKey('note_id')) {
      context.handle(
        _noteIdMeta,
        noteId.isAcceptableOrUnknown(data['note_id']!, _noteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_noteIdMeta);
    }
    if (data.containsKey('base_revision')) {
      context.handle(
        _baseRevisionMeta,
        baseRevision.isAcceptableOrUnknown(
          data['base_revision']!,
          _baseRevisionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_baseRevisionMeta);
    }
    if (data.containsKey('ordinal')) {
      context.handle(
        _ordinalMeta,
        ordinal.isAcceptableOrUnknown(data['ordinal']!, _ordinalMeta),
      );
    } else if (isInserting) {
      context.missing(_ordinalMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('block_id')) {
      context.handle(
        _blockIdMeta,
        blockId.isAcceptableOrUnknown(data['block_id']!, _blockIdMeta),
      );
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('last_attempt_at')) {
      context.handle(
        _lastAttemptAtMeta,
        lastAttemptAt.isAcceptableOrUnknown(
          data['last_attempt_at']!,
          _lastAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('attempt_count')) {
      context.handle(
        _attemptCountMeta,
        attemptCount.isAcceptableOrUnknown(
          data['attempt_count']!,
          _attemptCountMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {operationId};
  @override
  PendingNoteOperationData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingNoteOperationData(
      operationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation_id'],
      )!,
      noteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note_id'],
      )!,
      baseRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}base_revision'],
      )!,
      ordinal: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ordinal'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      blockId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}block_id'],
      ),
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      lastAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_attempt_at'],
      ),
      attemptCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt_count'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
    );
  }

  @override
  $PendingNoteOperationsTable createAlias(String alias) {
    return $PendingNoteOperationsTable(attachedDatabase, alias);
  }
}

class PendingNoteOperationData extends DataClass
    implements Insertable<PendingNoteOperationData> {
  final String operationId;
  final String noteId;
  final int baseRevision;
  final int ordinal;
  final String kind;
  final String? blockId;
  final String payloadJson;
  final DateTime createdAt;
  final DateTime? lastAttemptAt;
  final int attemptCount;
  final String status;
  const PendingNoteOperationData({
    required this.operationId,
    required this.noteId,
    required this.baseRevision,
    required this.ordinal,
    required this.kind,
    this.blockId,
    required this.payloadJson,
    required this.createdAt,
    this.lastAttemptAt,
    required this.attemptCount,
    required this.status,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['operation_id'] = Variable<String>(operationId);
    map['note_id'] = Variable<String>(noteId);
    map['base_revision'] = Variable<int>(baseRevision);
    map['ordinal'] = Variable<int>(ordinal);
    map['kind'] = Variable<String>(kind);
    if (!nullToAbsent || blockId != null) {
      map['block_id'] = Variable<String>(blockId);
    }
    map['payload_json'] = Variable<String>(payloadJson);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || lastAttemptAt != null) {
      map['last_attempt_at'] = Variable<DateTime>(lastAttemptAt);
    }
    map['attempt_count'] = Variable<int>(attemptCount);
    map['status'] = Variable<String>(status);
    return map;
  }

  PendingNoteOperationsCompanion toCompanion(bool nullToAbsent) {
    return PendingNoteOperationsCompanion(
      operationId: Value(operationId),
      noteId: Value(noteId),
      baseRevision: Value(baseRevision),
      ordinal: Value(ordinal),
      kind: Value(kind),
      blockId: blockId == null && nullToAbsent
          ? const Value.absent()
          : Value(blockId),
      payloadJson: Value(payloadJson),
      createdAt: Value(createdAt),
      lastAttemptAt: lastAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastAttemptAt),
      attemptCount: Value(attemptCount),
      status: Value(status),
    );
  }

  factory PendingNoteOperationData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingNoteOperationData(
      operationId: serializer.fromJson<String>(json['operationId']),
      noteId: serializer.fromJson<String>(json['noteId']),
      baseRevision: serializer.fromJson<int>(json['baseRevision']),
      ordinal: serializer.fromJson<int>(json['ordinal']),
      kind: serializer.fromJson<String>(json['kind']),
      blockId: serializer.fromJson<String?>(json['blockId']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      lastAttemptAt: serializer.fromJson<DateTime?>(json['lastAttemptAt']),
      attemptCount: serializer.fromJson<int>(json['attemptCount']),
      status: serializer.fromJson<String>(json['status']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'operationId': serializer.toJson<String>(operationId),
      'noteId': serializer.toJson<String>(noteId),
      'baseRevision': serializer.toJson<int>(baseRevision),
      'ordinal': serializer.toJson<int>(ordinal),
      'kind': serializer.toJson<String>(kind),
      'blockId': serializer.toJson<String?>(blockId),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'lastAttemptAt': serializer.toJson<DateTime?>(lastAttemptAt),
      'attemptCount': serializer.toJson<int>(attemptCount),
      'status': serializer.toJson<String>(status),
    };
  }

  PendingNoteOperationData copyWith({
    String? operationId,
    String? noteId,
    int? baseRevision,
    int? ordinal,
    String? kind,
    Value<String?> blockId = const Value.absent(),
    String? payloadJson,
    DateTime? createdAt,
    Value<DateTime?> lastAttemptAt = const Value.absent(),
    int? attemptCount,
    String? status,
  }) => PendingNoteOperationData(
    operationId: operationId ?? this.operationId,
    noteId: noteId ?? this.noteId,
    baseRevision: baseRevision ?? this.baseRevision,
    ordinal: ordinal ?? this.ordinal,
    kind: kind ?? this.kind,
    blockId: blockId.present ? blockId.value : this.blockId,
    payloadJson: payloadJson ?? this.payloadJson,
    createdAt: createdAt ?? this.createdAt,
    lastAttemptAt: lastAttemptAt.present
        ? lastAttemptAt.value
        : this.lastAttemptAt,
    attemptCount: attemptCount ?? this.attemptCount,
    status: status ?? this.status,
  );
  PendingNoteOperationData copyWithCompanion(
    PendingNoteOperationsCompanion data,
  ) {
    return PendingNoteOperationData(
      operationId: data.operationId.present
          ? data.operationId.value
          : this.operationId,
      noteId: data.noteId.present ? data.noteId.value : this.noteId,
      baseRevision: data.baseRevision.present
          ? data.baseRevision.value
          : this.baseRevision,
      ordinal: data.ordinal.present ? data.ordinal.value : this.ordinal,
      kind: data.kind.present ? data.kind.value : this.kind,
      blockId: data.blockId.present ? data.blockId.value : this.blockId,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      lastAttemptAt: data.lastAttemptAt.present
          ? data.lastAttemptAt.value
          : this.lastAttemptAt,
      attemptCount: data.attemptCount.present
          ? data.attemptCount.value
          : this.attemptCount,
      status: data.status.present ? data.status.value : this.status,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingNoteOperationData(')
          ..write('operationId: $operationId, ')
          ..write('noteId: $noteId, ')
          ..write('baseRevision: $baseRevision, ')
          ..write('ordinal: $ordinal, ')
          ..write('kind: $kind, ')
          ..write('blockId: $blockId, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastAttemptAt: $lastAttemptAt, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    operationId,
    noteId,
    baseRevision,
    ordinal,
    kind,
    blockId,
    payloadJson,
    createdAt,
    lastAttemptAt,
    attemptCount,
    status,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingNoteOperationData &&
          other.operationId == this.operationId &&
          other.noteId == this.noteId &&
          other.baseRevision == this.baseRevision &&
          other.ordinal == this.ordinal &&
          other.kind == this.kind &&
          other.blockId == this.blockId &&
          other.payloadJson == this.payloadJson &&
          other.createdAt == this.createdAt &&
          other.lastAttemptAt == this.lastAttemptAt &&
          other.attemptCount == this.attemptCount &&
          other.status == this.status);
}

class PendingNoteOperationsCompanion
    extends UpdateCompanion<PendingNoteOperationData> {
  final Value<String> operationId;
  final Value<String> noteId;
  final Value<int> baseRevision;
  final Value<int> ordinal;
  final Value<String> kind;
  final Value<String?> blockId;
  final Value<String> payloadJson;
  final Value<DateTime> createdAt;
  final Value<DateTime?> lastAttemptAt;
  final Value<int> attemptCount;
  final Value<String> status;
  final Value<int> rowid;
  const PendingNoteOperationsCompanion({
    this.operationId = const Value.absent(),
    this.noteId = const Value.absent(),
    this.baseRevision = const Value.absent(),
    this.ordinal = const Value.absent(),
    this.kind = const Value.absent(),
    this.blockId = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastAttemptAt = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.status = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PendingNoteOperationsCompanion.insert({
    required String operationId,
    required String noteId,
    required int baseRevision,
    required int ordinal,
    required String kind,
    this.blockId = const Value.absent(),
    required String payloadJson,
    required DateTime createdAt,
    this.lastAttemptAt = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.status = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : operationId = Value(operationId),
       noteId = Value(noteId),
       baseRevision = Value(baseRevision),
       ordinal = Value(ordinal),
       kind = Value(kind),
       payloadJson = Value(payloadJson),
       createdAt = Value(createdAt);
  static Insertable<PendingNoteOperationData> custom({
    Expression<String>? operationId,
    Expression<String>? noteId,
    Expression<int>? baseRevision,
    Expression<int>? ordinal,
    Expression<String>? kind,
    Expression<String>? blockId,
    Expression<String>? payloadJson,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? lastAttemptAt,
    Expression<int>? attemptCount,
    Expression<String>? status,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (operationId != null) 'operation_id': operationId,
      if (noteId != null) 'note_id': noteId,
      if (baseRevision != null) 'base_revision': baseRevision,
      if (ordinal != null) 'ordinal': ordinal,
      if (kind != null) 'kind': kind,
      if (blockId != null) 'block_id': blockId,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (createdAt != null) 'created_at': createdAt,
      if (lastAttemptAt != null) 'last_attempt_at': lastAttemptAt,
      if (attemptCount != null) 'attempt_count': attemptCount,
      if (status != null) 'status': status,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PendingNoteOperationsCompanion copyWith({
    Value<String>? operationId,
    Value<String>? noteId,
    Value<int>? baseRevision,
    Value<int>? ordinal,
    Value<String>? kind,
    Value<String?>? blockId,
    Value<String>? payloadJson,
    Value<DateTime>? createdAt,
    Value<DateTime?>? lastAttemptAt,
    Value<int>? attemptCount,
    Value<String>? status,
    Value<int>? rowid,
  }) {
    return PendingNoteOperationsCompanion(
      operationId: operationId ?? this.operationId,
      noteId: noteId ?? this.noteId,
      baseRevision: baseRevision ?? this.baseRevision,
      ordinal: ordinal ?? this.ordinal,
      kind: kind ?? this.kind,
      blockId: blockId ?? this.blockId,
      payloadJson: payloadJson ?? this.payloadJson,
      createdAt: createdAt ?? this.createdAt,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      attemptCount: attemptCount ?? this.attemptCount,
      status: status ?? this.status,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (operationId.present) {
      map['operation_id'] = Variable<String>(operationId.value);
    }
    if (noteId.present) {
      map['note_id'] = Variable<String>(noteId.value);
    }
    if (baseRevision.present) {
      map['base_revision'] = Variable<int>(baseRevision.value);
    }
    if (ordinal.present) {
      map['ordinal'] = Variable<int>(ordinal.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (blockId.present) {
      map['block_id'] = Variable<String>(blockId.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (lastAttemptAt.present) {
      map['last_attempt_at'] = Variable<DateTime>(lastAttemptAt.value);
    }
    if (attemptCount.present) {
      map['attempt_count'] = Variable<int>(attemptCount.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingNoteOperationsCompanion(')
          ..write('operationId: $operationId, ')
          ..write('noteId: $noteId, ')
          ..write('baseRevision: $baseRevision, ')
          ..write('ordinal: $ordinal, ')
          ..write('kind: $kind, ')
          ..write('blockId: $blockId, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastAttemptAt: $lastAttemptAt, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('status: $status, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NoteSyncErrorsTable extends NoteSyncErrors
    with TableInfo<$NoteSyncErrorsTable, NoteSyncErrorData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NoteSyncErrorsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _operationIdMeta = const VerificationMeta(
    'operationId',
  );
  @override
  late final GeneratedColumn<String> operationId = GeneratedColumn<String>(
    'operation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteIdMeta = const VerificationMeta('noteId');
  @override
  late final GeneratedColumn<String> noteId = GeneratedColumn<String>(
    'note_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _errorCodeMeta = const VerificationMeta(
    'errorCode',
  );
  @override
  late final GeneratedColumn<String> errorCode = GeneratedColumn<String>(
    'error_code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _messageMeta = const VerificationMeta(
    'message',
  );
  @override
  late final GeneratedColumn<String> message = GeneratedColumn<String>(
    'message',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    operationId,
    noteId,
    errorCode,
    message,
    payloadJson,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'note_sync_errors';
  @override
  VerificationContext validateIntegrity(
    Insertable<NoteSyncErrorData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('operation_id')) {
      context.handle(
        _operationIdMeta,
        operationId.isAcceptableOrUnknown(
          data['operation_id']!,
          _operationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_operationIdMeta);
    }
    if (data.containsKey('note_id')) {
      context.handle(
        _noteIdMeta,
        noteId.isAcceptableOrUnknown(data['note_id']!, _noteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_noteIdMeta);
    }
    if (data.containsKey('error_code')) {
      context.handle(
        _errorCodeMeta,
        errorCode.isAcceptableOrUnknown(data['error_code']!, _errorCodeMeta),
      );
    } else if (isInserting) {
      context.missing(_errorCodeMeta);
    }
    if (data.containsKey('message')) {
      context.handle(
        _messageMeta,
        message.isAcceptableOrUnknown(data['message']!, _messageMeta),
      );
    } else if (isInserting) {
      context.missing(_messageMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {operationId};
  @override
  NoteSyncErrorData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NoteSyncErrorData(
      operationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation_id'],
      )!,
      noteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note_id'],
      )!,
      errorCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_code'],
      )!,
      message: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $NoteSyncErrorsTable createAlias(String alias) {
    return $NoteSyncErrorsTable(attachedDatabase, alias);
  }
}

class NoteSyncErrorData extends DataClass
    implements Insertable<NoteSyncErrorData> {
  final String operationId;
  final String noteId;
  final String errorCode;
  final String message;
  final String payloadJson;
  final DateTime createdAt;
  const NoteSyncErrorData({
    required this.operationId,
    required this.noteId,
    required this.errorCode,
    required this.message,
    required this.payloadJson,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['operation_id'] = Variable<String>(operationId);
    map['note_id'] = Variable<String>(noteId);
    map['error_code'] = Variable<String>(errorCode);
    map['message'] = Variable<String>(message);
    map['payload_json'] = Variable<String>(payloadJson);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  NoteSyncErrorsCompanion toCompanion(bool nullToAbsent) {
    return NoteSyncErrorsCompanion(
      operationId: Value(operationId),
      noteId: Value(noteId),
      errorCode: Value(errorCode),
      message: Value(message),
      payloadJson: Value(payloadJson),
      createdAt: Value(createdAt),
    );
  }

  factory NoteSyncErrorData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NoteSyncErrorData(
      operationId: serializer.fromJson<String>(json['operationId']),
      noteId: serializer.fromJson<String>(json['noteId']),
      errorCode: serializer.fromJson<String>(json['errorCode']),
      message: serializer.fromJson<String>(json['message']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'operationId': serializer.toJson<String>(operationId),
      'noteId': serializer.toJson<String>(noteId),
      'errorCode': serializer.toJson<String>(errorCode),
      'message': serializer.toJson<String>(message),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  NoteSyncErrorData copyWith({
    String? operationId,
    String? noteId,
    String? errorCode,
    String? message,
    String? payloadJson,
    DateTime? createdAt,
  }) => NoteSyncErrorData(
    operationId: operationId ?? this.operationId,
    noteId: noteId ?? this.noteId,
    errorCode: errorCode ?? this.errorCode,
    message: message ?? this.message,
    payloadJson: payloadJson ?? this.payloadJson,
    createdAt: createdAt ?? this.createdAt,
  );
  NoteSyncErrorData copyWithCompanion(NoteSyncErrorsCompanion data) {
    return NoteSyncErrorData(
      operationId: data.operationId.present
          ? data.operationId.value
          : this.operationId,
      noteId: data.noteId.present ? data.noteId.value : this.noteId,
      errorCode: data.errorCode.present ? data.errorCode.value : this.errorCode,
      message: data.message.present ? data.message.value : this.message,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NoteSyncErrorData(')
          ..write('operationId: $operationId, ')
          ..write('noteId: $noteId, ')
          ..write('errorCode: $errorCode, ')
          ..write('message: $message, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    operationId,
    noteId,
    errorCode,
    message,
    payloadJson,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NoteSyncErrorData &&
          other.operationId == this.operationId &&
          other.noteId == this.noteId &&
          other.errorCode == this.errorCode &&
          other.message == this.message &&
          other.payloadJson == this.payloadJson &&
          other.createdAt == this.createdAt);
}

class NoteSyncErrorsCompanion extends UpdateCompanion<NoteSyncErrorData> {
  final Value<String> operationId;
  final Value<String> noteId;
  final Value<String> errorCode;
  final Value<String> message;
  final Value<String> payloadJson;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const NoteSyncErrorsCompanion({
    this.operationId = const Value.absent(),
    this.noteId = const Value.absent(),
    this.errorCode = const Value.absent(),
    this.message = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NoteSyncErrorsCompanion.insert({
    required String operationId,
    required String noteId,
    required String errorCode,
    required String message,
    required String payloadJson,
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : operationId = Value(operationId),
       noteId = Value(noteId),
       errorCode = Value(errorCode),
       message = Value(message),
       payloadJson = Value(payloadJson),
       createdAt = Value(createdAt);
  static Insertable<NoteSyncErrorData> custom({
    Expression<String>? operationId,
    Expression<String>? noteId,
    Expression<String>? errorCode,
    Expression<String>? message,
    Expression<String>? payloadJson,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (operationId != null) 'operation_id': operationId,
      if (noteId != null) 'note_id': noteId,
      if (errorCode != null) 'error_code': errorCode,
      if (message != null) 'message': message,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NoteSyncErrorsCompanion copyWith({
    Value<String>? operationId,
    Value<String>? noteId,
    Value<String>? errorCode,
    Value<String>? message,
    Value<String>? payloadJson,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return NoteSyncErrorsCompanion(
      operationId: operationId ?? this.operationId,
      noteId: noteId ?? this.noteId,
      errorCode: errorCode ?? this.errorCode,
      message: message ?? this.message,
      payloadJson: payloadJson ?? this.payloadJson,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (operationId.present) {
      map['operation_id'] = Variable<String>(operationId.value);
    }
    if (noteId.present) {
      map['note_id'] = Variable<String>(noteId.value);
    }
    if (errorCode.present) {
      map['error_code'] = Variable<String>(errorCode.value);
    }
    if (message.present) {
      map['message'] = Variable<String>(message.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NoteSyncErrorsCompanion(')
          ..write('operationId: $operationId, ')
          ..write('noteId: $noteId, ')
          ..write('errorCode: $errorCode, ')
          ..write('message: $message, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncSessionsTable extends SyncSessions
    with TableInfo<$SyncSessionsTable, SyncSessionData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _noteIdMeta = const VerificationMeta('noteId');
  @override
  late final GeneratedColumn<String> noteId = GeneratedColumn<String>(
    'note_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _knownRevisionMeta = const VerificationMeta(
    'knownRevision',
  );
  @override
  late final GeneratedColumn<int> knownRevision = GeneratedColumn<int>(
    'known_revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _operationIdsMeta = const VerificationMeta(
    'operationIds',
  );
  @override
  late final GeneratedColumn<String> operationIds = GeneratedColumn<String>(
    'operation_ids',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<String> startedAt = GeneratedColumn<String>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    noteId,
    knownRevision,
    operationIds,
    startedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncSessionData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('note_id')) {
      context.handle(
        _noteIdMeta,
        noteId.isAcceptableOrUnknown(data['note_id']!, _noteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_noteIdMeta);
    }
    if (data.containsKey('known_revision')) {
      context.handle(
        _knownRevisionMeta,
        knownRevision.isAcceptableOrUnknown(
          data['known_revision']!,
          _knownRevisionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_knownRevisionMeta);
    }
    if (data.containsKey('operation_ids')) {
      context.handle(
        _operationIdsMeta,
        operationIds.isAcceptableOrUnknown(
          data['operation_ids']!,
          _operationIdsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_operationIdsMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {noteId};
  @override
  SyncSessionData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncSessionData(
      noteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note_id'],
      )!,
      knownRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}known_revision'],
      )!,
      operationIds: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation_ids'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}started_at'],
      )!,
    );
  }

  @override
  $SyncSessionsTable createAlias(String alias) {
    return $SyncSessionsTable(attachedDatabase, alias);
  }
}

class SyncSessionData extends DataClass implements Insertable<SyncSessionData> {
  final String noteId;
  final int knownRevision;
  final String operationIds;
  final String startedAt;
  const SyncSessionData({
    required this.noteId,
    required this.knownRevision,
    required this.operationIds,
    required this.startedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['note_id'] = Variable<String>(noteId);
    map['known_revision'] = Variable<int>(knownRevision);
    map['operation_ids'] = Variable<String>(operationIds);
    map['started_at'] = Variable<String>(startedAt);
    return map;
  }

  SyncSessionsCompanion toCompanion(bool nullToAbsent) {
    return SyncSessionsCompanion(
      noteId: Value(noteId),
      knownRevision: Value(knownRevision),
      operationIds: Value(operationIds),
      startedAt: Value(startedAt),
    );
  }

  factory SyncSessionData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncSessionData(
      noteId: serializer.fromJson<String>(json['noteId']),
      knownRevision: serializer.fromJson<int>(json['knownRevision']),
      operationIds: serializer.fromJson<String>(json['operationIds']),
      startedAt: serializer.fromJson<String>(json['startedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'noteId': serializer.toJson<String>(noteId),
      'knownRevision': serializer.toJson<int>(knownRevision),
      'operationIds': serializer.toJson<String>(operationIds),
      'startedAt': serializer.toJson<String>(startedAt),
    };
  }

  SyncSessionData copyWith({
    String? noteId,
    int? knownRevision,
    String? operationIds,
    String? startedAt,
  }) => SyncSessionData(
    noteId: noteId ?? this.noteId,
    knownRevision: knownRevision ?? this.knownRevision,
    operationIds: operationIds ?? this.operationIds,
    startedAt: startedAt ?? this.startedAt,
  );
  SyncSessionData copyWithCompanion(SyncSessionsCompanion data) {
    return SyncSessionData(
      noteId: data.noteId.present ? data.noteId.value : this.noteId,
      knownRevision: data.knownRevision.present
          ? data.knownRevision.value
          : this.knownRevision,
      operationIds: data.operationIds.present
          ? data.operationIds.value
          : this.operationIds,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncSessionData(')
          ..write('noteId: $noteId, ')
          ..write('knownRevision: $knownRevision, ')
          ..write('operationIds: $operationIds, ')
          ..write('startedAt: $startedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(noteId, knownRevision, operationIds, startedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncSessionData &&
          other.noteId == this.noteId &&
          other.knownRevision == this.knownRevision &&
          other.operationIds == this.operationIds &&
          other.startedAt == this.startedAt);
}

class SyncSessionsCompanion extends UpdateCompanion<SyncSessionData> {
  final Value<String> noteId;
  final Value<int> knownRevision;
  final Value<String> operationIds;
  final Value<String> startedAt;
  final Value<int> rowid;
  const SyncSessionsCompanion({
    this.noteId = const Value.absent(),
    this.knownRevision = const Value.absent(),
    this.operationIds = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncSessionsCompanion.insert({
    required String noteId,
    required int knownRevision,
    required String operationIds,
    required String startedAt,
    this.rowid = const Value.absent(),
  }) : noteId = Value(noteId),
       knownRevision = Value(knownRevision),
       operationIds = Value(operationIds),
       startedAt = Value(startedAt);
  static Insertable<SyncSessionData> custom({
    Expression<String>? noteId,
    Expression<int>? knownRevision,
    Expression<String>? operationIds,
    Expression<String>? startedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (noteId != null) 'note_id': noteId,
      if (knownRevision != null) 'known_revision': knownRevision,
      if (operationIds != null) 'operation_ids': operationIds,
      if (startedAt != null) 'started_at': startedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncSessionsCompanion copyWith({
    Value<String>? noteId,
    Value<int>? knownRevision,
    Value<String>? operationIds,
    Value<String>? startedAt,
    Value<int>? rowid,
  }) {
    return SyncSessionsCompanion(
      noteId: noteId ?? this.noteId,
      knownRevision: knownRevision ?? this.knownRevision,
      operationIds: operationIds ?? this.operationIds,
      startedAt: startedAt ?? this.startedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (noteId.present) {
      map['note_id'] = Variable<String>(noteId.value);
    }
    if (knownRevision.present) {
      map['known_revision'] = Variable<int>(knownRevision.value);
    }
    if (operationIds.present) {
      map['operation_ids'] = Variable<String>(operationIds.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<String>(startedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncSessionsCompanion(')
          ..write('noteId: $noteId, ')
          ..write('knownRevision: $knownRevision, ')
          ..write('operationIds: $operationIds, ')
          ..write('startedAt: $startedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $NotesTable notes = $NotesTable(this);
  late final $TasksTable tasks = $TasksTable(this);
  late final $LocalTaskCompletionsTable localTaskCompletions =
      $LocalTaskCompletionsTable(this);
  late final $NoteLinksTable noteLinks = $NoteLinksTable(this);
  late final $AttachmentsTable attachments = $AttachmentsTable(this);
  late final $UserNotePreferencesTable userNotePreferences =
      $UserNotePreferencesTable(this);
  late final $LocalYjsStatesTable localYjsStates = $LocalYjsStatesTable(this);
  late final $LocalNoteDocumentsTable localNoteDocuments =
      $LocalNoteDocumentsTable(this);
  late final $PendingNoteOperationsTable pendingNoteOperations =
      $PendingNoteOperationsTable(this);
  late final $NoteSyncErrorsTable noteSyncErrors = $NoteSyncErrorsTable(this);
  late final $SyncSessionsTable syncSessions = $SyncSessionsTable(this);
  late final NotesDao notesDao = NotesDao(this as AppDatabase);
  late final TasksDao tasksDao = TasksDao(this as AppDatabase);
  late final TaskCompletionsDao taskCompletionsDao = TaskCompletionsDao(
    this as AppDatabase,
  );
  late final NoteLinksDao noteLinksDao = NoteLinksDao(this as AppDatabase);
  late final AttachmentsDao attachmentsDao = AttachmentsDao(
    this as AppDatabase,
  );
  late final UserNotePreferencesDao userNotePreferencesDao =
      UserNotePreferencesDao(this as AppDatabase);
  late final NoteOperationsDao noteOperationsDao = NoteOperationsDao(
    this as AppDatabase,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    notes,
    tasks,
    localTaskCompletions,
    noteLinks,
    attachments,
    userNotePreferences,
    localYjsStates,
    localNoteDocuments,
    pendingNoteOperations,
    noteSyncErrors,
    syncSessions,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'notes',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('local_yjs_states', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$NotesTableCreateCompanionBuilder =
    NotesCompanion Function({
      required String id,
      required String userId,
      Value<String?> contextId,
      required String content,
      Value<String?> excerpt,
      Value<String?> embeddingStatus,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<bool> isDirty,
      Value<bool> hasRemoteCopy,
      Value<bool> collapseImages,
      Value<String?> permission,
      Value<String?> sharedByEmail,
      Value<String?> sharedByName,
      Value<int> rowid,
    });
typedef $$NotesTableUpdateCompanionBuilder =
    NotesCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String?> contextId,
      Value<String> content,
      Value<String?> excerpt,
      Value<String?> embeddingStatus,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<bool> isDirty,
      Value<bool> hasRemoteCopy,
      Value<bool> collapseImages,
      Value<String?> permission,
      Value<String?> sharedByEmail,
      Value<String?> sharedByName,
      Value<int> rowid,
    });

final class $$NotesTableReferences
    extends BaseReferences<_$AppDatabase, $NotesTable, NoteData> {
  $$NotesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$LocalYjsStatesTable, List<LocalYjsState>>
  _localYjsStatesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.localYjsStates,
    aliasName: 'notes__id__local_yjs_states__note_id',
  );

  $$LocalYjsStatesTableProcessedTableManager get localYjsStatesRefs {
    final manager = $$LocalYjsStatesTableTableManager(
      $_db,
      $_db.localYjsStates,
    ).filter((f) => f.noteId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_localYjsStatesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$NotesTableFilterComposer extends Composer<_$AppDatabase, $NotesTable> {
  $$NotesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contextId => $composableBuilder(
    column: $table.contextId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get excerpt => $composableBuilder(
    column: $table.excerpt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get embeddingStatus => $composableBuilder(
    column: $table.embeddingStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDirty => $composableBuilder(
    column: $table.isDirty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get hasRemoteCopy => $composableBuilder(
    column: $table.hasRemoteCopy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get collapseImages => $composableBuilder(
    column: $table.collapseImages,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get permission => $composableBuilder(
    column: $table.permission,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sharedByEmail => $composableBuilder(
    column: $table.sharedByEmail,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sharedByName => $composableBuilder(
    column: $table.sharedByName,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> localYjsStatesRefs(
    Expression<bool> Function($$LocalYjsStatesTableFilterComposer f) f,
  ) {
    final $$LocalYjsStatesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.localYjsStates,
      getReferencedColumn: (t) => t.noteId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalYjsStatesTableFilterComposer(
            $db: $db,
            $table: $db.localYjsStates,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$NotesTableOrderingComposer
    extends Composer<_$AppDatabase, $NotesTable> {
  $$NotesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contextId => $composableBuilder(
    column: $table.contextId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get excerpt => $composableBuilder(
    column: $table.excerpt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get embeddingStatus => $composableBuilder(
    column: $table.embeddingStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDirty => $composableBuilder(
    column: $table.isDirty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get hasRemoteCopy => $composableBuilder(
    column: $table.hasRemoteCopy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get collapseImages => $composableBuilder(
    column: $table.collapseImages,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get permission => $composableBuilder(
    column: $table.permission,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sharedByEmail => $composableBuilder(
    column: $table.sharedByEmail,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sharedByName => $composableBuilder(
    column: $table.sharedByName,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NotesTableAnnotationComposer
    extends Composer<_$AppDatabase, $NotesTable> {
  $$NotesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get contextId =>
      $composableBuilder(column: $table.contextId, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get excerpt =>
      $composableBuilder(column: $table.excerpt, builder: (column) => column);

  GeneratedColumn<String> get embeddingStatus => $composableBuilder(
    column: $table.embeddingStatus,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<bool> get isDirty =>
      $composableBuilder(column: $table.isDirty, builder: (column) => column);

  GeneratedColumn<bool> get hasRemoteCopy => $composableBuilder(
    column: $table.hasRemoteCopy,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get collapseImages => $composableBuilder(
    column: $table.collapseImages,
    builder: (column) => column,
  );

  GeneratedColumn<String> get permission => $composableBuilder(
    column: $table.permission,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sharedByEmail => $composableBuilder(
    column: $table.sharedByEmail,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sharedByName => $composableBuilder(
    column: $table.sharedByName,
    builder: (column) => column,
  );

  Expression<T> localYjsStatesRefs<T extends Object>(
    Expression<T> Function($$LocalYjsStatesTableAnnotationComposer a) f,
  ) {
    final $$LocalYjsStatesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.localYjsStates,
      getReferencedColumn: (t) => t.noteId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalYjsStatesTableAnnotationComposer(
            $db: $db,
            $table: $db.localYjsStates,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$NotesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $NotesTable,
          NoteData,
          $$NotesTableFilterComposer,
          $$NotesTableOrderingComposer,
          $$NotesTableAnnotationComposer,
          $$NotesTableCreateCompanionBuilder,
          $$NotesTableUpdateCompanionBuilder,
          (NoteData, $$NotesTableReferences),
          NoteData,
          PrefetchHooks Function({bool localYjsStatesRefs})
        > {
  $$NotesTableTableManager(_$AppDatabase db, $NotesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NotesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NotesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NotesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String?> contextId = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<String?> excerpt = const Value.absent(),
                Value<String?> embeddingStatus = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<bool> isDirty = const Value.absent(),
                Value<bool> hasRemoteCopy = const Value.absent(),
                Value<bool> collapseImages = const Value.absent(),
                Value<String?> permission = const Value.absent(),
                Value<String?> sharedByEmail = const Value.absent(),
                Value<String?> sharedByName = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NotesCompanion(
                id: id,
                userId: userId,
                contextId: contextId,
                content: content,
                excerpt: excerpt,
                embeddingStatus: embeddingStatus,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                isDirty: isDirty,
                hasRemoteCopy: hasRemoteCopy,
                collapseImages: collapseImages,
                permission: permission,
                sharedByEmail: sharedByEmail,
                sharedByName: sharedByName,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                Value<String?> contextId = const Value.absent(),
                required String content,
                Value<String?> excerpt = const Value.absent(),
                Value<String?> embeddingStatus = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<bool> isDirty = const Value.absent(),
                Value<bool> hasRemoteCopy = const Value.absent(),
                Value<bool> collapseImages = const Value.absent(),
                Value<String?> permission = const Value.absent(),
                Value<String?> sharedByEmail = const Value.absent(),
                Value<String?> sharedByName = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NotesCompanion.insert(
                id: id,
                userId: userId,
                contextId: contextId,
                content: content,
                excerpt: excerpt,
                embeddingStatus: embeddingStatus,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                isDirty: isDirty,
                hasRemoteCopy: hasRemoteCopy,
                collapseImages: collapseImages,
                permission: permission,
                sharedByEmail: sharedByEmail,
                sharedByName: sharedByName,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$NotesTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({localYjsStatesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (localYjsStatesRefs) db.localYjsStates,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (localYjsStatesRefs)
                    await $_getPrefetchedData<
                      NoteData,
                      $NotesTable,
                      LocalYjsState
                    >(
                      currentTable: table,
                      referencedTable: $$NotesTableReferences
                          ._localYjsStatesRefsTable(db),
                      managerFromTypedResult: (p0) => $$NotesTableReferences(
                        db,
                        table,
                        p0,
                      ).localYjsStatesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.noteId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$NotesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $NotesTable,
      NoteData,
      $$NotesTableFilterComposer,
      $$NotesTableOrderingComposer,
      $$NotesTableAnnotationComposer,
      $$NotesTableCreateCompanionBuilder,
      $$NotesTableUpdateCompanionBuilder,
      (NoteData, $$NotesTableReferences),
      NoteData,
      PrefetchHooks Function({bool localYjsStatesRefs})
    >;
typedef $$TasksTableCreateCompanionBuilder =
    TasksCompanion Function({
      required String id,
      required String userId,
      required String noteId,
      required String title,
      required String status,
      Value<String> position,
      Value<TaskRecurrence?> recurrence,
      Value<DateTime?> dueDate,
      Value<bool> hasTime,
      Value<String?> reminder,
      Value<DateTime?> completedAt,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$TasksTableUpdateCompanionBuilder =
    TasksCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String> noteId,
      Value<String> title,
      Value<String> status,
      Value<String> position,
      Value<TaskRecurrence?> recurrence,
      Value<DateTime?> dueDate,
      Value<bool> hasTime,
      Value<String?> reminder,
      Value<DateTime?> completedAt,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

class $$TasksTableFilterComposer extends Composer<_$AppDatabase, $TasksTable> {
  $$TasksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<TaskRecurrence?, TaskRecurrence, String>
  get recurrence => $composableBuilder(
    column: $table.recurrence,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<DateTime> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get hasTime => $composableBuilder(
    column: $table.hasTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reminder => $composableBuilder(
    column: $table.reminder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TasksTableOrderingComposer
    extends Composer<_$AppDatabase, $TasksTable> {
  $$TasksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recurrence => $composableBuilder(
    column: $table.recurrence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get hasTime => $composableBuilder(
    column: $table.hasTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reminder => $composableBuilder(
    column: $table.reminder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TasksTableAnnotationComposer
    extends Composer<_$AppDatabase, $TasksTable> {
  $$TasksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get noteId =>
      $composableBuilder(column: $table.noteId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumnWithTypeConverter<TaskRecurrence?, String> get recurrence =>
      $composableBuilder(
        column: $table.recurrence,
        builder: (column) => column,
      );

  GeneratedColumn<DateTime> get dueDate =>
      $composableBuilder(column: $table.dueDate, builder: (column) => column);

  GeneratedColumn<bool> get hasTime =>
      $composableBuilder(column: $table.hasTime, builder: (column) => column);

  GeneratedColumn<String> get reminder =>
      $composableBuilder(column: $table.reminder, builder: (column) => column);

  GeneratedColumn<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$TasksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TasksTable,
          TaskData,
          $$TasksTableFilterComposer,
          $$TasksTableOrderingComposer,
          $$TasksTableAnnotationComposer,
          $$TasksTableCreateCompanionBuilder,
          $$TasksTableUpdateCompanionBuilder,
          (TaskData, BaseReferences<_$AppDatabase, $TasksTable, TaskData>),
          TaskData,
          PrefetchHooks Function()
        > {
  $$TasksTableTableManager(_$AppDatabase db, $TasksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TasksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TasksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TasksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> noteId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> position = const Value.absent(),
                Value<TaskRecurrence?> recurrence = const Value.absent(),
                Value<DateTime?> dueDate = const Value.absent(),
                Value<bool> hasTime = const Value.absent(),
                Value<String?> reminder = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TasksCompanion(
                id: id,
                userId: userId,
                noteId: noteId,
                title: title,
                status: status,
                position: position,
                recurrence: recurrence,
                dueDate: dueDate,
                hasTime: hasTime,
                reminder: reminder,
                completedAt: completedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                required String noteId,
                required String title,
                required String status,
                Value<String> position = const Value.absent(),
                Value<TaskRecurrence?> recurrence = const Value.absent(),
                Value<DateTime?> dueDate = const Value.absent(),
                Value<bool> hasTime = const Value.absent(),
                Value<String?> reminder = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TasksCompanion.insert(
                id: id,
                userId: userId,
                noteId: noteId,
                title: title,
                status: status,
                position: position,
                recurrence: recurrence,
                dueDate: dueDate,
                hasTime: hasTime,
                reminder: reminder,
                completedAt: completedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TasksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TasksTable,
      TaskData,
      $$TasksTableFilterComposer,
      $$TasksTableOrderingComposer,
      $$TasksTableAnnotationComposer,
      $$TasksTableCreateCompanionBuilder,
      $$TasksTableUpdateCompanionBuilder,
      (TaskData, BaseReferences<_$AppDatabase, $TasksTable, TaskData>),
      TaskData,
      PrefetchHooks Function()
    >;
typedef $$LocalTaskCompletionsTableCreateCompanionBuilder =
    LocalTaskCompletionsCompanion Function({
      required String id,
      required String taskId,
      required String userId,
      required DateTime completedAt,
      required DateTime scheduledAt,
      Value<int> rowid,
    });
typedef $$LocalTaskCompletionsTableUpdateCompanionBuilder =
    LocalTaskCompletionsCompanion Function({
      Value<String> id,
      Value<String> taskId,
      Value<String> userId,
      Value<DateTime> completedAt,
      Value<DateTime> scheduledAt,
      Value<int> rowid,
    });

class $$LocalTaskCompletionsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalTaskCompletionsTable> {
  $$LocalTaskCompletionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get taskId => $composableBuilder(
    column: $table.taskId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get scheduledAt => $composableBuilder(
    column: $table.scheduledAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalTaskCompletionsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalTaskCompletionsTable> {
  $$LocalTaskCompletionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get taskId => $composableBuilder(
    column: $table.taskId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get scheduledAt => $composableBuilder(
    column: $table.scheduledAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalTaskCompletionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalTaskCompletionsTable> {
  $$LocalTaskCompletionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get taskId =>
      $composableBuilder(column: $table.taskId, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get scheduledAt => $composableBuilder(
    column: $table.scheduledAt,
    builder: (column) => column,
  );
}

class $$LocalTaskCompletionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalTaskCompletionsTable,
          LocalTaskCompletionData,
          $$LocalTaskCompletionsTableFilterComposer,
          $$LocalTaskCompletionsTableOrderingComposer,
          $$LocalTaskCompletionsTableAnnotationComposer,
          $$LocalTaskCompletionsTableCreateCompanionBuilder,
          $$LocalTaskCompletionsTableUpdateCompanionBuilder,
          (
            LocalTaskCompletionData,
            BaseReferences<
              _$AppDatabase,
              $LocalTaskCompletionsTable,
              LocalTaskCompletionData
            >,
          ),
          LocalTaskCompletionData,
          PrefetchHooks Function()
        > {
  $$LocalTaskCompletionsTableTableManager(
    _$AppDatabase db,
    $LocalTaskCompletionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalTaskCompletionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalTaskCompletionsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$LocalTaskCompletionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> taskId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<DateTime> completedAt = const Value.absent(),
                Value<DateTime> scheduledAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalTaskCompletionsCompanion(
                id: id,
                taskId: taskId,
                userId: userId,
                completedAt: completedAt,
                scheduledAt: scheduledAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String taskId,
                required String userId,
                required DateTime completedAt,
                required DateTime scheduledAt,
                Value<int> rowid = const Value.absent(),
              }) => LocalTaskCompletionsCompanion.insert(
                id: id,
                taskId: taskId,
                userId: userId,
                completedAt: completedAt,
                scheduledAt: scheduledAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalTaskCompletionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalTaskCompletionsTable,
      LocalTaskCompletionData,
      $$LocalTaskCompletionsTableFilterComposer,
      $$LocalTaskCompletionsTableOrderingComposer,
      $$LocalTaskCompletionsTableAnnotationComposer,
      $$LocalTaskCompletionsTableCreateCompanionBuilder,
      $$LocalTaskCompletionsTableUpdateCompanionBuilder,
      (
        LocalTaskCompletionData,
        BaseReferences<
          _$AppDatabase,
          $LocalTaskCompletionsTable,
          LocalTaskCompletionData
        >,
      ),
      LocalTaskCompletionData,
      PrefetchHooks Function()
    >;
typedef $$NoteLinksTableCreateCompanionBuilder =
    NoteLinksCompanion Function({
      required String id,
      required String sourceId,
      required String targetId,
      Value<String> relation,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<bool> isDirty,
      Value<int> rowid,
    });
typedef $$NoteLinksTableUpdateCompanionBuilder =
    NoteLinksCompanion Function({
      Value<String> id,
      Value<String> sourceId,
      Value<String> targetId,
      Value<String> relation,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<bool> isDirty,
      Value<int> rowid,
    });

final class $$NoteLinksTableReferences
    extends BaseReferences<_$AppDatabase, $NoteLinksTable, NoteLinkData> {
  $$NoteLinksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $NotesTable _sourceIdTable(_$AppDatabase db) =>
      db.notes.createAlias('note_links__source_id__notes__id');

  $$NotesTableProcessedTableManager get sourceId {
    final $_column = $_itemColumn<String>('source_id')!;

    final manager = $$NotesTableTableManager(
      $_db,
      $_db.notes,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sourceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $NotesTable _targetIdTable(_$AppDatabase db) =>
      db.notes.createAlias('note_links__target_id__notes__id');

  $$NotesTableProcessedTableManager get targetId {
    final $_column = $_itemColumn<String>('target_id')!;

    final manager = $$NotesTableTableManager(
      $_db,
      $_db.notes,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_targetIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$NoteLinksTableFilterComposer
    extends Composer<_$AppDatabase, $NoteLinksTable> {
  $$NoteLinksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get relation => $composableBuilder(
    column: $table.relation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDirty => $composableBuilder(
    column: $table.isDirty,
    builder: (column) => ColumnFilters(column),
  );

  $$NotesTableFilterComposer get sourceId {
    final $$NotesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceId,
      referencedTable: $db.notes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NotesTableFilterComposer(
            $db: $db,
            $table: $db.notes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$NotesTableFilterComposer get targetId {
    final $$NotesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.targetId,
      referencedTable: $db.notes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NotesTableFilterComposer(
            $db: $db,
            $table: $db.notes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$NoteLinksTableOrderingComposer
    extends Composer<_$AppDatabase, $NoteLinksTable> {
  $$NoteLinksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get relation => $composableBuilder(
    column: $table.relation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDirty => $composableBuilder(
    column: $table.isDirty,
    builder: (column) => ColumnOrderings(column),
  );

  $$NotesTableOrderingComposer get sourceId {
    final $$NotesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceId,
      referencedTable: $db.notes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NotesTableOrderingComposer(
            $db: $db,
            $table: $db.notes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$NotesTableOrderingComposer get targetId {
    final $$NotesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.targetId,
      referencedTable: $db.notes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NotesTableOrderingComposer(
            $db: $db,
            $table: $db.notes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$NoteLinksTableAnnotationComposer
    extends Composer<_$AppDatabase, $NoteLinksTable> {
  $$NoteLinksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get relation =>
      $composableBuilder(column: $table.relation, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get isDirty =>
      $composableBuilder(column: $table.isDirty, builder: (column) => column);

  $$NotesTableAnnotationComposer get sourceId {
    final $$NotesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceId,
      referencedTable: $db.notes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NotesTableAnnotationComposer(
            $db: $db,
            $table: $db.notes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$NotesTableAnnotationComposer get targetId {
    final $$NotesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.targetId,
      referencedTable: $db.notes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NotesTableAnnotationComposer(
            $db: $db,
            $table: $db.notes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$NoteLinksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $NoteLinksTable,
          NoteLinkData,
          $$NoteLinksTableFilterComposer,
          $$NoteLinksTableOrderingComposer,
          $$NoteLinksTableAnnotationComposer,
          $$NoteLinksTableCreateCompanionBuilder,
          $$NoteLinksTableUpdateCompanionBuilder,
          (NoteLinkData, $$NoteLinksTableReferences),
          NoteLinkData,
          PrefetchHooks Function({bool sourceId, bool targetId})
        > {
  $$NoteLinksTableTableManager(_$AppDatabase db, $NoteLinksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NoteLinksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NoteLinksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NoteLinksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> sourceId = const Value.absent(),
                Value<String> targetId = const Value.absent(),
                Value<String> relation = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> isDirty = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NoteLinksCompanion(
                id: id,
                sourceId: sourceId,
                targetId: targetId,
                relation: relation,
                createdAt: createdAt,
                updatedAt: updatedAt,
                isDirty: isDirty,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String sourceId,
                required String targetId,
                Value<String> relation = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> isDirty = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NoteLinksCompanion.insert(
                id: id,
                sourceId: sourceId,
                targetId: targetId,
                relation: relation,
                createdAt: createdAt,
                updatedAt: updatedAt,
                isDirty: isDirty,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$NoteLinksTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sourceId = false, targetId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (sourceId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.sourceId,
                                referencedTable: $$NoteLinksTableReferences
                                    ._sourceIdTable(db),
                                referencedColumn: $$NoteLinksTableReferences
                                    ._sourceIdTable(db)
                                    .id,
                              )
                              as T;
                    }
                    if (targetId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.targetId,
                                referencedTable: $$NoteLinksTableReferences
                                    ._targetIdTable(db),
                                referencedColumn: $$NoteLinksTableReferences
                                    ._targetIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$NoteLinksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $NoteLinksTable,
      NoteLinkData,
      $$NoteLinksTableFilterComposer,
      $$NoteLinksTableOrderingComposer,
      $$NoteLinksTableAnnotationComposer,
      $$NoteLinksTableCreateCompanionBuilder,
      $$NoteLinksTableUpdateCompanionBuilder,
      (NoteLinkData, $$NoteLinksTableReferences),
      NoteLinkData,
      PrefetchHooks Function({bool sourceId, bool targetId})
    >;
typedef $$AttachmentsTableCreateCompanionBuilder =
    AttachmentsCompanion Function({
      required String id,
      required String noteId,
      Value<String?> localPath,
      Value<String?> remoteUrl,
      required String fileName,
      required String mimeType,
      required int fileSize,
      Value<String> status,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$AttachmentsTableUpdateCompanionBuilder =
    AttachmentsCompanion Function({
      Value<String> id,
      Value<String> noteId,
      Value<String?> localPath,
      Value<String?> remoteUrl,
      Value<String> fileName,
      Value<String> mimeType,
      Value<int> fileSize,
      Value<String> status,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$AttachmentsTableFilterComposer
    extends Composer<_$AppDatabase, $AttachmentsTable> {
  $$AttachmentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remoteUrl => $composableBuilder(
    column: $table.remoteUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fileSize => $composableBuilder(
    column: $table.fileSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AttachmentsTableOrderingComposer
    extends Composer<_$AppDatabase, $AttachmentsTable> {
  $$AttachmentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remoteUrl => $composableBuilder(
    column: $table.remoteUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fileSize => $composableBuilder(
    column: $table.fileSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AttachmentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AttachmentsTable> {
  $$AttachmentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get noteId =>
      $composableBuilder(column: $table.noteId, builder: (column) => column);

  GeneratedColumn<String> get localPath =>
      $composableBuilder(column: $table.localPath, builder: (column) => column);

  GeneratedColumn<String> get remoteUrl =>
      $composableBuilder(column: $table.remoteUrl, builder: (column) => column);

  GeneratedColumn<String> get fileName =>
      $composableBuilder(column: $table.fileName, builder: (column) => column);

  GeneratedColumn<String> get mimeType =>
      $composableBuilder(column: $table.mimeType, builder: (column) => column);

  GeneratedColumn<int> get fileSize =>
      $composableBuilder(column: $table.fileSize, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$AttachmentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AttachmentsTable,
          AttachmentData,
          $$AttachmentsTableFilterComposer,
          $$AttachmentsTableOrderingComposer,
          $$AttachmentsTableAnnotationComposer,
          $$AttachmentsTableCreateCompanionBuilder,
          $$AttachmentsTableUpdateCompanionBuilder,
          (
            AttachmentData,
            BaseReferences<_$AppDatabase, $AttachmentsTable, AttachmentData>,
          ),
          AttachmentData,
          PrefetchHooks Function()
        > {
  $$AttachmentsTableTableManager(_$AppDatabase db, $AttachmentsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AttachmentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AttachmentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AttachmentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> noteId = const Value.absent(),
                Value<String?> localPath = const Value.absent(),
                Value<String?> remoteUrl = const Value.absent(),
                Value<String> fileName = const Value.absent(),
                Value<String> mimeType = const Value.absent(),
                Value<int> fileSize = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AttachmentsCompanion(
                id: id,
                noteId: noteId,
                localPath: localPath,
                remoteUrl: remoteUrl,
                fileName: fileName,
                mimeType: mimeType,
                fileSize: fileSize,
                status: status,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String noteId,
                Value<String?> localPath = const Value.absent(),
                Value<String?> remoteUrl = const Value.absent(),
                required String fileName,
                required String mimeType,
                required int fileSize,
                Value<String> status = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => AttachmentsCompanion.insert(
                id: id,
                noteId: noteId,
                localPath: localPath,
                remoteUrl: remoteUrl,
                fileName: fileName,
                mimeType: mimeType,
                fileSize: fileSize,
                status: status,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AttachmentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AttachmentsTable,
      AttachmentData,
      $$AttachmentsTableFilterComposer,
      $$AttachmentsTableOrderingComposer,
      $$AttachmentsTableAnnotationComposer,
      $$AttachmentsTableCreateCompanionBuilder,
      $$AttachmentsTableUpdateCompanionBuilder,
      (
        AttachmentData,
        BaseReferences<_$AppDatabase, $AttachmentsTable, AttachmentData>,
      ),
      AttachmentData,
      PrefetchHooks Function()
    >;
typedef $$UserNotePreferencesTableCreateCompanionBuilder =
    UserNotePreferencesCompanion Function({
      required String userId,
      required String noteId,
      Value<bool> favorite,
      Value<bool> archived,
      Value<bool> hideCompleted,
      Value<String> filters,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<bool> isDirty,
      Value<int> rowid,
    });
typedef $$UserNotePreferencesTableUpdateCompanionBuilder =
    UserNotePreferencesCompanion Function({
      Value<String> userId,
      Value<String> noteId,
      Value<bool> favorite,
      Value<bool> archived,
      Value<bool> hideCompleted,
      Value<String> filters,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<bool> isDirty,
      Value<int> rowid,
    });

class $$UserNotePreferencesTableFilterComposer
    extends Composer<_$AppDatabase, $UserNotePreferencesTable> {
  $$UserNotePreferencesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get favorite => $composableBuilder(
    column: $table.favorite,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get hideCompleted => $composableBuilder(
    column: $table.hideCompleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filters => $composableBuilder(
    column: $table.filters,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDirty => $composableBuilder(
    column: $table.isDirty,
    builder: (column) => ColumnFilters(column),
  );
}

class $$UserNotePreferencesTableOrderingComposer
    extends Composer<_$AppDatabase, $UserNotePreferencesTable> {
  $$UserNotePreferencesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get favorite => $composableBuilder(
    column: $table.favorite,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get hideCompleted => $composableBuilder(
    column: $table.hideCompleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filters => $composableBuilder(
    column: $table.filters,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDirty => $composableBuilder(
    column: $table.isDirty,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$UserNotePreferencesTableAnnotationComposer
    extends Composer<_$AppDatabase, $UserNotePreferencesTable> {
  $$UserNotePreferencesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get noteId =>
      $composableBuilder(column: $table.noteId, builder: (column) => column);

  GeneratedColumn<bool> get favorite =>
      $composableBuilder(column: $table.favorite, builder: (column) => column);

  GeneratedColumn<bool> get archived =>
      $composableBuilder(column: $table.archived, builder: (column) => column);

  GeneratedColumn<bool> get hideCompleted => $composableBuilder(
    column: $table.hideCompleted,
    builder: (column) => column,
  );

  GeneratedColumn<String> get filters =>
      $composableBuilder(column: $table.filters, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get isDirty =>
      $composableBuilder(column: $table.isDirty, builder: (column) => column);
}

class $$UserNotePreferencesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $UserNotePreferencesTable,
          UserNotePreferenceData,
          $$UserNotePreferencesTableFilterComposer,
          $$UserNotePreferencesTableOrderingComposer,
          $$UserNotePreferencesTableAnnotationComposer,
          $$UserNotePreferencesTableCreateCompanionBuilder,
          $$UserNotePreferencesTableUpdateCompanionBuilder,
          (
            UserNotePreferenceData,
            BaseReferences<
              _$AppDatabase,
              $UserNotePreferencesTable,
              UserNotePreferenceData
            >,
          ),
          UserNotePreferenceData,
          PrefetchHooks Function()
        > {
  $$UserNotePreferencesTableTableManager(
    _$AppDatabase db,
    $UserNotePreferencesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UserNotePreferencesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UserNotePreferencesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$UserNotePreferencesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<String> noteId = const Value.absent(),
                Value<bool> favorite = const Value.absent(),
                Value<bool> archived = const Value.absent(),
                Value<bool> hideCompleted = const Value.absent(),
                Value<String> filters = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> isDirty = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UserNotePreferencesCompanion(
                userId: userId,
                noteId: noteId,
                favorite: favorite,
                archived: archived,
                hideCompleted: hideCompleted,
                filters: filters,
                createdAt: createdAt,
                updatedAt: updatedAt,
                isDirty: isDirty,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                required String noteId,
                Value<bool> favorite = const Value.absent(),
                Value<bool> archived = const Value.absent(),
                Value<bool> hideCompleted = const Value.absent(),
                Value<String> filters = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> isDirty = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UserNotePreferencesCompanion.insert(
                userId: userId,
                noteId: noteId,
                favorite: favorite,
                archived: archived,
                hideCompleted: hideCompleted,
                filters: filters,
                createdAt: createdAt,
                updatedAt: updatedAt,
                isDirty: isDirty,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$UserNotePreferencesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $UserNotePreferencesTable,
      UserNotePreferenceData,
      $$UserNotePreferencesTableFilterComposer,
      $$UserNotePreferencesTableOrderingComposer,
      $$UserNotePreferencesTableAnnotationComposer,
      $$UserNotePreferencesTableCreateCompanionBuilder,
      $$UserNotePreferencesTableUpdateCompanionBuilder,
      (
        UserNotePreferenceData,
        BaseReferences<
          _$AppDatabase,
          $UserNotePreferencesTable,
          UserNotePreferenceData
        >,
      ),
      UserNotePreferenceData,
      PrefetchHooks Function()
    >;
typedef $$LocalYjsStatesTableCreateCompanionBuilder =
    LocalYjsStatesCompanion Function({
      required String noteId,
      required Uint8List state,
      Value<Uint8List?> syncedStateVector,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$LocalYjsStatesTableUpdateCompanionBuilder =
    LocalYjsStatesCompanion Function({
      Value<String> noteId,
      Value<Uint8List> state,
      Value<Uint8List?> syncedStateVector,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$LocalYjsStatesTableReferences
    extends BaseReferences<_$AppDatabase, $LocalYjsStatesTable, LocalYjsState> {
  $$LocalYjsStatesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $NotesTable _noteIdTable(_$AppDatabase db) =>
      db.notes.createAlias('local_yjs_states__note_id__notes__id');

  $$NotesTableProcessedTableManager get noteId {
    final $_column = $_itemColumn<String>('note_id')!;

    final manager = $$NotesTableTableManager(
      $_db,
      $_db.notes,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_noteIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$LocalYjsStatesTableFilterComposer
    extends Composer<_$AppDatabase, $LocalYjsStatesTable> {
  $$LocalYjsStatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<Uint8List> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get syncedStateVector => $composableBuilder(
    column: $table.syncedStateVector,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$NotesTableFilterComposer get noteId {
    final $$NotesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.noteId,
      referencedTable: $db.notes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NotesTableFilterComposer(
            $db: $db,
            $table: $db.notes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LocalYjsStatesTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalYjsStatesTable> {
  $$LocalYjsStatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<Uint8List> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get syncedStateVector => $composableBuilder(
    column: $table.syncedStateVector,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$NotesTableOrderingComposer get noteId {
    final $$NotesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.noteId,
      referencedTable: $db.notes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NotesTableOrderingComposer(
            $db: $db,
            $table: $db.notes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LocalYjsStatesTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalYjsStatesTable> {
  $$LocalYjsStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<Uint8List> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<Uint8List> get syncedStateVector => $composableBuilder(
    column: $table.syncedStateVector,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$NotesTableAnnotationComposer get noteId {
    final $$NotesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.noteId,
      referencedTable: $db.notes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NotesTableAnnotationComposer(
            $db: $db,
            $table: $db.notes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LocalYjsStatesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalYjsStatesTable,
          LocalYjsState,
          $$LocalYjsStatesTableFilterComposer,
          $$LocalYjsStatesTableOrderingComposer,
          $$LocalYjsStatesTableAnnotationComposer,
          $$LocalYjsStatesTableCreateCompanionBuilder,
          $$LocalYjsStatesTableUpdateCompanionBuilder,
          (LocalYjsState, $$LocalYjsStatesTableReferences),
          LocalYjsState,
          PrefetchHooks Function({bool noteId})
        > {
  $$LocalYjsStatesTableTableManager(
    _$AppDatabase db,
    $LocalYjsStatesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalYjsStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalYjsStatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalYjsStatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> noteId = const Value.absent(),
                Value<Uint8List> state = const Value.absent(),
                Value<Uint8List?> syncedStateVector = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalYjsStatesCompanion(
                noteId: noteId,
                state: state,
                syncedStateVector: syncedStateVector,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String noteId,
                required Uint8List state,
                Value<Uint8List?> syncedStateVector = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalYjsStatesCompanion.insert(
                noteId: noteId,
                state: state,
                syncedStateVector: syncedStateVector,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$LocalYjsStatesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({noteId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (noteId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.noteId,
                                referencedTable: $$LocalYjsStatesTableReferences
                                    ._noteIdTable(db),
                                referencedColumn:
                                    $$LocalYjsStatesTableReferences
                                        ._noteIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$LocalYjsStatesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalYjsStatesTable,
      LocalYjsState,
      $$LocalYjsStatesTableFilterComposer,
      $$LocalYjsStatesTableOrderingComposer,
      $$LocalYjsStatesTableAnnotationComposer,
      $$LocalYjsStatesTableCreateCompanionBuilder,
      $$LocalYjsStatesTableUpdateCompanionBuilder,
      (LocalYjsState, $$LocalYjsStatesTableReferences),
      LocalYjsState,
      PrefetchHooks Function({bool noteId})
    >;
typedef $$LocalNoteDocumentsTableCreateCompanionBuilder =
    LocalNoteDocumentsCompanion Function({
      required String noteId,
      required int revision,
      required String documentJson,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$LocalNoteDocumentsTableUpdateCompanionBuilder =
    LocalNoteDocumentsCompanion Function({
      Value<String> noteId,
      Value<int> revision,
      Value<String> documentJson,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$LocalNoteDocumentsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalNoteDocumentsTable> {
  $$LocalNoteDocumentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get documentJson => $composableBuilder(
    column: $table.documentJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalNoteDocumentsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalNoteDocumentsTable> {
  $$LocalNoteDocumentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get documentJson => $composableBuilder(
    column: $table.documentJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalNoteDocumentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalNoteDocumentsTable> {
  $$LocalNoteDocumentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get noteId =>
      $composableBuilder(column: $table.noteId, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<String> get documentJson => $composableBuilder(
    column: $table.documentJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$LocalNoteDocumentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalNoteDocumentsTable,
          LocalNoteDocumentData,
          $$LocalNoteDocumentsTableFilterComposer,
          $$LocalNoteDocumentsTableOrderingComposer,
          $$LocalNoteDocumentsTableAnnotationComposer,
          $$LocalNoteDocumentsTableCreateCompanionBuilder,
          $$LocalNoteDocumentsTableUpdateCompanionBuilder,
          (
            LocalNoteDocumentData,
            BaseReferences<
              _$AppDatabase,
              $LocalNoteDocumentsTable,
              LocalNoteDocumentData
            >,
          ),
          LocalNoteDocumentData,
          PrefetchHooks Function()
        > {
  $$LocalNoteDocumentsTableTableManager(
    _$AppDatabase db,
    $LocalNoteDocumentsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalNoteDocumentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalNoteDocumentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalNoteDocumentsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> noteId = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<String> documentJson = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalNoteDocumentsCompanion(
                noteId: noteId,
                revision: revision,
                documentJson: documentJson,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String noteId,
                required int revision,
                required String documentJson,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => LocalNoteDocumentsCompanion.insert(
                noteId: noteId,
                revision: revision,
                documentJson: documentJson,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalNoteDocumentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalNoteDocumentsTable,
      LocalNoteDocumentData,
      $$LocalNoteDocumentsTableFilterComposer,
      $$LocalNoteDocumentsTableOrderingComposer,
      $$LocalNoteDocumentsTableAnnotationComposer,
      $$LocalNoteDocumentsTableCreateCompanionBuilder,
      $$LocalNoteDocumentsTableUpdateCompanionBuilder,
      (
        LocalNoteDocumentData,
        BaseReferences<
          _$AppDatabase,
          $LocalNoteDocumentsTable,
          LocalNoteDocumentData
        >,
      ),
      LocalNoteDocumentData,
      PrefetchHooks Function()
    >;
typedef $$PendingNoteOperationsTableCreateCompanionBuilder =
    PendingNoteOperationsCompanion Function({
      required String operationId,
      required String noteId,
      required int baseRevision,
      required int ordinal,
      required String kind,
      Value<String?> blockId,
      required String payloadJson,
      required DateTime createdAt,
      Value<DateTime?> lastAttemptAt,
      Value<int> attemptCount,
      Value<String> status,
      Value<int> rowid,
    });
typedef $$PendingNoteOperationsTableUpdateCompanionBuilder =
    PendingNoteOperationsCompanion Function({
      Value<String> operationId,
      Value<String> noteId,
      Value<int> baseRevision,
      Value<int> ordinal,
      Value<String> kind,
      Value<String?> blockId,
      Value<String> payloadJson,
      Value<DateTime> createdAt,
      Value<DateTime?> lastAttemptAt,
      Value<int> attemptCount,
      Value<String> status,
      Value<int> rowid,
    });

class $$PendingNoteOperationsTableFilterComposer
    extends Composer<_$AppDatabase, $PendingNoteOperationsTable> {
  $$PendingNoteOperationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get baseRevision => $composableBuilder(
    column: $table.baseRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get ordinal => $composableBuilder(
    column: $table.ordinal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get blockId => $composableBuilder(
    column: $table.blockId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastAttemptAt => $composableBuilder(
    column: $table.lastAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PendingNoteOperationsTableOrderingComposer
    extends Composer<_$AppDatabase, $PendingNoteOperationsTable> {
  $$PendingNoteOperationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get baseRevision => $composableBuilder(
    column: $table.baseRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get ordinal => $composableBuilder(
    column: $table.ordinal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get blockId => $composableBuilder(
    column: $table.blockId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastAttemptAt => $composableBuilder(
    column: $table.lastAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PendingNoteOperationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PendingNoteOperationsTable> {
  $$PendingNoteOperationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get noteId =>
      $composableBuilder(column: $table.noteId, builder: (column) => column);

  GeneratedColumn<int> get baseRevision => $composableBuilder(
    column: $table.baseRevision,
    builder: (column) => column,
  );

  GeneratedColumn<int> get ordinal =>
      $composableBuilder(column: $table.ordinal, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get blockId =>
      $composableBuilder(column: $table.blockId, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastAttemptAt => $composableBuilder(
    column: $table.lastAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);
}

class $$PendingNoteOperationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PendingNoteOperationsTable,
          PendingNoteOperationData,
          $$PendingNoteOperationsTableFilterComposer,
          $$PendingNoteOperationsTableOrderingComposer,
          $$PendingNoteOperationsTableAnnotationComposer,
          $$PendingNoteOperationsTableCreateCompanionBuilder,
          $$PendingNoteOperationsTableUpdateCompanionBuilder,
          (
            PendingNoteOperationData,
            BaseReferences<
              _$AppDatabase,
              $PendingNoteOperationsTable,
              PendingNoteOperationData
            >,
          ),
          PendingNoteOperationData,
          PrefetchHooks Function()
        > {
  $$PendingNoteOperationsTableTableManager(
    _$AppDatabase db,
    $PendingNoteOperationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PendingNoteOperationsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$PendingNoteOperationsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$PendingNoteOperationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> operationId = const Value.absent(),
                Value<String> noteId = const Value.absent(),
                Value<int> baseRevision = const Value.absent(),
                Value<int> ordinal = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String?> blockId = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> lastAttemptAt = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PendingNoteOperationsCompanion(
                operationId: operationId,
                noteId: noteId,
                baseRevision: baseRevision,
                ordinal: ordinal,
                kind: kind,
                blockId: blockId,
                payloadJson: payloadJson,
                createdAt: createdAt,
                lastAttemptAt: lastAttemptAt,
                attemptCount: attemptCount,
                status: status,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String operationId,
                required String noteId,
                required int baseRevision,
                required int ordinal,
                required String kind,
                Value<String?> blockId = const Value.absent(),
                required String payloadJson,
                required DateTime createdAt,
                Value<DateTime?> lastAttemptAt = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PendingNoteOperationsCompanion.insert(
                operationId: operationId,
                noteId: noteId,
                baseRevision: baseRevision,
                ordinal: ordinal,
                kind: kind,
                blockId: blockId,
                payloadJson: payloadJson,
                createdAt: createdAt,
                lastAttemptAt: lastAttemptAt,
                attemptCount: attemptCount,
                status: status,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PendingNoteOperationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PendingNoteOperationsTable,
      PendingNoteOperationData,
      $$PendingNoteOperationsTableFilterComposer,
      $$PendingNoteOperationsTableOrderingComposer,
      $$PendingNoteOperationsTableAnnotationComposer,
      $$PendingNoteOperationsTableCreateCompanionBuilder,
      $$PendingNoteOperationsTableUpdateCompanionBuilder,
      (
        PendingNoteOperationData,
        BaseReferences<
          _$AppDatabase,
          $PendingNoteOperationsTable,
          PendingNoteOperationData
        >,
      ),
      PendingNoteOperationData,
      PrefetchHooks Function()
    >;
typedef $$NoteSyncErrorsTableCreateCompanionBuilder =
    NoteSyncErrorsCompanion Function({
      required String operationId,
      required String noteId,
      required String errorCode,
      required String message,
      required String payloadJson,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$NoteSyncErrorsTableUpdateCompanionBuilder =
    NoteSyncErrorsCompanion Function({
      Value<String> operationId,
      Value<String> noteId,
      Value<String> errorCode,
      Value<String> message,
      Value<String> payloadJson,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$NoteSyncErrorsTableFilterComposer
    extends Composer<_$AppDatabase, $NoteSyncErrorsTable> {
  $$NoteSyncErrorsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get errorCode => $composableBuilder(
    column: $table.errorCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NoteSyncErrorsTableOrderingComposer
    extends Composer<_$AppDatabase, $NoteSyncErrorsTable> {
  $$NoteSyncErrorsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorCode => $composableBuilder(
    column: $table.errorCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NoteSyncErrorsTableAnnotationComposer
    extends Composer<_$AppDatabase, $NoteSyncErrorsTable> {
  $$NoteSyncErrorsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get noteId =>
      $composableBuilder(column: $table.noteId, builder: (column) => column);

  GeneratedColumn<String> get errorCode =>
      $composableBuilder(column: $table.errorCode, builder: (column) => column);

  GeneratedColumn<String> get message =>
      $composableBuilder(column: $table.message, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$NoteSyncErrorsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $NoteSyncErrorsTable,
          NoteSyncErrorData,
          $$NoteSyncErrorsTableFilterComposer,
          $$NoteSyncErrorsTableOrderingComposer,
          $$NoteSyncErrorsTableAnnotationComposer,
          $$NoteSyncErrorsTableCreateCompanionBuilder,
          $$NoteSyncErrorsTableUpdateCompanionBuilder,
          (
            NoteSyncErrorData,
            BaseReferences<
              _$AppDatabase,
              $NoteSyncErrorsTable,
              NoteSyncErrorData
            >,
          ),
          NoteSyncErrorData,
          PrefetchHooks Function()
        > {
  $$NoteSyncErrorsTableTableManager(
    _$AppDatabase db,
    $NoteSyncErrorsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NoteSyncErrorsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NoteSyncErrorsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NoteSyncErrorsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> operationId = const Value.absent(),
                Value<String> noteId = const Value.absent(),
                Value<String> errorCode = const Value.absent(),
                Value<String> message = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NoteSyncErrorsCompanion(
                operationId: operationId,
                noteId: noteId,
                errorCode: errorCode,
                message: message,
                payloadJson: payloadJson,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String operationId,
                required String noteId,
                required String errorCode,
                required String message,
                required String payloadJson,
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => NoteSyncErrorsCompanion.insert(
                operationId: operationId,
                noteId: noteId,
                errorCode: errorCode,
                message: message,
                payloadJson: payloadJson,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NoteSyncErrorsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $NoteSyncErrorsTable,
      NoteSyncErrorData,
      $$NoteSyncErrorsTableFilterComposer,
      $$NoteSyncErrorsTableOrderingComposer,
      $$NoteSyncErrorsTableAnnotationComposer,
      $$NoteSyncErrorsTableCreateCompanionBuilder,
      $$NoteSyncErrorsTableUpdateCompanionBuilder,
      (
        NoteSyncErrorData,
        BaseReferences<_$AppDatabase, $NoteSyncErrorsTable, NoteSyncErrorData>,
      ),
      NoteSyncErrorData,
      PrefetchHooks Function()
    >;
typedef $$SyncSessionsTableCreateCompanionBuilder =
    SyncSessionsCompanion Function({
      required String noteId,
      required int knownRevision,
      required String operationIds,
      required String startedAt,
      Value<int> rowid,
    });
typedef $$SyncSessionsTableUpdateCompanionBuilder =
    SyncSessionsCompanion Function({
      Value<String> noteId,
      Value<int> knownRevision,
      Value<String> operationIds,
      Value<String> startedAt,
      Value<int> rowid,
    });

class $$SyncSessionsTableFilterComposer
    extends Composer<_$AppDatabase, $SyncSessionsTable> {
  $$SyncSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get knownRevision => $composableBuilder(
    column: $table.knownRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get operationIds => $composableBuilder(
    column: $table.operationIds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncSessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncSessionsTable> {
  $$SyncSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get knownRevision => $composableBuilder(
    column: $table.knownRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operationIds => $composableBuilder(
    column: $table.operationIds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncSessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncSessionsTable> {
  $$SyncSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get noteId =>
      $composableBuilder(column: $table.noteId, builder: (column) => column);

  GeneratedColumn<int> get knownRevision => $composableBuilder(
    column: $table.knownRevision,
    builder: (column) => column,
  );

  GeneratedColumn<String> get operationIds => $composableBuilder(
    column: $table.operationIds,
    builder: (column) => column,
  );

  GeneratedColumn<String> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);
}

class $$SyncSessionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncSessionsTable,
          SyncSessionData,
          $$SyncSessionsTableFilterComposer,
          $$SyncSessionsTableOrderingComposer,
          $$SyncSessionsTableAnnotationComposer,
          $$SyncSessionsTableCreateCompanionBuilder,
          $$SyncSessionsTableUpdateCompanionBuilder,
          (
            SyncSessionData,
            BaseReferences<_$AppDatabase, $SyncSessionsTable, SyncSessionData>,
          ),
          SyncSessionData,
          PrefetchHooks Function()
        > {
  $$SyncSessionsTableTableManager(_$AppDatabase db, $SyncSessionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> noteId = const Value.absent(),
                Value<int> knownRevision = const Value.absent(),
                Value<String> operationIds = const Value.absent(),
                Value<String> startedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncSessionsCompanion(
                noteId: noteId,
                knownRevision: knownRevision,
                operationIds: operationIds,
                startedAt: startedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String noteId,
                required int knownRevision,
                required String operationIds,
                required String startedAt,
                Value<int> rowid = const Value.absent(),
              }) => SyncSessionsCompanion.insert(
                noteId: noteId,
                knownRevision: knownRevision,
                operationIds: operationIds,
                startedAt: startedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncSessionsTable,
      SyncSessionData,
      $$SyncSessionsTableFilterComposer,
      $$SyncSessionsTableOrderingComposer,
      $$SyncSessionsTableAnnotationComposer,
      $$SyncSessionsTableCreateCompanionBuilder,
      $$SyncSessionsTableUpdateCompanionBuilder,
      (
        SyncSessionData,
        BaseReferences<_$AppDatabase, $SyncSessionsTable, SyncSessionData>,
      ),
      SyncSessionData,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$NotesTableTableManager get notes =>
      $$NotesTableTableManager(_db, _db.notes);
  $$TasksTableTableManager get tasks =>
      $$TasksTableTableManager(_db, _db.tasks);
  $$LocalTaskCompletionsTableTableManager get localTaskCompletions =>
      $$LocalTaskCompletionsTableTableManager(_db, _db.localTaskCompletions);
  $$NoteLinksTableTableManager get noteLinks =>
      $$NoteLinksTableTableManager(_db, _db.noteLinks);
  $$AttachmentsTableTableManager get attachments =>
      $$AttachmentsTableTableManager(_db, _db.attachments);
  $$UserNotePreferencesTableTableManager get userNotePreferences =>
      $$UserNotePreferencesTableTableManager(_db, _db.userNotePreferences);
  $$LocalYjsStatesTableTableManager get localYjsStates =>
      $$LocalYjsStatesTableTableManager(_db, _db.localYjsStates);
  $$LocalNoteDocumentsTableTableManager get localNoteDocuments =>
      $$LocalNoteDocumentsTableTableManager(_db, _db.localNoteDocuments);
  $$PendingNoteOperationsTableTableManager get pendingNoteOperations =>
      $$PendingNoteOperationsTableTableManager(_db, _db.pendingNoteOperations);
  $$NoteSyncErrorsTableTableManager get noteSyncErrors =>
      $$NoteSyncErrorsTableTableManager(_db, _db.noteSyncErrors);
  $$SyncSessionsTableTableManager get syncSessions =>
      $$SyncSessionsTableTableManager(_db, _db.syncSessions);
}
