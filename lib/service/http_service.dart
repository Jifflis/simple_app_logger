import 'package:http/http.dart' as http;

abstract class HttpService {
  Future<http.Response?> get({required String url});
}
