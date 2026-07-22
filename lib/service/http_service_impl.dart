import 'package:http/http.dart' as http;

import 'http_service.dart';
import 'http_util.dart';

class HttpServiceImpl implements HttpService {
  @override
  Future<http.Response?> get({required String url}) {
    return HttpUtil.get(url: url);
  }
}