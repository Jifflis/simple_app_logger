import 'package:hive_ce/hive.dart';

part 'failed_request.g.dart';

@HiveType(typeId: 0)
class FailedRequest extends HiveObject {
  @HiveField(0)
  String url;

  @HiveField(1)
  Map<String, String> headers;

  @HiveField(2)
  Map<String, dynamic> body;

  @HiveField(3)
  int retryCount;

  @HiveField(4)
  String method;

  FailedRequest({
    required this.url,
    required this.headers,
    required this.body,
    this.retryCount = 0,
    this.method = 'POST',
  });
}
