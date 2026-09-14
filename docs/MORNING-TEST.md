# VidaVoice — Morning Test Cheat Sheet

For: Adam (non-technical tester). Goal: build the app, get it on a tablet,
and run a 5-minute smoke test. No coding needed.

## Part 1 — Build the APK (on your computer, ~10 minutes first time)

You need the Flutter SDK installed. If `flutter` isn't on your PATH yet,
install it from https://docs.flutter.dev/get-started/install/windows
(Windows) or the macOS/Linux equivalent, then restart your terminal.

```powershell
git clone https://github.com/aitkenadam1/VidaVoice.git
cd VidaVoice
git checkout atlas/overnight-features
flutter pub get
flutter build apk --debug
```

When it finishes, the installable file is at:

```
build\app\outputs\flutter-apk\app-debug.apk
```

(That's a "debug" build — perfect for testing, not for the Play Store.)

## Part 2 — Install it on a tablet

### Regular Android tablet (Samsung, Lenovo, etc.)
1. Copy `app-debug.apk` to the tablet (USB cable, Google Drive, or email it
   to yourself and download it on the tablet).
2. On the tablet, open the file with a file manager.
3. Android will ask permission to "install unknown apps" — allow it for
   your browser/file manager when prompted.
4. Tap **Install**. The VidaVoice icon appears in the app drawer.

### Amazon Fire tablet (sideload)
1. On the Fire tablet: **Settings → Security & Privacy → Apps from Unknown
   Sources** → allow it for the Silk browser (or your file manager).
2. Copy `app-debug.apk` to the tablet (USB cable or download from Drive).
3. Open the file and tap **Install**.

## Part 3 — The 5-minute test script

Do these in order. Everything must work **offline** — turn on airplane
mode first if you want to prove it.

1. **First run.** Open VidaVoice. You should see a welcome screen with the
   VidaVoice logo. Tap **Continue** through the 4 setup steps
   (welcome → name → voice speed → quick tour). Then go back: force-close
   the app, clear its data (Settings → Apps → VidaVoice → Storage → Clear
   data), reopen, and this time tap **Skip for now** — you should land
   straight on the word board.
2. **Tap 10 words.** Tap any 10 words on the home board. Each one should
   speak out loud immediately. (If you hear nothing: the tablet needs a
   text-to-speech engine — install "Google Text-to-Speech" from the
   Play Store / Amazon Appstore and try again.)
3. **Build a sentence.** Tap "I" → "want" → "juice". The words appear in
   the bar at the bottom. Press **Speak** — it should say the whole
   sentence. Press the backspace icon to undo one word, then **Clear**.
4. **Open a folder.** Tap the **Food** tile (🍎). More words appear.
   Tap "apple" — it speaks and lands in the bottom bar. Press the back
   arrow — you're back on the home board, sentence intact.
5. **Switch language.** Tap the ⚙️ **Settings** icon → **Language** →
   **Español**. Every word label changes to Spanish; nothing moves position.
   Tap 3 words (they should speak Spanish). Switch back to English.
6. **Caregiver profile + first-week plan.** Tap the 👨‍👩‍👧 **Caregiver** icon →
   **Add profile**, type a name. Below, find **First-week plan**: open
   Day 1, read the "Try it today" prompt, check the box. The progress bar
   should move to 1 of 7. Switch profiles (or add another) — the plan
   progress is separate per profile.
7. **Voice speed.** Settings → **Voice** → drag the speed slider, press
   **Hear it**. Try the pitch slider too.
8. **Most used words.** Go back to **Caregiver** → scroll to
   **Most used words**. The words you tapped in steps 2–5 should be
   listed, most-tapped first, with counts.
9. **Vocabulary levels.** In **Caregiver** → **Vocabulary level**, choose
   **Level 1 — Starter**. Go back to the word board: you should see far
   fewer words, and the locked ones are blank cells — nothing moved
   position. Open a folder: some words inside are blank too, but never
   the folder tiles themselves. Now set **Level 2**, then **Level 3**:
   more words fill into the blanks each time, and every word you could
   already see is exactly where it was.

## Part 4 — What to write down

For each problem, note: what you tapped, what you expected, what happened.

- Any word that doesn't speak, or speaks the wrong language
- Any picture that clearly doesn't match its word
- Any screen with no obvious way back
- Any text that's confusing for a non-technical caregiver
- Anything that felt slow or broken

Send the notes back and they'll go straight into the next build.
