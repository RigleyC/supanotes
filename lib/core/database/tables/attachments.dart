import 'package:drift/drift.dart';

@DataClassName('AttachmentData')
class Attachments extends Table {
  TextColumn get id => text()();

  TextColumn get noteId => text().customConstraint(
    'NOT NULL REFERENCES notes(id) ON DELETE CASCADE'
  )();

  TextColumn get localPath => text().nullable()();
  TextColumn get remoteUrl => text().nullable()();
  TextColumn get fileName => text()();
  TextColumn get mimeType => text()();
  IntColumn get fileSize => integer()();

  TextColumn get status => text().withDefault(const Constant('local'))();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
