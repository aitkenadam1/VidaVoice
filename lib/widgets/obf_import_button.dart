import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/obf_import_service.dart';
import '../state/session_state.dart';

/// "Import a board file" button with the full OBF/OBZ import flow.
///
/// Extracted from DashboardSection so onboarding can offer the same flow
/// inline. Behavior is identical in both places: pick an .obf/.obz/.json
/// file, confirm the import (warns when it replaces an existing
/// dashboard), save, and notify [onChanged] so the surrounding UI
/// refreshes.
class ObfImportButton extends StatefulWidget {
  const ObfImportButton({super.key, required this.onChanged});

  /// Called after a successful import so the host can refresh.
  final VoidCallback onChanged;

  @override
  State<ObfImportButton> createState() => _ObfImportButtonState();
}

class _ObfImportButtonState extends State<ObfImportButton> {
  bool _busy = false;

  Future<void> _importFile() async {
    final session = context.read<SessionState>();
    final profile = session.profiles.active;
    if (profile == null) {
      _showError('Add a communicator profile first.');
      return;
    }
    final profileId = profile.id;
    final profileName = profile.name;
    final List<PlatformFile> files;
    try {
      files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['obf', 'obz', 'json'],
      );
    } catch (e) {
      _showError('Could not open the file picker: $e');
      return;
    }
    if (files.isEmpty) return; // user cancelled
    setState(() => _busy = true);
    try {
      final picked = files.single;
      final bytes = await picked.readAsBytes();
      final report = ObfImportService().importBytes(
        bytes,
        profileId: profileId,
        fileName: picked.name,
      );
      if (!mounted) return;
      final existing = session.dashboards.forProfile(profileId);
      final hasExisting = existing != null && existing.cells.isNotEmpty;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Import "${report.dashboard.name}"?'),
          content: Text(
            '${report.buttonCount} buttons'
            '${hasExisting ? ' will replace the current dashboard' : ''}.'
            '\n\nImported buttons speak their text immediately when tapped '
            '— they do not build sentences.'
            '${report.warnings.isNotEmpty ? '\n\nNotes:\n${report.warnings.join('\n')}' : ''}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Import'),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
      final dashboard = session.dashboards.ensureFor(
        profileId,
        name: profileName,
      );
      final wasEnabled = dashboard.enabled;
      dashboard.name = report.dashboard.name;
      dashboard.source = report.dashboard.source;
      dashboard.cells
        ..clear()
        ..addAll(report.dashboard.cells);
      dashboard.enabled = wasEnabled;
      await session.dashboards.save(dashboard);
      widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Imported ${report.buttonCount} buttons'
              '${report.imageCount > 0 ? ' (${report.imageCount} with images)' : ''}.',
            ),
          ),
        );
      }
    } on ObfImportError catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Import failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import failed'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_busy) const LinearProgressIndicator(),
        OutlinedButton.icon(
          icon: const Icon(Icons.upload_file),
          label: const Text('Import a board file'),
          onPressed: _busy ? null : _importFile,
        ),
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text(
            'From another AAC app (.obf, .obz) or a board backup (.json).',
            style: TextStyle(fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
