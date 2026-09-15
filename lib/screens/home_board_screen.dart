import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_config.dart';
import '../models/dashboard.dart';
import '../models/word.dart';
import '../state/session_state.dart';
import '../widgets/dashboard_tile.dart';
import '../widgets/message_bar.dart';
import '../widgets/tts_banner.dart';
import '../widgets/word_button.dart';
import 'caregiver_screen.dart';
import 'category_screen.dart';
import 'settings_screen.dart';

/// The home board: 282 core words in FIXED positions (see en.json — motor
/// planning is sacred) plus 4 folder tiles. Max 2 taps to any word.
class HomeBoardScreen extends StatelessWidget {
  const HomeBoardScreen({super.key});

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
          const MessageBar(),
        ],
      ),
    );
  }

  /// The personal dashboard: the caregiver's arranged cells in order.
  /// Vocabulary cells render as standard word buttons (same look, same
  /// behavior); custom buttons get their own tile.
  Widget _dashboardGrid(
    SessionState session,
    LanguagePack pack,
    double scale,
  ) {
    final profileId = session.profiles.active?.id;
    final dashboard = profileId == null
        ? null
        : session.dashboards.forProfile(profileId);
    // Defensive: showDashboard already guards empty dashboards.
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
    // A cell above the unlocked level renders empty, keeping its slot in the
    // grid. Every visible word therefore stays exactly where it was.
    final item = pack.itemAt(row, col, unlockedLevel: unlockedLevel);
    if (item == null) return const SizedBox.shrink();
    return WordButton(
      item: item,
      scale: scale,
      hasSymbol: session.symbols.hasSymbol(item.id),
      onTap: () {
        if (item.isFolder) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CategoryScreen(folderId: item.id),
            ),
          );
        } else {
          session.tapWord(item);
        }
      },
    );
  }
}
