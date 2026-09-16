abstract final class AppRoutes {
  static const splash = '/splash';
  static const login = '/login';
  static const register = '/register';
  static const home = '/home';
  static const tasks = '/tasks';
  static const notes = '/notes';
  static const completedTasks = '/tasks/completed';
  static const standaloneTask = '/tasks/standalone';
  static const settings = '/settings';
  static const mcp = '/settings/mcp';
  static const shareLink = '/s/:token';

  static String note(String id, {String? blockId}) {
    final path = '$notes/$id';
    if (blockId == null || blockId.isEmpty) return path;
    return '$path?blockId=${Uri.encodeQueryComponent(blockId)}';
  }
}
