import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/profile_backup_service.dart';
import '../state/session_state.dart';

/// Profile backup and restore, in the caregiver hub.
///
/// Export writes one JSON file (settings, word usage, sentence history,
/// first-week plan progress) and opens the OS share sheet so the caregiver
/// can save it to Drive, email it to themselves, etc. Import reads such a
/// file back, validates it, and — only after an explicit Replace/Merge
/// choice — writes it to this device. Only the backup's own profile is ever
/// touched; other profiles are never modified.
///
/// [pickFile] and [shareFile] are injectable so widget tests can drive the
/// flow with a fake file layer.
class BackupSection extends StatefulWidget {
  const BackupSection({
    super.key,
    this.pickFile,
    this.shareFile,
    this.onImported,
    this.service,
  });

  /// Returns the chosen import file's path, or null if cancelled.
  final Future<String?> Function()? pickFile;

  /// Shares the exported file (OS share sheet in production).
  final Future<void> Function(String path)? shareFile;

  /// Called after a successful import so the host screen can reload
  /// profile data and repaint.
  final Future<void> Function()? onImported;

  /// Override for tests.
  final ProfileBackupService? service;

  @override
  State<BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends State<BackupSection> {
  bool _busy = false;

  ProfileBackupService get _service =>
      widget.service ?? ProfileBackupService();

  Future<String?> _defaultPickFile() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    return files.isEmpty ? null : files.single.path;
  }

  Future<void> _defaultShareFile(String path) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path)],
        subject: 'VidaVoice profile backup',
        text: 'VidaVoice profile backup — keep this file somewhere safe.',
      ),
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _export() async {
    final session = context.read<SessionState>();
    final profile = session.profiles.active;
    if (profile == null) {
      _snack('No profile to back up.');
      return;
    }
    setState(() => _busy = true);
    try {
      final backup = await _service.build(profile.id);
      final dir = await getTemporaryDirectory();
      final file = await _service.writeToDirectory(backup, dir);
      await (widget.shareFile ?? _defaultShareFile)(file.path);
    } catch (e) {
      _snack('Export failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final session = context.read<SessionState>();
    final path = await (widget.pickFile ?? _defaultPickFile)();
    if (path == null) return; // user cancelled
    late final String raw;
    try {
      raw = await File(path).readAsString();
    } catch (e) {
      _snack('Could not read that file: $e');
      return;
    }
    late final ProfileBackup backup;
    try {
      backup = ProfileBackup.decode(raw);
    } on BackupFormatException catch (e) {
      // Corrupt file: show the error, touch nothing.
      _snack(e.message);
      return;
    }
    if (!mounted) return;
    final merge = await _confirmImport(context, backup);
    if (merge == null) return; // user cancelled
    setState(() => _busy = true);
    try {
      await _service.apply(backup, merge: merge);
      if (!merge) {
        // Replace mode restores device settings through the live session
        // so in-memory state and persisted prefs stay in sync.
        await session.setLocale(backup.locale);
        await session.setSpeechRate(backup.speechRate);
        await session.setSpeechPitch(backup.speechPitch);
        await session.setButtonScale(backup.buttonScale);
        await session.setUnlockedLevel(backup.unlockedLevel);
        await session.setOnboardingComplete(backup.onboardingComplete);
        await session.usage.load();
      }
      await widget.onImported?.call();
      _snack(
        merge
            ? 'Backup merged into “${backup.profileName}”.'
            : '“${backup.profileName}” restored from backup.',
      );
    } catch (e) {
      _snack('Import failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Returns true for merge, false for replace, null for cancel.
  Future<bool?> _confirmImport(
    BuildContext context,
    ProfileBackup backup,
  ) async {
    final date =
        '${backup.exportedAt.year}-'
        '${backup.exportedAt.month.toString().padLeft(2, '0')}-'
        '${backup.exportedAt.day.toString().padLeft(2, '0')}';
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore backup?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Profile: ${backup.profileName}'),
            Text('Exported: $date'),
            Text(
              '${backup.historyEntries.length} recent sentences · '
              '${backup.totalTaps} word taps · '
              '${backup.planDays.length}/7 plan days',
            ),
            const SizedBox(height: 12),
            const Text(
              'Replace overwrites this profile’s data and voice settings '
              'with the backup. Merge adds the backup’s words, sentences '
              'and plan progress to what’s already here and leaves your '
              'current settings alone.',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Merge'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final name = session.profiles.active?.name ?? 'this profile';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Back up this profile',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              'Save $name’s words, sentences, plan progress and voice '
              'settings to a file you can keep somewhere safe — or restore '
              'one you saved before. Only this profile is affected.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            if (_busy)
              const Center(child: CircularProgressIndicator())
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.upload_outlined),
                      label: const Text('Export backup'),
                      onPressed: _export,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Import backup'),
                      onPressed: _import,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
