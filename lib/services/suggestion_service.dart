/// On-device AI-suggested replies for the OneVoz calling flow (Phase 1).
///
/// PRIVACY CONTRACT — this service is pure computation over the inputs it is
/// handed. It keeps no state, writes nothing to disk, sends nothing over the
/// network, and produces no logs or analytics. Suggestion content (including
/// the caller's own bank phrases) exists only in memory for the duration of
/// the call and is never persisted. This upholds the same no-content promise
/// as the encrypted dashboard sync: the device answers, but it does not
/// remember what was said.
///
/// STATELESS BY DESIGN — [SuggestionService] holds no fields and remembers
/// nothing between invocations. The caller re-invokes [suggestionsFor] for
/// every new incoming message, so the newest question always wins: the
/// suggestion set reflects only the latest text it was given.
///
/// LATENCY — intent detection is a handful of in-memory keyword scans over a
/// single short utterance. There is no I/O, no model load, and no network
/// round trip, so the 2s on-device latency budget from the spec is met
/// trivially (microseconds, not seconds).
///
/// This file imports only `package:onevoz/models/calling_safety.dart` — pure
/// Dart, no flutter/material imports — so it is unit-testable on the VM.
library;

import 'package:onevoz/models/calling_safety.dart';

/// One suggested reply card.
///
/// [source] is 'bank' for a caregiver-authored phrase that matched the
/// detected intent, 'emergency' for a vetted emergency-mode reply set, or
/// 'static' for vetted static content (quick answers and the non-emergency
/// vetted intent sets).
class Suggestion {
  const Suggestion({required this.text, required this.source});

  final String text;
  final String source;

  @override
  bool operator ==(Object other) =>
      other is Suggestion && other.text == text && other.source == source;

  @override
  int get hashCode => Object.hash(text, source);

  @override
  String toString() => 'Suggestion(source: $source, text: "$text")';
}

/// Detected intent of the caller's latest utterance.
enum _Intent {
  emergency,
  address,
  alone,
  areYouOk,
  name,
  help,
  none,
}

/// Pure, stateless suggestion engine for in-call replies.
///
/// See the library doc comment for the privacy and statelessness contracts.
class SuggestionService {
  /// Detection patterns per intent (spec §5). Checked in this order, most
  /// specific first.
  static const Map<_Intent, List<String>> _intentPatterns = {
    _Intent.emergency: [
      'what is your emergency',
      "what's your emergency",
      'what happened',
      "what's wrong",
      'what is wrong',
    ],
    _Intent.address: ['address', 'where are you', 'location'],
    _Intent.alone: ['anyone with you', 'are you alone'],
    _Intent.areYouOk: [
      'are you okay',
      'are you ok',
      'are you hurt',
      'are you safe',
    ],
    _Intent.name: ['your name', 'who is this'],
    _Intent.help: ['help', 'need'],
  };

  /// Content keywords per intent, used for bank-phrase matching: a caregiver
  /// phrase "shares a keyword with the detected intent" when its normalized
  /// text contains any of these. Single words match on word boundaries;
  /// multi-word phrases match as phrases.
  static const Map<_Intent, List<String>> _bankKeywords = {
    _Intent.emergency: [
      'emergency',
      'fire',
      'medical',
      'hurt',
      'break-in',
      'happened',
      'wrong',
    ],
    _Intent.address: ['address', 'location', 'gps'],
    _Intent.alone: ['alone', 'anyone'],
    _Intent.areYouOk: ['okay', 'ok', 'hurt', 'safe', 'scared'],
    _Intent.name: ['name', 'who is this'],
    _Intent.help: ['help', 'need'],
  };

  /// Suggest 3-4 reply cards for [incomingText].
  ///
  /// - [bank] is the caregiver-authored phrase bank, checked first when
  ///   [preferOwnPhrases] is true.
  /// - [emergencyMode] gates the emergency reply set (Fire, Medical
  ///   emergency, ...); it is only ever offered in emergency mode.
  /// - [emergency] provides placeholder values ({child_name}, {home_address},
  ///   ...) resolved through [resolvePlaceholders]. When null, intent sets
  ///   fall back to safe static wording and bank phrases are used verbatim.
  /// - [gps] is the child's current location string; it enables the
  ///   "Send my GPS location" card and resolves {gps} placeholders.
  List<Suggestion> suggestionsFor({
    required String incomingText,
    required List<CallPhrase> bank,
    required bool preferOwnPhrases,
    required bool emergencyMode,
    EmergencyProfileData? emergency,
    String? gps,
  }) {
    final normalized = incomingText.toLowerCase().trim();

    // Empty / whitespace input: no signal, offer the static quick answers.
    if (normalized.isEmpty) {
      return _finalize(
        staticQuickAnswers
            .map((t) => Suggestion(text: t, source: 'static'))
            .toList(),
      );
    }

    final intent = _detectIntent(normalized);

    // The emergency reply set is reserved for emergency mode: outside it,
    // the emergency intent is treated as low-confidence for the *vetted*
    // set. The caregiver bank may still answer (it is their own vetted
    // content); otherwise the static quick answers win. The emergency set
    // is never surfaced in a non-emergency call.
    final emergencyGated = intent == _Intent.emergency && !emergencyMode;

    final quickCards = staticQuickAnswers
        .map((t) => Suggestion(text: t, source: 'static'))
        .toList();

    List<Suggestion> cards;
    if (preferOwnPhrases && intent != _Intent.none) {
      final bankHit = _findBankMatch(bank, intent, emergency, gps);
      if (bankHit != null) {
        cards = [bankHit];
      } else if (emergencyGated) {
        cards = quickCards;
      } else {
        cards = _vettedSet(
          intent,
          emergencyMode: emergencyMode,
          emergency: emergency,
          gps: gps,
        );
      }
    } else if (intent != _Intent.none && !emergencyGated) {
      cards = _vettedSet(
        intent,
        emergencyMode: emergencyMode,
        emergency: emergency,
        gps: gps,
      );
    } else {
      // Low confidence: no intent matched, or an emergency question outside
      // emergency mode with no bank answer. Never invent sensitive
      // content — no medical advice, no personal data beyond placeholders.
      cards = quickCards;
    }

    return _finalize(cards);
  }

  /// Detects the intent of the normalized utterance. Most specific patterns
  /// are checked first; "help"/"need" match on word boundaries so they do
  /// not fire inside unrelated words.
  _Intent _detectIntent(String normalized) {
    bool contains(String pattern) => normalized.contains(pattern);
    bool word(String w) =>
        RegExp('\\b${RegExp.escape(w)}\\b').hasMatch(normalized);

    if (_intentPatterns[_Intent.emergency]!.any(contains)) {
      return _Intent.emergency;
    }
    if (_intentPatterns[_Intent.address]!.any(contains)) {
      return _Intent.address;
    }
    if (_intentPatterns[_Intent.alone]!.any(contains)) {
      return _Intent.alone;
    }
    if (_intentPatterns[_Intent.areYouOk]!.any(contains)) {
      return _Intent.areYouOk;
    }
    if (_intentPatterns[_Intent.name]!.any(contains)) {
      return _Intent.name;
    }
    if (word('help') || word('need')) {
      return _Intent.help;
    }
    return _Intent.none;
  }

  /// Returns the first bank phrase (caregiver-curated order wins) whose
  /// normalized text shares a keyword with [intent], with placeholders
  /// resolved. Null when nothing matches.
  Suggestion? _findBankMatch(
    List<CallPhrase> bank,
    _Intent intent,
    EmergencyProfileData? emergency,
    String? gps,
  ) {
    final keywords = _bankKeywords[intent] ?? const <String>[];
    for (final phrase in bank) {
      final text = phrase.text.toLowerCase();
      final matches = keywords.any((k) {
        // Short single-word keywords match on word boundaries to avoid
        // false positives; multi-word patterns match as phrases.
        if (!k.contains(' ')) {
          return RegExp('\\b${RegExp.escape(k)}\\b').hasMatch(text);
        }
        return text.contains(k);
      });
      if (!matches) {
        continue;
      }
      final resolved = emergency != null
          ? resolvePlaceholders(phrase.text, emergency, gps: gps)
          : phrase.text;
      return Suggestion(text: resolved, source: 'bank');
    }
    return null;
  }

  /// Vetted reply sets per intent. Only ever invented-safe content: the
  /// sets below, placeholders resolved from the emergency profile, and
  /// nothing else.
  List<Suggestion> _vettedSet(
    _Intent intent, {
    required bool emergencyMode,
    required EmergencyProfileData? emergency,
    required String? gps,
  }) {
    String resolve(String template) => emergency != null
        ? resolvePlaceholders(template, emergency, gps: gps)
        : template;

    switch (intent) {
      case _Intent.emergency:
        // Offered ONLY when emergencyMode is true (enforced by the caller of
        // this method via the gating in suggestionsFor).
        return const [
          Suggestion(text: 'Fire', source: 'emergency'),
          Suggestion(text: 'Medical emergency', source: 'emergency'),
          Suggestion(text: 'Someone is hurt', source: 'emergency'),
          Suggestion(text: 'Break-in', source: 'emergency'),
        ];
      case _Intent.address:
        final cards = <Suggestion>[];
        if (gps != null && gps.trim().isNotEmpty) {
          cards.add(
            const Suggestion(
              text: 'Send my GPS location',
              source: 'static',
            ),
          );
        }
        final address = emergency?.homeAddress.trim() ?? '';
        if (address.isNotEmpty) {
          cards.add(
            Suggestion(
              text: resolve('My address is {home_address}'),
              source: 'static',
            ),
          );
        }
        return cards;
      case _Intent.alone:
        return const [
          Suggestion(text: 'Yes', source: 'static'),
          Suggestion(text: "No, I'm alone", source: 'static'),
          Suggestion(text: "I don't know", source: 'static'),
        ];
      case _Intent.areYouOk:
        return const [
          Suggestion(text: "I'm okay", source: 'static'),
          Suggestion(text: 'I need help', source: 'static'),
          Suggestion(text: "I'm scared", source: 'static'),
        ];
      case _Intent.name:
        final childName = emergency?.childName.trim() ?? '';
        return [
          Suggestion(
            text: childName.isNotEmpty
                ? resolve('Hi, this is {child_name}')
                : 'Hi, this is me',
            source: 'static',
          ),
        ];
      case _Intent.help:
        return const [
          Suggestion(text: 'I need help', source: 'static'),
          Suggestion(text: 'Please call my parent', source: 'static'),
        ];
      case _Intent.none:
        return const [];
    }
  }

  /// Post-processing applied to every result: dedupe (case-insensitive,
  /// order-preserving), pad from [staticQuickAnswers] to a minimum of 3
  /// cards, and cap at 4.
  List<Suggestion> _finalize(List<Suggestion> cards) {
    final seen = <String>{};
    final deduped = <Suggestion>[];
    for (final card in cards) {
      final key = card.text.toLowerCase().trim();
      if (key.isEmpty || !seen.add(key)) {
        continue;
      }
      deduped.add(card);
    }
    for (final quick in staticQuickAnswers) {
      if (deduped.length >= 3) {
        break;
      }
      final key = quick.toLowerCase().trim();
      if (seen.add(key)) {
        deduped.add(Suggestion(text: quick, source: 'static'));
      }
    }
    return deduped.take(4).toList();
  }
}
