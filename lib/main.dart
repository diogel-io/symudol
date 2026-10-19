import 'package:symudol/app/diogel_log.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';

void main() {
  diogelLog('App starting main()');
  runApp(
    const ProviderScope(
      child: DiogelApp(),
    ),
  );
}
