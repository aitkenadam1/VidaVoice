import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/profile_service.dart';
import '../state/session_state.dart';
import '../theme/onevoz_theme.dart';
import '../widgets/calling_safety/contact_editor.dart';
import '../widgets/calling_safety/emergency_editor.dart';
import '../widgets/calling_safety/phrase_editor.dart';
import 'calling_safety_setup_screen.dart';

/// Calling & Safety hub: the single caregiver entry point for everything
/// about calling — contacts, the phrase bank, emergency details, and
/// safety preferences — for the selected communicator profile.
///
/// All data lives on the profile (encrypted with everything else); edits
/// go through the [ProfileService] mutators, whose onChanged wiring
/// schedules the encrypted sync push automatically.
class CallingSafetyHubScreen extends StatefulWidget {
  const CallingSafetyHubScreen({super.key});

  @override
  State<CallingSafetyHubScreen> createState() => _CallingSafetyHubScreenState();
}

class _CallingSafetyHubScreenState extends State<CallingSafetyHubScreen> {
  String? _profileId;

  String? _resolveProfileId(SessionState session) {
    final profiles = session.profiles.profiles;
    if (profiles.isEmpty) return null;
    final wanted = _profileId ?? session.profiles.active?.id;
    if (wanted != null && profiles.any((p) => p.id == wanted)) return wanted;
    return profiles.first.id;
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final profiles = session.profiles.profiles;
    final profileId = _resolveProfileId(session);
    final profileName = profiles
        .where((p) => p.id == profileId)
        .map((p) => p.name)
        .firstOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Calling & Safety')),
      body: profileId == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Add a communicator profile first — calling and safety '
                  'settings belong to a profile.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (profiles.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _profileSwitcher(session, profiles, profileId),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          OneVozColors.blue.withValues(alpha: 0.12),
                          OneVozColors.teal.withValues(alpha: 0.16),
                        ],
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [OneVozColors.azure, OneVozColors.teal],
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            (profileName ?? '?').isNotEmpty
                                ? (profileName ?? '?')[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Calling & Safety for '
                                '${profileName ?? 'this profile'}',
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Who they can reach, what they can say, '
                                'and the emergency details that fill in '
                                'their phrases.',
                                style: TextStyle(fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _HubCard(
                  icon: Icons.contacts_outlined,
                  title: 'Contacts',
                  child: ContactListEditor(
                    key: ValueKey('contacts-$profileId'),
                    profileId: profileId,
                    onChanged: _refresh,
                  ),
                ),
                _HubCard(
                  icon: Icons.chat_bubble_outline,
                  title: 'Call phrases',
                  child: PhraseBankEditor(
                    key: ValueKey('phrases-$profileId'),
                    profileId: profileId,
                    onChanged: _refresh,
                  ),
                ),
                _HubCard(
                  icon: Icons.medical_information_outlined,
                  title: 'Emergency details',
                  child: EmergencyDetailsEditor(
                    key: ValueKey('emergency-$profileId'),
                    profileId: profileId,
                    onChanged: _refresh,
                  ),
                ),
                _HubCard(
                  icon: Icons.shield_outlined,
                  title: 'Safety',
                  child: SafetyTogglesCard(
                    key: ValueKey('safety-$profileId'),
                    profileId: profileId,
                    onChanged: _refresh,
                  ),
                ),
                const _HonestLimitsCard(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.replay_outlined),
                    label: const Text('Run guided setup again'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CallingSafetySetupScreen(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _profileSwitcher(
    SessionState session,
    List<UserProfile> profiles,
    String profileId,
  ) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
        child: Row(
          children: [
            const Icon(Icons.person_outline),
            const SizedBox(width: 12),
            const Text('Profile'),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButton<String>(
                value: profileId,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                items: [
                  for (final p in profiles)
                    DropdownMenuItem(value: p.id, child: Text(p.name)),
                ],
                onChanged: (id) async {
                  if (id == null) return;
                  await session.switchProfile(id);
                  if (!mounted) return;
                  setState(() => _profileId = id);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One hub section: a titled card wrapping an editor.
class _HubCard extends StatelessWidget {
  const _HubCard({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.only(bottom: 12), child: child),
        ],
      ),
    );
  }
}

/// The honest-limit notes (spec §6/§9): always visible on the hub, calm
/// tone, never buried. OneVoz complements built-in Emergency SOS — it
/// never replaces calling 911, and no 911 capability is ever claimed.
class _HonestLimitsCard extends StatelessWidget {
  const _HonestLimitsCard();

  static const _notes = [
    (
      Icons.sms_outlined,
      'About texting 911',
      'Text-to-911 works only where your local 911 center accepts texts. '
          'It doesn\u2019t work while roaming, can\u2019t send photos, and '
          'texts can arrive late or out of order.',
    ),
    (
      Icons.emergency_outlined,
      'OneVoz is a complement, not a replacement',
      'OneVoz complements your device\u2019s built-in Emergency SOS \u2014 '
          'it never replaces calling 911 directly.',
    ),
    (
      Icons.volume_up_outlined,
      'About speakerphone',
      'On calls, phrases play through the speaker \u2014 best-effort on '
          'Android.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Good to know',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            for (final (icon, title, body) in _notes) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        Text(body, style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}
