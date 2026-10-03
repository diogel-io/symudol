import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android manifest exposes nostrsigner scheme via bridge activity', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:name=".MainActivity"'));
    expect(manifest, contains('android:launchMode="singleTop"'));
    expect(manifest, isNot(contains('android:taskAffinity=""')));
    expect(manifest, contains('android:name=".Nip55BridgeActivity"'));
    expect(manifest, contains('android:exported="true"'));
    expect(
      manifest,
      contains(
        'android:name=".Nip55BridgeActivity"\n            android:exported="true"\n            android:launchMode="singleTop"',
      ),
    );
    expect(manifest, contains('android.intent.action.VIEW'));
    expect(manifest, contains('android.intent.category.DEFAULT'));
    expect(manifest, contains('android.intent.category.BROWSABLE'));
    expect(manifest, contains('android:scheme="@string/scheme_nostrsigner"'));

    final strings = File(
      'android/app/src/main/res/values/strings.xml',
    ).readAsStringSync();
    expect(
      strings,
      contains('<string name="scheme_nostrsigner">nostrsigner</string>'),
    );
    expect(manifest, contains('android:theme="@style/Nip55BridgeTheme"'));

    final lightStyles = File(
      'android/app/src/main/res/values/styles.xml',
    ).readAsStringSync();
    final nightStyles = File(
      'android/app/src/main/res/values-night/styles.xml',
    ).readAsStringSync();
    expect(lightStyles, contains('style name="Nip55BridgeTheme"'));
    expect(lightStyles, contains('android:windowIsTranslucent'));
    expect(nightStyles, contains('style name="Nip55BridgeTheme"'));
    expect(nightStyles, contains('android:windowIsTranslucent'));
  });

  test('manifest advertises SIGN_MESSAGE after implementation', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(manifest, contains(r'${applicationId}.SIGN_MESSAGE'));
  });

  test('production manifest does not declare Amber package identity or authorities', () {
    // Workstream B / Product Decision: production Diogel must not impersonate Amber.
    // Provider authority aliases for com.greenart7c3.nostrsigner are only permitted
    // in an explicitly gated compatibility build flavor, not in the default manifest.
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(
      manifest,
      isNot(contains('com.greenart7c3.nostrsigner')),
      reason:
          'Production manifest must not declare Amber package identity or provider authorities. '
          'Authority aliases conflict with Amber when both apps are installed. '
          'See documentation/nip55-signer-discovery.md §3c.',
    );
  });

  test('signer discovery documentation exists and covers required topics', () {
    final doc = File(
      'documentation/nip55-signer-discovery.md',
    ).readAsStringSync();

    // NIP-55 intended discovery flow
    expect(doc, contains('queryIntentActivities'));
    expect(doc, contains('nostrsigner:'));
    // Diogel production identity documented
    expect(doc, contains('io.diogel.symudol'));
    // Platform constraints documented
    expect(
      doc,
      contains('Provider Authority Aliases Do Not Satisfy PackageManager'),
    );
    expect(doc, contains('Package-Targeted Intents Cannot Resolve'));
    expect(doc, contains('Amber Authority Aliases Conflict'));
    // Primal compatibility matrix present
    expect(doc, contains('Stock Diogel result'));
    // Manual verification commands present
    expect(doc, contains('adb shell cmd package query-intent-activities'));
    // Upstream recommendation for Primal present
    expect(doc, contains('Recommended change'));
    // Explicit statement that stock Primal cannot discover stock Diogel
    expect(
      doc,
      contains('stock Primal cannot discover stock Diogel'),
    );
  });

  test('client discovery reference document exists', () {
    final doc = File(
      'documentation/nip55-client-discovery-reference.md',
    ).readAsStringSync();

    // Shows intent-based discovery, not hardcoded package names
    expect(doc, contains('queryIntentActivities'));
    expect(doc, contains('Never hardcode a package name'));
    // Shows ContentProvider URI construction from discovered package
    expect(doc, contains(r'content://$signerPackage'));
    // Covers null and rejected cursor handling
    expect(doc, contains('null'));
    expect(doc, contains('rejected'));
    // Covers foreground Intent fallback
    expect(doc, contains('fallback'));
  });
}
