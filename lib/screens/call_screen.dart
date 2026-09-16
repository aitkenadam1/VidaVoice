import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/calling_safety.dart';
import '../services/location_service.dart';
import '../services/suggestion_service.dart';
import '../state/session_state.dart';
import '../theme/onevoz_theme.dart';

/// The in-call / practice-call screen.
///
/// Shown when the child wants something to say during (or before) a call:
/// caregiver-written phrase cards with `{child_name}`-style placeholders
/// resolved, one-tap quick answers, and — when [SafetySettings.aiSuggestions]
/// is on — a "Dispatcher says…" field whose replies are suggested on-device
/// by [SuggestionService] and spoken via TTS on tap.
///
/// Reached from the emergency screen's "Practice 911 text replies" link
/// (emergencyMode: true gates the vetted emergency reply set).
class CallScreen extends StatefulWidget {
  const CallScreen({
    super.key,
    this.contact,
    this.phrases = const [],
    this.emergency,
    this.safety = const SafetySettings(),
    this.emergencyMode = false,
    LocationService? locationService,
  }) : locationService = locationService ?? const NoopLocationService();

  /// Who is being called. Null means "practice" — no dialing involved.
  final SafetyContact? contact;

  final List<CallPhrase> phrases;
  final EmergencyProfileData? emergency;
  final SafetySettings safety;

  /// True on the 911 dispatcher-reply path: unlocks the vetted emergency
  /// reply set inside [SuggestionService].
  final bool emergencyMode;

  final LocationService locationService;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  String? _gps;
  List<Suggestion> _suggestions = const [];
  final _dispatcherController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // NoopLocationService always resolves null (tests / denied permission). The UI degrades
    // honestly — {gps} renders as "location unavailable", never a guess.
    widget.locationService.currentCoords().then((coords) {
      if (mounted) setState(() => _gps = coords);
    });
  }

  @override
  void dispose() {
    _dispatcherController.dispose();
    super.dispose();
  }

  String _resolve(String text) {
    final emergency = widget.emergency;
    if (emergency == null) return text;
    return resolvePlaceholders(
      text,
      emergency,
      gps: _gps ?? 'location unavailable',
    );
  }

  void _speak(String text) {
    context.read<SessionState>().tts.speak(text);
    _showUndoBar();
  }

  /// 3-second Undo bar after every spoken phrase/suggestion.
  ///
  /// SMS UNDO DEVIATION: the spec's "Undo cancels before the SMS sends"
  /// assumed in-app SMS composition. Phase 1 opens the native SMS composer
  /// via `sms:` instead, so the OS Send button is the human gate — there is
  /// nothing of ours left to cancel once the composer opens. Undo therefore
  /// covers TTS only: it stops whatever is currently being spoken.
  void _showUndoBar() {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Spoken — undo stops the voice.'),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => context.read<SessionState>().tts.stop(),
        ),
      ),
    );
  }

  void _onDispatcherChanged(String value) {
    // Stateless re-invoke: the newest input always replaces the cards.
    // SuggestionService keeps no memory between calls by design.
    setState(() {
      _suggestions = value.trim().isEmpty
          ? const []
          : SuggestionService().suggestionsFor(
              incomingText: value,
              bank: widget.phrases,
              preferOwnPhrases: widget.safety.preferOwnPhrases,
              emergencyMode: widget.emergencyMode,
              emergency: widget.emergency,
              gps: _gps,
            );
    });
  }

  /// Accent colors for the reply cards, cycling teal -> yellow -> blue —
  /// the mockup's `.reply-card` color bars.
  static const _accents = [
    OneVozColors.teal,
    OneVozColors.yellow,
    OneVozColors.blue,
  ];

  @override
  Widget build(BuildContext context) {
    final name = widget.emergencyMode
        ? 'Emergency replies'
        : widget.contact != null && widget.contact!.name.isNotEmpty
        ? 'Call: ${widget.contact!.name}'
        : 'Practice call';
    final initial = widget.emergencyMode
        ? '!'
        : widget.contact != null && widget.contact!.name.isNotEmpty
        ? widget.contact!.name[0].toUpperCase()
        : '?';
    return Theme(
      data: OneVozTheme.childTheme(),
      child: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              // Navy gradient hero, matching the mockup's `.call-hero`.
              Container(
                decoration: const BoxDecoration(
                  gradient: OneVozColors.heroGradient,
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(24),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(8, 8, 20, 28),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Back',
                          icon: const Icon(
                            Icons.arrow_back,
                            color: Colors.white,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const WaveformMotif(
                          barCount: 5,
                          height: 26,
                          barWidth: 5,
                          gap: 4,
                          color: Colors.white,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.6),
                          width: 3,
                        ),
                        color: Colors.white.withValues(alpha: 0.16),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        initial,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Tap a card to speak it.',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionLabel(context, 'Say it — tap to speak'),
                    ...widget.phrases.indexed.map(
                      (entry) => _replyCard(
                        context,
                        _resolve(entry.$2.text),
                        _accents[entry.$1 % _accents.length],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _sectionLabel(context, 'Quick answers'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final answer in staticQuickAnswers)
                          _quickAnswer(context, answer),
                      ],
                    ),
                    if (widget.safety.aiSuggestions) ...[
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: OneVozColors.teal,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Suggested answers',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: OneVozColors.tealDeep,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _dispatcherController,
                        decoration: const InputDecoration(
                          hintText: 'Type what they say',
                          border: OutlineInputBorder(),
                        ),
                        textInputAction: TextInputAction.done,
                        onChanged: _onDispatcherChanged,
                      ),
                      const SizedBox(height: 8),
                      ..._suggestions.indexed.map(
                        (entry) => _replyCard(
                          context,
                          entry.$2.text,
                          OneVozColors.purple,
                          Icons.smart_toy_outlined,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Text(
                      'Speakerphone works best for calls (best-effort on Android).',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }

  /// One speakable reply card: white rounded row with a colored accent
  /// bar on the left and a speaker icon — the mockup's `.reply-card`.
  /// Tapping speaks the text via TTS with a 3-second Undo.
  Widget _replyCard(
    BuildContext context,
    String text, [
    Color accent = OneVozColors.teal,
    IconData icon = Icons.record_voice_over,
  ]) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        elevation: 1,
        child: InkWell(
          onTap: () => _speak(text),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    text,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  icon,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _quickAnswer(BuildContext context, String text) {
    return FilledButton.tonal(
      onPressed: () => _speak(text),
      style: FilledButton.styleFrom(
        minimumSize: const Size(96, 64),
        textStyle: const TextStyle(fontSize: 18),
      ),
      child: Text(text),
    );
  }
}
