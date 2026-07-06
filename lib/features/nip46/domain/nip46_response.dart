import 'dart:convert';

class Nip46Response {
  final String id;
  final String? result;
  final String? error;

  const Nip46Response({required this.id, this.result, this.error})
    : assert(
        (result != null) != (error != null),
        'Exactly one of result or error must be non-null',
      );

  factory Nip46Response.ok(String id, String result) =>
      Nip46Response(id: id, result: result);

  factory Nip46Response.error(String id, String error) =>
      Nip46Response(id: id, error: error);

  Map<String, Object?> toJson() => {'id': id, 'result': result, 'error': error};

  @override
  String toString() => jsonEncode(toJson());
}
