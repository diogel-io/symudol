import 'dart:async';
import 'package:android_diogel/app/utils/concurrency_utils.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  ConcurrencyUtils.useSynchronousTasks = true;
  await testMain();
}
