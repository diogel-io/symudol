import 'dart:convert';

import 'nip46_method.dart';

class Nip46Request {
  final String id;
  final Nip46Method method;
  // Positional params; empty strings already normalized to '' by the parser.
  final List<String> params;

  const Nip46Request({
    required this.id,
    required this.method,
    required this.params,
  });

  static Nip46Request fromDecryptedJson(Map<String, Object?> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      throw const Nip46ParseException('Request is missing a non-empty id field');
    }
    final methodRaw = json['method'] as String?;
    final method = Nip46Method.fromWire(methodRaw);

    final rawParams = json['params'];
    final params = <String>[];
    if (rawParams is List) {
      for (final p in rawParams) {
        params.add(p is String ? p : '');
      }
    }

    return Nip46Request(id: id, method: method, params: params);
  }

  /// Returns the param at [index], or an empty string if out of range.
  String param(int index) => index < params.length ? params[index] : '';

  /// Returns the param at [index] or null if it is empty/missing.
  String? optionalParam(int index) {
    final v = param(index);
    return v.isEmpty ? null : v;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'method': method.wireName,
    'params': params,
  };

  @override
  String toString() => jsonEncode(toJson());
}

class Nip46ParseException implements Exception {
  final String message;
  const Nip46ParseException(this.message);

  @override
  String toString() => 'Nip46ParseException: $message';
}
