import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/activity_stats.dart';
import '../../models/run.dart';
import '../format.dart';
import '../history/history_screen.dart';
import '../theme.dart';
import '../widgets/metric.dart';

/// This week's daily distances, or a month calendar of active days.
class StatsView extends StatefulWidget {
  const StatsView({super.key});

  @override
  State<StatsView> createState() => _StatsViewState();
}

class _StatsViewState extends State<StatsView> {
  Period _period = Period.week;
  DateTime _month = periodStart(DateTime.now(), Period.month);

  @override
  Widget build(BuildContext context) {
    return RunsLoader(
      builder: (context, runs) {
        if (runs == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return _buildContent(context, runs);
      },
    );
  }

  Widget _buildContent(BuildContext context, List<RunSummary> runs) {
    final now = DateTime.now();
    final allKm = runs.fold<double>(0, (d, r) => d + r.distanceMeters);

    final List<Widget> body;
    if (_period == Period.week) {
      final days = weekDays(runs, now);
      final monday = days.first.start;
      final sunday = days.last.start;
      body = [
        _TotalsPanel(
          label:
              'This week · ${DateFormat.MMMd().format(monday)} – '
              '${DateFormat.MMMd().format(sunday)}',
          totals: _sum(days, monday),
        ),
        const SizedBox(height: 12),
        Panel(
          padding: const EdgeInsets.fromLTRB(12, 20, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 16),
                child: Text(
                  'KM PER DAY',
                  style: labelStyle(color: AppColors.ink),
                ),
              ),
              SizedBox(
                height: 200,
                child: _DailyChart(
                  days: days,
                  today: periodStart(now, Period.day),
                ),
              ),
            ],
          ),
        ),
      ];
    } else {
      final days = monthDays(runs, _month);
      final current = periodStart(now, Period.month);
      final earliest = runs.isEmpty
          ? current
          : periodStart(runs.last.startTime, Period.month);
      body = [
        _MonthSwitcher(
          month: _month,
          onPrevious: _month.isAfter(earliest)
              ? () => setState(
                  () => _month = DateTime(_month.year, _month.month - 1),
                )
              : null,
          onNext: _month.isBefore(current)
              ? () => setState(
                  () => _month = DateTime(_month.year, _month.month + 1),
                )
              : null,
        ),
        const SizedBox(height: 4),
        _TotalsPanel(label: 'Month total', totals: _sum(days, _month)),
        const SizedBox(height: 12),
        Panel(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
          child: _MonthCalendar(
            days: days,
            today: periodStart(now, Period.day),
          ),
        ),
      ];
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        _PeriodToggle(
          value: _period,
          onChanged: (p) => setState(() {
            _period = p;
            _month = periodStart(DateTime.now(), Period.month);
          }),
        ),
        const SizedBox(height: 16),
        ...body,
        const SizedBox(height: 12),
        Panel(
          color: AppColors.volt,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              const Icon(Icons.emoji_events_rounded, color: AppColors.ink),
              const SizedBox(width: 10),
              Text('ALL TIME', style: labelStyle(color: AppColors.ink)),
              const Spacer(),
              Text(formatKm(allKm), style: numberStyle(26)),
              Text(' KM  ·  ', style: numberStyle(14)),
              Text('${runs.length}', style: numberStyle(26)),
              Text(' RUNS', style: numberStyle(14)),
            ],
          ),
        ),
      ],
    );
  }

  static PeriodTotals _sum(List<PeriodTotals> days, DateTime start) {
    final total = PeriodTotals(start);
    for (final d in days) {
      total.runs += d.runs;
      total.distanceMeters += d.distanceMeters;
      total.duration += d.duration;
    }
    return total;
  }
}

/// The black summary card: distance, runs, time and pace.
class _TotalsPanel extends StatelessWidget {
  const _TotalsPanel({required this.label, required this.totals});

  final String label;
  final PeriodTotals totals;

  @override
  Widget build(BuildContext context) {
    Metric small(String value, String label) => Metric(
      value: value,
      label: label,
      size: 28,
      color: Colors.white,
      labelColor: Colors.white70,
      alignment: CrossAxisAlignment.start,
    );
    return Panel(
      color: AppColors.ink,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: labelStyle(color: Colors.white70)),
          const SizedBox(height: 8),
          Metric(
            value: formatKm(totals.distanceMeters),
            unit: 'KM',
            label: 'Distance',
            size: 72,
            color: AppColors.volt,
            labelColor: Colors.white70,
            alignment: CrossAxisAlignment.start,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: small('${totals.runs}', 'Runs')),
              Expanded(child: small(formatDuration(totals.duration), 'Time')),
              Expanded(
                child: small(formatPace(totals.paceSecPerKm), 'Pace /km'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DailyChart extends StatelessWidget {
  const _DailyChart({required this.days, required this.today});

  final List<PeriodTotals> days;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final axisStyle = labelStyle(size: 11);
    final maxKm =
        days.fold<double>(
          0,
          (m, d) => d.distanceMeters > m ? d.distanceMeters : m,
        ) /
        1000;
    final top = maxKm < 5 ? 5.0 : maxKm * 1.15;

    return BarChart(
      BarChartData(
        maxY: top,
        alignment: BarChartAlignment.spaceAround,
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => const FlLine(
            color: AppColors.line,
            strokeWidth: 1,
            dashArray: [4, 4],
          ),
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(enabled: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              getTitlesWidget: (value, meta) => SideTitleWidget(
                meta: meta,
                // The chart top is padded above the best day: no label there.
                child: value == meta.max && value % 1 != 0
                    ? const SizedBox.shrink()
                    : Text(meta.formattedValue, style: axisStyle),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                final day = days[value.toInt()].start;
                return SideTitleWidget(
                  meta: meta,
                  child: Text(
                    DateFormat.E().format(day).substring(0, 1),
                    style: labelStyle(
                      size: 12,
                      color: day == today ? AppColors.ink : AppColors.muted,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < days.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: days[i].distanceMeters / 1000,
                  width: 22,
                  color: days[i].start == today
                      ? AppColors.ink
                      : AppColors.volt,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(8),
                  ),
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: top,
                    color: AppColors.canvas,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// "‹  SEPTEMBER 2026  ›"
class _MonthSwitcher extends StatelessWidget {
  const _MonthSwitcher({
    required this.month,
    required this.onPrevious,
    required this.onNext,
  });

  final DateTime month;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    Widget arrow(IconData icon, VoidCallback? onPressed, String tooltip) =>
        IconButton(
          onPressed: onPressed,
          tooltip: tooltip,
          icon: Icon(icon, size: 30),
          color: AppColors.ink,
          disabledColor: AppColors.line,
        );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        arrow(Icons.chevron_left_rounded, onPrevious, 'Previous month'),
        SizedBox(
          width: 210,
          child: Text(
            DateFormat.yMMMM().format(month).toUpperCase(),
            textAlign: TextAlign.center,
            style: headlineStyle(26),
          ),
        ),
        arrow(Icons.chevron_right_rounded, onNext, 'Next month'),
      ],
    );
  }
}

/// Month grid where each active day gets a yellow circle whose intensity
/// goes from 35% (shortest day of the month) to 100% (longest).
class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({required this.days, required this.today});

  final List<PeriodTotals> days;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final active = days
        .where((d) => d.distanceMeters > 0)
        .map((d) => d.distanceMeters);
    final min = active.isEmpty ? 0.0 : active.reduce((a, b) => a < b ? a : b);
    final max = active.isEmpty ? 0.0 : active.reduce((a, b) => a > b ? a : b);
    final leading = days.first.start.weekday - DateTime.monday;
    final cells = <Widget>[
      for (var i = 0; i < leading; i++) const SizedBox.shrink(),
      for (final d in days)
        _DayCell(
          day: d,
          intensity: dayIntensity(d.distanceMeters, min, max),
          isToday: d.start == today,
          isFuture: d.start.isAfter(today),
        ),
    ];
    // Monday-first weekday initials, localized.
    final monday = DateTime(2024, 1, 1);
    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Center(
                  child: Text(
                    DateFormat.E()
                        .format(
                          DateTime(monday.year, monday.month, monday.day + i),
                        )
                        .substring(0, 1)
                        .toUpperCase(),
                    style: labelStyle(size: 11),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          children: cells,
        ),
      ],
    );
  }
}

/// Opaque mix of white and electric yellow.
Color _dayColor(double intensity) =>
    Color.lerp(AppColors.canvas, AppColors.volt, intensity)!;

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.intensity,
    required this.isToday,
    required this.isFuture,
  });

  final PeriodTotals day;
  final double intensity;
  final bool isToday;
  final bool isFuture;

  @override
  Widget build(BuildContext context) {
    final active = intensity > 0;
    return Tooltip(
      message: active ? '${formatKm(day.distanceMeters)} km' : '',
      triggerMode: active ? TooltipTriggerMode.tap : TooltipTriggerMode.manual,
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? _dayColor(intensity) : null,
          border: isToday ? Border.all(color: AppColors.ink, width: 2) : null,
        ),
        alignment: Alignment.center,
        child: Text(
          '${day.start.day}',
          style: TextStyle(
            fontSize: 15,
            fontWeight: active || isToday ? FontWeight.w700 : FontWeight.w500,
            color: isFuture
                ? AppColors.muted.withValues(alpha: 0.35)
                : (active ? AppColors.ink : AppColors.muted),
          ),
        ),
      ),
    );
  }
}

class _PeriodToggle extends StatelessWidget {
  const _PeriodToggle({required this.value, required this.onChanged});

  final Period value;
  final ValueChanged<Period> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget option(Period p, String label) {
      final selected = p == value;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(p),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? AppColors.volt : Colors.transparent,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Text(
              label,
              style: labelStyle(
                color: selected ? AppColors.ink : Colors.white,
                size: 13,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(26),
      ),
      child: Row(
        children: [
          option(Period.week, 'THIS WEEK'),
          option(Period.month, 'MONTHLY'),
        ],
      ),
    );
  }
}
