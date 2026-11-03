import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:block_editor/block_editor.dart';

void main() {
  group('ImageBlockConfig', () {
    test('default values are set correctly', () {
      const config = ImageBlockConfig();
      expect(config.onUploadRequested, isNull);
      expect(config.onError, isNull);
      expect(config.onLoading, isNull);
      expect(config.scale, 1.0);
      expect(config.borderRadius, BorderRadius.zero);
      expect(config.fit, BoxFit.contain);
    });

    test('copyWith replaces scale', () {
      const config = ImageBlockConfig();
      expect(config.copyWith(scale: 2.0).scale, 2.0);
    });

    test('copyWith replaces fit', () {
      const config = ImageBlockConfig();
      expect(config.copyWith(fit: BoxFit.cover).fit, BoxFit.cover);
    });

    test('copyWith preserves unchanged fields', () {
      const config = ImageBlockConfig(scale: 1.5);
      expect(config.copyWith(fit: BoxFit.fill).scale, 1.5);
    });
  });

  group('VideoBlockConfig', () {
    test('default values are set correctly', () {
      const config = VideoBlockConfig();
      expect(config.autoPlay, isFalse);
      expect(config.showControls, isTrue);
      expect(config.onError, isNull);
      expect(config.onLoading, isNull);
    });

    test('copyWith replaces autoPlay', () {
      const config = VideoBlockConfig();
      expect(config.copyWith(autoPlay: true).autoPlay, isTrue);
    });

    test('copyWith replaces showControls', () {
      const config = VideoBlockConfig();
      expect(config.copyWith(showControls: false).showControls, isFalse);
    });

    test('copyWith preserves unchanged fields', () {
      const config = VideoBlockConfig(autoPlay: true);
      expect(config.copyWith(showControls: false).autoPlay, isTrue);
    });
  });

  group('YouTubeBlockConfig', () {
    test('default values are set correctly', () {
      const config = YouTubeBlockConfig();
      expect(config.autoPlay, isFalse);
      expect(config.showControls, isTrue);
      expect(config.privacyEnhanced, isTrue);
      expect(config.onError, isNull);
      expect(config.onLoading, isNull);
    });

    test('copyWith replaces privacyEnhanced', () {
      const config = YouTubeBlockConfig();
      expect(config.copyWith(privacyEnhanced: false).privacyEnhanced, isFalse);
    });

    test('copyWith preserves unchanged fields', () {
      const config = YouTubeBlockConfig(autoPlay: true);
      expect(config.copyWith(showControls: false).autoPlay, isTrue);
    });
  });

  group('FileBlockConfig', () {
    test('default values are set correctly', () {
      const config = FileBlockConfig();
      expect(config.onDownload, isNull);
      expect(config.onOpen, isNull);
      expect(config.onError, isNull);
      expect(config.allowedExtensions, isEmpty);
    });

    test('copyWith replaces allowedExtensions', () {
      const config = FileBlockConfig();
      final updated = config.copyWith(allowedExtensions: ['pdf', 'docx']);
      expect(updated.allowedExtensions, ['pdf', 'docx']);
    });

    test('copyWith preserves unchanged fields', () {
      const config = FileBlockConfig(allowedExtensions: ['pdf']);
      expect(config.copyWith(onDownload: null).allowedExtensions, ['pdf']);
    });
  });

  group('CodeBlockConfig', () {
    test('default values are set correctly', () {
      const config = CodeBlockConfig();
      expect(config.theme, isNull);
      expect(config.fontSize, 14.0);
      expect(config.showLineNumbers, isTrue);
      expect(config.showLanguageSelector, isTrue);
      expect(config.tabSize, 2);
    });

    test('copyWith replaces fontSize', () {
      const config = CodeBlockConfig();
      expect(config.copyWith(fontSize: 16.0).fontSize, 16.0);
    });

    test('copyWith replaces theme', () {
      const config = CodeBlockConfig();
      expect(config.copyWith(theme: 'monokai').theme, 'monokai');
    });

    test('copyWith can set theme to null', () {
      const config = CodeBlockConfig(theme: 'dracula');
      expect(config.copyWith(theme: null).theme, isNull);
    });

    test('copyWith replaces tabSize', () {
      const config = CodeBlockConfig();
      expect(config.copyWith(tabSize: 4).tabSize, 4);
    });

    test('copyWith preserves unchanged fields', () {
      const config = CodeBlockConfig(fontSize: 18.0);
      expect(config.copyWith(tabSize: 4).fontSize, 18.0);
    });
  });

  group('CalloutBlockConfig', () {
    test('default values are set correctly', () {
      const config = CalloutBlockConfig();
      expect(config.infoColor, isNull);
      expect(config.warningColor, isNull);
      expect(config.errorColor, isNull);
      expect(config.infoIcon, isNull);
      expect(config.warningIcon, isNull);
      expect(config.errorIcon, isNull);
      expect(config.borderRadius, const BorderRadius.all(Radius.circular(6)));
    });

    test('copyWith replaces infoColor', () {
      const config = CalloutBlockConfig();
      const color = Color(0xFF0000FF);
      expect(config.copyWith(infoColor: color).infoColor, color);
    });

    test('copyWith can set infoColor to null', () {
      const config = CalloutBlockConfig(infoColor: Color(0xFF0000FF));
      expect(config.copyWith(infoColor: null).infoColor, isNull);
    });

    test('copyWith replaces borderRadius', () {
      const config = CalloutBlockConfig();
      const radius = BorderRadius.all(Radius.circular(12));
      expect(config.copyWith(borderRadius: radius).borderRadius, radius);
    });

    test('copyWith preserves unchanged fields', () {
      const config = CalloutBlockConfig(infoColor: Color(0xFF0000FF));
      expect(
        config.copyWith(borderRadius: BorderRadius.zero).infoColor,
        const Color(0xFF0000FF),
      );
    });
  });

  group('LinkBlockConfig', () {
    test('default values are set correctly', () {
      const config = LinkBlockConfig();
      expect(config.onOpen, isNull);
      expect(config.onError, isNull);
      expect(config.previewEnabled, isTrue);
    });

    test('copyWith replaces previewEnabled', () {
      const config = LinkBlockConfig();
      expect(config.copyWith(previewEnabled: false).previewEnabled, isFalse);
    });

    test('copyWith preserves unchanged fields', () {
      const config = LinkBlockConfig(previewEnabled: false);
      expect(config.copyWith(onOpen: null).previewEnabled, isFalse);
    });
  });

  group('BlockEditorScope — config fields', () {
    testWidgets('all config fields default to null', (tester) async {
      late BlockEditorScope? scope;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: BlockEditorScope(
            child: Builder(
              builder: (context) {
                scope = BlockEditorScope.maybeOf(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(scope!.imageConfig, isNull);
      expect(scope!.videoConfig, isNull);
      expect(scope!.youTubeConfig, isNull);
      expect(scope!.fileConfig, isNull);
      expect(scope!.codeConfig, isNull);
      expect(scope!.calloutConfig, isNull);
      expect(scope!.linkConfig, isNull);
    });

    testWidgets('imageConfig is accessible from context', (tester) async {
      late BlockEditorScope? scope;
      const config = ImageBlockConfig(scale: 2.0);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: BlockEditorScope(
            imageConfig: config,
            child: Builder(
              builder: (context) {
                scope = BlockEditorScope.maybeOf(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(scope!.imageConfig!.scale, 2.0);
    });

    testWidgets('codeConfig is accessible from context', (tester) async {
      late BlockEditorScope? scope;
      const config = CodeBlockConfig(tabSize: 4);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: BlockEditorScope(
            codeConfig: config,
            child: Builder(
              builder: (context) {
                scope = BlockEditorScope.maybeOf(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(scope!.codeConfig!.tabSize, 4);
    });
  });
}
