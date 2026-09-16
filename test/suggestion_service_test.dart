/// Unit tests for [SuggestionService].
///
/// Pure-Dart tests (flutter_test only for the harness): no storage, no
/// network, no logging anywhere in the service under test.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:onevoz/models/calling_safety.dart';
import 'package:onevoz/services/suggestion_service.dart';

const _profile = EmergencyProfileData(
  childName: 'Mia',
  homeAddress: '123 Main St',
);

const _gps = '40.7,-74.0';

List<Suggestion> suggest({
  required String text,
  List<CallPhrase> bank = const [],
  bool preferOwnPhrases = true,
  bool emergencyMode = false,
  EmergencyProfileData? emergency = _profile,
  String? gps,
}) {
  return SuggestionService().suggestionsFor(
    incomingText: text,
    bank: bank,
    preferOwnPhrases: preferOwnPhrases,
    emergencyMode: emergencyMode,
    emergency: emergency,
    gps: gps,
  );
}

void main() {
  group('bank-first ranking', () {
    const addressBank = [
      CallPhrase(id: 'addr', text: 'My address is {home_address}'),
    ];

    test('bank phrase matching the intent wins when preferOwnPhrases=true', () {
      final result = suggest(
        text: 'What is your address?',
        bank: addressBank,
        preferOwnPhrases: true,
      );
      expect(result, isNotEmpty);
      expect(result.first.source, 'bank');
      expect(result.first.text, 'My address is 123 Main St');
    });

    test('vetted set wins when preferOwnPhrases=false', () {
      final result = suggest(
        text: 'What is your address?',
        bank: addressBank,
        preferOwnPhrases: false,
      );
      expect(
        result.any((s) => s.source == 'bank'),
        isFalse,
        reason: 'no bank card should be offered when preferOwnPhrases=false',
      );
      expect(
        result.any((s) => s.text == 'My address is 123 Main St'),
        isTrue,
      );
    });

    test('bank matching is intent-scoped: no cross-intent wins', () {
      final result = suggest(
        text: 'Do you need help?',
        bank: addressBank,
        preferOwnPhrases: true,
      );
      expect(result.any((s) => s.source == 'bank'), isFalse);
      expect(result.any((s) => s.text == 'I need help'), isTrue);
    });

    test('placeholders in bank phrases are resolved', () {
      final result = suggest(
        text: 'Who is this?',
        bank: const [
          CallPhrase(id: 'intro', text: 'My name is {child_name}'),
        ],
      );
      expect(result.first.text, 'My name is Mia');
      expect(result.first.source, 'bank');
      expect(result.first.text.contains('{'), isFalse);
    });
  });

  group('emergency intent', () {
    test('emergency set in emergencyMode', () {
      final result = suggest(
        text: 'What is your emergency?',
        emergencyMode: true,
        preferOwnPhrases: false,
      );
      expect(
        result.map((s) => s.text),
        ['Fire', 'Medical emergency', 'Someone is hurt', 'Break-in'],
      );
      expect(result.every((s) => s.source == 'emergency'), isTrue);
    });

    test('emergency set NOT offered outside emergencyMode', () {
      final result = suggest(
        text: "What's wrong?",
        emergencyMode: false,
        preferOwnPhrases: false,
      );
      expect(
        result.any((s) =>
            ['Fire', 'Medical emergency', 'Someone is hurt', 'Break-in']
                .contains(s.text)),
        isFalse,
      );
      // Falls back to the static quick answers.
      expect(
        result.map((s) => s.text).toList(),
        staticQuickAnswers.take(4).toList(),
      );
    });

    test('bank may still answer an emergency question outside emergencyMode',
        () {
      final result = suggest(
        text: 'What happened?',
        emergencyMode: false,
        preferOwnPhrases: true,
        bank: const [
          CallPhrase(id: 'e1', text: 'There is a fire at my house'),
        ],
      );
      expect(result.first.source, 'bank');
      expect(result.first.text, 'There is a fire at my house');
      expect(result.any((s) => s.source == 'emergency'), isFalse);
    });

    test("what's your emergency variant also matches", () {
      final result = suggest(
        text: "What's your emergency?",
        emergencyMode: true,
        preferOwnPhrases: false,
      );
      expect(result.map((s) => s.text), contains('Fire'));
    });
  });

  group('address intent', () {
    test('resolves {home_address} and offers GPS card when gps given', () {
      final result = suggest(
        text: 'Where are you right now?',
        preferOwnPhrases: false,
        gps: _gps,
      );
      expect(
        result.any((s) => s.text == 'Send my GPS location'),
        isTrue,
      );
      expect(
        result.any((s) => s.text == 'My address is 123 Main St'),
        isTrue,
      );
      expect(result.any((s) => s.text.contains('{')), isFalse);
    });

    test('no GPS card when gps is null', () {
      final result = suggest(
        text: 'What is your address?',
        preferOwnPhrases: false,
      );
      expect(
        result.any((s) => s.text == 'Send my GPS location'),
        isFalse,
      );
      expect(
        result.any((s) => s.text == 'My address is 123 Main St'),
        isTrue,
      );
    });

    test('no address card when profile has no address', () {
      final result = suggest(
        text: 'What is your address?',
        preferOwnPhrases: false,
        emergency: const EmergencyProfileData(childName: 'Mia'),
        gps: _gps,
      );
      // Only the GPS card comes from the intent set; the rest is padding.
      expect(result.any((s) => s.text == 'Send my GPS location'), isTrue);
      expect(result.any((s) => s.text.contains('address is')), isFalse);
    });
  });

  group('other intents', () {
    test('alone intent', () {
      final result = suggest(
        text: 'Are you alone? Is anyone with you?',
        preferOwnPhrases: false,
      );
      expect(
        result.map((s) => s.text),
        containsAll(["Yes", "No, I'm alone", "I don't know"]),
      );
    });

    test('are-you-ok intent', () {
      final result = suggest(
        text: 'Are you okay? Are you hurt?',
        preferOwnPhrases: false,
      );
      expect(
        result.map((s) => s.text),
        containsAll(["I'm okay", 'I need help', "I'm scared"]),
      );
    });

    test('name intent resolves {child_name}', () {
      final result = suggest(
        text: 'What is your name? Who is this?',
        preferOwnPhrases: false,
      );
      expect(result.any((s) => s.text == 'Hi, this is Mia'), isTrue);
      expect(result.any((s) => s.text.contains('{child_name}')), isFalse);
    });

    test('name intent without profile uses safe static wording', () {
      final result = suggest(
        text: 'Who is this?',
        preferOwnPhrases: false,
        emergency: null,
      );
      expect(result.any((s) => s.text == 'Hi, this is me'), isTrue);
      expect(result.any((s) => s.text.contains('{')), isFalse);
    });

    test('help intent', () {
      final result = suggest(
        text: 'Do you need help with anything?',
        preferOwnPhrases: false,
      );
      expect(
        result.map((s) => s.text),
        containsAll(['I need help', 'Please call my parent']),
      );
    });

    test("'need' does not fire inside unrelated words", () {
      // "knee" contains "nee" but not the word "need" — and "help"/"need"
      // as whole words must not match inside other words.
      final result = suggest(
        text: 'My knee hurts a bit',
        preferOwnPhrases: false,
      );
      expect(
        result.map((s) => s.text).toList(),
        staticQuickAnswers.take(4).toList(),
      );
    });
  });

  group('fallback and empty input', () {
    test('gibberish falls back to staticQuickAnswers', () {
      final result = suggest(
        text: 'zxqwv blorp fnord',
        preferOwnPhrases: false,
      );
      expect(
        result.map((s) => s.text).toList(),
        staticQuickAnswers.take(4).toList(),
      );
      expect(result.every((s) => s.source == 'static'), isTrue);
    });

    test('empty input returns staticQuickAnswers', () {
      final result = suggest(text: '', preferOwnPhrases: false);
      expect(
        result.map((s) => s.text).toList(),
        staticQuickAnswers.take(4).toList(),
      );
    });

    test('whitespace-only input returns staticQuickAnswers', () {
      final result = suggest(text: '   \n\t  ', preferOwnPhrases: false);
      expect(
        result.map((s) => s.text).toList(),
        staticQuickAnswers.take(4).toList(),
      );
    });
  });

  group('card-count and purity guarantees', () {
    test('never more than 4 cards, never fewer than 3', () {
      final inputs = [
        '',
        'zxqwv blorp',
        'What is your emergency?',
        'Where are you?',
        'Who is this?',
        'Do you need help?',
        'Are you alone?',
        'Are you okay?',
      ];
      for (final input in inputs) {
        for (final prefer in [true, false]) {
          for (final emergencyMode in [true, false]) {
            final result = suggest(
              text: input,
              preferOwnPhrases: prefer,
              emergencyMode: emergencyMode,
              gps: _gps,
            );
            expect(result.length, lessThanOrEqualTo(4),
                reason: 'input "$input"');
            expect(result.length, greaterThanOrEqualTo(3),
                reason: 'input "$input"');
          }
        }
      }
    });

    test('no duplicate cards (case-insensitive)', () {
      // "I need help" is both a bank match and a quick answer — it must
      // appear exactly once.
      final result = suggest(
        text: 'Do you need help?',
        bank: const [CallPhrase(id: 'h', text: 'I need help')],
      );
      final keys = result.map((s) => s.text.toLowerCase()).toList();
      expect(keys.toSet().length, keys.length);
    });

    test('pure function: identical calls return equal results', () {
      final args = (
        incomingText: 'What is your address?',
        bank: const [CallPhrase(id: 'a', text: 'My address is {home_address}')],
        preferOwnPhrases: true,
        emergencyMode: false,
        emergency: _profile,
        gps: _gps,
      );
      List<Suggestion> call() => SuggestionService().suggestionsFor(
            incomingText: args.incomingText,
            bank: args.bank,
            preferOwnPhrases: args.preferOwnPhrases,
            emergencyMode: args.emergencyMode,
            emergency: args.emergency,
            gps: args.gps,
          );
      expect(call(), equals(call()));
      // A second service instance behaves identically: no hidden state.
      expect(SuggestionService().suggestionsFor(
            incomingText: args.incomingText,
            bank: args.bank,
            preferOwnPhrases: args.preferOwnPhrases,
            emergencyMode: args.emergencyMode,
            emergency: args.emergency,
            gps: args.gps,
          ),
          equals(call()));
    });

    test('no raw placeholders leak in any suggestion', () {
      final inputs = [
        'Where are you?',
        'Who is this?',
        'What is your address?',
      ];
      for (final input in inputs) {
        final result = suggest(text: input, gps: _gps);
        for (final card in result) {
          expect(card.text.contains('{') || card.text.contains('}'), isFalse,
              reason: 'card "${card.text}" for input "$input"');
        }
      }
    });
  });
}
