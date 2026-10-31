import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../requests/domain/nostr_event_draft.dart';
import '../../requests/domain/signed_nostr_event.dart';
import '../../vault/application/vault_providers.dart';
import '../../vault/domain/vault_exceptions.dart';
import '../data/blossom_client.dart';
import '../data/profile_relay_client.dart';
import '../data/relay_profile_service.dart';
import '../domain/nostr_profile.dart';
import '../domain/profile_content.dart';
import '../domain/profile_image.dart';
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
    this.blossomServers = const [],
    this.uploading,
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

  /// The Blossom servers the identity lists, from the last lookup
  /// (diogel-io/symudol#43).
  final List<String> blossomServers;

  /// The image being uploaded; null when none is.
  final ProfileImageKind? uploading;

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
    ProfileImageKind? uploading,
    bool clearUploading = false,
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
      blossomServers: blossomServers,
      uploading: clearUploading ? null : (uploading ?? this.uploading),
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

/// An image that was not uploaded, with a message for the user.
class ProfileUploadException implements Exception {
  const ProfileUploadException(this.message);

  final String message;

  @override
  String toString() => 'ProfileUploadException: $message';
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
      ProfileLoaded(
        content: null,
        :final searchedRelays,
        :final blossomServers,
      ) =>
        ProfileEditorState(
          phase: ProfileEditorPhase.noProfile,
          searchedRelays: searchedRelays,
          blossomServers: blossomServers,
        ),
      ProfileLoaded(
        :final content,
        :final searchedRelays,
        :final blossomServers,
      ) =>
        () {
          final form = formFromContent(content);
          return ProfileEditorState(
            phase: ProfileEditorPhase.editing,
            form: form,
            saved: form,
            searchedRelays: searchedRelays,
            blossomServers: blossomServers,
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

  /// Where an image is uploaded: the first Blossom server the identity
  /// lists, or else the one chosen in Settings (diogel-io/symudol#43).
  Future<String> uploadServer() async =>
      state.blossomServers.firstOrNull ??
      (await ref.read(profileNetworkSettingsProvider.future)).blossomServer;

  /// Re-encodes [bytes] as a JPEG without metadata, uploads it to [server]
  /// authorised by the active identity, and returns its URL for the
  /// [kind]'s field (diogel-io/symudol#43). The form itself is not changed:
  /// the screen fills the field. Throws [ProfileUploadException].
  Future<String> uploadImage(
    ProfileImageKind kind,
    Uint8List bytes, {
    required String server,
  }) async {
    if (state.uploading != null || state.saving) {
      throw const ProfileUploadException(
        'Wait for the current upload or save to finish.',
      );
    }
    state = state.copyWith(uploading: kind);
    final link = ref.keepAlive();
    try {
      final active = ref.read(vaultControllerProvider).activeIdentity;
      if (active == null || active.publicKey != pubkeyHex) {
        throw const ProfileUploadException(
          'This identity is no longer the active one. '
          'Make it active to upload its images.',
        );
      }

      final Uint8List jpeg;
      try {
        jpeg = await stripAndResize(bytes, maxSide: kind.maxSide);
      } on ProfileImageException catch (error) {
        throw ProfileUploadException(error.message);
      }

      final SignedNostrEvent auth;
      try {
        auth = await ref
            .read(vaultServiceProvider)
            .signNostrEvent(
              identityLocalId: active.localId,
              draft: blossomUploadAuth(blobSha256(jpeg)),
            );
      } on VaultLockedException {
        throw const ProfileUploadException(
          'Symudol is locked. Unlock it, then try again.',
        );
      } on VaultException {
        throw const ProfileUploadException("Couldn't sign the upload.");
      }

      try {
        return await ref
            .read(blossomClientProvider)
            .upload(server: server, bytes: jpeg, auth: auth);
      } on BlossomException catch (error) {
        throw ProfileUploadException(error.message);
      }
    } on ProfileUploadException {
      rethrow;
    } catch (_) {
      throw const ProfileUploadException(
        "Couldn't upload the image. Try again.",
      );
    } finally {
      if (ref.mounted) state = state.copyWith(clearUploading: true);
      link.close();
    }
  }

  /// Checks the form and reads the newest profile, so the user can confirm
  /// the relays a save will publish to before anything is signed. The form
  /// is rebased onto that reading, keeping the user's edits, so the screen
  /// shows what the save will sign. Pass the result to [save]. Throws
  /// [ProfileSaveException] when it can't be saved.
  Future<ProfileLookup> prepareSave() => _guard(() async {
    _validate();
    final latest = await _latest();
    if (ref.mounted) {
      state = state.copyWith(
        saving: false,
        form: _rebased(latest),
        saved: formFromContent(latest.content),
      );
    }
    return latest;
  });

  /// Merges the form into [prepared], or the newest profile read again now,
  /// signs it with the active identity and publishes it. Returns how each
  /// relay answered; throws [ProfileSaveException] when nothing was
  /// published. Afterwards the form holds what was published.
  Future<Map<String, RelayPublishResult>> save({ProfileLookup? prepared}) =>
      _guard(() async {
        _validate();
        final latest = prepared ?? await _latest();
        final form = _rebased(latest);
        final results = await _publish(form, latest);
        if (ref.mounted) {
          state = state.copyWith(
            saving: false,
            form: form,
            saved: form,
            publishResults: results,
          );
        }
        return results;
      });

  /// The newest profile in [latest] with only the fields the user changed
  /// since loading applied, so a save does not revert what another app
  /// changed meanwhile.
  ProfileForm _rebased(ProfileLookup latest) =>
      applyEdits(formFromContent(latest.content), state.saved, state.form);

  /// Runs [step] with the saving flag set, keeping the editor alive until it
  /// ends even if the screen closes, and turns any failure into a
  /// [ProfileSaveException] recorded in [ProfileEditorState.saveError].
  Future<T> _guard<T>(Future<T> Function() step) async {
    state = state.copyWith(saving: true, clearSaveError: true);
    final link = ref.keepAlive();
    try {
      return await step();
    } catch (error) {
      final failure = error is ProfileSaveException
          ? error
          : const ProfileSaveException("Couldn't save the profile. Try again.");
      if (ref.mounted) {
        state = state.copyWith(saving: false, saveError: failure.message);
      }
      throw failure;
    } finally {
      link.close();
    }
  }

  void _validate() {
    final errors = validateProfileForm(state.form);
    state = state.copyWith(fieldErrors: errors);
    if (errors.isNotEmpty) {
      throw const ProfileSaveException('Fix the highlighted fields first.');
    }
  }

  /// The newest profile, read again so fields another app set since the form
  /// was loaded are kept. With no relay answering, a save could drop fields,
  /// so refuse.
  Future<ProfileLookup> _latest() async {
    final ProfileLookup latest;
    try {
      latest = await ref
          .read(relayProfileServiceProvider)
          .fetchProfile(pubkeyHex);
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
    return latest;
  }

  Future<Map<String, RelayPublishResult>> _publish(
    ProfileForm form,
    ProfileLookup latest,
  ) async {
    final service = ref.read(relayProfileServiceProvider);

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
            blossomServers: latest.blossomServers,
          ),
        );
    return results;
  }

  /// How far ahead of this phone's clock an event can be dated: relays
  /// commonly refuse events more than about 15 minutes in the future.
  static const Duration _maxAhead = Duration(minutes: 10);

  /// Now, or a second after [current] when that is not earlier: a
  /// replaceable event must be newer than the one it replaces, or relays
  /// keep the old one. Throws [ProfileSaveException] when that would date
  /// the event further ahead than relays accept, because then no update can
  /// replace [current] (diogel-io/symudol#118 review).
  static DateTime _createdAfter(DateTime? current) {
    final now = DateTime.fromMillisecondsSinceEpoch(
      DateTime.now().millisecondsSinceEpoch ~/ 1000 * 1000,
    );
    if (current == null || now.isAfter(current)) return now;
    final next = current.add(const Duration(seconds: 1));
    if (next.isAfter(now.add(_maxAhead))) {
      throw const ProfileSaveException(
        "This identity's newest profile is dated ahead of this phone's clock, "
        'so relays would keep it over an update. Check the date and time on '
        'this phone, and in the app that published that profile.',
      );
    }
    return next;
  }
}
