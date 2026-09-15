import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_config.dart';
import '../models/dashboard.dart';
import '../models/word.dart';
import '../state/session_state.dart';
import '../widgets/build_strip_bar.dart';
import '../widgets/dashboard_tile.dart';
import '../widgets/tts_banner.dart';
import '../widgets/word_button.dart';
import 'caregiver_screen.dart';
import 'category_screen.dart';
import 'settings_screen.dart';

/// The Build-mode home board (Phase 3 of the modes plan): the same
/// 282-word home grid, folder tiles, and personal-dashboard support as
/// [HomeBoardScreen], but symbol taps collect into the phrase strip and
/// NOTHING speaks until the communicator presses Speak.
///
/// Tap mode's [HomeBoardScreen] is untouched — this screen mirrors it so
/// Build behavior can never regress Tap behavior by sharing a branch.
class BuildBoardScreen extends StatelessWidget {
  const BuildBoardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pack = context.select<SessionState, LanguagePack>((s) => s.pack);
    final scale = context.select<SessionState, double>((s) => s.buttonScale);
    final unlockedLevel = context.select<SessionState, int>(
      (s) => s.unlockedLevel,
    );
    final showDashboard = context.select<SessionState, bool>(
      (s) => s.showDashboard,
    );
    final canRestoreDashboard = context.select<SessionState, bool>(
      (s) => s.canRestoreDashboard,
    );
    final session = context.read<SessionState>();

    return Scaffold(
      appBar: AppBar(
        title: Text(AppConfig.appDisplayName),
        actions: [
          IconButton(
            tooltip: 'Caregiver',
            icon: const Icon(Icons.family_restroom),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const CaregiverScreen())),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: Column(
        children: [
          const TtsBanner(),
          Expanded(
            child: showDashboard
                ? _dashboardGrid(session, pack, scale)
                : GridView.count(
                    crossAxisCount: pack.gridColumns,
                    padding: const EdgeInsets.all(8),
                    childAspectRatio: 0.92,
                    children: [
                      for (var r = 0; r < pack.gridRows; r++)
                        for (var c = 0; c < pack.gridColumns; c++)
                          _cell(
                            context,
                            session,
                            pack,
                            r,
                            c,
                            scale,
                            unlockedLevel,
                          ),
                    ],
                  ),
          ),
          if (showDashboard)
            TextButton.icon(
              onPressed: session.bypassDashboard,
              icon: const Icon(Icons.grid_view),
              label: const Text('Show all words'),
            )
          else if (canRestoreDashboard)
            TextButton.icon(
              onPressed: session.restoreDashboard,
              icon: const Icon(Icons.dashboard),
              label: const Text('Back to my board'),
            ),
          const BuildStripBar(),
        ],
      ),
    );
  }

  /// The personal dashboard: same cells as Tap mode. The only difference
  /// is routing — taps go through [SessionState.tapDashboardCell], which
  /// collects into the strip in Build mode instead of speaking.
  Widget _dashboardGrid(
    SessionState session,
    LanguagePack pack,
    double scale,
  ) {
    final profileId = session.profiles.active?.id;
    final dashboard = profileId == null
        ? null
        : session.dashboards.forProfile(profileId);
    if (dashboard == null || dashboard.cells.isEmpty) {
      return const Center(child: Text('This dashboard is empty.'));
    }
    return GridView.count(
      crossAxisCount: pack.gridColumns,
      padding: const EdgeInsets.all(8),
      childAspectRatio: 0.92,
      children: [
        for (final cell in dashboard.cells)
          _dashboardCell(session, pack, cell, scale),
      ],
    );
  }

  Widget _dashboardCell(
    SessionState session,
    LanguagePack pack,
    DashboardCell cell,
    double scale,
  ) {
    final wordId = cell.wordId;
    if (wordId != null) {
      try {
        final item = pack.wordById(wordId);
        return WordButton(
          item: item,
          scale: scale,
          hasSymbol: session.symbols.hasSymbol(item.id),
          imageOverride: session.symbolOverrideFor(item.id),
          onTap: () => session.tapDashboardCell(cell),
        );
      } on Object {
        // Word vanished from a newer pack — render the stored text below.
      }
    }
    return DashboardTile(
      label: cell.label.isNotEmpty ? cell.label : cell.speakText,
      emoji: cell.emoji,
      imageData: cell.imageData,
      color: cell.color,
      scale: scale,
      onTap: () => session.tapDashboardCell(cell),
    );
  }

  Widget _cell(
    BuildContext context,
    SessionState session,
    LanguagePack pack,
    int row,
    int col,
    double scale,
    int unlockedLevel,
  ) {
    final item = pack.itemAt(row, col, unlockedLevel: unlockedLevel);
    if (item == null) return const SizedBox.shrink();
    return WordButton(
      item: item,
      scale: scale,
      hasSymbol: session.symbols.hasSymbol(item.id),
      imageOverride: session.symbolOverrideFor(item.id),
      onTap: () {
        if (item.isFolder) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CategoryScreen(folderId: item.id),
            ),
          );
        } else {
          // Build routing: collects into the strip, never speaks here.
          session.tapBoardItem(item);
        }
      },
    );
  }
}
