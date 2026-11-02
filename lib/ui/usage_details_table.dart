import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/models.dart';
import 'widgets.dart';
import 'localized.dart';

class UsageDetailsTable extends StatefulWidget {
  final List<UsageEvent> events;
  final ValueChanged<UsageEvent> onSelect;
  final String? emptyMessage;
  final VoidCallback? onEmptyTap;
  const UsageDetailsTable({
    super.key,
    required this.events,
    required this.onSelect,
    this.emptyMessage,
    this.onEmptyTap,
  });
  @override
  State<UsageDetailsTable> createState() => _UsageDetailsTableState();
}

class _UsageDetailsTableState extends State<UsageDetailsTable> {
  final horizontal = ScrollController();
  static const weights = [10, 24, 12, 12, 10, 13, 13, 11];
  @override
  void dispose() {
    horizontal.dispose();
    super.dispose();
  }

  Widget row(List<Widget> cells, {bool header = false}) => Builder(
    builder: (context) => Container(
      height: header ? 38 : 44,
      padding: EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: header ? themeColor(context, C.bg) : null,
        borderRadius: header ? BorderRadius.circular(9) : null,
        border: header
            ? null
            : Border(bottom: BorderSide(color: themeColor(context, C.line))),
      ),
      child: Row(
        children: [
          for (var i = 0; i < cells.length; i++)
            Expanded(
              flex: weights[i],
              child: Padding(
                padding: EdgeInsets.only(right: 10),
                child: cells[i],
              ),
            ),
        ],
      ),
    ),
  );
  Widget heading(String name, [String? hint]) => Builder(
    builder: (context) => Row(
      children: [
        Flexible(
          child: label(name, size: 12, color: themeColor(context, C.muted)),
        ),
        if (hint != null) ...[
          SizedBox(width: 5),
          LocalizedTooltip(
            message: hint,
            child: Icon(
              LucideIcons.circleHelp,
              size: 14,
              color: themeColor(context, C.muted),
            ),
          ),
        ],
      ],
    ),
  );
  Widget number(int value, {bool abbreviated = false}) => LocalizedTooltip(
    message: '${detailTokenCount(value)} Token',
    child: label(detailTokenCount(value, abbreviated: abbreviated), size: 13),
  );
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Scrollbar(
      controller: horizontal,
      thumbVisibility: true,
      notificationPredicate: (n) => n.depth == 0,
      child: SingleChildScrollView(
        controller: horizontal,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: math.max(1040, constraints.maxWidth),
          height: constraints.maxHeight,
          child: Column(
            children: [
              row([
                heading('时间', '本地时间；悬停可查看完整日期。'),
                heading('模型'),
                heading('成本', 'API 等价估算，非订阅实际扣费。缺少模型单价时无法估算。'),
                heading('新增输入', '输入 Token 减去缓存命中 Token；Claude 记录包含缓存写入。'),
                heading('输出'),
                heading('缓存命中'),
                heading(
                  '速度',
                  '≈ 为按日志请求区间估算的平均输出速度，包含等待，尽量排除工具执行时间。少于 200 输出 Token 或时间不足时显示 —。',
                ),
                heading(
                  '首字',
                  '≈ 为请求起点至首个模型输出项（含思考）开始的估算延迟，依据 started_at_ms；并非精确网络首字测量。缺失时显示 —。',
                ),
              ], header: true),
              Expanded(
                child: widget.events.isEmpty
                    ? EmptyState(
                        '暂无用量明细',
                        widget.emptyMessage ?? '同步本机记录或选择其他时间范围。',
                        onTap: widget.onEmptyTap,
                      )
                    : ListView.builder(
                        primary: false,
                        padding: EdgeInsets.only(bottom: 14),
                        itemCount: widget.events.length,
                        itemBuilder: (context, index) {
                          final e = widget.events[index];
                          return InkWell(
                            onTap: () => widget.onSelect(e),
                            child: row([
                              LocalizedTooltip(
                                message: e.at.toLocal().toString(),
                                child: label(detailTime(e.at), size: 13),
                              ),
                              LocalizedTooltip(
                                message: e.model,
                                localize: false,
                                child: label(
                                  e.model,
                                  size: 13,
                                  localize: false,
                                ),
                              ),
                              LocalizedTooltip(
                                message: e.cost == null
                                    ? '请在设置中配置该模型的参考单价。'
                                    : 'API 等价估算，不代表实际扣费。',
                                child: label(
                                  e.cost == null
                                      ? '未配置单价'
                                      : '\$${e.cost!.toStringAsFixed(4)}',
                                  size: 13,
                                  color: e.cost == null
                                      ? themeColor(context, C.muted)
                                      : themeColor(context, C.ink),
                                ),
                              ),
                              number(e.freshInput),
                              number(e.tokens.output),
                              number(e.tokens.cached, abbreviated: true),
                              label(
                                speedText(e),
                                size: 12,
                                color: e.outputTokensPerSecond == null
                                    ? themeColor(context, C.muted)
                                    : themeColor(context, C.ink),
                              ),
                              label(
                                firstTokenText(e),
                                size: 13,
                                color: e.firstTokenSeconds == null
                                    ? themeColor(context, C.muted)
                                    : themeColor(context, C.ink),
                              ),
                            ]),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
