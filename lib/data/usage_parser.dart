import 'models.dart';

abstract interface class UsageParser {
  Json get state;
  UsageEvent? parse(String line);
  AccountSnapshot? get quota;
}
