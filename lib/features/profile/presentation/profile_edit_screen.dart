import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/route_pop.dart';
import '../../../theme/tokens.dart';
import '../../accounts/presentation/widgets/load_profile_action.dart';
import '../../identity/domain/vault_identity.dart';
import '../application/profile_editor.dart';
import '../application/profile_providers.dart';
import '../data/profile_image_picker.dart';
import '../data/profile_relay_client.dart';
import '../domain/profile_content.dart';
import '../domain/profile_image.dart';
import '../domain/profile_relays.dart';

/// Labels for the text fields, by kind 0 key.
const Map<String, String> _labels = {
  'name': 'Name',
  'display_name': 'Display name',
  'about': 'About',
  'website': 'Website',
  'picture': 'Picture URL',
  'banner': 'Banner URL',
  'nip05': 'NIP-05 identifier',
  'lud16': 'Lightning address',
};

/// The fields an image can be uploaded for, by kind 0 key.
final Map<String, ProfileImageKind> _uploadKinds = {
  for (final kind in ProfileImageKind.values) kind.field: kind,
};

/// Edits and publishes the active identity's profile (diogel-io/symudol#41).
/// Opening it asks before reaching any relay (diogel-io/symudol#83).
class ProfileEditScreen extends ConsumerStatefulWidget {
  const ProfileEditScreen({super.key, required this.identity});

  final VaultIdentity identity;

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  final Map<String, TextEditingController> _text = {
    for (final key in profileTextFields) key: TextEditingController(),
  };
  final Map<String, TextEditingController> _birthday = {
    for (final part in const ['year', 'month', 'day'])
      part: TextEditingController(),
  };
  bool _showImages = false;

  String get _pubkey => widget.identity.publicKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _askThenLoad());
  }

  @override
  void dispose() {
    for (final controller in [..._text.values, ..._birthday.values]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _askThenLoad() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => const LoadProfileDialog(),
    );
    if (!mounted) return;
    if (confirmed != true) {
      // A lock closes the dialog and this screen together (#123).
      popIfCurrent(context);
      return;
    }
    await _load();
  }

  Future<void> _load() async {
    final notifier = ref.read(profileEditorProvider(_pubkey).notifier);
    await notifier.load();
    if (mounted) _fill(ref.read(profileEditorProvider(_pubkey)).form);
  }

  void _fill(ProfileForm form) {
    for (final key in profileTextFields) {
      _text[key]!.text = form[key];
    }
    _birthday['year']!.text = form.birthday.year;
    _birthday['month']!.text = form.birthday.month;
    _birthday['day']!.text = form.birthday.day;
  }

  void _changed() {
    final current = ref.read(profileEditorProvider(_pubkey)).form;
    var form = current.copyWith(
      birthday: ProfileBirthday(
        year: _birthday['year']!.text,
        month: _birthday['month']!.text,
        day: _birthday['day']!.text,
      ),
    );
    for (final key in profileTextFields) {
      form = form.withText(key, _text[key]!.text);
    }
    ref.read(profileEditorProvider(_pubkey).notifier).updateForm(form);
  }

  Future<void> _save() async {
    final editor = ref.read(profileEditorProvider(_pubkey).notifier);
    try {
      // Read the newest profile first, so the dialog names the relays this
      // save will publish to, and the save uses that same reading.
      final prepared = await editor.prepareSave();
      if (!mounted) return;
      // The form now holds what the save will sign: the newest profile with
      // the user's edits applied.
      _fill(ref.read(profileEditorProvider(_pubkey)).form);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => _PublishDialog(
          identityName: widget.identity.displayName ?? 'this identity',
          relays: prepared.publishRelays,
        ),
      );
      if (confirmed != true || !mounted) return;

      final results = await editor.save(prepared: prepared);
      if (!mounted) return;
      _fill(ref.read(profileEditorProvider(_pubkey)).form);
      await showModalBottomSheet<void>(
        context: context,
        builder: (context) => _PublishResultsSheet(results: results),
      );
    } on ProfileSaveException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: DiogelColors.stateError,
        ),
      );
    }
  }

  /// Picks or takes an image, confirms the server, uploads it without its
  /// metadata and puts its URL in [kind]'s field (diogel-io/symudol#43).
  /// Nothing is published until the user saves.
  Future<void> _upload(ProfileImageKind kind) async {
    final source = await showModalBottomSheet<ProfileImageSource>(
      context: context,
      builder: (context) => const _ImageSourceSheet(),
    );
    if (source == null || !mounted) return;

    final Uint8List? bytes;
    try {
      bytes = await ref
          .read(pickingProfileImageProvider.notifier)
          .during(() => ref.read(profileImagePickerProvider).pick(source));
    } on PlatformException {
      if (mounted) {
        _showError(
          source == ProfileImageSource.camera
              ? "Couldn't open the camera."
              : "Couldn't open your photos.",
        );
      }
      return;
    }
    if (bytes == null || !mounted) return;

    final editor = ref.read(profileEditorProvider(_pubkey).notifier);
    final String server;
    try {
      server = await editor.uploadServer();
    } catch (_) {
      if (mounted) _showError("Couldn't read the media server setting.");
      return;
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _UploadDialog(host: Uri.parse(server).host),
    );
    if (confirmed != true || !mounted) return;

    try {
      final url = await editor.uploadImage(kind, bytes, server: server);
      if (!mounted) return;
      _text[kind.field]!.text = url;
      _changed();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Image uploaded. Save to publish it on your profile.'),
        ),
      );
    } on ProfileUploadException catch (error) {
      if (mounted) _showError(error.message);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: DiogelColors.stateError,
      ),
    );
  }

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Your edits to this profile have not been saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final editor = ref.watch(profileEditorProvider(_pubkey));
    final editing = editor.phase == ProfileEditorPhase.editing;

    return PopScope(
      canPop: !(editing && editor.dirty),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Edit profile'),
          actions: [
            if (editing)
              TextButton(
                onPressed: editor.saving || editor.uploading != null
                    ? null
                    : _save,
                child: const Text('Save'),
              ),
          ],
        ),
        body: switch (editor.phase) {
          // Nothing is loading while the user decides whether to load.
          ProfileEditorPhase.notLoaded => const SizedBox.shrink(),
          ProfileEditorPhase.loading => const Center(
            child: CircularProgressIndicator(),
          ),
          ProfileEditorPhase.loadFailed => _LoadFailed(onRetry: _load),
          ProfileEditorPhase.noProfile => _NoProfile(
            searchedRelays: editor.searchedRelays,
            onCreate: () => ref
                .read(profileEditorProvider(_pubkey).notifier)
                .confirmCreate(),
          ),
          ProfileEditorPhase.editing => _buildForm(editor),
        },
      ),
    );
  }

  Widget _buildForm(ProfileEditorState editor) {
    final form = editor.form;
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.all(DiogelSpacing.space4),
          children: [
            _Preview(
              form: form,
              showImages: _showImages,
              onShowImages: () => setState(() => _showImages = true),
            ),
            const SizedBox(height: DiogelSpacing.space6),
            for (final key in profileTextFields) ...[
              TextField(
                controller: _text[key],
                onChanged: (_) => _changed(),
                maxLines: key == 'about' ? 5 : 1,
                minLines: 1,
                keyboardType: switch (key) {
                  'website' || 'picture' || 'banner' => TextInputType.url,
                  'nip05' || 'lud16' => TextInputType.emailAddress,
                  'about' => TextInputType.multiline,
                  _ => TextInputType.text,
                },
                decoration: InputDecoration(
                  labelText: _labels[key],
                  errorText: editor.fieldErrors[key],
                  suffixIcon: switch (_uploadKinds[key]) {
                    final ProfileImageKind kind => _UploadButton(
                      kind: kind,
                      uploading: editor.uploading == kind,
                      onPressed: editor.uploading != null || editor.saving
                          ? null
                          : () => _upload(kind),
                    ),
                    null => null,
                  },
                ),
              ),
              const SizedBox(height: DiogelSpacing.space4),
            ],
            Text('Birthday', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: DiogelSpacing.space2),
            Row(
              children: [
                for (final (part, label) in const [
                  ('year', 'Year'),
                  ('month', 'Month'),
                  ('day', 'Day'),
                ]) ...[
                  Expanded(
                    child: TextField(
                      controller: _birthday[part],
                      onChanged: (_) => _changed(),
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: label),
                    ),
                  ),
                  if (part != 'day')
                    const SizedBox(width: DiogelSpacing.space3),
                ],
              ],
            ),
            if (editor.fieldErrors['birthday'] case final String error)
              Padding(
                padding: const EdgeInsets.only(top: DiogelSpacing.space2),
                child: Text(
                  error,
                  style: const TextStyle(color: DiogelColors.stateError),
                ),
              ),
            const SizedBox(height: DiogelSpacing.space4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('This is a bot'),
              subtitle: const Text('Marks the profile as automated (NIP-24).'),
              value: form.bot,
              onChanged: (value) => ref
                  .read(profileEditorProvider(_pubkey).notifier)
                  .updateForm(form.copyWith(bot: value)),
            ),
            if (editor.saveError case final String error)
              Padding(
                padding: const EdgeInsets.only(top: DiogelSpacing.space4),
                child: Text(
                  error,
                  style: const TextStyle(color: DiogelColors.stateError),
                ),
              ),
            const SizedBox(height: DiogelSpacing.space8),
          ],
        ),
        if (editor.saving)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x88000000),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DiogelSpacing.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Couldn't reach the relays, so the profile can't be edited now.",
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: DiogelSpacing.space4),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

/// No relay holds a profile: list the relays that answered, and ask before
/// creating one, which could hide a profile held elsewhere.
class _NoProfile extends StatelessWidget {
  const _NoProfile({required this.searchedRelays, required this.onCreate});

  final List<String> searchedRelays;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(DiogelSpacing.space6),
      children: [
        Text('No profile found', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: DiogelSpacing.space3),
        const Text('None of these relays holds a profile for this identity:'),
        const SizedBox(height: DiogelSpacing.space2),
        for (final relay in searchedRelays) Text(relayHost(relay)),
        const SizedBox(height: DiogelSpacing.space4),
        const Text(
          'If this identity has a profile on other relays, creating a new one '
          'here may replace it in apps that read these relays.',
        ),
        const SizedBox(height: DiogelSpacing.space6),
        FilledButton(
          onPressed: onCreate,
          child: const Text('Create a new profile'),
        ),
      ],
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({
    required this.form,
    required this.showImages,
    required this.onShowImages,
  });

  final ProfileForm form;
  final bool showImages;
  final VoidCallback onShowImages;

  @override
  Widget build(BuildContext context) {
    final name = form['display_name'].trim().isNotEmpty
        ? form['display_name'].trim()
        : form['name'].trim();
    final picture = form['picture'].trim();
    final banner = form['banner'].trim();
    final hasImages = picture.isNotEmpty || banner.isNotEmpty;

    Widget image(String url, double height, {double? width}) => Image.network(
      url,
      height: height,
      width: width,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => SizedBox(
        height: height,
        width: width,
        child: const Icon(Icons.broken_image, color: DiogelColors.textTertiary),
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: DiogelColors.surfaceBase,
        borderRadius: BorderRadius.circular(DiogelRadius.large),
        border: Border.all(color: DiogelColors.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showImages && banner.isNotEmpty)
            image(banner, 96, width: double.infinity),
          Padding(
            padding: const EdgeInsets.all(DiogelSpacing.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: DiogelColors.surfaceContainerHigh,
                      child: ClipOval(
                        child: showImages && picture.isNotEmpty
                            ? image(picture, 48, width: 48)
                            : const Icon(
                                Icons.person,
                                color: DiogelColors.textSecondary,
                              ),
                      ),
                    ),
                    const SizedBox(width: DiogelSpacing.space3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name.isEmpty ? 'No name' : name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (form['nip05'].trim().isNotEmpty)
                            Text(
                              form['nip05'].trim(),
                              style: const TextStyle(
                                color: DiogelColors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (form.bot) const Chip(label: Text('Bot')),
                  ],
                ),
                if (form['about'].trim().isNotEmpty) ...[
                  const SizedBox(height: DiogelSpacing.space3),
                  Text(form['about'].trimRight()),
                ],
                if (form['lud16'].trim().isNotEmpty) ...[
                  const SizedBox(height: DiogelSpacing.space2),
                  Text(
                    '⚡ ${form['lud16'].trim()}',
                    style: const TextStyle(color: DiogelColors.textSecondary),
                  ),
                ],
                if (hasImages && !showImages) ...[
                  const SizedBox(height: DiogelSpacing.space3),
                  // Loading an image tells its host this device's IP address,
                  // so the preview shows images only when asked (#83).
                  TextButton.icon(
                    onPressed: onShowImages,
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('Show images'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Asks before signing and publishing, naming the relays.
/// The upload button in an image URL field, or a spinner while uploading.
class _UploadButton extends StatelessWidget {
  const _UploadButton({
    required this.kind,
    required this.uploading,
    required this.onPressed,
  });

  final ProfileImageKind kind;
  final bool uploading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (uploading) {
      return const Padding(
        padding: EdgeInsets.all(DiogelSpacing.space3),
        child: SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return IconButton(
      tooltip: kind == ProfileImageKind.picture
          ? 'Upload picture'
          : 'Upload banner',
      icon: const Icon(Icons.upload_outlined),
      onPressed: onPressed,
    );
  }
}

/// Asks where the image comes from.
class _ImageSourceSheet extends StatelessWidget {
  const _ImageSourceSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from photos'),
            onTap: () => Navigator.of(context).pop(ProfileImageSource.photos),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.of(context).pop(ProfileImageSource.camera),
          ),
        ],
      ),
    );
  }
}

/// Confirms the upload and names the server before anything is sent.
class _UploadDialog extends StatelessWidget {
  const _UploadDialog({required this.host});

  final String host;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Upload to $host?'),
      content: const Text(
        'The image is re-encoded first, so its location and camera details '
        'are removed. Anyone with the link can see it, even if you do not '
        'save the profile.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Upload'),
        ),
      ],
    );
  }
}

class _PublishDialog extends StatelessWidget {
  const _PublishDialog({required this.identityName, required this.relays});

  final String identityName;
  final List<String> relays;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sign and publish?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Symudol will sign this profile with $identityName and publish '
              'it to ${relays.length} relays:',
            ),
            const SizedBox(height: DiogelSpacing.space2),
            for (final relay in relays) Text(relayHost(relay)),
            const SizedBox(height: DiogelSpacing.space3),
            const Text('Anyone can read a published profile.'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Sign and publish'),
        ),
      ],
    );
  }
}

/// How each relay answered a published profile.
class _PublishResultsSheet extends StatelessWidget {
  const _PublishResultsSheet({required this.results});

  final Map<String, RelayPublishResult> results;

  @override
  Widget build(BuildContext context) {
    final accepted = results.values.where((result) => result.accepted).length;
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(DiogelSpacing.space4),
        children: [
          Text(
            'Profile published',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: DiogelSpacing.space2),
          Text('$accepted of ${results.length} relays accepted it.'),
          const SizedBox(height: DiogelSpacing.space3),
          for (final MapEntry(key: relay, value: result) in results.entries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                switch (result.status) {
                  RelayPublishStatus.accepted => Icons.check_circle,
                  RelayPublishStatus.rejected => Icons.cancel,
                  RelayPublishStatus.noAnswer => Icons.help_outline,
                },
                color: switch (result.status) {
                  RelayPublishStatus.accepted => DiogelColors.stateSuccess,
                  RelayPublishStatus.rejected => DiogelColors.stateError,
                  RelayPublishStatus.noAnswer => DiogelColors.textTertiary,
                },
              ),
              title: Text(relayHost(relay)),
              subtitle: Text(
                switch (result.status) {
                      RelayPublishStatus.accepted => 'Accepted',
                      RelayPublishStatus.rejected => 'Rejected',
                      RelayPublishStatus.noAnswer => 'No answer',
                    } +
                    (result.message.isEmpty ? '' : ': ${result.message}'),
              ),
            ),
        ],
      ),
    );
  }
}
