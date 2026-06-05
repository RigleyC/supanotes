import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/contexts.dart';

part 'contexts_dao.g.dart';

@DriftAccessor(tables: [Contexts])
class ContextsDao extends DatabaseAccessor<AppDatabase>
    with _$ContextsDaoMixin {
  ContextsDao(super.db);

  /// Streams every context the user has, alphabetically. Filter by
  /// [userId] upstream if the table ever gains shared rows.
  Stream<List<ContextData>> watchContexts({String? userId}) {
    final query = select(contexts)
      ..orderBy([
        (t) => OrderingTerm(expression: t.name, mode: OrderingMode.asc),
      ]);
    if (userId != null) {
      query.where((t) => t.userId.equals(userId));
    }
    return query.watch();
  }

  Stream<List<ContextData>> watchAllContexts() => watchContexts();

  Future<ContextData?> getContextById(String id) {
    return (select(contexts)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<void> createContext(ContextsCompanion context) {
    return into(contexts).insert(context);
  }

  /// Returns every context that has unsynced local changes.
  Future<List<ContextData>> getDirtyContexts() {
    return (select(contexts)..where((t) => t.isDirty.equals(true))).get();
  }

  /// Flips the dirty flag off after a successful push.
  Future<void> clearDirtyFlag(String id) async {
    await (update(contexts)..where((t) => t.id.equals(id)))
        .write(const ContextsCompanion(isDirty: Value(false)));
  }

  /// Stores a context that came back from the backend. Uses
  /// `insertOnConflictUpdate` so a re-pulled row replaces the local copy
  /// in place, and always sets [isDirty] to `false` so the row does not
  /// get pushed back to the server.
  Future<void> upsertFromRemote(ContextData context) async {
    final incoming = context.copyWith(isDirty: false);
    await into(contexts).insertOnConflictUpdate(incoming);
  }
}
