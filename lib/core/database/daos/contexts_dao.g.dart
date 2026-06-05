// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'contexts_dao.dart';

// ignore_for_file: type=lint
mixin _$ContextsDaoMixin on DatabaseAccessor<AppDatabase> {
  $ContextsTable get contexts => attachedDatabase.contexts;
  ContextsDaoManager get managers => ContextsDaoManager(this);
}

class ContextsDaoManager {
  final _$ContextsDaoMixin _db;
  ContextsDaoManager(this._db);
  $$ContextsTableTableManager get contexts =>
      $$ContextsTableTableManager(_db.attachedDatabase, _db.contexts);
}
