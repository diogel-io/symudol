import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:symudol/features/nip46/application/nip46_link_handler.dart';
import 'package:symudol/features/nip46/domain/nip46_connection_token.dart';

const _link =
    'nostrconnect://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    '?relay=wss%3A%2F%2Frelay.example.com&secret=s1';

/// Links from the Android side, as Nip46Links.kt hands them over.
class _FakeLinks implements Nip46Links {
  String? pending;
  bool? enabled;
  final _available = StreamController<void>.broadcast();

  void arrive(String link) {
    pending = link;
    _available.add(null);
  }

  @override
  Future<String?> takeLink() async {
    final link = pending;
    pending = null;
    return link;
  }

  @override
  Stream<void> get linkAvailable => _available.stream;

  @override
  Future<void> setLinksEnabled(bool enabled) async => this.enabled = enabled;
}

void main() {
  late _FakeLinks links;
  late bool unlocked;
  late bool pendingApproval;
  late List<String> imported;
  late int approvalsOpened;
  late List<String> messages;
  Object? importError;

  Nip46LinkHandler handler({bool enabled = true}) => Nip46LinkHandler(
    links: links,
    enabled: enabled,
    isUnlocked: () => unlocked,
    hasPendingApproval: () => pendingApproval,
    importLink: (uri) async {
      if (importError != null) throw importError!;
      imported.add(uri);
      pendingApproval = true;
    },
    openApproval: () => approvalsOpened++,
    showMessage: messages.add,
  );

  setUp(() {
    links = _FakeLinks();
    unlocked = true;
    pendingApproval = false;
    imported = [];
    approvalsOpened = 0;
    messages = [];
    importError = null;
  });

  group('Nip46LinkHandler (#31)', () {
    test('a link Symudol opened with is imported and its approval opened', () async {
      links.pending = _link;

      await handler().start();

      expect(links.enabled, isTrue);
      expect(imported, [_link]);
      expect(approvalsOpened, 1);
      expect(messages, isEmpty);
    });

    test('a link arriving while running is imported', () async {
      await handler().start();

      links.arrive(_link);
      await pumpEventQueue();

      expect(imported, [_link]);
      expect(approvalsOpened, 1);
    });

    test('a link while locked is held, and imported after unlock', () async {
      unlocked = false;
      links.pending = _link;
      final subject = handler();

      await subject.start();
      expect(imported, isEmpty);
      expect(approvalsOpened, 0);

      unlocked = true;
      await subject.onUnlocked();
      expect(imported, [_link]);
      expect(approvalsOpened, 1);

      // Handled once.
      await subject.onUnlocked();
      expect(imported, [_link]);
    });

    test('a wipe drops a held link', () async {
      unlocked = false;
      links.pending = _link;
      final subject = handler();
      await subject.start();

      subject.onVaultWiped();
      unlocked = true;
      await subject.onUnlocked();

      expect(imported, isEmpty);
    });

    test('a build that hides NIP-46 turns links off and handles none', () async {
      links.pending = _link;

      await handler(enabled: false).start();

      expect(links.enabled, isFalse);
      expect(imported, isEmpty);
      expect(links.pending, _link);
    });

    test('a link while another connection waits for approval is refused', () async {
      pendingApproval = true;
      await handler().start();

      links.arrive(_link);
      await pumpEventQueue();

      expect(imported, isEmpty);
      expect(approvalsOpened, 0);
      expect(messages.single, contains('Another connection is waiting'));
    });

    test('an invalid link shows a message without the link', () async {
      importError = const Nip46TokenParseException('missing secret');
      links.pending = 'nostrconnect://bad?secret=top-secret';

      await handler().start();

      expect(approvalsOpened, 0);
      expect(messages.single, 'This nostrconnect:// link isn’t valid.');
      expect(messages.single, isNot(contains('top-secret')));
    });

    test('a failed import shows a message and opens nothing', () async {
      importError = StateError('relay down');
      links.pending = _link;

      await handler().start();

      expect(approvalsOpened, 0);
      expect(messages.single, 'Symudol couldn’t connect to the client.');
    });
  });
}
