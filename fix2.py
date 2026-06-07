import os

def replace_in_file(path, old, new):
    if not os.path.exists(path): return
    with open(path, 'r', encoding='utf-8') as f: c = f.read()
    c = c.replace(old, new)
    with open(path, 'w', encoding='utf-8') as f: f.write(c)

replace_in_file(r'd:\projects\supanotes\lib\core\database\daos\tasks_dao.dart', 'TasksDao(super.db)', 'TasksDao(super.db);')
replace_in_file(r'd:\projects\supanotes\lib\core\database\database.dart', "import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';\n", '')
replace_in_file(r'd:\projects\supanotes\lib\features\notes\presentation\inbox_screen.dart', "title: text,\n", "title: text,\n            position: 0,\n")
replace_in_file(r'd:\projects\supanotes\lib\features\notes\presentation\note_editor_screen.dart', "title: text,\n", "title: text,\n            position: 0,\n")
replace_in_file(r'd:\projects\supanotes\lib\features\tasks\data\local\tasks_local_repository.dart', "import 'package:drift/drift.dart';\n", '')

print('Fixed remaining files')
