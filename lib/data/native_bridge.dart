import 'package:flutter/services.dart';

class NativeBridge {
  static const channel = MethodChannel('dev.quotamate/native');
  static Future<T?> call<T>(String method, [Map<String, dynamic>? args]) async {
    try {
      return await channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    }
  }
}
