import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/calling_safety.dart';
import '../../state/session_state.dart';
import '../pick_button_image.dart';

/// Contact list editor for the Calling & Safety hub and guided setup flow.
///
/// Reads the profile's contacts and writes through
/// [ProfileService.setContacts]. The session's onChanged wiring schedules
/// the encrypted sync push automatically, so this widget only rebuilds
/// locally after each save.
class ContactListEditor extends StatefulWidget {
  const ContactListEditor({
    super.key,
    required this.profileId,
    this.onChanged,
  });

  final String profileId;
  final VoidCallback? onChanged;

  @override
  State<ContactListEditor> createState() => _ContactListEditorState();
}

class _ContactListEditorState extends State<ContactListEditor> {
  bool _saving = false;

  List<SafetyContact> _contacts(SessionState session) {
    for (final p in session.profiles.profiles) {
      if (p.id == widget.profileId) return List.of(p.contacts);
    }
    return const [];
  }

  Future<void> _save(SessionState session, List<SafetyContact> contacts) async {
    setState(() => _saving = true);
    try {
      await session.profiles.setContacts(widget.profileId, contacts);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    widget.onChanged?.call();
  }

  Future<void> _addDialog(SessionState session) async {
    final result = await showDialog<SafetyContact>(
      context: context,
      builder: (ctx) => _ContactDialog(
        existing: _contacts(session),
      ),
    );
    if (result == null || !mounted) return;
    final sessionNow = context.read<SessionState>();
    await _save(sessionNow, [..._contacts(sessionNow), result]);
  }

  Future<void> _editDialog(SessionState session, SafetyContact contact) async {
    final result = await showDialog<SafetyContact>(
      context: context,
      builder: (ctx) => _ContactDialog(
        initial: contact,
        existing: _contacts(session),
      ),
    );
    if (result == null || !mounted) return;
    final sessionNow = context.read<SessionState>();
    final updated = [
      for (final c in _contacts(sessionNow))
        if (c.id == contact.id) result else c,
    ];
    await _save(sessionNow, updated);
  }

  Future<void> _deleteDialog(SessionState session, SafetyContact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove contact?'),
        content: Text(
          '${contact.name} will no longer be available to call from this '
          'profile. You can add them back any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final sessionNow = context.read<SessionState>();
    await _save(
      sessionNow,
      [
        for (final c in _contacts(sessionNow))
          if (c.id != contact.id) c,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final contacts = _contacts(session);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (contacts.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Text(
              'No contacts yet. Add the people they should be able to '
              'reach — family first, then anyone else they call often.',
              style: TextStyle(fontSize: 13),
            ),
          )
        else
          for (final c in contacts) _contactRow(session, c),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: OutlinedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add contact'),
            onPressed: _saving ? null : () => _addDialog(session),
          ),
        ),
        if (_saving)
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }

  Widget _contactRow(SessionState session, SafetyContact contact) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      leading: _avatar(contact),
      title: Text(contact.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(contact.phone),
          const SizedBox(height: 2),
          _kindChip(contact.kind),
        ],
      ),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Edit ${contact.name}',
            icon: const Icon(Icons.edit_outlined),
            onPressed: _saving ? null : () => _editDialog(session, contact),
          ),
          IconButton(
            tooltip: 'Remove ${contact.name}',
            icon: const Icon(Icons.delete_outline),
            onPressed: _saving ? null : () => _deleteDialog(session, contact),
          ),
        ],
      ),
      onTap: _saving ? null : () => _editDialog(session, contact),
    );
  }

  Widget _avatar(SafetyContact contact) {
    final data = contact.imageData;
    if (data != null && data.isNotEmpty) {
      try {
        return CircleAvatar(
          backgroundImage: MemoryImage(base64.decode(data)),
        );
      } catch (_) {
        // Corrupt payload — fall through to the placeholder icon.
      }
    }
    return const CircleAvatar(child: Icon(Icons.person_outline));
  }

  Widget _kindChip(String kind) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Text(
        kindLabel(kind),
        style: const TextStyle(fontSize: 11),
      ),
    );
  }
}

/// Caregiver-facing label for a contact kind. The model stores kinds as
/// free-form strings ('mom', 'dad', 'grandparent', 'custom', ...); unknown
/// kinds render capitalized so they survive the round trip untouched.
String kindLabel(String kind) {
  switch (kind) {
    case 'mom':
      return 'Mom';
    case 'dad':
      return 'Dad';
    case 'grandparent':
      return 'Grandparent';
    case 'custom':
      return 'Custom';
    default:
      return kind.isEmpty ? 'Custom' : kind[0].toUpperCase() + kind.substring(1);
  }
}

/// The kinds offered in the picker. The model accepts any string, but the
/// picker keeps the common cases one tap away.
const contactKindValues = ['mom', 'dad', 'grandparent', 'custom'];

/// Add/edit dialog for one safety contact. Returns the new or updated
/// contact, or null when the caregiver cancels.
class _ContactDialog extends StatefulWidget {
  const _ContactDialog({this.initial, required this.existing});

  final SafetyContact? initial;
  final List<SafetyContact> existing;

  @override
  State<_ContactDialog> createState() => _ContactDialogState();
}

class _ContactDialogState extends State<_ContactDialog> {
  static int _idCounter = 0;

  late final TextEditingController _name;
  late final TextEditingController _phone;
  late String _kind;
  String? _imageData;
  bool _pickingPhoto = false;
  String? _photoError;
  String? _phoneError;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initial?.name ?? '');
    _phone = TextEditingController(text: widget.initial?.phone ?? '');
    _kind = widget.initial?.kind ?? 'mom';
    _imageData = widget.initial?.imageData;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    setState(() {
      _pickingPhoto = true;
      _photoError = null;
    });
    try {
      final data = await pickButtonImage();
      if (!mounted) return;
      if (data != null) setState(() => _imageData = data);
    } on ButtonImageException catch (e) {
      if (!mounted) return;
      setState(() => _photoError = e.message);
    } finally {
      if (mounted) setState(() => _pickingPhoto = false);
    }
  }

  void _submit() {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    if (name.isEmpty) return;
    // A contact without a phone number would produce a Call button that
    // dials `tel:` with an empty path. Require the number up front, with
    // a plain-language message; the confirm screen also defensively
    // disables Call for any legacy contact missing a number.
    if (phone.isEmpty) {
      setState(() {
        _phoneError =
            'Add a phone number so the Call button can reach this person.';
      });
      return;
    }
    final initial = widget.initial;
    Navigator.of(context).pop(
      SafetyContact(
        id: initial?.id ??
            'sc-${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}',
        name: name,
        phone: phone,
        imageData: _imageData,
        kind: _kind,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initial != null;
    return AlertDialog(
      title: Text(isEdit ? 'Edit contact' : 'Add contact'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _photoPreview(),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextButton.icon(
                        icon: _pickingPhoto
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.photo_outlined, size: 18),
                        label: Text(
                          _imageData == null ? 'Add photo' : 'Change photo',
                        ),
                        onPressed: _pickingPhoto ? null : _pickPhoto,
                      ),
                      if (_imageData != null)
                        TextButton.icon(
                          icon: const Icon(
                            Icons.delete_outline,
                            size: 18,
                          ),
                          label: const Text('Remove photo'),
                          onPressed: () =>
                              setState(() => _imageData = null),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (_photoError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _photoError!,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Mom',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Phone number',
                hintText: 'e.g. +1 555 010 2030',
                border: const OutlineInputBorder(),
                errorText: _phoneError,
              ),
              onChanged: (_) => setState(() {
                _phoneError = null;
              }),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _kind,
              decoration: const InputDecoration(
                labelText: 'Who is this?',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final k in contactKindValues)
                  DropdownMenuItem(value: k, child: Text(kindLabel(k))),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _kind = v);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed:
              _name.text.trim().isEmpty || _phone.text.trim().isEmpty
              ? null
              : _submit,
          child: Text(isEdit ? 'Save' : 'Add'),
        ),
      ],
    );
  }

  Widget _photoPreview() {
    final data = _imageData;
    if (data != null && data.isNotEmpty) {
      try {
        return CircleAvatar(
          radius: 28,
          backgroundImage: MemoryImage(base64.decode(data)),
        );
      } catch (_) {
        // fall through to placeholder
      }
    }
    return const CircleAvatar(
      radius: 28,
      child: Icon(Icons.person_outline),
    );
  }
}
