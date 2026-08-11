import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/auth/domain/user.dart';
import 'package:supanotes/features/auth/presentation/controllers/auth_controller.dart';
import 'package:supanotes/features/notes/catalog/model/remote_note_metadata.dart';
import 'package:supanotes/features/notes/sharing/application/share_link_access_provider.dart';
import 'package:supanotes/features/notes/sharing/application/share_link_access_resolver.dart';

class _Gateway implements ShareLinkAccessGateway {
  @override
  Future<ShareLinkTarget> validateToken(String token) async =>
      const ShareLinkTarget(noteId: 'note-1');

  @override
  Future<RemoteNoteMetadata?> metadataFor(String noteId) async {
    throw StateError('metadata must not be requested without a user');
  }
}

class _FailingAuthController extends AuthController {
  @override
  Future<User?> build() async => throw StateError('restore failed');
}

void main() {
  test('does not downgrade an auth restore failure to guest access', () async {
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(_FailingAuthController.new),
        shareLinkAccessResolverProvider.overrideWithValue(
          ShareLinkAccessResolver(_Gateway()),
        ),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(shareLinkAccessProvider('token').future),
      throwsA(isA<StateError>()),
    );
  });
}
