import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/word.dart';
import '../state/session_state.dart';
import '../widgets/activity_summary_section.dart';
import '../widgets/backup_section.dart';
import '../widgets/custom_symbols_section.dart';
import '../widgets/dashboard_section.dart';
import '../widgets/device_section.dart';
import '../widgets/first_week_plan_section.dart';
import '../widgets/word_finder_section.dart';

/// Caregiver hub: a customizable, collapsible set of sections.
///
/// Busy by default is the enemy here — caregivers open this screen between
/// therapy sessions, not to study it. So every section is a collapsible card
/// (only Vocabulary level starts open), each collapsed card shows a one-line
/// summary, and the caregiver can reorder sections and pin the ones they use
/// most to the top. Pinning only controls position — a pinned card can still
/// be collapsed. Order, pins, and collapsed state persist per device in
/// SharedPreferences; sections added in future updates arrive with their
/// default collapsed/pinned state even for caregivers who already customized
/// the hub, and unreadable prefs fall back to defaults instead of breaking
/// the screen.
class CaregiverScreen extends StatefulWidget {
  const CaregiverScreen({super.key});

  @override
  State<CaregiverScreen> createState() => _CaregiverScreenState();
}

/// One hub section: identity, collapsed summary, and expanded content.
class _Section {
  const _Section({
    required this.id,
    required this.title,
    required this.icon,
    required this.summary,
    required this.content,
    this.defaultPinned = false,
    this.defaultCollapsed = true,
  });

  final String id;
  final String title;
  final IconData icon;
  final String Function(SessionState session) summary;
  final Widget Function(
    BuildContext context,
    SessionState session,
    VoidCallback refresh,
  )
  content;
  final bool defaultPinned;
  final bool defaultCollapsed;
}

class _CaregiverScreenState extends State<CaregiverScreen> {
  static const _orderKey = 'vidavoice.caregiver.order';
  static const _pinnedKey = 'vidavoice.caregiver.pinned';
  static const _collapsedKey = 'vidavoice.caregiver.collapsed';

  /// What each vocabulary level adds, in caregiver language. Index 0 = level 1.
  static const _levelInfo = [
    (
      'Level 1 — Starter',
      'The words that get a first message across: want, more, stop, help, go, '
          'yes, no, and the four folders. Everything else is left blank on '
          'purpose, so there is less to scan.',
    ),
    (
      'Level 2 — Growing',
      'Adds describing and asking words — colors, numbers, animals, when, '
          'how, why, hot, cold, fast, and more verbs. Move here once they '
          'are combining two words.',
    ),
    (
      'Level 3 — Full board',
      'Every word in the pack, including time words, opposites and the small '
          'connecting words (and, but, because).',
    ),
  ];
  static const _tips = [
    (
      'Model, don\u2019t quiz',
      'Use VoiceSimple to talk WITH them, not test them. When you hand them '
          'juice, tap \u201cI want juice\u201d yourself. They learn by watching you use it.',
    ),
    (
      'Follow their lead',
      'Talk about whatever has their attention right now — not what you wish '
          'they\u2019d notice. If they\u2019re staring at the dog, model \u201cI see dog\u201d.',
    ),
    (
      'One step ahead',
      'If they use one word, you model two. They tap \u201cjuice\u201d — you tap '
          '\u201cwant juice\u201d. Always just one step beyond where they are.',
    ),
    (
      'Presume competence',
      'Talk about everything, all day — feelings, jokes, plans — exactly like '
          'you would with any child. Don\u2019t limit topics to needs and wants.',
    ),
    (
      'Give wait time',
      'After you model, silently count to 10. Processing takes time — don\u2019t '
          'rush to fill the silence or answer for them.',
    ),
    (
      'Never force repetition',
      'Don\u2019t demand \u201csay it on the app\u201d. If they don\u2019t respond, just model '
          'the word once more yourself and move on.',
    ),
    (
      'Keep it within reach, all day',
      'The voice should be available everywhere — not just at the therapy '
          'table. Communication doesn\u2019t keep office hours.',
    ),
  ];

  static const _planned = [
    'Custom words and personal folders (photos from the camera)',
    'Backup & sync across devices',
  ];

  late final List<_Section> _sections;
  List<String> _order = [];
  Set<String> _pinned = {};
  Set<String> _collapsed = {};
  bool _customizing = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _sections = _buildSections();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = _sections.map((s) => s.id).toList();
      final savedOrder = prefs.getStringList(_orderKey);
      final savedPinned = prefs.getStringList(_pinnedKey);
      final savedCollapsed = prefs.getStringList(_collapsedKey);
      if (savedOrder == null && savedPinned == null && savedCollapsed == null) {
        _applyFirstRunDefaults();
      } else {
        final order = savedOrder ?? [];
        // Saved order first, then any new sections appended at the end.
        _order = [
          for (final id in order)
            if (ids.contains(id)) id,
          for (final id in ids)
            if (!order.contains(id)) id,
        ];
        _pinned = {
          for (final id in savedPinned ?? [])
            if (ids.contains(id)) id,
        };
        _collapsed = {
          for (final id in savedCollapsed ?? [])
            if (ids.contains(id)) id,
        };
        // Upgrade path: sections the saved prefs have never seen (absent
        // from the saved order) arrive with their default collapsed/pinned
        // state, so a future section that defaults to collapsed doesn't land
        // fully expanded for caregivers who already customized their hub.
        for (final s in _sections) {
          if (!order.contains(s.id)) {
            if (s.defaultCollapsed) _collapsed.add(s.id);
            if (s.defaultPinned) _pinToTop(s.id);
          }
        }
      }
    } catch (_) {
      // Corrupt or unreadable prefs (e.g. a wrong-typed value under one of
      // our keys): fall back to first-run defaults rather than leaving the
      // hub on an infinite spinner.
      _applyFirstRunDefaults();
    }
    if (mounted) setState(() => _ready = true);
  }

  /// First-run layout: vocabulary level pinned to the top and open, every
  /// other section collapsed. Also the fallback when prefs are unreadable.
  void _applyFirstRunDefaults() {
    _order = _sections.map((s) => s.id).toList();
    _pinned = {};
    _collapsed = {};
    for (final s in _sections) {
      if (s.defaultCollapsed) _collapsed.add(s.id);
      if (s.defaultPinned) _pinToTop(s.id);
    }
  }

  /// Pins [id] and moves it in [_order] to sit right after the other pinned
  /// sections, so the hub list and the customize list always agree on order.
  void _pinToTop(String id) {
    _pinned.add(id);
    _order.remove(id);
    final boundary = _order.where((other) => _pinned.contains(other)).length;
    _order.insert(boundary, id);
  }

  /// Stable partition: pinned sections first, preserving relative order.
  /// Keeps the "pinned sections stay at the top" promise no matter how the
  /// list is reordered or unpinned.
  void _pinnedSectionsFirst() {
    _order = [
      for (final id in _order)
        if (_pinned.contains(id)) id,
      for (final id in _order)
        if (!_pinned.contains(id)) id,
    ];
  }

  Future<void> _savePrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_orderKey, _order);
      await prefs.setStringList(_pinnedKey, _pinned.toList());
      await prefs.setStringList(_collapsedKey, _collapsed.toList());
    } catch (_) {
      // Best effort: layout prefs must never crash the hub.
    }
  }

  _Section _byId(String id) => _sections.firstWhere((s) => s.id == id);

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    return Scaffold(
      appBar: AppBar(
        title: Text(_customizing ? 'Customize hub' : 'Caregiver'),
        actions: [
          IconButton(
            tooltip: _customizing ? 'Done' : 'Customize',
            icon: Icon(_customizing ? Icons.check : Icons.tune),
            onPressed: _ready
                ? () => setState(() => _customizing = !_customizing)
                : null,
          ),
        ],
      ),
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : _customizing
          ? _customizeList()
          : _hubList(context, session),
    );
  }

  // ---------------------------------------------------------------- hub ---

  /// The hub renders [_order] straight through: pinned sections live at the
  /// top (pinning moves them there), so this list and the customize list can
  /// never disagree about order.
  Widget _hubList(BuildContext context, SessionState session) {
    void refresh() {
      if (mounted) setState(() {});
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final id in _order)
          // Device management needs a signed-in caregiver account: the
          // whole card is hidden until then (the customize list still
          // shows it so order/pins can be arranged ahead of time).
          if (id != 'devices' || session.proxySignedIn)
            _sectionCard(context, _byId(id), session, refresh),
      ],
    );
  }

  Widget _sectionCard(
    BuildContext context,
    _Section s,
    SessionState session,
    VoidCallback refresh,
  ) {
    // Pinning only controls position (pinned sections sit at the top);
    // collapse is independent, so a pinned card can still be folded away.
    final isPinned = _pinned.contains(s.id);
    final collapsed = _collapsed.contains(s.id);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          ListTile(
            leading: Icon(s.icon),
            title: Text(
              s.title,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: collapsed
                ? Text(
                    s.summary(session),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isPinned)
                  Icon(
                    Icons.push_pin,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                Icon(collapsed ? Icons.expand_more : Icons.expand_less),
              ],
            ),
            onTap: () {
              setState(() {
                if (collapsed) {
                  _collapsed.remove(s.id);
                } else {
                  _collapsed.add(s.id);
                }
              });
              _savePrefs();
            },
          ),
          if (!collapsed)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
              child: s.content(context, session, refresh),
            ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------- customize ---

  Widget _customizeList() {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(
            'Drag sections into the order you want. Pin the ones you use '
            'most — pinned sections stay at the top of the hub. This list '
            'shows exactly the order the hub uses.',
            style: TextStyle(fontSize: 13),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
          child: Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('Reset layout'),
              onPressed: () {
                setState(_applyFirstRunDefaults);
                _savePrefs();
              },
            ),
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _order.length,
            // onReorderItem (not the deprecated onReorder) already adjusts
            // newIndex for the removed item — no manual correction needed.
            onReorderItem: (oldIndex, newIndex) {
              setState(() {
                final id = _order.removeAt(oldIndex);
                _order.insert(newIndex, id);
                _pinnedSectionsFirst();
              });
              _savePrefs();
            },
            itemBuilder: (context, index) {
              final s = _byId(_order[index]);
              final isPinned = _pinned.contains(s.id);
              return Card(
                key: ValueKey(s.id),
                child: ListTile(
                  leading: Icon(s.icon),
                  title: Text(s.title),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: isPinned ? 'Unpin' : 'Pin to top',
                        icon: Icon(
                          Icons.push_pin,
                          color: isPinned
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey,
                        ),
                        onPressed: () {
                          setState(() {
                            if (isPinned) {
                              _pinned.remove(s.id);
                              _pinnedSectionsFirst();
                            } else {
                              _pinToTop(s.id);
                            }
                          });
                          _savePrefs();
                        },
                      ),
                      ReorderableDragStartListener(
                        index: index,
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(Icons.drag_handle),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ sections ---

  List<_Section> _buildSections() {
    return [
      _Section(
        id: 'level',
        title: 'Vocabulary level',
        icon: Icons.tune,
        defaultPinned: true,
        defaultCollapsed: false,
        summary: (session) => _levelInfo[session.unlockedLevel - 1].$1,
        content: (context, session, refresh) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(left: 12),
                    child: Text(
                      'Locked words stay blank in place. Unlocking fills the '
                      'gaps — nothing moves.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Why levels work this way',
                  icon: const Icon(Icons.info_outline),
                  onPressed: () => showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Why levels work this way'),
                      content: const Text(
                        'Every word has a fixed position on the board — that '
                        'is what builds the motor pattern. Words above the '
                        'chosen level are left as blank cells. When you '
                        'unlock more, every word you can already see keeps '
                        'exactly the same position: the board grows into the '
                        'gaps, it never rearranges.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('Got it'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            RadioGroup<int>(
              groupValue: session.unlockedLevel,
              onChanged: (v) {
                if (v != null) session.setUnlockedLevel(v);
              },
              child: Column(
                children: [
                  for (
                    var level = LanguagePack.minSupportedLevel;
                    level <= LanguagePack.maxSupportedLevel;
                    level++
                  )
                    RadioListTile<int>(
                      value: level,
                      title: Text(_levelInfo[level - 1].$1),
                      subtitle: Text(_levelInfo[level - 1].$2),
                      isThreeLine: true,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      _Section(
        id: 'finder',
        title: 'Find a word',
        icon: Icons.search,
        summary: (session) {
          final pack = session.pack;
          var n = pack.homeItems.where((i) => !i.isFolder).length;
          for (final f in pack.folders.values) {
            n += f.words.length;
          }
          return 'Search all $n words';
        },
        content: (context, session, refresh) => const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                'Tapping a result speaks it so you can hear it — nothing on '
                'the board changes.',
                style: TextStyle(fontSize: 13),
              ),
            ),
            WordFinderSection(),
          ],
        ),
      ),
      _Section(
        id: 'symbols',
        title: 'Custom symbols',
        icon: Icons.image_outlined,
        summary: (session) {
          final profile = session.profiles.active;
          if (profile == null) return 'Add a profile first';
          final n = session.symbolOverrides.countFor(profile.id);
          return n == 0
              ? 'Standard symbols for ${profile.name}'
              : '$n custom symbol${n == 1 ? '' : 's'} for ${profile.name}';
        },
        content: (context, session, refresh) =>
            CustomSymbolsSection(refresh: refresh),
      ),
      _Section(
        id: 'profiles',
        title: 'Communicator profiles',
        icon: Icons.person_outline,
        summary: (session) {
          final profiles = session.profiles;
          final active = profiles.active;
          if (active == null) return 'No profile yet';
          final n = profiles.profiles.length;
          return n > 1 ? '${active.name} · $n profiles' : active.name;
        },
        content: (context, session, refresh) {
          final profiles = session.profiles;
          return Column(
            children: [
              for (final p in profiles.profiles)
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(p.name),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (p.id == profiles.active?.id)
                        const Icon(Icons.check, color: Colors.green)
                      else
                        TextButton(
                          onPressed: () async {
                            await session.switchProfile(p.id);
                            refresh();
                          },
                          child: const Text('Switch'),
                        ),
                      if (profiles.profiles.length > 1)
                        IconButton(
                          tooltip: 'Remove profile',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await session.removeProfile(p.id);
                            refresh();
                          },
                        ),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add profile'),
                    onPressed: () =>
                        _addProfileDialog(context, session, refresh),
                  ),
                ),
              ),
            ],
          );
        },
      ),
      _Section(
        id: 'dashboard',
        title: 'Personal dashboard',
        icon: Icons.dashboard_outlined,
        summary: (session) {
          final id = session.profiles.active?.id;
          if (id == null) return 'No profile yet';
          final dashboard = session.dashboards.forProfile(id);
          if (dashboard == null || dashboard.cells.isEmpty) {
            return 'Not set up';
          }
          final state = dashboard.enabled ? 'On' : 'Off';
          final n = dashboard.cells.length;
          return '$state · $n button${n == 1 ? '' : 's'}';
        },
        content: (context, session, refresh) => DashboardSection(
          key: ValueKey(session.profiles.active?.id ?? 'none'),
          refresh: refresh,
        ),
      ),
      _Section(
        id: 'plan',
        title: 'First week plan',
        icon: Icons.calendar_month_outlined,
        summary: (session) {
          final profileId = session.profiles.active?.id;
          if (profileId == null) return 'A daily plan for week one';
          final done = session.plan.completedCount(profileId);
          return '$done of 7 days done';
        },
        content: (context, session, refresh) {
          final active = session.profiles.active;
          if (active == null) return const SizedBox.shrink();
          return FirstWeekPlanSection(
            key: ValueKey(active.id),
            profileId: active.id,
            profileName: active.name,
          );
        },
      ),
      _Section(
        id: 'activity',
        title: 'Activity summary',
        icon: Icons.insights_outlined,
        summary: (session) {
          final taps = session.usage.tapsToday();
          return taps == 0 ? 'No taps today yet' : '$taps taps today';
        },
        content: (context, session, refresh) => const ActivitySummarySection(),
      ),
      _Section(
        id: 'usage',
        title: 'Most used words',
        icon: Icons.leaderboard_outlined,
        summary: (session) {
          final top = session.usage.top(1);
          if (top.isEmpty) return 'No taps yet';
          String label;
          try {
            label = session.pack.wordById(top.first.key).label;
          } catch (_) {
            label = top.first.key;
          }
          return 'Top: $label ×${top.first.value}';
        },
        content: (context, session, refresh) {
          final top = session.usage.top(10);
          if (top.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No taps recorded yet. Words tapped on the board will show up '
                'here, most-used first.',
                style: TextStyle(fontSize: 13),
              ),
            );
          }
          return Column(
            children: [
              for (var i = 0; i < top.length; i++)
                _usageRow(session, i + 1, top[i].key, top[i].value),
            ],
          );
        },
      ),
      _Section(
        id: 'tips',
        title: 'Modeling tips',
        icon: Icons.lightbulb_outline,
        summary: (session) => '${_tips.length} habits that make AAC work',
        content: (context, session, refresh) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Text(
                'How you use the device matters more than any setting. These '
                'are the habits that work:',
                style: TextStyle(fontSize: 13),
              ),
            ),
            for (final (title, body) in _tips)
              ExpansionTile(
                leading: const Icon(Icons.lightbulb_outline),
                title: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Text(body),
                  ),
                ],
              ),
          ],
        ),
      ),
      _Section(
        id: 'data',
        title: 'Backup & sync',
        icon: Icons.backup_outlined,
        summary: (session) => 'Save & restore profiles',
        content: (context, session, refresh) => BackupSection(
          onImported: () async {
            await session.reloadProfileData();
            await session.usage.load();
            refresh();
          },
        ),
      ),
      _Section(
        id: 'devices',
        title: 'Devices',
        icon: Icons.devices_outlined,
        summary: (session) => 'Manage this family\u2019s devices',
        content: (context, session, refresh) => const DeviceSection(),
      ),
      _Section(
        id: 'more',
        title: 'Setup & what\u2019s next',
        icon: Icons.more_horiz,
        summary: (session) => 'Tour, roadmap, credits',
        content: (context, session, refresh) => Column(
          children: [
            ListTile(
              leading: const Icon(Icons.replay_outlined),
              title: const Text('Re-run setup'),
              subtitle: const Text(
                'Run the first-run wizard again (welcome, account, import, '
                'voice, quick tour).',
              ),
              onTap: () {
                session.reopenOnboarding();
                Navigator.of(context).pop();
              },
            ),
            const Divider(),
            for (final item in _planned)
              ListTile(
                dense: true,
                leading: const Icon(Icons.schedule_outlined),
                title: Text(item),
              ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                'Word symbols: ARASAAC (CC BY-NC-SA), https://arasaac.org',
                style: TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    ];
  }

  // -------------------------------------------------------------- pieces ---

  Widget _usageRow(SessionState session, int rank, String id, int count) {
    String label;
    try {
      label = session.pack.wordById(id).label;
    } catch (_) {
      label = id; // word removed from a newer pack; show the raw id
    }
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 14,
        child: Text('$rank', style: const TextStyle(fontSize: 12)),
      ),
      title: Text(label),
      trailing: Text(
        '\u00d7$count',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }

  Future<void> _addProfileDialog(
    BuildContext context,
    SessionState session,
    VoidCallback refresh,
  ) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New profile'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'First name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => Navigator.of(ctx).pop(controller.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await session.profiles.addProfile(name.trim());
      refresh();
    }
  }
}
