import 'package:drift/native.dart';
import 'package:supanotes/core/database/database.dart';

AppDatabase createTestDatabase() {
  return AppDatabase.test(executor: NativeDatabase.memory());
}
