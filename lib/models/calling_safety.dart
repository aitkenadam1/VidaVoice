/// Calling & safety models (Phase 1).
///
/// Everything in this file travels inside the existing end-to-end encrypted
/// sync blob (see DashboardSyncService) — never plaintext to any endpoint,
/// never as new backend fields. Contacts, phrases, and emergency info are
/// per-profile data on [UserProfile]; these classes are the serializable
/// value objects they use.
library;

/// One trusted contact the child can call during the Phase 1 calling flow.
class SafetyContact {
  const SafetyContact({
    required this.id,
    this.name = '',
    this.phone = '',
    this.imageData,
    this.kind = 'custom',
  });

  /// Stable contact id (never a phone number — numbers change).
  final String id;

  /// Display name, e.g. "Mom".
  final String name;

  /// Dialable phone number, digits with any formatting the caregiver typed.
  final String phone;

  /// Base64-encoded photo, same convention as [DashboardCell.imageData].
  /// Null when none.
  final String? imageData;

  /// Contact kind: 'mom', 'dad', 'grandparent', 'custom', ... Free-form;
  /// unknown kinds survive the round trip untouched.
  final String kind;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'phone': phone,
    if (imageData != null) 'imageData': imageData,
    'kind': kind,
  };

  factory SafetyContact.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('SafetyContact needs a non-empty id.');
    }
    final name = json['name'];
    final phone = json['phone'];
    final imageData = json['imageData'];
    final kind = json['kind'];
    return SafetyContact(
      id: id,
      name: name is String ? name : '',
      phone: phone is String ? phone : '',
      imageData: imageData is String && imageData.isNotEmpty
          ? imageData
          : null,
      kind: kind is String && kind.isNotEmpty ? kind : 'custom',
    );
  }
}

/// A pre-written phrase the child can speak during a call.
class CallPhrase {
  const CallPhrase({required this.id, this.text = ''});

  /// Stable phrase id.
  final String id;

  /// The phrase text. May contain placeholders resolved at send time:
  /// {child_name} {home_address} {parent_name} {parent_phone} {gps}.
  final String text;

  Map<String, dynamic> toJson() => {'id': id, 'text': text};

  factory CallPhrase.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('CallPhrase needs a non-empty id.');
    }
    final text = json['text'];
    return CallPhrase(id: id, text: text is String ? text : '');
  }
}

/// The child's emergency details, used for the emergency SMS and for
/// placeholder resolution in call phrases. Stored per profile.
class EmergencyProfileData {
  const EmergencyProfileData({
    this.childName = '',
    this.homeAddress = '',
    this.parentName = '',
    this.parentPhone = '',
    this.medicalNotes = '',
    this.emergencyEnabled = true,
  });

  final String childName;
  final String homeAddress;
  final String parentName;
  final String parentPhone;
  final String medicalNotes;

  /// Whether the emergency flow is available for this profile. Defaults
  /// true; the caregiver can switch it off per child.
  final bool emergencyEnabled;

  Map<String, dynamic> toJson() => {
    'childName': childName,
    'homeAddress': homeAddress,
    'parentName': parentName,
    'parentPhone': parentPhone,
    'medicalNotes': medicalNotes,
    'emergencyEnabled': emergencyEnabled,
  };

  factory EmergencyProfileData.fromJson(Map<String, dynamic> json) {
    // Migration-safe: every key is optional; a pre-feature map yields the
    // defaults. Only apply a value when its type is exactly right.
    String s(Object? v) => v is String ? v : '';
    return EmergencyProfileData(
      childName: s(json['childName']),
      homeAddress: s(json['homeAddress']),
      parentName: s(json['parentName']),
      parentPhone: s(json['parentPhone']),
      medicalNotes: s(json['medicalNotes']),
      emergencyEnabled: json['emergencyEnabled'] is bool
          ? (json['emergencyEnabled'] as bool)
          : true,
    );
  }
}

/// Calling & safety behavior toggles, stored per profile.
class SafetySettings {
  const SafetySettings({this.aiSuggestions = true, this.preferOwnPhrases = true});

  /// Whether AI-suggested phrases may appear in the calling flow.
  final bool aiSuggestions;

  /// Whether the child's own phrases are preferred over suggestions.
  final bool preferOwnPhrases;

  Map<String, dynamic> toJson() => {
    'aiSuggestions': aiSuggestions,
    'preferOwnPhrases': preferOwnPhrases,
  };

  factory SafetySettings.fromJson(Map<String, dynamic> json) {
    return SafetySettings(
      aiSuggestions: json['aiSuggestions'] is bool
          ? (json['aiSuggestions'] as bool)
          : true,
      preferOwnPhrases: json['preferOwnPhrases'] is bool
          ? (json['preferOwnPhrases'] as bool)
          : true,
    );
  }
}

/// Replaces {child_name} {home_address} {parent_name} {parent_phone} with
/// the emergency profile's fields; {gps} resolves to [gps] or '' when no
/// location was provided. Pure: never touches storage or the network.
String resolvePlaceholders(
  String text,
  EmergencyProfileData e, {
  String? gps,
}) {
  return text
      .replaceAll('{child_name}', e.childName)
      .replaceAll('{home_address}', e.homeAddress)
      .replaceAll('{parent_name}', e.parentName)
      .replaceAll('{parent_phone}', e.parentPhone)
      .replaceAll('{gps}', gps ?? '');
}

/// The starter phrase bank seeded into every new profile. Caregivers edit
/// or replace it from here — these are safe, generic, always-useful lines.
List<CallPhrase> defaultCallPhrases() => const [
  CallPhrase(id: 'intro', text: 'Hi, this is {child_name}'),
  CallPhrase(id: 'need-help', text: 'I need help'),
  CallPhrase(id: 'im-okay', text: "I'm okay"),
  CallPhrase(id: 'call-mom', text: 'Please call my mom'),
  CallPhrase(id: 'lost', text: "I'm lost"),
];

/// One-tap answers the child can give during a call, without composing.
List<String> get staticQuickAnswers => const [
  'Yes',
  'No',
  "I don't know",
  'Please repeat that',
  'I need help',
  'Hold on',
];

/// Composes the emergency SMS from the profile's emergency data. Empty
/// fields are skipped gracefully — no dangling labels or trailing junk.
/// The GPS segment appears only when [gps] is non-null and non-blank.
String composeEmergencySms(EmergencyProfileData e, {String? gps}) {
  final parts = <String>[];
  final child = e.childName.trim();
  parts.add(
    child.isNotEmpty
        ? 'EMERGENCY - $child is nonverbal, please communicate by text.'
        : 'EMERGENCY - nonverbal, please communicate by text.',
  );
  final address = e.homeAddress.trim();
  if (address.isNotEmpty) {
    parts.add('Address: $address.');
  }
  final parent = [
    e.parentName.trim(),
    e.parentPhone.trim(),
  ].where((s) => s.isNotEmpty).join(' ');
  if (parent.isNotEmpty) {
    parts.add('Parent: $parent.');
  }
  final loc = gps?.trim() ?? '';
  if (loc.isNotEmpty) {
    parts.add('GPS: $loc.');
  }
  return parts.join(' ');
}

/// Builds a dialable `tel:` URI from a caregiver-entered phone number.
///
/// Keeps a single leading `+` and ASCII digits; drops spaces, dashes,
/// parentheses and anything else the dialer can't use, so numbers typed
/// casually ("+1 555 010 2030") still dial.
Uri telUri(String phone) {
  final cleaned = phone.replaceAll(RegExp(r'[^0-9+]'), '');
  final normalized = cleaned.startsWith('+')
      ? '+${cleaned.substring(1).replaceAll('+', '')}'
      : cleaned.replaceAll('+', '');
  return Uri(scheme: 'tel', path: normalized);
}

/// Builds a native SMS composer URI with a prefilled body.
///
/// iOS only honors the prefilled body after `&` (`sms:911&body=…`);
/// Android expects the usual `?body=…`. Pass [iosStyle] from the caller's
/// platform check — the OS Send button stays the human gate either way.
Uri smsUri(String number, String body, {required bool iosStyle}) {
  final encoded = Uri.encodeComponent(body);
  return Uri.parse('sms:$number${iosStyle ? '&' : '?'}body=$encoded');
}
