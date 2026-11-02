library;

import 'package:flutter/services.dart';
import 'package:block_editor/block_editor.dart';
import 'package:flutter/widgets.dart';

/// Carries the state of the four modifier keys at the moment a key event fires.
///
/// [ModifierKeys] is constructed by the caller before invoking
/// [KeyboardShortcutHandler.handle], decoupling the handler from
/// [HardwareKeyboard.instance] and making it testable without the Flutter
/// binding.
class ModifierKeys {
  /// Creates a [ModifierKeys] snapshot.
  ///
  /// All parameters default to false, representing no modifiers held.
  const ModifierKeys({this.cmd = false, this.shift = false, this.alt = false});

  /// True when the platform command key (Ctrl on Windows/Linux, Meta on macOS)
  /// is held.
  final bool cmd;

  /// True when either Shift key is held.
  final bool shift;

  /// True when either Alt/Option key is held.
  final bool alt;

  /// Reads the current modifier state from [HardwareKeyboard.instance].
  ///
  /// This factory requires the Flutter [ServicesBinding] to be initialised.
  /// Use the default constructor in tests to avoid the binding dependency.
  factory ModifierKeys.fromHardware() => ModifierKeys(
    cmd:
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed,
    shift: HardwareKeyboard.instance.isShiftPressed,
    alt: HardwareKeyboard.instance.isAltPressed,
  );
}

/// Centralises all keyboard shortcut matching and dispatch for the block editor.
///
/// [KeyboardShortcutHandler] owns the full mapping from hardware key events to
/// editing operations. [BlockEditorWidget] holds a single instance and forwards
/// every [KeyDownEvent] and [KeyRepeatEvent] to [handle] together with a
/// [ModifierKeys] snapshot read from [HardwareKeyboard.instance] at the call
/// site.
///
/// Modifier state is injected rather than read inside [handle], so every
/// shortcut path is testable without initialising the Flutter binding.
class KeyboardShortcutHandler {
  /// Creates a [KeyboardShortcutHandler] bound to [controller] and [ops].
  ///
  /// [controller] is used for operations that do not pass through
  /// [EditorEditingOperations] — [BlockController.undo], [BlockController.redo],
  /// [BlockController.selectAll], and [BlockController.clearSelection].
  ///
  /// [ops] handles every character-level and selection operation.
  const KeyboardShortcutHandler({required this.controller, required this.ops});

  /// The document and selection owner.
  final BlockController controller;

  /// The editing operations delegate.
  final EditorEditingOperations ops;

  /// Dispatches [event] to the appropriate operation and returns a
  /// [KeyEventResult] indicating whether the event was consumed.
  ///
  /// [modifiers] must reflect the hardware modifier state at the instant the
  /// event fired. Callers in production read this via [ModifierKeys.fromHardware].
  /// Test callers construct [ModifierKeys] directly.
  ///
  /// Only [KeyDownEvent] and [KeyRepeatEvent] are handled. All other event
  /// types return [KeyEventResult.ignored] immediately.
  KeyEventResult handle(KeyEvent event, ModifierKeys modifiers) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final isCmd = modifiers.cmd;
    final isShift = modifiers.shift;
    final isAlt = modifiers.alt;
    final key = event.logicalKey;

    if (isCmd && !isShift && !isAlt && key == LogicalKeyboardKey.keyA) {
      controller.selectAll();
      return KeyEventResult.handled;
    }

    if (isCmd && !isShift && !isAlt && key == LogicalKeyboardKey.keyZ) {
      controller.undo();
      return KeyEventResult.handled;
    }

    if ((isCmd && isShift && !isAlt && key == LogicalKeyboardKey.keyZ) ||
        (isCmd && !isShift && !isAlt && key == LogicalKeyboardKey.keyY)) {
      controller.redo();
      return KeyEventResult.handled;
    }

    if (isCmd && !isShift && !isAlt && key == LogicalKeyboardKey.keyB) {
      ops.applyBold();
      return KeyEventResult.handled;
    }

    if (isCmd && !isShift && !isAlt && key == LogicalKeyboardKey.keyI) {
      ops.applyItalic();
      return KeyEventResult.handled;
    }

    if (isCmd && !isShift && !isAlt && key == LogicalKeyboardKey.keyU) {
      ops.applyUnderline();
      return KeyEventResult.handled;
    }

    if (!isCmd && !isShift && !isAlt && key == LogicalKeyboardKey.escape) {
      controller.clearSelection();
      return KeyEventResult.handled;
    }

    if (!isCmd && !isShift && !isAlt && key == LogicalKeyboardKey.backspace) {
      ops.backspace();
      return KeyEventResult.handled;
    }

    if (!isCmd && !isShift && !isAlt && key == LogicalKeyboardKey.delete) {
      ops.delete();
      return KeyEventResult.handled;
    }

    if (!isCmd &&
        !isAlt &&
        (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter)) {
      ops.insertNewline();
      return KeyEventResult.handled;
    }

    if (!isCmd && !isAlt && key == LogicalKeyboardKey.tab) {
      isShift ? ops.dedent() : ops.indent();
      return KeyEventResult.handled;
    }

    if (!isAlt && key == LogicalKeyboardKey.home) {
      if (isCmd && isShift) {
        ops.extendSelectionToDocumentStart();
      } else if (isCmd && !isShift) {
        ops.moveToDocumentStart();
      } else if (!isCmd && isShift) {
        ops.extendSelectionToLineStart();
      } else {
        ops.moveToLineStart();
      }
      return KeyEventResult.handled;
    }

    if (!isAlt && key == LogicalKeyboardKey.end) {
      if (isCmd && isShift) {
        ops.extendSelectionToDocumentEnd();
      } else if (isCmd && !isShift) {
        ops.moveToDocumentEnd();
      } else if (!isCmd && isShift) {
        ops.extendSelectionToLineEnd();
      } else {
        ops.moveToLineEnd();
      }
      return KeyEventResult.handled;
    }

    if (isAlt && !isCmd && key == LogicalKeyboardKey.arrowLeft) {
      isShift ? ops.extendSelectionWordLeft() : ops.moveWordLeft();
      return KeyEventResult.handled;
    }

    if (isAlt && !isCmd && key == LogicalKeyboardKey.arrowRight) {
      isShift ? ops.extendSelectionWordRight() : ops.moveWordRight();
      return KeyEventResult.handled;
    }

    if (!isCmd && !isAlt && isShift && key == LogicalKeyboardKey.arrowLeft) {
      ops.extendSelectionLeft();
      return KeyEventResult.handled;
    }

    if (!isCmd && !isAlt && isShift && key == LogicalKeyboardKey.arrowRight) {
      ops.extendSelectionRight();
      return KeyEventResult.handled;
    }

    if (!isCmd && !isAlt && isShift && key == LogicalKeyboardKey.arrowUp) {
      ops.extendSelectionUp();
      return KeyEventResult.handled;
    }

    if (!isCmd && !isAlt && isShift && key == LogicalKeyboardKey.arrowDown) {
      ops.extendSelectionDown();
      return KeyEventResult.handled;
    }

    if (!isCmd && !isAlt && !isShift && key == LogicalKeyboardKey.arrowLeft) {
      ops.moveCharLeft();
      return KeyEventResult.handled;
    }

    if (!isCmd && !isAlt && !isShift && key == LogicalKeyboardKey.arrowRight) {
      ops.moveCharRight();
      return KeyEventResult.handled;
    }

    if (!isCmd && !isAlt && !isShift && key == LogicalKeyboardKey.arrowUp) {
      ops.moveLineUp();
      return KeyEventResult.handled;
    }

    if (!isCmd && !isAlt && !isShift && key == LogicalKeyboardKey.arrowDown) {
      ops.moveLineDown();
      return KeyEventResult.handled;
    }

    if (!isCmd && !isAlt && event.character != null) {
      final char = event.character!;
      if (char.isNotEmpty && !_isControlCharacter(char)) {
        ops.insertCharacter(char);
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  bool _isControlCharacter(String char) {
    final code = char.codeUnitAt(0);
    return code < 32 || code == 127;
  }
}
