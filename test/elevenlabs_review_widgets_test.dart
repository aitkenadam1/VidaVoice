import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vidavoice/models/dashboard.dart';
import 'package:vidavoice/services/button_image.dart';
import 'package:vidavoice/services/elevenlabs_key_store.dart';
import 'package:vidavoice/services/elevenlabs_service.dart';
import 'package:vidavoice/services/tts_service.dart';
import 'package:vidavoice/services/voice_sample_recorder.dart';
import 'package:vidavoice/state/session_state.dart';
import 'package:vidavoice/widgets/dashboard_section.dart';
import 'package:vidavoice/widgets/elevenlabs_section.dart';
import 'package:vidavoice/widgets/pick_button_image.dart';

/// TTS double: never touches the platform channel.
class _FakeTts extends TtsService {
  @override
  Future<bool> init({
    required String language,
    double rate = 0.5,
    double pitch = 1.0,
  }) async => true;

  @override
  Future<void> setLanguage(String language) async {}

  @override
  Future<void> setRate(double rate) async {}

  @override
  Future<void> setPitch(double pitch) async {}

  @override
  Future<void> speak(String text) async {}

  @override
  Future<List<TtsVoice>> getVoices() async => const [];

  @override
  Future<void> setVoice(TtsVoice voice) async {}

  @override
  Future<void> clearVoice() async {}
}

/// Scripted cloud service: cloning succeeds with a canned id and every
/// cloud deletion is recorded.
class _ScriptedElevenLabs extends ElevenLabsService {
  _ScriptedElevenLabs() : super(apiKey: 'test-key');

  int cloneCalls = 0;
  String? lastCloneName;
  final deletedIds = <String>[];

  @override
  Future<String> cloneVoice({
    required String name,
    required List<VoiceSample> samples,
  }) async {
    cloneCalls++;
    lastCloneName = name;
    return 'cloned-1';
  }

  @override
  Future<void> deleteVoice(String voiceId) async {
    deletedIds.add(voiceId);
  }
}

/// cloneVoice throws a raw, non-ElevenLabsException error — the dialog must
/// still clear its busy state.
class _RawBoomElevenLabs extends ElevenLabsService {
  _RawBoomElevenLabs() : super(apiKey: 'test-key');

  @override
  Future<String> cloneVoice({
    required String name,
    required List<VoiceSample> samples,
  }) {
    throw StateError('raw boom');
  }
}

/// Recorder double: no microphone, instant 35s sample.
class _FakeRecorder extends VoiceSampleRecorder {
  @override
  Future<void> startSample() async {}

  @override
  Future<VoiceSample> stopSample() async => const VoiceSample(
    path: '/tmp/vv_widget_test_sample.wav',
    duration: Duration(seconds: 35),
  );

  @override
  Future<void> cancelSample() async {}
}

/// Builds a solid-color PNG and prepares it the way the picker would.
String _testImageBase64() {
  final image = img.Image(width: 120, height: 80);
  img.fill(image, color: img.ColorRgb8(40, 120, 200));
  return ButtonImage.prepare(img.encodePng(image))!;
}

/// In-memory keychain: the method-channel mock can't work on desktop test
/// runners (flutter_secure_storage_linux bypasses the channel), so tests
/// inject this through SessionState instead.
class _FakeSecureStore implements SecureValueStore {
  String? key;

  @override
  Future<String?> read(String key) async => this.key;

  @override
  Future<void> write(String key, String value) async => this.key = value;

  @override
  Future<void> delete(String key) async => this.key = null;
}

void main() {
  Future<SessionState> makeSession({String? apiKey}) async {
    SharedPreferences.setMockInitialValues({});
    final session = SessionState(
      tts: _FakeTts(),
      elevenLabsKeys: ElevenLabsKeyStore(
        store: _FakeSecureStore()..key = apiKey,
      ),
    );
    await session.profiles.load();
    return session;
  }

  Future<void> pumpSection(WidgetTester tester, SessionState session) async {
    await tester.pumpWidget(
      // Provider must sit above MaterialApp: dialogs (clone, consent,
      // image picker) open on the root navigator, outside MaterialApp's
      // home subtree, and still need SessionState — same as production.
      // UniqueKey: each pump builds fresh section state (initState reloads
      // the saved-voice list), so tests can re-pump after seeding the
      // store directly — mirroring the clone dialog's _loadSaved on pop.
      ChangeNotifierProvider<SessionState>.value(
        value: session,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ElevenLabsSection(
                key: UniqueKey(),
                onVoicesChanged: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // The BYO key UI lives collapsed under "Advanced" now — expand it so
    // the clone/delete flows below exercise the same widgets as before.
    final tile = find.text('Advanced: use my own ElevenLabs key');
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pumpAndSettle();
  }

  /// Opens the clone dialog with one 35s sample recorded and a name typed.
  Future<void> readyCloneDialog(
    WidgetTester tester, {
    String name = 'Maya test',
  }) async {
    final cloneButton = find.text('Clone a new voice');
    await tester.ensureVisible(cloneButton);
    await tester.pumpAndSettle();
    await tester.tap(cloneButton);
    await tester.pumpAndSettle();
    expect(find.text('Clone a voice'), findsOneWidget);

    await tester.tap(find.text('Record a sample'));
    await tester.pump();
    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(find.textContaining('Sample 1'), findsOneWidget);

    // The section's managed-card sign-in form also has TextFields, so scope
    // the name entry to the clone dialog.
    final nameField = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(nameField, name);
    await tester.pump();
  }

  group('clone consent', () {
    testWidgets('cancel does not upload; accept clones', (tester) async {
      VoiceSampleRecorder.debugFactory = _FakeRecorder.new;
      addTearDown(() => VoiceSampleRecorder.debugFactory = null);
      final deletedPaths = <String>[];
      VoiceSampleRecorder.debugDeleteSampleFile = (path) async {
        deletedPaths.add(path);
      };
      addTearDown(() => VoiceSampleRecorder.debugDeleteSampleFile = null);
      final session = await makeSession(apiKey: 'k');
      final svc = _ScriptedElevenLabs();
      session.tts.elevenLabs = svc;

      await pumpSection(tester, session);
      await readyCloneDialog(tester);

      // Create -> consent dialog appears.
      await tester.tap(find.text('Create voice'));
      await tester.pumpAndSettle();
      expect(find.text('Upload recordings to ElevenLabs?'), findsOneWidget);
      expect(
        find.textContaining('deleted from this device after upload'),
        findsOneWidget,
      );

      // Cancel the consent (the topmost Cancel): no upload happens and the
      // clone dialog stays open.
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(svc.cloneCalls, 0);
      expect(find.text('Upload recordings to ElevenLabs?'), findsNothing);
      expect(find.text('Clone a voice'), findsOneWidget);

      // Accept: the upload happens exactly once.
      await tester.tap(find.text('Create voice'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Upload & create'));
      await tester.pumpAndSettle();
      expect(svc.cloneCalls, 1);
      expect(svc.lastCloneName, 'Maya test');
      // Success closes the clone dialog.
      expect(find.text('Clone a voice'), findsNothing);
      // And the new voice is saved for the profile.
      expect(find.text('Maya test'), findsOneWidget);
      // The local recording was deleted from the device after upload.
      expect(deletedPaths, ['/tmp/vv_widget_test_sample.wav']);
    });
  });

  group('clone failure', () {
    testWidgets('raw error shows a message and clears the busy state', (
      tester,
    ) async {
      VoiceSampleRecorder.debugFactory = _FakeRecorder.new;
      addTearDown(() => VoiceSampleRecorder.debugFactory = null);
      VoiceSampleRecorder.debugDeleteSampleFile = (_) async {};
      addTearDown(() => VoiceSampleRecorder.debugDeleteSampleFile = null);
      final session = await makeSession(apiKey: 'k');
      session.tts.elevenLabs = _RawBoomElevenLabs();

      await pumpSection(tester, session);
      await readyCloneDialog(tester);

      await tester.tap(find.text('Create voice'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Upload & create'));
      await tester.pumpAndSettle();

      // Caregiver-readable error, dialog still open, spinner gone and the
      // Create button usable again — the busy flag was cleared by finally.
      expect(
        find.text('Something went wrong. Please try again.'),
        findsOneWidget,
      );
      expect(find.text('Clone a voice'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Create voice'), findsOneWidget);
    });
  });

  group('voice deletion', () {
    Future<void> seedVoice(
      SessionState session, {
      required String id,
      required String name,
      required bool createdByApp,
    }) async {
      final profileId = session.profiles.active!.id;
      await session.elevenLabsVoices.add(
        profileId,
        SavedElevenLabsVoice(
          id: id,
          name: name,
          locale: 'en',
          createdByApp: createdByApp,
        ),
      );
    }

    testWidgets(
      'remove here only deletes locally; delete everywhere calls the cloud',
      (tester) async {
        final session = await makeSession(apiKey: 'k');
        final svc = _ScriptedElevenLabs();
        session.tts.elevenLabs = svc;
        await seedVoice(
          session,
          id: 'v1',
          name: 'Maya clone',
          createdByApp: true,
        );

        await pumpSection(tester, session);
        expect(find.text('Maya clone'), findsOneWidget);

        // Remove here only: local removal, no cloud call.
        final removeButton1 = find.byTooltip('Remove from profile');
        await tester.ensureVisible(removeButton1);
        await tester.pumpAndSettle();
        await tester.tap(removeButton1);
        await tester.pumpAndSettle();
        expect(find.text('Remove "Maya clone"?'), findsOneWidget);
        await tester.tap(find.text('Remove here only'));
        await tester.pumpAndSettle();
        expect(svc.deletedIds, isEmpty);
        expect(find.text('Maya clone'), findsNothing);

        // Delete everywhere: cloud deletion plus local removal. Re-seed
        // behind the widget's back, then re-pump for fresh section state
        // (initState reloads the saved list, like the clone dialog's pop).
        await seedVoice(
          session,
          id: 'v1',
          name: 'Maya clone',
          createdByApp: true,
        );
        await pumpSection(tester, session);
        expect(find.text('Maya clone'), findsOneWidget);
        final removeButton2 = find.byTooltip('Remove from profile');
        await tester.ensureVisible(removeButton2);
        await tester.pumpAndSettle();
        await tester.tap(removeButton2);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete everywhere'));
        await tester.pumpAndSettle();
        expect(svc.deletedIds, ['v1']);
        expect(find.text('Maya clone'), findsNothing);
      },
    );

    testWidgets(
      'cancel keeps the voice; imported voices never touch the cloud',
      (tester) async {
        final session = await makeSession(apiKey: 'k');
        final svc = _ScriptedElevenLabs();
        session.tts.elevenLabs = svc;
        await seedVoice(
          session,
          id: 'v1',
          name: 'Maya clone',
          createdByApp: true,
        );

        await pumpSection(tester, session);

        // Cancel: nothing is removed anywhere.
        final removeButton3 = find.byTooltip('Remove from profile');
        await tester.ensureVisible(removeButton3);
        await tester.pumpAndSettle();
        await tester.tap(removeButton3);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.text('Maya clone'), findsOneWidget);
        expect(svc.deletedIds, isEmpty);

        // Imported (not app-created) voices are removed locally with no
        // confirmation dialog and never deleted from the cloud. Swap the
        // store contents behind the widget, then re-pump for fresh state.
        await session.elevenLabsVoices.remove(
          session.profiles.active!.id,
          'v1',
        );
        await seedVoice(
          session,
          id: 'v2',
          name: 'Library voice',
          createdByApp: false,
        );
        await pumpSection(tester, session);
        expect(find.text('Library voice'), findsOneWidget);
        final removeButton4 = find.byTooltip('Remove from profile');
        await tester.ensureVisible(removeButton4);
        await tester.pumpAndSettle();
        await tester.tap(removeButton4);
        await tester.pumpAndSettle();
        expect(find.text('Remove "Library voice"?'), findsNothing);
        expect(find.text('Library voice'), findsNothing);
        expect(svc.deletedIds, isEmpty);
      },
    );
  });

  group('custom button images', () {
    Future<void> pumpDashboard(
      WidgetTester tester,
      SessionState session,
    ) async {
      await tester.pumpWidget(
        // Provider above MaterialApp (see pumpSection): the add/edit
        // dialogs open on the root navigator and need SessionState.
        ChangeNotifierProvider<SessionState>.value(
          value: session,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: DashboardSection(refresh: () {}),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('choose, change, and remove image in the add dialog', (
      tester,
    ) async {
      debugPickButtonImage = () async => _testImageBase64();
      addTearDown(() => debugPickButtonImage = null);
      final session = await makeSession();

      await pumpDashboard(tester, session);
      await tester.tap(find.text('Add custom'));
      await tester.pumpAndSettle();
      expect(find.text('Custom button'), findsOneWidget);
      expect(find.text('Choose image'), findsOneWidget);
      expect(find.text('Remove image'), findsNothing);

      // Choose: preview appears with change/remove actions.
      await tester.tap(find.text('Choose image'));
      await tester.pumpAndSettle();
      expect(find.text('Choose image'), findsNothing);
      expect(find.text('Change image'), findsOneWidget);
      expect(find.text('Remove image'), findsOneWidget);

      // Remove: back to the empty state.
      await tester.tap(find.text('Remove image'));
      await tester.pump();
      expect(find.text('Choose image'), findsOneWidget);
      expect(find.text('Remove image'), findsNothing);
    });

    testWidgets('saved custom button keeps its image', (tester) async {
      final picked = _testImageBase64();
      debugPickButtonImage = () async => picked;
      addTearDown(() => debugPickButtonImage = null);
      final session = await makeSession();

      await pumpDashboard(tester, session);
      await tester.tap(find.text('Add custom'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choose image'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Break please');
      await tester.pump();
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      final profileId = session.profiles.active!.id;
      final dashboard = session.dashboards.forProfile(profileId)!;
      final cell = dashboard.cells.firstWhere((c) => c.label == 'Break please');
      expect(cell.imageData, picked);
      // And the stored bytes decode to the picked image.
      expect(base64.decode(cell.imageData!), isNotEmpty);
    });

    testWidgets('edit dialog can change and remove an existing image', (
      tester,
    ) async {
      final picked = _testImageBase64();
      debugPickButtonImage = () async => _testImageBase64();
      addTearDown(() => debugPickButtonImage = null);
      final session = await makeSession();
      final profileId = session.profiles.active!.id;

      // Seed a custom cell that already has an image.
      final dashboard = session.dashboards.ensureFor(profileId);
      dashboard.cells.add(
        DashboardCell(
          id: 'c1',
          label: 'Break please',
          speakText: 'I need a break',
          imageData: picked,
        ),
      );
      await session.dashboards.save(dashboard);

      await pumpDashboard(tester, session);
      // Open the edit dialog for the custom cell.
      await tester.tap(find.byTooltip('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Edit button'), findsOneWidget);
      expect(find.text('Change image'), findsOneWidget);

      // Remove the image and save: the cell keeps its label, loses the image.
      await tester.tap(find.text('Remove image'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final updated = session.dashboards
          .forProfile(profileId)!
          .cells
          .firstWhere((c) => c.id == 'c1');
      expect(updated.imageData, isNull);
      expect(updated.label, 'Break please');
    });
  });
}
