import 'dart:async';
import 'package:symudol/app/utils/concurrency_utils.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  ConcurrencyUtils.useSynchronousTasks = true;
  await testMain();
}
