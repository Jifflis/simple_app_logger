import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class PrefsUtil {
  PrefsUtil._internal();

  static final PrefsUtil _instance = PrefsUtil._internal();

  factory PrefsUtil() => _instance;

  static late SharedPreferences prefs;

  static Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
  }

  Map<String, dynamic>? getJsonData(String key) {
    final jsonString = prefs.getString(key);
    if (jsonString == null) return null;
    return jsonDecode(jsonString);
  }

  Future<void> saveJsonData({
    required String key,
    required Map<String, dynamic> data,
  }) async {
    final jsonString = jsonEncode(data);
    await prefs.setString(key, jsonString);
  }

  Future<void> remove(String key) async {
    prefs.remove(key);
  }
}
