import 'package:flutter/material.dart';

import 'data_sheet.dart';
import 'history/history_screen.dart';
import 'stats/stats_view.dart';
import 'territory/territory_view.dart';
import 'theme.dart';

/// Past runs and weekly/monthly activity.
class ActivityScreen extends StatelessWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 12, 16),
                child: Row(
                  children: [
                    Expanded(child: Text('ACTIVITY', style: headlineStyle(44))),
                    FilledButton.icon(
                      onPressed: () => showDataSheet(context),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.card,
                        foregroundColor: AppColors.ink,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      icon: const Icon(Icons.import_export_rounded, size: 20),
                      label: Text(
                        'BACKUP',
                        style: labelStyle(color: AppColors.ink, size: 13),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: TabBar(
                    dividerHeight: 0,
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicator: BoxDecoration(
                      color: AppColors.ink,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    labelColor: AppColors.volt,
                    unselectedLabelColor: AppColors.muted,
                    labelStyle: labelStyle(size: 13),
                    splashBorderRadius: BorderRadius.circular(20),
                    tabs: const [
                      Tab(text: 'RUNS'),
                      Tab(text: 'PROGRESS'),
                      Tab(text: 'TERRITORY'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Expanded(
                child: TabBarView(
                  children: [HistoryView(), StatsView(), TerritoryView()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
