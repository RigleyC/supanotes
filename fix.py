import os

def replace_in_file(path, old, new):
    if not os.path.exists(path): return
    with open(path, 'r', encoding='utf-8') as f: c = f.read()
    c = c.replace(old, new)
    with open(path, 'w', encoding='utf-8') as f: f.write(c)

# Fix tasks_dao
path = r'd:\projects\supanotes\lib\core\database\daos\tasks_dao.dart'
replace_in_file(path, 't.isCompleted', "t.status.equals('completed')")
replace_in_file(path, 'TasksDao(AppDatabase db)', 'TasksDao(super.db)')

# Fix tasks_local_repository
path = r'd:\projects\supanotes\lib\features\tasks\data\local\tasks_local_repository.dart'
replace_in_file(path, '../../../core/database/database.dart', 'package:supanotes/core/database/database.dart')
replace_in_file(path, '../../../core/database/daos/tasks_dao.dart', 'package:supanotes/core/database/daos/tasks_dao.dart')

# Fix today_tasks_screen
path = r'd:\projects\supanotes\lib\features\tasks\presentation\today_tasks_screen.dart'
replace_in_file(path, '../../../core/database/database.dart', 'package:supanotes/core/database/database.dart')
replace_in_file(path, 'task.isCompleted', "task.status == 'completed'")
replace_in_file(path, 'isCompleted: const drift.Value(false)', "status: const drift.Value('pending')")
replace_in_file(path, 'task.content', 'task.title')
replace_in_file(path, 'Colors.grey.withOpacity(0.2)', 'Colors.grey.withValues(alpha: 0.2)')

# Fix note_editor_screen
path = r'd:\projects\supanotes\lib\features\notes\presentation\note_editor_screen.dart'
replace_in_file(path, 'content: drift.Value(text)', 'title: drift.Value(text)')
replace_in_file(path, 'isCompleted: drift.Value(node.isComplete)', "status: drift.Value(node.isComplete ? 'completed' : 'pending')")
replace_in_file(path, 'content: text', 'title: text')
replace_in_file(path, 'isCompleted: node.isComplete', "status: node.isComplete ? 'completed' : 'pending'")

# Fix inbox_screen
path = r'd:\projects\supanotes\lib\features\notes\presentation\inbox_screen.dart'
replace_in_file(path, 'content: drift.Value(text)', 'title: drift.Value(text)')
replace_in_file(path, 'isCompleted: drift.Value(node.isComplete)', "status: drift.Value(node.isComplete ? 'completed' : 'pending')")
replace_in_file(path, 'content: text', 'title: text')
replace_in_file(path, 'isCompleted: node.isComplete', "status: node.isComplete ? 'completed' : 'pending'")

print('Fixed files')
