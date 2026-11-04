import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../requests/domain/nostr_event_draft.dart';
import '../../requests/domain/signed_nostr_event.dart';
import '../../vault/application/vault_providers.dart';
import '../../vault/domain/vault_exceptions.dart';
import '../data/profile_relay_client.dart';
import '../data/relay_profile_service.dart';
import '../domain/relay_list.dart';
import '../domain/replaceable_event.dart';
import 'profile_providers.dart';

/// Where the relay list editor stands.
enum RelayListEditorPhase { notLoaded, loading, loadFailed, noList, editing }

/// The relay list editor's state (diogel-io/symudol#88).
@immutable
class RelayListEditorState {
  const RelayListEditorState({
    this.phase = RelayListEditorPhase.notLoaded,
    this.relays = const [],
    this.saved = const [],
    this.searchedRelays = const [],
    this.createConfirmed = false,
    this.saving = false,
    this.saveError,
    this.inputError,
    this.publishResults,
  });

  final RelayListEditorPhase phase;

  /// The relays being edited.
  final List<RelayListEntry> relays;

  /// The relays as last loaded or saved, to tell whether there are edits.
  final List<RelayListEntry> saved;

  /// The relays that answered the last lookup.
  final List<String> searchedRelays;

  /// Whether the user has confirmed creating a list where none was found.
  final bool createConfirmed;

  final bool saving;

  /// Why the last save failed; null when it did not.
  final String? saveError;

  /// Why the last relay typed in was not added; null when it was.
  final String? inputError;

  /// How each relay answered the last save; null before any save.
  final Map<String, RelayPublishResult>? publishResults;

  bool get dirty => !listEquals(relays, saved);

  RelayListEditorState copyWith({
    RelayListEditorPhase? phase,
    List<RelayListEntry>? relays,
    List<RelayListEntry>? saved,
    List<String>? searchedRelays,
    bool? createConfirmed,
    bool? saving,
    String? saveError,
    bool clearSaveError = false,
    String? inputError,
    bool clearInputError = false,
    Map<String, RelayPublishResult>? publishResults,
  }) {
    return RelayListEditorState(
      phase: phase ?? this.phase,
      relays: relays ?? this.relays,
      saved: saved ?? this.saved,
      searchedRelays: searchedRelays ?? this.searchedRelays,
      createConfirmed: createConfirmed ?? this.createConfirmed,
      saving: saving ?? this.saving,
      saveError: clearSaveError ? null : (saveError ?? this.saveError),
      inputError: clearInputError ? null : (inputError ?? this.inputError),
      publishResults: publishResults ?? this.publishResults,
    );
  }
}

/// A save that did not publish, with a message for the user.
class RelayListSaveException implements Exception {
  const RelayListSaveException(this.message);

  final String message;

  @override
  String toString() => 'RelayListSaveException: $message';
}

/// A save checked and ready to sign: the list read again, the relays it
/// will replace it with, and where it will be published.
class PreparedRelayListSave {
  const PreparedRelayListSave({
    required this.latest,
    required this.relays,
    required this.publishRelays,
  });

  final RelayListLookup latest;
  final List<RelayListEntry> relays;
  final List<String> publishRelays;
}

/// The relay list editor for one public key, which must be the active
/// identity's to save.
final relayListEditorProvider = NotifierProvider.autoDispose
    .family<RelayListEditorNotifier, RelayListEditorState, String>(
      RelayListEditorNotifier.new,
    );

/// Loads the identity's NIP-65 relay list (kind 10002) and saves it: the
/// user's changes are applied to the newest list read again at save time,
/// then signed with the vault and published (diogel-io/symudol#88). Like the
/// profile editor (#41), [load] and [save] reach relays, so call them only
/// after the user has asked (#83).
class RelayListEditorNotifier extends Notifier<RelayListEditorState> {
  RelayListEditorNotifier(this.pubkeyHex);

  final String pubkeyHex;

  @override
  RelayListEditorState build() => const RelayListEditorState();

  /// Looks the relay list up and fills the editor from it.
  Future<void> load() async {
    state = state.copyWith(phase: RelayListEditorPhase.loading);
    final RelayListLookup lookup;
    try {
      lookup = await ref
          .read(relayProfileServiceProvider)
          .fetchRelayList(pubkeyHex);
    } on ProfileFetchException {
      if (ref.mounted) {
        state = const RelayListEditorState(
          phase: RelayListEditorPhase.loadFailed,
        );
      }
      return;
    }
    if (!ref.mounted) return;
    final relays = lookup.entries;
    state = RelayListEditorState(
      phase: lookup.found
          ? RelayListEditorPhase.editing
          : RelayListEditorPhase.noList,
      relays: relays,
      saved: relays,
      searchedRelays: lookup.searchedRelays,
    );
  }

  /// Confirms creating a list where no relay held one.
  void confirmCreate() {
    state = state.copyWith(
      phase: RelayListEditorPhase.editing,
      createConfirmed: true,
    );
  }

  /// Adds the relay the user typed, marked read and write. Returns whether
  /// it was added; when not, [RelayListEditorState.inputError] says why.
  bool add(String text) {
    final url = parseRelayInput(text);
    if (url == null) {
      state = state.copyWith(
        inputError: "That isn't a relay address (wss://…).",
      );
      return false;
    }
    if (state.relays.any((entry) => entry.url == url)) {
      state = state.copyWith(inputError: 'That relay is already listed.');
      return false;
    }
    state = state.copyWith(
      relays: [...state.relays, RelayListEntry(url)],
      clearInputError: true,
    );
    return true;
  }

  /// Marks [url] read, write or both. A relay is always one or the other,
  /// so turning both off is ignored.
  void setMarkers(String url, {bool? read, bool? write}) {
    RelayListEntry marked(RelayListEntry entry) {
      final nextRead = read ?? entry.read;
      final nextWrite = write ?? entry.write;
      if (!nextRead && !nextWrite) return entry;
      return entry.copyWith(read: nextRead, write: nextWrite);
    }

    state = state.copyWith(
      relays: [
        for (final entry in state.relays)
          entry.url == url ? marked(entry) : entry,
      ],
    );
  }

  void remove(String url) {
    state = state.copyWith(
      relays: [
        for (final entry in state.relays)
          if (entry.url != url) entry,
      ],
    );
  }

  /// Reads the newest list again and applies the user's changes to it, so
  /// the user can confirm where a save will publish before anything is
  /// signed. The editor then shows what the save will sign. Pass the result
  /// to [save]. Throws [RelayListSaveException] when it can't be saved.
  Future<PreparedRelayListSave> prepareSave() => _guard(() async {
    final prepared = await _prepare();
    if (ref.mounted) {
      state = state.copyWith(
        saving: false,
        relays: prepared.relays,
        saved: prepared.latest.entries,
      );
    }
    return prepared;
  });

  /// Signs and publishes [prepared], or the list prepared now. Returns how
  /// each relay answered; throws [RelayListSaveException] when no relay
  /// accepted it. Afterwards the editor holds what was published.
  Future<Map<String, RelayPublishResult>> save({
    PreparedRelayListSave? prepared,
  }) => _guard(() async {
    final ready = prepared ?? await _prepare();
    final results = await _publish(ready);
    if (ref.mounted) {
      state = state.copyWith(
        saving: false,
        relays: ready.relays,
        saved: ready.relays,
        publishResults: results,
      );
    }
    return results;
  });

  Future<PreparedRelayListSave> _prepare() async {
    if (state.relays.isEmpty) {
      throw const RelayListSaveException(
        'Keep at least one relay, or other apps can’t find your events.',
      );
    }
    final service = ref.read(relayProfileServiceProvider);
    final RelayListLookup latest;
    try {
      latest = await service.fetchRelayList(pubkeyHex);
    } on ProfileFetchException {
      throw const RelayListSaveException(
        "No relay answered, so saving could overwrite a list you haven't "
        'seen. Your relays have not changed. Try again.',
      );
    }
    if (!latest.found && state.saved.isNotEmpty) {
      throw const RelayListSaveException(
        'No relay holds a relay list for this identity now. '
        'Load it again before saving.',
      );
    }
    if (!latest.found && !state.createConfirmed) {
      throw const RelayListSaveException(
        'No relay holds a relay list for this identity now. '
        'Load it again to create a new one.',
      );
    }
    final relays = applyRelayEdits(latest.entries, state.saved, state.relays);
    if (relays.isEmpty) {
      throw const RelayListSaveException(
        'Keep at least one relay, or other apps can’t find your events.',
      );
    }
    return PreparedRelayListSave(
      latest: latest,
      relays: relays,
      publishRelays: await service.relayListPublishRelays(
        latest.entries,
        relays,
      ),
    );
  }

  /// Runs [step] with the saving flag set, keeping the editor alive until it
  /// ends even if the screen closes, and turns any failure into a
  /// [RelayListSaveException] recorded in [RelayListEditorState.saveError].
  Future<T> _guard<T>(Future<T> Function() step) async {
    state = state.copyWith(saving: true, clearSaveError: true);
    final link = ref.keepAlive();
    try {
      return await step();
    } catch (error) {
      final failure = error is RelayListSaveException
          ? error
          : const RelayListSaveException(
              "Couldn't save the relays. Try again.",
            );
      if (ref.mounted) {
        state = state.copyWith(saving: false, saveError: failure.message);
      }
      throw failure;
    } finally {
      link.close();
    }
  }

  Future<Map<String, RelayPublishResult>> _publish(
    PreparedRelayListSave prepared,
  ) async {
    final active = ref.read(vaultControllerProvider).activeIdentity;
    if (active == null || active.publicKey != pubkeyHex) {
      throw const RelayListSaveException(
        'This identity is no longer the active one. '
        'Make it active to save its relays.',
      );
    }

    final DateTime createdAt;
    try {
      createdAt = createdAfter(prepared.latest.createdAt);
    } on ReplaceableEventDateException {
      throw const RelayListSaveException(
        "This identity's newest relay list is dated ahead of this phone's "
        'clock, so relays would keep it over an update. Check the date and '
        'time on this phone, and in the app that published that list.',
      );
    }
    final draft = NostrEventDraft(
      kind: 10002,
      content: '',
      tags: relayListTags(
        prepared.relays,
        otherTags: nonRelayTags(prepared.latest.tags),
      ),
      createdAt: createdAt,
    );

    final SignedNostrEvent signed;
    try {
      signed = await ref
          .read(vaultServiceProvider)
          .signNostrEvent(identityLocalId: active.localId, draft: draft);
    } on VaultLockedException {
      throw const RelayListSaveException(
        'Symudol is locked. Unlock it, then save again.',
      );
    } on VaultException {
      throw const RelayListSaveException("Couldn't sign the relay list.");
    }

    final results = await ref
        .read(relayProfileServiceProvider)
        .publishRelayList(signed, prepared.publishRelays);
    if (!results.values.any((result) => result.accepted)) {
      throw const RelayListSaveException(
        'No relay accepted the update, so your relays have not changed. '
        'Try again.',
      );
    }
    return results;
  }
}
