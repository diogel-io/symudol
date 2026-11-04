import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Symudol's privacy policy on the website (#39). The Play listing links to the
/// same address, so it must not move.
final symudolPrivacyPolicyUrl = Uri.parse('https://diogel.io/privacy/symudol');

/// Opens [uri] outside Symudol, returning whether a browser took it.
typedef ExternalLinkLauncher = Future<bool> Function(Uri uri);

/// The browser, by default; tests override it.
final externalLinkLauncherProvider = Provider<ExternalLinkLauncher>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// Opens the privacy policy, or says where to find it when no browser can.
Future<void> openPrivacyPolicy(BuildContext context, WidgetRef ref) async {
  final launch = ref.read(externalLinkLauncherProvider);
  final messenger = ScaffoldMessenger.of(context);
  var opened = false;
  try {
    opened = await launch(symudolPrivacyPolicyUrl);
  } on Exception {
    opened = false;
  }
  if (!opened) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          "Couldn't open a browser. The privacy policy is at "
          '${symudolPrivacyPolicyUrl.host}${symudolPrivacyPolicyUrl.path}',
        ),
      ),
    );
  }
}
