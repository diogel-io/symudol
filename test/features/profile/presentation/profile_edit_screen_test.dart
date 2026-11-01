import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_nostr/dart_nostr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:symudol/features/accounts/presentation/accounts_screen.dart';
import 'package:symudol/features/profile/application/profile_providers.dart';
import 'package:symudol/features/profile/data/blossom_client.dart';
import 'package:symudol/features/profile/data/nip05_client.dart';
import 'package:symudol/features/profile/data/profile_image_picker.dart';
import 'package:symudol/features/profile/data/relay_profile_service.dart';
import 'package:symudol/features/profile/presentation/profile_edit_screen.dart';
import 'package:symudol/features/vault/application/vault_controller.dart';
import 'package:symudol/features/vault/application/vault_providers.dart';
import 'package:symudol/features/vault/domain/vault_service_impl.dart';

import '../../../fakes/fake_profile_network_store.dart';
import '../../../fakes/fake_profile_relay_client.dart';
import '../../../fakes/fake_vault_store.dart';

/// Returns [image] for every pick, and records the sources asked for.
class _FakePicker implements ProfileImagePicker {
  _FakePicker(this.image);

  Uint8List? image;

  /// Whether the camera can be used, as on Android; false as on desktop.
  bool camera = true;

  /// When set, [pick] throws it, as a failed read of the chosen file does.
  Object? error;
  final List<ProfileImageSource> sources = [];

  @override
  bool supports(ProfileImageSource source) =>
      source != ProfileImageSource.camera || camera;

  @override
  Future<Uint8List?> pick(ProfileImageSource source) async {
    sources.add(source);
    if (error case final Object error) throw error;
    return image;
  }
}

/// The profile editor asks before reaching relays, before creating a profile
/// and before publishing (diogel-io/symudol#41, #83).
void main() {
  late VaultServiceImpl vault;
  late VaultController controller;
  late FakeProfileRelayClient relays;
  late _FakePicker picker;
  late List<http.Request> uploads;
  late List<http.Request> nip05Requests;
  late Future<http.Response> Function(http.Request) nip05Answer;

  setUp(() async {
    vault = VaultServiceImpl(FakeVaultStore());
    await vault.createVault('123456');
    await vault.createIdentity(displayName: 'Account 1');
    await vault.createIdentity(displayName: 'Account 2');
    controller = VaultController(vault);
    await controller.initialize();
    await controller.unlock('123456');
    relays = FakeProfileRelayClient();
    picker = _FakePicker(
      img.encodeJpg(
        img.Image(width: 8, height: 8)..clear(img.ColorRgb8(1, 2, 3)),
      ),
    );
    uploads = [];
    nip05Requests = [];
    nip05Answer = (_) async => http.Response('{"names": {}}', 200);
  });

  Widget app(Widget home) => ProviderScope(
    overrides: [
      vaultServiceProvider.overrideWithValue(vault),
      vaultControllerProvider.overrideWith((ref) => controller),
      profileNetworkStoreProvider.overrideWithValue(FakeProfileNetworkStore()),
      relayProfileServiceProvider.overrideWithValue(
        RelayProfileService(client: relays),
      ),
      profileImagePickerProvider.overrideWithValue(picker),
      blossomClientProvider.overrideWithValue(
        BlossomClient(
          client: MockClient((request) async {
            uploads.add(request);
            final sha = blobSha256(request.bodyBytes);
            return http.Response(
              jsonEncode({
                'url': 'https://cdn.example/$sha.jpg',
                'sha256': sha,
              }),
              200,
            );
          }),
        ),
      ),
      nip05ClientProvider.overrideWithValue(
        Nip05Client(
          client: MockClient((request) {
            nip05Requests.add(request);
            return nip05Answer(request);
          }),
        ),
      ),
    ],
    child: MaterialApp(home: home),
  );

  Future<void> openEditor(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.reset());
    final identity = controller.state.activeIdentity!;
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ProfileEditScreen(identity: identity),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  void holdProfile(Map<String, Object?> content) {
    relays.held['wss://purplepag.es'] = [
      NostrEvent(
        id: 'kind0',
        kind: 0,
        content: jsonEncode(content),
        sig: 'sig',
        pubkey: controller.state.activeIdentity!.publicKey,
        createdAt: DateTime.fromMillisecondsSinceEpoch(10000),
        tags: const [],
      ),
    ];
  }

  testWidgets('opening asks before reaching any relay', (tester) async {
    await openEditor(tester);

    expect(find.text('Load profile from relays?'), findsOneWidget);
    expect(relays.queries, isEmpty);
  });

  testWidgets('cancelling closes the editor and fetches nothing', (
    tester,
  ) async {
    await openEditor(tester);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(ProfileEditScreen), findsNothing);
    expect(relays.queries, isEmpty);
  });

  testWidgets('no profile lists the relays and asks before creating one', (
    tester,
  ) async {
    await openEditor(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Load profile'));
    await tester.pumpAndSettle();

    expect(find.text('No profile found'), findsOneWidget);
    expect(find.text('purplepag.es'), findsOneWidget);
    expect(find.text('Save'), findsNothing);

    await tester.tap(find.text('Create a new profile'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'Name'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('saving names the relays, then shows how each answered', (
    tester,
  ) async {
    holdProfile({'name': 'alice'});
    await openEditor(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Load profile'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'alice'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'About'), 'hello');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Sign and publish?'), findsOneWidget);
    expect(find.text('relay.damus.io'), findsOneWidget);
    expect(relays.published, isEmpty);

    await tester.tap(find.text('Sign and publish'));
    await tester.pumpAndSettle();

    expect(find.text('Profile published'), findsOneWidget);
    expect(find.text('3 of 3 relays accepted it.'), findsOneWidget);
    expect(jsonDecode(relays.published.single.event.content), {
      'name': 'alice',
      'about': 'hello',
    });
  });

  testWidgets('images in the preview load only when asked', (tester) async {
    holdProfile({'name': 'alice', 'picture': 'https://example.com/a.png'});
    await openEditor(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Load profile'));
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsNothing);
    expect(find.text('Show images'), findsOneWidget);
  });

  testWidgets('leaving with unsaved edits asks first', (tester) async {
    holdProfile({'name': 'alice'});
    await openEditor(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Load profile'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'About'), 'hello');
    await tester.pump();

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileEditScreen), findsNothing);
  });

  testWidgets('only the active identity offers Edit profile', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.reset());
    await tester.pumpWidget(app(const AccountsScreen()));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Edit profile'), findsOneWidget);
    expect(find.byTooltip('Load profile'), findsNWidgets(2));
  });

  group('uploading an image (#43)', () {
    Future<void> openLoaded(WidgetTester tester) async {
      holdProfile({'name': 'alice'});
      await openEditor(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Load profile'));
      await tester.pumpAndSettle();
    }

    Future<void> pickFromPhotos(WidgetTester tester, String tooltip) async {
      await tester.tap(find.byTooltip(tooltip));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose from photos'));
      await tester.pumpAndSettle();
    }

    /// Lets the re-encode isolate and the upload finish.
    Future<void> finishUpload(WidgetTester tester) async {
      for (
        var i = 0;
        i < 100 && find.byType(SnackBar).evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    testWidgets('names the server before sending anything', (tester) async {
      await openLoaded(tester);

      await pickFromPhotos(tester, 'Upload picture');

      expect(picker.sources, [ProfileImageSource.photos]);
      expect(find.text('Upload to blossom.primal.net?'), findsOneWidget);
      expect(find.textContaining('location and camera details'), findsOne);
      expect(uploads, isEmpty);
    });

    testWidgets('fills the field with the URL, and Save publishes it', (
      tester,
    ) async {
      await openLoaded(tester);
      await pickFromPhotos(tester, 'Upload picture');

      await tester.tap(find.widgetWithText(FilledButton, 'Upload'));
      await finishUpload(tester);

      final sha = blobSha256(uploads.single.bodyBytes);
      expect(
        find.widgetWithText(TextField, 'https://cdn.example/$sha.jpg'),
        findsOneWidget,
      );
      expect(
        find.text('Image uploaded. Save to publish it on your profile.'),
        findsOneWidget,
      );
      expect(relays.published, isEmpty);
      final save = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Save'),
      );
      expect(save.onPressed, isNotNull);
    });

    testWidgets('the banner field takes a photo from the camera', (
      tester,
    ) async {
      await openLoaded(tester);
      await tester.scrollUntilVisible(
        find.byTooltip('Upload banner'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      await tester.tap(find.byTooltip('Upload banner'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Take a photo'));
      await tester.pumpAndSettle();

      expect(picker.sources, [ProfileImageSource.camera]);
    });

    testWidgets('offers no camera where there is none', (tester) async {
      picker.camera = false;
      await openLoaded(tester);

      await tester.tap(find.byTooltip('Upload picture'));
      await tester.pumpAndSettle();

      expect(find.text('Choose from photos'), findsOneWidget);
      expect(find.text('Take a photo'), findsNothing);
    });

    testWidgets('cancelling the confirm uploads nothing', (tester) async {
      await openLoaded(tester);
      await pickFromPhotos(tester, 'Upload picture');

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(uploads, isEmpty);
      expect(find.textContaining('https://cdn.example'), findsNothing);
    });

    testWidgets('a chosen file that cannot be read shows why', (tester) async {
      picker.error = const FileSystemException('unreadable');
      await openLoaded(tester);

      await pickFromPhotos(tester, 'Upload picture');

      expect(find.text("Couldn't read that image."), findsOneWidget);
      expect(find.textContaining('Upload to'), findsNothing);
      expect(uploads, isEmpty);
    });

    testWidgets('cancelling the picker asks nothing more', (tester) async {
      picker.image = null;
      await openLoaded(tester);

      await pickFromPhotos(tester, 'Upload picture');

      expect(find.textContaining('Upload to'), findsNothing);
      expect(uploads, isEmpty);
    });

    testWidgets('a locked vault shows why nothing was uploaded', (
      tester,
    ) async {
      await openLoaded(tester);
      await pickFromPhotos(tester, 'Upload picture');
      await vault.lock();

      await tester.tap(find.widgetWithText(FilledButton, 'Upload'));
      await finishUpload(tester);

      expect(
        find.text('Symudol is locked. Unlock it, then try again.'),
        findsOneWidget,
      );
      expect(uploads, isEmpty);
    });
  });

  group('verifying the NIP-05 identifier (#44)', () {
    late String pubkey;

    Future<void> openLoaded(WidgetTester tester, {String? nip05}) async {
      pubkey = controller.state.activeIdentity!.publicKey;
      holdProfile({'name': 'alice', 'nip05': ?nip05});
      await openEditor(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Load profile'));
      await tester.pumpAndSettle();
    }

    Finder field() => find.widgetWithText(TextField, 'NIP-05 identifier');
    Finder verify() => find.widgetWithText(TextButton, 'Verify');

    void answer(Map<String, String> names) {
      nip05Answer = (_) async =>
          http.Response(jsonEncode({'names': names}), 200);
    }

    testWidgets('nothing is fetched until Verify is tapped', (tester) async {
      await openLoaded(tester, nip05: 'alice@example.com');
      await tester.enterText(field(), 'bob@example.com');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign and publish'));
      await tester.pumpAndSettle();

      expect(nip05Requests, isEmpty);
    });

    testWidgets('says it runs only when asked, then verifies on a tap', (
      tester,
    ) async {
      await openLoaded(tester, nip05: 'alice@example.com');
      answer({'alice': pubkey});

      expect(
        find.text('Not verified yet. Verification runs only when you ask.'),
        findsOneWidget,
      );
      await tester.tap(verify());
      await tester.pumpAndSettle();

      expect(nip05Requests, hasLength(1));
      expect(
        nip05Requests.single.url.toString(),
        'https://example.com/.well-known/nostr.json?name=alice',
      );
      expect(
        find.text("Verified: example.com lists this identity's public key."),
        findsOneWidget,
      );
    });

    final failures = <String, (Future<http.Response> Function(http.Request), String)>{
      'not found': (
        (_) async => http.Response('{"names": {}}', 200),
        'example.com does not list this name.',
      ),
      'a different key': (
        (_) async => http.Response(
          jsonEncode({
            'names': {'alice': 'ab' * 32},
          }),
          200,
        ),
        'example.com lists this name for a different public key.',
      ),
      'an invalid answer': (
        (_) async => http.Response('<html>', 200),
        "example.com's answer is not a valid NIP-05 response.",
      ),
      'a network error': (
        (_) async => throw const SocketException('no route'),
        "Couldn't reach example.com. Check the connection and try again.",
      ),
    };
    for (final MapEntry(key: what, value: (reply, message))
        in failures.entries) {
      testWidgets('reports $what', (tester) async {
        await openLoaded(tester, nip05: 'alice@example.com');
        nip05Answer = reply;

        await tester.tap(verify());
        await tester.pumpAndSettle();

        expect(find.text(message), findsOneWidget);
      });
    }

    testWidgets('Verify is off for an empty or malformed identifier', (
      tester,
    ) async {
      await openLoaded(tester);

      expect(tester.widget<TextButton>(verify()).onPressed, isNull);
      await tester.enterText(field(), 'alice');
      await tester.pump();

      expect(tester.widget<TextButton>(verify()).onPressed, isNull);
      expect(
        find.text('Enter an identifier like name@example.com.'),
        findsOneWidget,
      );
      await tester.tap(verify());
      await tester.pumpAndSettle();
      expect(nip05Requests, isEmpty);
    });

    testWidgets('editing the identifier clears the result', (tester) async {
      await openLoaded(tester, nip05: 'alice@example.com');
      answer({'alice': pubkey});
      await tester.tap(verify());
      await tester.pumpAndSettle();
      expect(find.textContaining('Verified:'), findsOneWidget);

      await tester.enterText(field(), 'alice@example.org');
      await tester.pump();

      expect(find.textContaining('Verified:'), findsNothing);
      expect(
        find.text('Not verified yet. Verification runs only when you ask.'),
        findsOneWidget,
      );
    });

    testWidgets('a result that arrives after an edit is dropped', (
      tester,
    ) async {
      await openLoaded(tester, nip05: 'alice@example.com');
      final reply = Completer<http.Response>();
      nip05Answer = (_) => reply.future;
      await tester.tap(verify());
      await tester.pump();
      expect(find.text('Verifying…'), findsOneWidget);

      await tester.enterText(field(), 'alice@example.org');
      await tester.pump();
      reply.complete(
        http.Response(
          jsonEncode({
            'names': {'alice': pubkey},
          }),
          200,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Verified:'), findsNothing);
      expect(
        find.text('Not verified yet. Verification runs only when you ask.'),
        findsOneWidget,
      );
      // Typing the old value back shows nothing stale either.
      await tester.enterText(field(), 'alice@example.com');
      await tester.pump();
      expect(find.textContaining('Verified:'), findsNothing);
    });
  });
}
