import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_config.dart';
import '../models/word.dart';
import '../state/session_state.dart';
import '../widgets/message_bar.dart';
import '../widgets/word_button.dart';
import 'caregiver_screen.dart';
import 'category_screen.dart';
import 'settings_screen.dart';

/// The home board: 192 core words in FIXED positions (see en.json — motor
/// planning is sacred) plus 4 folder tiles. Max 2 taps to any word.
class HomeBoardScreen extends StatelessWidget {
  const HomeBoardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pack = context.select<SessionState, LanguagePack>((s) => s.pack);
    final scale = context.select<SessionState, double>((s) => s.buttonScale);
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
          Expanded(
            child: GridView.count(
              crossAxisCount: pack.gridColumns,
              padding: const EdgeInsets.all(8),
              childAspectRatio: 0.92,
              children: [
                for (var r = 0; r < pack.gridRows; r++)
                  for (var c = 0; c < pack.gridColumns; c++)
                    _cell(context, session, pack, r, c, scale),
              ],
            ),
          ),
          const MessageBar(),
        ],
      ),
    );
  }

  Widget _cell(
    BuildContext context,
    SessionState session,
    LanguagePack pack,
    int row,
    int col,
    double scale,
  ) {
    final item = pack.itemAt(row, col);
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
