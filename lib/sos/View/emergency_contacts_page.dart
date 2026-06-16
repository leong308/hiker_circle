import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../app/Model/app_session.dart';
import '../../authentication/Data/phone_number_formatter.dart';
import '../Data/emergency_contacts_repository.dart';
import '../Data/sos_device_alert_service.dart';
import '../Model/sos_models.dart';
import '../ModelView/emergency_contacts_view_model.dart';

class EmergencyContactsPage extends StatefulWidget {
  const EmergencyContactsPage({
    super.key,
    required this.session,
    required this.initialContacts,
    this.repository = const EmergencyContactsRepository(),
    this.onboardingRequired = false,
    this.onOnboardingCompleted,
  }) : assert(!onboardingRequired || onOnboardingCompleted != null);

  final AppSession session;
  final List<EmergencyContact> initialContacts;
  final EmergencyContactsRepository repository;
  final bool onboardingRequired;
  final Future<void> Function(List<EmergencyContact> contacts)?
  onOnboardingCompleted;

  @override
  State<EmergencyContactsPage> createState() => _EmergencyContactsPageState();
}

class _EmergencyContactsPageState extends State<EmergencyContactsPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _relationshipController = TextEditingController();
  final SosDeviceAlertService _deviceAlertService =
      const SosDeviceAlertService();
  late final EmergencyContactsViewModel viewModel;
  List<EmergencyContactCandidate> _deviceContacts = const [];
  bool _isLoadingDeviceContacts = false;
  bool _isCompletingOnboarding = false;
  String? _deviceContactsMessage;
  String? _onboardingErrorMessage;

  @override
  void initState() {
    super.initState();
    viewModel = EmergencyContactsViewModel(
      session: widget.session,
      initialContacts: widget.initialContacts,
      repository: widget.repository,
    );
    viewModel.addListener(_refresh);
    unawaited(_loadDeviceContacts());
  }

  @override
  void dispose() {
    viewModel.removeListener(_refresh);
    viewModel.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _relationshipController.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {});
  }

  Future<void> _close() async {
    if (!widget.onboardingRequired) {
      Navigator.of(context).pop(viewModel.contacts);
      return;
    }
    if (viewModel.contacts.isEmpty ||
        viewModel.isSaving ||
        _isCompletingOnboarding) {
      return;
    }

    setState(() {
      _isCompletingOnboarding = true;
      _onboardingErrorMessage = null;
    });
    try {
      await widget.onOnboardingCompleted?.call(viewModel.contacts);
    } catch (error) {
      if (mounted) {
        setState(() {
          _onboardingErrorMessage = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCompletingOnboarding = false;
        });
      }
    }
  }

  Future<void> _addContact() async {
    if (viewModel.isSaving) {
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final wasAdded = await viewModel.addContact(
      name: _nameController.text,
      phoneNumber: _phoneController.text,
      relationship: _relationshipController.text,
    );
    if (!wasAdded || !mounted) {
      return;
    }

    _nameController.clear();
    _phoneController.clear();
    _relationshipController.clear();
    FocusScope.of(context).unfocus();
  }

  Future<void> _editContact(int index, EmergencyContact contact) async {
    if (viewModel.isSaving) {
      return;
    }

    final updatedContact = await showModalBottomSheet<EmergencyContact>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _EditContactSheet(contact: contact),
    );

    if (updatedContact == null || !mounted) {
      return;
    }

    await viewModel.updateContact(
      index,
      name: updatedContact.name,
      phoneNumber: updatedContact.phoneNumber,
      relationship: updatedContact.relationship,
    );
  }

  Future<void> _deleteContact(int index, EmergencyContact contact) async {
    if (viewModel.isSaving) {
      return;
    }

    final shouldDelete = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) {
        return CupertinoAlertDialog(
          title: const Text('Delete contact?'),
          content: Text('${contact.name} will be removed from SOS alerts.'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete == true) {
      await viewModel.deleteContact(index);
    }
  }

  Future<void> _loadDeviceContacts() async {
    setState(() {
      _isLoadingDeviceContacts = true;
      _deviceContactsMessage = null;
    });

    final contacts = await _deviceAlertService.loadDeviceContacts();
    if (!mounted) {
      return;
    }

    setState(() {
      _deviceContacts = contacts;
      _isLoadingDeviceContacts = false;
      if (contacts.isEmpty) {
        _deviceContactsMessage =
            'No phone contacts are available or permission was not granted.';
      }
    });
  }

  void _selectDeviceContact(EmergencyContactCandidate contact) {
    setState(() {
      _nameController.text = contact.displayName;
      _phoneController.text = PhoneNumberFormatter.normalize(
        contact.primaryPhoneNumber,
      );
    });
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('${contact.displayName} filled into the form.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final isBusy = viewModel.isSaving || _isCompletingOnboarding;
    return PopScope(
      canPop: !widget.onboardingRequired,
      child: Scaffold(
        backgroundColor: _ContactsColors.backgroundFor(context),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(
                      onAction: _close,
                      onboardingRequired: widget.onboardingRequired,
                      canContinue: viewModel.contacts.isNotEmpty && !isBusy,
                    ),
                    if (widget.onboardingRequired) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Step 2 of 2. Add at least one contact, then tap Continue.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: _ContactsColors.secondaryTextFor(context),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    _SummaryCard(
                      count: viewModel.contacts.length,
                      max: EmergencyContactsViewModel.maxContacts,
                      isSaving: isBusy,
                      saveErrorMessage:
                          _onboardingErrorMessage ?? viewModel.saveErrorMessage,
                    ),
                    const SizedBox(height: 18),
                    _ContactsList(
                      contacts: viewModel.contacts,
                      isSaving: isBusy,
                      onEditContact: _editContact,
                      onDeleteContact: _deleteContact,
                    ),
                    const SizedBox(height: 18),
                    _DeviceContactsPicker(
                      contacts: _deviceContacts,
                      savedContacts: viewModel.contacts,
                      isLoading: _isLoadingDeviceContacts,
                      message: _deviceContactsMessage,
                      canSelect: viewModel.canAddContact && !isBusy,
                      onSelectContact: _selectDeviceContact,
                    ),
                    const SizedBox(height: 18),
                    _AddContactForm(
                      formKey: _formKey,
                      nameController: _nameController,
                      phoneController: _phoneController,
                      relationshipController: _relationshipController,
                      canAddContact: viewModel.canAddContact && !isBusy,
                      remainingSlots: viewModel.remainingSlots,
                      onAddContact: _addContact,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.onAction,
    required this.onboardingRequired,
    required this.canContinue,
  });

  final VoidCallback onAction;
  final bool onboardingRequired;
  final bool canContinue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
      child: Row(
        children: [
          Tooltip(
            message: onboardingRequired ? 'Continue' : 'Back',
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size.square(36),
              onPressed: onboardingRequired && !canContinue ? null : onAction,
              child: Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  onboardingRequired
                      ? CupertinoIcons.check_mark
                      : CupertinoIcons.chevron_back,
                  color: onboardingRequired && !canContinue
                      ? _ContactsColors.secondaryTextFor(context)
                      : _ContactsColors.green,
                  size: 20,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Emergency Contacts',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: _ContactsColors.textFor(context),
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Add up to 3 people for SOS alerts',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _ContactsColors.secondaryTextFor(context),
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          if (onboardingRequired) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: canContinue ? onAction : null,
              child: const Text('Continue'),
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.count,
    required this.max,
    required this.isSaving,
    required this.saveErrorMessage,
  });

  final int count;
  final int max;
  final bool isSaving;
  final String? saveErrorMessage;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const _Glyph(icon: Icons.contacts_rounded),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$count/$max contacts added',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: _ContactsColors.textFor(context),
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0,
                            ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        isSaving
                            ? 'Saving emergency contacts...'
                            : 'These contacts receive emergency SOS messages first.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _ContactsColors.secondaryTextFor(context),
                          fontWeight: FontWeight.w400,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (isSaving) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(minHeight: 2),
            ],
            if (saveErrorMessage case final message?) ...[
              const SizedBox(height: 10),
              Text(
                message,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _ContactsColors.destructiveFor(context),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DeviceContactsPicker extends StatelessWidget {
  const _DeviceContactsPicker({
    required this.contacts,
    required this.savedContacts,
    required this.isLoading,
    required this.message,
    required this.canSelect,
    required this.onSelectContact,
  });

  final List<EmergencyContactCandidate> contacts;
  final List<EmergencyContact> savedContacts;
  final bool isLoading;
  final String? message;
  final bool canSelect;
  final ValueChanged<EmergencyContactCandidate> onSelectContact;

  @override
  Widget build(BuildContext context) {
    final savedNumbers = savedContacts.map((contact) {
      return PhoneNumberFormatter.normalize(contact.phoneNumber);
    }).toSet();
    final candidates = contacts
        .where(
          (contact) => PhoneNumberFormatter.isValid(contact.primaryPhoneNumber),
        )
        .toList();

    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const _Glyph(icon: Icons.phone_iphone_rounded),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'From phone contacts',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: _ContactsColors.textFor(context),
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0,
                            ),
                      ),
                      Text(
                        'Tap a contact to fill name and number.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _ContactsColors.secondaryTextFor(context),
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (isLoading) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(minHeight: 2),
            ] else if (candidates.isEmpty) ...[
              const SizedBox(height: 12),
              Text(
                message ?? 'No phone contacts available.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _ContactsColors.secondaryTextFor(context),
                  letterSpacing: 0,
                ),
              ),
            ] else ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 178,
                child: ListView.separated(
                  itemCount: candidates.length,
                  separatorBuilder: (context, index) =>
                      const _HorizontalSeparator(),
                  itemBuilder: (context, index) {
                    final contact = candidates[index];
                    final isAdded = savedNumbers.contains(
                      PhoneNumberFormatter.normalize(
                        contact.primaryPhoneNumber,
                      ),
                    );
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const _Glyph(icon: Icons.person_rounded),
                      title: Text(
                        contact.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        PhoneNumberFormatter.normalize(
                          contact.primaryPhoneNumber,
                        ),
                      ),
                      trailing: isAdded
                          ? const _StatusPill(
                              label: 'Added',
                              color: _ContactsColors.green,
                            )
                          : FilledButton(
                              onPressed: canSelect
                                  ? () => onSelectContact(contact)
                                  : null,
                              child: const Text('Add'),
                            ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ContactsList extends StatelessWidget {
  const _ContactsList({
    required this.contacts,
    required this.isSaving,
    required this.onEditContact,
    required this.onDeleteContact,
  });

  final List<EmergencyContact> contacts;
  final bool isSaving;
  final Future<void> Function(int index, EmergencyContact contact)
  onEditContact;
  final Future<void> Function(int index, EmergencyContact contact)
  onDeleteContact;

  @override
  Widget build(BuildContext context) {
    if (contacts.isEmpty) {
      return _InsetGroup(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Center(
            child: Text(
              'No emergency contacts yet',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _ContactsColors.secondaryTextFor(context),
                letterSpacing: 0,
              ),
            ),
          ),
        ),
      );
    }

    return _InsetGroup(
      child: Column(
        children: [
          for (var index = 0; index < contacts.length; index++) ...[
            _SwipeContactCell(
              index: index,
              contact: contacts[index],
              isSaving: isSaving,
              onEditContact: onEditContact,
              onDeleteContact: onDeleteContact,
            ),
            if (index != contacts.length - 1)
              const Padding(
                padding: EdgeInsets.only(left: 58),
                child: _HorizontalSeparator(),
              ),
          ],
        ],
      ),
    );
  }
}

class _SwipeContactCell extends StatelessWidget {
  const _SwipeContactCell({
    required this.index,
    required this.contact,
    required this.isSaving,
    required this.onEditContact,
    required this.onDeleteContact,
  });

  final int index;
  final EmergencyContact contact;
  final bool isSaving;
  final Future<void> Function(int index, EmergencyContact contact)
  onEditContact;
  final Future<void> Function(int index, EmergencyContact contact)
  onDeleteContact;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('${contact.name}-${contact.phoneNumber}-$index'),
      confirmDismiss: (direction) async {
        if (isSaving) {
          return false;
        }

        if (direction == DismissDirection.startToEnd) {
          await onEditContact(index, contact);
          return false;
        }

        await onDeleteContact(index, contact);
        return false;
      },
      background: const _SwipeActionBackground(
        alignment: Alignment.centerLeft,
        color: _ContactsColors.edit,
        icon: Icons.edit_rounded,
        label: 'Edit',
      ),
      secondaryBackground: _SwipeActionBackground(
        alignment: Alignment.centerRight,
        color: _ContactsColors.destructiveFor(context),
        icon: Icons.delete_rounded,
        label: 'Delete',
      ),
      child: _ContactCell(contact: contact),
    );
  }
}

class _ContactCell extends StatelessWidget {
  const _ContactCell({required this.contact});

  final EmergencyContact contact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      child: Row(
        children: [
          const _Glyph(icon: Icons.person_rounded),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: _ContactsColors.textFor(context),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${contact.relationship} - ${contact.phoneNumber}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _ContactsColors.secondaryTextFor(context),
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            CupertinoIcons.chevron_forward,
            color: _ContactsColors.chevronFor(context),
            size: 16,
          ),
        ],
      ),
    );
  }
}

class _SwipeActionBackground extends StatelessWidget {
  const _SwipeActionBackground({
    required this.alignment,
    required this.color,
    required this.icon,
    required this.label,
  });

  final Alignment alignment;
  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final isLeft = alignment == Alignment.centerLeft;

    return Container(
      color: color,
      alignment: alignment,
      padding: EdgeInsets.only(left: isLeft ? 18 : 0, right: isLeft ? 0 : 18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: isLeft
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.end,
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(height: 3),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

const List<String> _relationshipOptions = [
  'Parent',
  'Child',
  'Partner',
  'Friend',
  'Colleague',
  'Relative',
  'Sibling',
  'Guardian',
  'Neighbor',
  'Doctor',
];

class _RelationshipDropdown extends StatelessWidget {
  const _RelationshipDropdown({
    required this.controller,
    required this.decoration,
    required this.validator,
    this.enabled = true,
  });

  final TextEditingController controller;
  final InputDecoration decoration;
  final FormFieldValidator<String> validator;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final currentValue = _relationshipOptions.contains(controller.text)
        ? controller.text
        : null;

    return DropdownButtonFormField<String>(
      initialValue: currentValue,
      decoration: decoration,
      validator: validator,
      items: [
        for (final relationship in _relationshipOptions)
          DropdownMenuItem<String>(
            value: relationship,
            child: Text(relationship),
          ),
      ],
      onChanged: enabled
          ? (value) {
              if (value != null) {
                controller.text = value;
              }
            }
          : null,
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _AddContactForm extends StatelessWidget {
  const _AddContactForm({
    required this.formKey,
    required this.nameController,
    required this.phoneController,
    required this.relationshipController,
    required this.canAddContact,
    required this.remainingSlots,
    required this.onAddContact,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController nameController;
  final TextEditingController phoneController;
  final TextEditingController relationshipController;
  final bool canAddContact;
  final int remainingSlots;
  final Future<void> Function() onAddContact;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Add Contact',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: _ContactsColors.textFor(context),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                canAddContact
                    ? '$remainingSlots slots remaining'
                    : 'Maximum of 3 contacts reached',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _ContactsColors.secondaryTextFor(context),
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: nameController,
                enabled: canAddContact,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                validator: _requiredValidator,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: phoneController,
                enabled: canAddContact,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Phone number',
                  prefixIcon: Icon(Icons.phone_iphone_rounded),
                ),
                validator: _phoneValidator,
              ),
              const SizedBox(height: 10),
              _RelationshipDropdown(
                controller: relationshipController,
                enabled: canAddContact,
                decoration: const InputDecoration(
                  labelText: 'Relationship',
                  prefixIcon: Icon(Icons.group_outlined),
                ),
                validator: _requiredValidator,
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: canAddContact
                    ? () => unawaited(onAddContact())
                    : null,
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('Add contact'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Required';
    }
    return null;
  }

  static String? _phoneValidator(String? value) {
    final required = _requiredValidator(value);
    if (required != null) {
      return required;
    }
    if (!PhoneNumberFormatter.isValid(value!)) {
      return 'Use country code, for example +60123456789';
    }
    return null;
  }
}

class _EditContactSheet extends StatefulWidget {
  const _EditContactSheet({required this.contact});

  final EmergencyContact contact;

  @override
  State<_EditContactSheet> createState() => _EditContactSheetState();
}

class _EditContactSheetState extends State<_EditContactSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _relationshipController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.contact.name);
    _phoneController = TextEditingController(text: widget.contact.phoneNumber);
    _relationshipController = TextEditingController(
      text: widget.contact.relationship,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _relationshipController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    Navigator.of(context).pop(
      EmergencyContact(
        name: _nameController.text,
        phoneNumber: _phoneController.text,
        relationship: _relationshipController.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _ContactsColors.surfaceFor(context),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Edit Contact',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: _ContactsColors.textFor(context),
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0,
                                    ),
                              ),
                            ),
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size.square(32),
                              onPressed: () => Navigator.of(context).pop(),
                              child: Icon(
                                CupertinoIcons.xmark,
                                color: _ContactsColors.secondaryTextFor(
                                  context,
                                ),
                                size: 18,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _nameController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Name',
                            prefixIcon: Icon(Icons.person_outline_rounded),
                          ),
                          validator: _AddContactForm._requiredValidator,
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Phone number',
                            prefixIcon: Icon(Icons.phone_iphone_rounded),
                          ),
                          validator: _AddContactForm._phoneValidator,
                        ),
                        const SizedBox(height: 10),
                        _RelationshipDropdown(
                          controller: _relationshipController,
                          decoration: const InputDecoration(
                            labelText: 'Relationship',
                            prefixIcon: Icon(Icons.group_outlined),
                          ),
                          validator: _AddContactForm._requiredValidator,
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: _save,
                          icon: const Icon(Icons.check_rounded),
                          label: const Text('Save changes'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Glyph extends StatelessWidget {
  const _Glyph({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: _ContactsColors.green,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(icon, color: Colors.white, size: 18),
    );
  }
}

class _InsetGroup extends StatelessWidget {
  const _InsetGroup({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _ContactsColors.surfaceFor(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      ),
    );
  }
}

class _HorizontalSeparator extends StatelessWidget {
  const _HorizontalSeparator();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 0.7,
      color: _ContactsColors.separatorFor(context),
    );
  }
}

abstract final class _ContactsColors {
  static const Color background = Color(0xFFF2F2F7);
  static const Color green = Color(0xFF34A853);
  static const Color separator = Color(0xFFD9E1DC);
  static const Color text = Color(0xFF111111);
  static const Color secondaryText = Color(0xFF6E6E73);
  static const Color chevron = Color(0xFFC7C7CC);
  static const Color edit = Color(0xFF2F8E50);
  static const Color destructive = Color(0xFFFF3B30);

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color backgroundFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF0C120F) : background;

  static Color surfaceFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF141C17) : Colors.white;

  static Color separatorFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF2B3A31) : separator;

  static Color textFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFEAF4EE) : text;

  static Color secondaryTextFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFA8B8AE) : secondaryText;

  static Color chevronFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF6F8175) : chevron;

  static Color destructiveFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFFF6B61) : destructive;
}
