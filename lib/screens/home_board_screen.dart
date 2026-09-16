import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_config.dart';
import '../models/calling_safety.dart';
import '../models/dashboard.dart';
import '../models/word.dart';
import '../state/session_state.dart';
import '../theme/onevoz_theme.dart';
import '../widgets/dashboard_tile.dart';
import '../widgets/hold_to_confirm_button.dart';
import '../widgets/message_bar.dart';
import '../widgets/safety_contact_avatar.dart';
import '../widgets/tts_banner.dart';
import '../widgets/word_button.dart';
import 'call_confirm_screen.dart';
import 'caregiver_screen.dart';
import 'category_screen.dart';
import 'emergency_screen.dart';
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

    return Theme(
      data: OneVozTheme.childTheme(),
      child: Scaffold(
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
          const _CallActionArea(),
          const MessageBar(),
        ],
      ),
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
    // A cell above the unlocked level renders empty, keeping its slot in the
    // grid. Every visible word therefore stays exactly where it was.
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
          session.tapWord(item);
        }
      },
    );
  }
}

/// Persistent calling & safety action area: photo call buttons for ALL of
/// the active profile's Mom/Dad contacts (every contact of those kinds,
/// not just the first) plus the hold-to-confirm Emergency button. Sits
/// below the board, above the [MessageBar]; the board grid itself is
/// untouched.
///
/// Renders nothing at all when no call contacts are configured and the
/// emergency flow is disabled — no dead ends, no decorative buttons.
class _CallActionArea extends StatelessWidget {
  const _CallActionArea();

  /// Every contact the child can call from the board: all Mom-kind and
  /// all Dad-kind contacts, in profile order.
  List<SafetyContact> _callContacts(List<SafetyContact> contacts) {
    return [
      for (final c in contacts)
        if (c.kind == 'mom' || c.kind == 'dad') c,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final profile = session.profiles.active;
    if (profile == null) return const SizedBox.shrink();
    final callContacts = _callContacts(profile.contacts);
    final emergencyOn = profile.emergency.emergencyEnabled;
    if (callContacts.isEmpty && !emergencyOn) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      // Wrap (not a Row of Expanded) so any number of contacts fits:
      // buttons size to their content and flow onto more lines on
      // narrow phones. Each child carries its own minHeight (96).
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          for (final c in callContacts) _CallContactButton(contact: c),
          if (emergencyOn)
            HoldToConfirmButton(
              onConfirmed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EmergencyScreen(
                    emergency: profile.emergency,
                    contacts: profile.contacts,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Photo button for one trusted contact: tap speaks the contact's name via
/// TTS (zero-reading confirmation — the child hears who they picked) and
/// opens the call-confirm screen for tap 2 of the 2-tap calling rule.
class _CallContactButton extends StatelessWidget {
  const _CallContactButton({required this.contact});

  final SafetyContact contact;

  @override
  Widget build(BuildContext context) {
    final session = context.read<SessionState>();
    final label = contact.name.isNotEmpty ? contact.name : 'Call';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        onTap: () {
          session.tts.speak(contact.name);
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CallConfirmScreen(contact: contact),
            ),
          );
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          constraints: const BoxConstraints(minHeight: 96),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              SafetyContactAvatar(contact: contact, radius: 28),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
