import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/shared/theme/desktop_layout_tokens.dart';

void main() {
  group('DesktopLayoutTokens', () {
    test('limits the sidebar maximum to 35 percent of a small desktop', () {
      expect(DesktopLayoutTokens.maxSidebarWidth(900), closeTo(315, 0.001));
      expect(DesktopLayoutTokens.maxSidebarWidth(1200), closeTo(420, 0.001));
    });

    test('clamps a restored width to the viewport-safe range', () {
      expect(
        DesktopLayoutTokens.clampSidebarWidth(100, viewportWidth: 1200),
        DesktopLayoutTokens.sidebarMinWidth,
      );
      expect(
        DesktopLayoutTokens.clampSidebarWidth(900, viewportWidth: 1200),
        DesktopLayoutTokens.sidebarMaxWidth,
      );
    });
  });
}
