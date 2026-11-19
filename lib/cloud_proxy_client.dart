import 'package:http/http.dart' as http;

/// Test builds only: keep the Supabase origin/session identity unchanged.
class CloudProxyClient extends http.BaseClient {
  CloudProxyClient({http.Client? inner}) : _inner = inner ?? http.Client();
  static const enabled = bool.fromEnvironment(
    'TP_CLOUD_NETLIFY_TEST',
    defaultValue: false,
  );
  static const upstream = 'https://hylxyyzwsppaufzmqcbg.supabase.co';
  static const proxy = 'https://rainbow-trifle-8aa5a1.netlify.app';
  static const paths = [
    '/auth/v1/',
    '/rest/v1/',
    '/storage/v1/',
    '/functions/v1/',
  ];
  final http.Client _inner;
  static http.Client? forBuild() => enabled ? CloudProxyClient() : null;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final uri = request.url;
    if (uri.origin != upstream || !paths.any((p) => uri.path.startsWith(p))) {
      return _inner.send(request);
    }
    // Uri.replace leaves the existing encoded path/query untouched.
    final destination = uri.replace(
      scheme: 'https',
      host: Uri.parse(proxy).host,
    );
    return _inner.send(_ForwardRequest(request, destination));
  }

  @override
  void close() => _inner.close();
}

class _ForwardRequest extends http.BaseRequest {
  _ForwardRequest(this.source, Uri url) : super(source.method, url) {
    // MultipartRequest finalization adds its boundary header before we copy it.
    _body = source.finalize();
    headers.addAll(source.headers);
    headers.removeWhere((key, _) => key.toLowerCase() == 'host');
    headers['Cache-Control'] = 'no-store';
    contentLength = source.contentLength;
    followRedirects = false;
    persistentConnection = source.persistentConnection;
  }
  final http.BaseRequest source;
  late final http.ByteStream _body;
  @override
  http.ByteStream finalize() {
    super.finalize();
    return _body;
  }
}
