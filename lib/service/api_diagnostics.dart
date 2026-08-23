import 'dart:convert';

const _redacted = '<redacted>';
const _sensitiveKeys = {
  'authorization',
  'api_key',
  'apikey',
  'installation_token',
  'access_token',
  'refresh_token',
  'token',
};

String formatApiRequest({
  required String method,
  required String url,
  required Map<String, String> headers,
  Object? payload,
}) {
  return '[API] $method $url\n'
      'Headers: ${_formatValue(headers)}\n'
      'Payload: ${_formatValue(payload)}';
}

String formatApiResponse({
  required String method,
  required String url,
  required int statusCode,
  required String body,
}) {
  return '[API] $method $url -> $statusCode\n'
      'Response: ${_formatResponseBody(body)}';
}

String _formatResponseBody(String body) {
  if (body.isEmpty) return '<empty>';
  try {
    return _formatValue(jsonDecode(body));
  } on FormatException {
    return body;
  }
}

String _formatValue(Object? value) {
  if (value == null) return '<none>';
  return jsonEncode(_sanitize(value));
}

Object? _sanitize(Object? value, [String? key]) {
  if (key != null && _sensitiveKeys.contains(key.toLowerCase())) {
    return _redacted;
  }
  if (value is Map) {
    return value.map(
      (entryKey, entryValue) => MapEntry(
        entryKey.toString(),
        _sanitize(entryValue, entryKey.toString()),
      ),
    );
  }
  if (value is Iterable) {
    return value.map((item) => _sanitize(item)).toList(growable: false);
  }
  return value;
}
