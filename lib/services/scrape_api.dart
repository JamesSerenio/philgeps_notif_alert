import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class ScrapeApi {
  ScrapeApi({
    required this.baseUrl,
    required this.accessToken,
    http.Client? client,
    Future<void> Function(Duration)? wait,
  })  : _client = client ?? http.Client(),
        _wait = wait ?? Future<void>.delayed;

  final String baseUrl;
  final Future<String> Function() accessToken;
  final http.Client _client;
  final Future<void> Function(Duration) _wait;

  Future<Map<String, dynamic>> _request(String path,
      {bool post = false}) async {
    final headers = {'Authorization': 'Bearer ${await accessToken()}'};
    final uri = Uri.parse('$baseUrl$path');
    final response = await (post
            ? _client.post(uri, headers: headers)
            : _client.get(uri, headers: headers))
        .timeout(const Duration(seconds: 30));
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          body['error'] ?? 'Railway returned ${response.statusCode}');
    }
    return body;
  }

  Future<Map<String, dynamic>> check() async {
    final request = await _request('/check', post: true);
    final requestedRun = request['run'] as Map<String, dynamic>?;
    if (requestedRun == null)
      throw Exception('Railway did not return a scraping run.');
    final id = requestedRun['id'];
    // Never infer success from the initial acceptance or a busy response.
    for (var attempt = 0; attempt < 300; attempt++) {
      final state = await _request('/check/status');
      final run = state['run'] as Map<String, dynamic>?;
      if (run == null || run['id'] != id) {
        throw Exception(
            'The scraping run changed. Retry to check its current status.');
      }
      if (run['status'] == 'failed')
        throw Exception(run['error'] ?? 'Scraping failed.');
      if (run['status'] == 'completed') return state;
      await _wait(const Duration(seconds: 5));
    }
    throw TimeoutException(
        'The scrape is taking longer than expected. Retry to check its status.');
  }

  void close() => _client.close();
}
