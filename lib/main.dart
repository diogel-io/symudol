import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';

void main() {
  dev.log('App starting main()', name: 'Diogel');
  runApp(
    const ProviderScope(
      child: DiogelApp(),
    ),
  );
}
