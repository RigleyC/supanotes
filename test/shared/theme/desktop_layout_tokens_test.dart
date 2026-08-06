import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/shared/theme/desktop_layout_tokens.dart';

void main() {
  group('DesktopLayoutTokens', () {
    test('limits the sidebar maximum to 35 percent of a small desktop', () {
      expect(DesktopLayoutTokens.maxSidebarWidth(900), closeTo(315, 0.001));
      expect(DesktopLayoutTokens.maxSidebarWidth(1200), closeTo(420, 0.001));
      expect(DesktopLayoutTokens.maxSidebarWidth(1440), closeTo(420, 0.001));
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

    test('uses Writer-like desktop density and chrome metrics', () {
      expect(DesktopLayoutTokens.sidebarInitialWidth, 240);
      expect(DesktopLayoutTokens.sidebarCollapsedWidth, 48);
      expect(DesktopLayoutTokens.sidebarRowHeight, 32);
      expect(DesktopLayoutTokens.chromeHeight, 56);
      expect(DesktopLayoutTokens.chromeControlHeight, 32);
    });

    test('uses Writer-like document spacing', () {
      expect(DesktopLayoutTokens.editorTopPadding, 144);
      expect(DesktopLayoutTokens.editorBottomPaddingForHeight(800), 320);
    });
  });
}
