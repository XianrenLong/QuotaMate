import 'models.dart';

AccountSnapshot demoAccount(DateTime now, {bool claude = false}) =>
    AccountSnapshot(
      email: 'demo@quotamate.example',
      plan: claude ? 'claude_pro' : 'plus',
      authMode: claude ? 'claude' : 'chatgpt',
      primary: QuotaWindow(
        38,
        300,
        now.add(const Duration(hours: 2, minutes: 12)),
      ),
      secondary: QuotaWindow(65, 10080, now.add(const Duration(days: 3))),
      observed: now,
      source: '演示数据',
      subscriptionExpiresAt: now.add(const Duration(days: 21)),
      availableQuotaResets: claude ? null : 2,
    );
List<UsageEvent> demoEvents(DateTime now, {bool claude = false}) {
  final today = DateTime(now.year, now.month, now.day);
  const counts = [440000, 580000, 620000, 800000, 920000, 560000, 1240000];
  final events = <UsageEvent>[];
  for (var day = 0; day < 7; day++) {
    final count = day == 6 ? 26 : (day < 2 ? 16 : 15);
    for (var i = 0; i < count; i++) {
      final total =
          counts[day] ~/ count + (i == count - 1 ? counts[day] % count : 0);
      final input = (total * .8062).round();
      events.add(
        UsageEvent(
          id: 'demo-$day-$i',
          session: 'session-$day-${i % 3}',
          project: ['工具开发', '个人网站', '文档整理'][i % 3],
          model: claude ? 'claude-sonnet-4-6' : 'GPT · 示例模型',
          at: today
              .subtract(Duration(days: 6 - day))
              .add(Duration(hours: 9 + i % 6, minutes: i * 7 % 60)),
          tokens: Tokens(input, (input * .68).round(), total - input),
          cost: 18.24 * total / 5160000,
          outputTokensPerSecond: i % 4 == 0 ? null : 19.0 + i % 9,
          firstTokenSeconds: i % 5 == 0 ? null : 10.3 + (i % 4) * .4,
          timingEstimated: true,
        ),
      );
    }
  }
  return events..sort((a, b) => b.at.compareTo(a.at));
}
