import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'distributed artwork and timing references include their license notices',
    () async {
      final own = await rootBundle.loadString('LICENSE');
      final icons = await rootBundle.loadString('docs/licenses/lucide.txt');
      final timing = await rootBundle.loadString('docs/cc-switch-LICENSE.txt');
      expect(own, contains('MIT License'));
      expect(icons, contains('ISC License'));
      expect(icons, contains('Cole Bemis'));
      expect(timing, contains('Jason Young'));
      expect(timing, contains('MIT License'));
    },
  );
}
