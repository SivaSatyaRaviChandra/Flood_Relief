/// The user's own emergency contacts.
///
/// The list starts empty on purpose. Shipping invented government or NGO
/// hotline numbers would be unsafe — during a flood, a confidently wrong
/// number is worse than none — so this build makes the user enter the contacts
/// for their own district.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/errors/app_error.dart';
import '../../models/emergency_contact.dart';
import '../widgets/state_views.dart';

class ContactsScreen extends ConsumerWidget {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contactsAsync = ref.watch(contactsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency contacts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt),
            tooltip: 'Add a contact',
            onPressed: () => _edit(context, ref, null),
          ),
        ],
      ),
      body: contactsAsync.when(
        loading: () => const LoadingStateView(),
        error: (error, _) => ErrorStateView(
          error: error,
          onRetry: () => ref.invalidate(contactsProvider),
        ),
        data: (contacts) {
          if (contacts.isEmpty) {
            return EmptyState(
              icon: Icons.contact_phone_outlined,
              title: 'No contacts yet',
              message: 'Add the people or services you want to be able to '
                  'call. This app ships with none on purpose: a made-up '
                  'emergency number is more dangerous than a missing one.',
              action: FilledButton.icon(
                onPressed: () => _edit(context, ref, null),
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Add a contact'),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Text(
                  'These numbers are stored only on this device and are never '
                  'transmitted by this build.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              for (final contact in contacts)
                _ContactTile(
                  contact: contact,
                  onEdit: () => _edit(context, ref, contact),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    EmergencyContact? existing,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ContactForm(contactId: existing?.contactId, initial: existing),
    );
  }
}

class _ContactTile extends ConsumerWidget {
  const _ContactTile({required this.contact, required this.onEdit});

  final EmergencyContact contact;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: scheme.primary.withValues(alpha: 0.12),
          child: Icon(_icon(contact.kind), color: scheme.primary),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                contact.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (contact.isPrimary) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'PRIMARY',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: scheme.onPrimary,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(contact.phone),
            Text(
              contact.notes ?? contact.kind.label,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) => _handle(context, ref, value),
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'call', child: Text('Call')),
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(
              value: 'primary',
              enabled: !contact.isPrimary,
              child: const Text('Make primary'),
            ),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
        onTap: () => _handle(context, ref, 'edit'),
      ),
    );
  }

  static IconData _icon(ContactKind kind) => switch (kind) {
        ContactKind.family => Icons.family_restroom,
        ContactKind.friend => Icons.people_outline,
        ContactKind.neighbour => Icons.home_outlined,
        ContactKind.authority => Icons.account_balance_outlined,
        ContactKind.medical => Icons.medical_services_outlined,
        ContactKind.rescue => Icons.health_and_safety_outlined,
        ContactKind.other => Icons.contact_page_outlined,
      };

  Future<void> _handle(
    BuildContext context,
    WidgetRef ref,
    String action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    switch (action) {
      case 'call':
        // No `url_launcher` dependency is bundled, so this build does not
        // pretend it can place a call. Say so instead of opening nothing.
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Dialling is not available in this build. The number is '
              '${contact.phone}.',
            ),
          ),
        );
      case 'edit':
        onEdit();
      case 'primary':
        try {
          await ref
              .read(emergencyContactServiceProvider)
              .setPrimary(contact.contactId);
          messenger.showSnackBar(
            SnackBar(content: Text('${contact.name} is now the primary contact.')),
          );
        } catch (e) {
          messenger.showSnackBar(
            SnackBar(content: Text('Could not set primary: $e')),
          );
        }
      case 'delete':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('Delete ${contact.name}?'),
            content: Text('${contact.phone} will be removed from this device.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Keep'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        try {
          await ref
              .read(emergencyContactServiceProvider)
              .delete(contact.contactId);
          messenger.showSnackBar(
            const SnackBar(content: Text('Contact deleted.')),
          );
        } catch (e) {
          messenger.showSnackBar(
            SnackBar(content: Text('Could not delete: $e')),
          );
        }
    }
  }
}

class _ContactForm extends ConsumerStatefulWidget {
  const _ContactForm({this.contactId, this.initial});

  final String? contactId;
  final EmergencyContact? initial;

  @override
  ConsumerState<_ContactForm> createState() => _ContactFormState();
}

class _ContactFormState extends ConsumerState<_ContactForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _notesController;
  late ContactKind _kind;
  late bool _primary;
  bool _saving = false;
  List<String> _errors = const [];

  @override
  void initState() {
    super.initState();
    final c = widget.initial;
    _nameController = TextEditingController(text: c?.name ?? '');
    _phoneController = TextEditingController(text: c?.phone ?? '');
    _notesController = TextEditingController(text: c?.notes ?? '');
    _kind = c?.kind ?? ContactKind.family;
    _primary = c?.isPrimary ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final errors = ref
        .read(emergencyContactServiceProvider)
        .validateDraft(
          name: _nameController.text,
          phone: _phoneController.text,
          kind: _kind,
          notes: _notesController.text,
        );
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }
    setState(() {
      _saving = true;
      _errors = const [];
    });
    try {
      await ref.read(emergencyContactServiceProvider).saveContact(
            contactId: widget.contactId,
            name: _nameController.text,
            phone: _phoneController.text,
            kind: _kind,
            notes: _notesController.text,
            isPrimary: _primary,
          );
      if (mounted) Navigator.of(context).pop();
    } on InvalidFormError catch (e) {
      if (mounted) setState(() => _errors = e.errors);
    } on AppError catch (e) {
      if (mounted) setState(() => _errors = [e.message]);
    } catch (e) {
      if (mounted) setState(() => _errors = ['Could not save: $e']);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.contactId == null ? 'Add a contact' : 'Edit contact',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone number',
                  helperText: 'Digits, spaces, +, -, ( ) and . are allowed.',
                  helperMaxLines: 2,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ContactKind>(
                initialValue: _kind,
                decoration: const InputDecoration(labelText: 'Kind'),
                items: [
                  for (final k in ContactKind.values)
                    DropdownMenuItem(value: k, child: Text(k.label)),
                ],
                onChanged: (v) => setState(() => _kind = v ?? _kind),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesController,
                maxLines: 2,
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                ),
              ),
              SwitchListTile(
                value: _primary,
                onChanged: (v) => setState(() => _primary = v),
                title: const Text('Primary contact'),
                subtitle: const Text(
                  'The contact listed first. Only one contact can be primary.',
                ),
                contentPadding: EdgeInsets.zero,
              ),
              if (_errors.isNotEmpty)
                Card(
                  color: const Color(0xFFD32F2F).withValues(alpha: 0.1),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final e in _errors)
                          Text(
                            '• $e',
                            style: const TextStyle(color: Color(0xFFD32F2F)),
                          ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Saving...' : 'Save contact'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
