import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/auth/domain/user.dart';
import 'package:supanotes/features/notes/sharing/application/share_link_access_resolver.dart';

class _FakeGateway implements ShareLinkAccessGateway {
  _FakeGateway({this.permission});

  final String? permission;
  int validationCalls = 0;
  int permissionCalls = 0;

  @override
  Future<ShareLinkTarget> validateToken(String token) async {
    validationCalls++;
    return const ShareLinkTarget(noteId: 'note-1');
  }

  @override
  Future<String?> permissionFor(String noteId) async {
    permissionCalls++;
    return permission;
  }
}

void main() {
  const guest = User(id: 'guest', email: 'guest@example.com', name: 'Guest');

  test('validates a token before returning guest read access', () async {
    final gateway = _FakeGateway();
    final result = await ShareLinkAccessResolver(gateway).resolve('token');

    expect(result.noteId, 'note-1');
    expect(result.mode, ShareLinkAccessMode.guest);
    expect(gateway.validationCalls, 1);
    expect(gateway.permissionCalls, 0);
  });

  test('opens the normal note flow for an authenticated owner', () async {
    final gateway = _FakeGateway(permission: 'owner');
    final result = await ShareLinkAccessResolver(
      gateway,
    ).resolve('token', user: guest);

    expect(result.mode, ShareLinkAccessMode.editor);
  });

  test('opens the normal note flow for an authenticated editor', () async {
    final gateway = _FakeGateway(permission: 'edit');
    final result = await ShareLinkAccessResolver(
      gateway,
    ).resolve('token', user: guest);

    expect(result.mode, ShareLinkAccessMode.editor);
  });

  test('keeps an authenticated viewer in read-only mode', () async {
    final gateway = _FakeGateway(permission: 'view');
    final result = await ShareLinkAccessResolver(
      gateway,
    ).resolve('token', user: guest);

    expect(result.mode, ShareLinkAccessMode.viewer);
  });

  test(
    'falls back to guest read access when the user has no direct share',
    () async {
      final gateway = _FakeGateway();
      final result = await ShareLinkAccessResolver(
        gateway,
      ).resolve('token', user: guest);

      expect(result.mode, ShareLinkAccessMode.guest);
    },
  );
}
