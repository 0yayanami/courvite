import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/backup.dart';
import '../data/run_repository.dart';
import 'theme.dart';

/// Opens the "Your data" sheet: export all runs to a `.courvite` file, or
/// import one (e.g. made on another phone).
Future<void> showDataSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  backgroundColor: AppColors.canvas,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => const _DataSheet(),
);

class _DataSheet extends StatefulWidget {
  const _DataSheet();

  @override
  State<_DataSheet> createState() => _DataSheetState();
}

class _DataSheetState extends State<_DataSheet> {
  bool _busy = false;

  Future<void> _run(Future<String?> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    String? message;
    try {
      message = await action();
    } on FormatException catch (e) {
      message = e.message;
    } on Object catch (e) {
      message = 'Something went wrong: $e';
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (message != null) {
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// Returns the message to show, or null if the user cancelled.
  Future<String?> _export() async {
    final runs = await context.read<RunRepository>().exportRuns();
    if (runs.isEmpty) return 'No runs to export yet.';
    final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final uri = await FilePicker.saveFile(
      fileName: 'courvite-backup-$date.${Backup.extension}',
      bytes: Backup.encode(runs),
    );
    if (uri == null) return null;
    return 'Backup saved: ${runs.length} run${runs.length == 1 ? '' : 's'}.';
  }

  Future<String?> _import() async {
    final repo = context.read<RunRepository>();
    final file = await FilePicker.pickFile();
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    final runs = Backup.decode(bytes);
    final result = await repo.importRuns(runs);
    final added = '${result.added} run${result.added == 1 ? '' : 's'} imported';
    return result.skipped == 0
        ? '$added.'
        : '$added, ${result.skipped} already on this phone.';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('YOUR DATA', style: headlineStyle(34)),
            const SizedBox(height: 8),
            const Text(
              'Your runs never leave this phone on their own. Export a backup '
              'to keep a copy safe or move your runs to another phone.',
              style: TextStyle(fontSize: 15, color: AppColors.inkSoft),
            ),
            const SizedBox(height: 20),
            _ActionTile(
              icon: Icons.upload_rounded,
              title: 'Export backup',
              subtitle: 'Save all your runs to a .courvite file',
              color: AppColors.volt,
              onTap: _busy ? null : () => _run(_export),
            ),
            const SizedBox(height: 10),
            _ActionTile(
              icon: Icons.download_rounded,
              title: 'Import backup',
              subtitle:
                  'Add runs from a .courvite file. Runs you already '
                  'have are skipped.',
              color: AppColors.card,
              onTap: _busy ? null : () => _run(_import),
            ),
            if (_busy) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(
                color: AppColors.ink,
                backgroundColor: AppColors.volt,
                borderRadius: BorderRadius.all(Radius.circular(4)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Panel(
      color: color,
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: AppColors.ink,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.volt),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.inkSoft,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
