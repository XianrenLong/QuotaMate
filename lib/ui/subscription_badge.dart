import 'package:flutter/material.dart';

import '../data/subscription_info.dart';
import 'widgets.dart';
import 'localized.dart';

class SubscriptionBadge extends StatelessWidget {
  final SubscriptionInfo info;
  final bool historical;
  final bool compact;
  const SubscriptionBadge(
    this.info, {
    super.key,
    this.historical = false,
    this.compact = false,
  });
  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (info.tone) {
      SubscriptionTone.neutral => (
        themeColor(context, Color(0xFFE8E8ED)),
        themeColor(context, Color(0xFF656978)),
      ),
      SubscriptionTone.blue => (
        themeColor(context, Color(0xFFE1EBFF)),
        themeColor(context, Color(0xFF226CE4)),
      ),
      SubscriptionTone.gold => (
        themeColor(context, Color(0xFFFFEDBD)),
        themeColor(context, Color(0xFF91600A)),
      ),
    };
    return LocalizedTooltip(
      message: historical ? '历史订阅快照，刷新后确认当前等级。' : '订阅等级来自当前账号查询。',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 11,
          vertical: compact ? 3 : 5,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(30),
          border: info.tone == SubscriptionTone.gold
              ? Border.all(
                  color: themeColor(context, Color(0xFFE7C366)),
                  width: .6,
                )
              : null,
        ),
        child: label(
          info.label,
          size: compact ? 11 : 12,
          color: foreground,
          weight: FontWeight.w600,
        ),
      ),
    );
  }
}
