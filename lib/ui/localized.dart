import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import 'palette.dart';

class AppLocale extends InheritedWidget {
  final AppStrings strings;
  const AppLocale({super.key, required this.strings, required super.child});
  static String text(BuildContext context, String value) =>
      context.dependOnInheritedWidgetOfExactType<AppLocale>()?.strings.text(
        value,
      ) ??
      value;
  @override
  bool updateShouldNotify(AppLocale oldWidget) =>
      strings.language != oldWidget.strings.language;
}

class LocalizedText extends StatelessWidget {
  final String data;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final bool localize;
  const LocalizedText(
    this.data, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.localize = true,
  });
  @override
  Widget build(BuildContext context) => Text(
    localize ? AppLocale.text(context, data) : data,
    style: style?.copyWith(
      color: style?.color == null ? null : themeColor(context, style!.color!),
    ),
    maxLines: maxLines,
    overflow: overflow,
    textAlign: textAlign,
  );
}

class LocalizedTooltip extends StatelessWidget {
  final String message;
  final Widget child;
  final bool localize;
  const LocalizedTooltip({
    super.key,
    required this.message,
    required this.child,
    this.localize = true,
  });
  @override
  Widget build(BuildContext context) => Tooltip(
    message: localize ? AppLocale.text(context, message) : message,
    child: child,
  );
}
