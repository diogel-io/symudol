import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../requests/domain/nostr_event_draft.dart';
import '../../requests/domain/signed_nostr_event.dart';
import '../../vault/application/vault_providers.dart';
import '../../vault/domain/vault_exceptions.dart';
import '../data/profile_relay_client.dart';
import '../data/relay_profile_service.dart';
import '../domain/nostr_profile.dart';
import '../domain/profile_content.dart';
import '../domain/profile_load_state.dart';
import 'profile_providers.dart';

/// Where the profile editor stands.
enum ProfileEditorPhase { notLoaded, loading, loadFailed, noProfile, editing }

/// The profile editor's state (diogel-io/symudol#41).
class ProfileEditorState {
  const ProfileEditorState({
    this.phase = ProfileEditorPhase.notLoaded,
    this.form = const ProfileForm(),
    this.saved = const ProfileForm(),
    this.searchedRelays = const [],
    this.createConfirmed = false,
    this.saving = false,
    this.saveError,
    this.fieldErrors = const {},
    this.publishResults,
  });

  final ProfileEditorPhase phase;

  /// The values being edited.
  final ProfileForm form;

  /// The values as last loaded or saved, to tell whether there are edits.
  final ProfileForm saved;

  /// The relays that answered the last lookup.
  final List<String> searchedRelays;

  /// Whether the user has confirmed creating a profile where none was found.
  final bool createConfirmed;

  final bool saving;

  /// Why the last save failed; null when it did not.
  final String? saveError;

  /// Field problems that stopped the last save, by kind 0 key.
  final Map<String, String> fieldErrors;

  /// How each relay answered the last save; null before any save.
  final Map<String, RelayPublishResult>? publishResults;

  bool get dirty => form != saved;

  ProfileEditorState copyWith({
    ProfileEditorPhase? phase,
    ProfileForm? form,
    ProfileForm? saved,
    List<String>? searchedRelays,
    bool? createConfirmed,
    bool? saving,
    String? saveError,
    bool clearSaveError = false,
    Map<String, String>? fieldErrors,
    Map<String, RelayPublishResult>? publishResults,
  }) {
    return ProfileEditorState(
      phase: phase ?? this.phase,
      form: form ?? this.form,
      saved: saved ?? this.saved,
      searchedRelays: searchedRelays ?? this.searchedRelays,
      createConfirmed: createConfirmed ?? this.createConfirmed,
      saving: saving ?? this.saving,
      saveError: clearSaveError ? null : (saveError ?? this.saveError),
      fieldErrors: fieldErrors ?? this.fieldErrors,
      publishResults: publishResults ?? this.publishResults,
    );
  }
}

/// A save that did not publish, with a message for the user.
class ProfileSaveException implements Exception {
  const ProfileSaveException(this.message);

  final String message;

  @override
  String toString() => 'ProfileSaveException: $message';
}

/// The profile editor for one public key, which must be the active
/// identity's to save.
final profileEditorProvider = NotifierProvider.autoDispose
    .family<ProfileEditorNotifier, ProfileEditorState, String>(
      ProfileEditorNotifier.new,
    );

/// Loads the identity's profile into a form and saves it: the form is merged
/// into the newest kind 0 read again at save time, so every field the form
/// does not edit is kept, then signed with the vault and published
/// (diogel-io/symudol#41). Like every profile fetch, [load] and [save] reach
/// relays, so call them only after the user has asked (diogel-io/symudol#83).
class ProfileEditorNotifier extends Notifier<ProfileEditorState> {
  ProfileEditorNotifier(this.pubkeyHex);

  final String pubkeyHex;

  @override
  ProfileEditorState build() => const ProfileEditorState();

  /// Looks the profile up and fills the form from it.
  Future<void> load() async {
    state = state.copyWith(phase: ProfileEditorPhase.loading);
    final result = await ref
        .read(nostrProfileProvider(pubkeyHex).notifier)
        .load();
    if (!ref.mounted) return;
    state = switch (result) {
      ProfileLoaded(content: null, :final searchedRelays) => ProfileEditorState(
        phase: ProfileEditorPhase.noProfile,
        searchedRelays: searchedRelays,
      ),
      ProfileLoaded(:final content, :final searchedRelays) => () {
        final form = formFromContent(content);
        return ProfileEditorState(
          phase: ProfileEditorPhase.editing,
          form: form,
          saved: form,
          searchedRelays: searchedRelays,
        );
      }(),
      _ => const ProfileEditorState(phase: ProfileEditorPhase.loadFailed),
    };
  }

  /// Confirms creating a new profile where no relay held one.
  void confirmCreate() {
    state = state.copyWith(
      phase: ProfileEditorPhase.editing,
      createConfirmed: true,
    );
  }

  void updateForm(ProfileForm form) {
    state = state.copyWith(form: form);
  }

  /// Merges the form into the newest profile, signs it with the active
  /// identity and publishes it. Returns how each relay answered; throws
  /// [ProfileSaveException] when nothing was published.
  Future<Map<String, RelayPublishResult>> save() async {
    final errors = validateProfileForm(state.form);
    if (errors.isNotEmpty) {
      state = state.copyWith(fieldErrors: errors, clearSaveError: true);
      throw const ProfileSaveException('Fix the highlighted fields first.');
    }
    state = state.copyWith(
      saving: true,
      fieldErrors: const {},
      clearSaveError: true,
    );
    try {
      final results = await _save(state.form);
      if (ref.mounted) {
        state = state.copyWith(
          saving: false,
          saved: state.form,
          publishResults: results,
        );
      }
      return results;
    } on ProfileSaveException catch (error) {
      if (ref.mounted) {
        state = state.copyWith(saving: false, saveError: error.message);
      }
      rethrow;
    }
  }

  Future<Map<String, RelayPublishResult>> _save(ProfileForm form) async {
    final service = ref.read(relayProfileServiceProvider);

    // Read the newest profile again, so fields another app set since the
    // form was loaded are kept. With no relay answering, a save could drop
    // fields, so refuse.
    final ProfileLookup latest;
    try {
      latest = await service.fetchProfile(pubkeyHex);
    } on ProfileFetchException {
      throw const ProfileSaveException(
        "No relay answered, so saving could drop fields set in other apps. "
        'Your profile has not changed. Try again.',
      );
    }
    if (latest.content == null && !state.createConfirmed) {
      throw const ProfileSaveException(
        'No relay holds a profile for this identity now. '
        'Load it again to create a new one.',
      );
    }

    final active = ref.read(vaultControllerProvider).activeIdentity;
    if (active == null || active.publicKey != pubkeyHex) {
      throw const ProfileSaveException(
        'This identity is no longer the active one. '
        'Make it active to save its profile.',
      );
    }

    final content = mergeProfile(latest.content, form);
    final draft = NostrEventDraft(
      kind: 0,
      content: jsonEncode(content),
      tags: const [],
      createdAt: _createdAfter(latest.createdAt),
    );

    final SignedNostrEvent signed;
    try {
      signed = await ref
          .read(vaultServiceProvider)
          .signNostrEvent(identityLocalId: active.localId, draft: draft);
    } on VaultLockedException {
      throw const ProfileSaveException(
        'Symudol is locked. Unlock it, then save again.',
      );
    } on VaultException {
      throw const ProfileSaveException("Couldn't sign the profile.");
    }

    final results = await service.publishProfile(signed, latest.publishRelays);
    if (!results.values.any((result) => result.accepted)) {
      throw const ProfileSaveException(
        'No relay accepted the update, so your profile has not changed. '
        'Try again.',
      );
    }

    ref
        .read(nostrProfileProvider(pubkeyHex).notifier)
        .published(
          ProfileLoaded(
            NostrProfile.fromJson(content),
            content: content,
            createdAt: draft.createdAt,
            searchedRelays: latest.searchedRelays,
            publishRelays: latest.publishRelays,
          ),
        );
    return results;
  }

  /// Now, or a second after [current] when that is not earlier: a
  /// replaceable event must be newer than the one it replaces, or relays
  /// keep the old one.
  static DateTime _createdAfter(DateTime? current) {
    final now = DateTime.fromMillisecondsSinceEpoch(
      DateTime.now().millisecondsSinceEpoch ~/ 1000 * 1000,
    );
    if (current == null || now.isAfter(current)) return now;
    return current.add(const Duration(seconds: 1));
  }
}
