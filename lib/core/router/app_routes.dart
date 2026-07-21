abstract final class AppRoutes {
  static const splash = '/splash';
  static const login = '/login';
  static const register = '/register';
  static const home = '/home';
  static const settings = '/settings';
  static const mcp = '/settings/mcp';

  static const _noteBase = '/notes';
  static String note(String id) => '$_noteBase/$id';
}
