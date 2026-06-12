abstract final class AppRoutes {
  static const splash = '/splash';
  static const login = '/login';
  static const register = '/register';
  static const home = '/home';
  static const inbox = '/inbox';
  static const settings = '/settings';
  static const soul = '/soul';
  static const contexts = '/contexts';
  static const routines = '/routines';
  static const routinesLogs = '/routines/logs';
  static const telegram = '/telegram';
  static const chat = '/chat';
  static const search = '/search';
  static const memories = '/memories';

  static const _noteBase = '/notes';
  static String note(String id) => '$_noteBase/$id';
}
