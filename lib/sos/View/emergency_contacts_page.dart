import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../Model/sos_models.dart';
import '../ModelView/emergency_contacts_view_model.dart';

class EmergencyContactsPage extends StatefulWidget {
  const EmergencyContactsPage({super.key, required this.initialContacts});

  final List<EmergencyContact> initialContacts;

  @override
  State<EmergencyContactsPage> createState() => _EmergencyContactsPageState();
}

class _EmergencyContactsPageState extends State<EmergencyContactsPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _relationshipController = TextEditingController();
  late final EmergencyContactsViewModel viewModel;

  @override
  void initState() {
    super.initState();
    viewModel = EmergencyContactsViewModel(
      initialContacts: widget.initialContacts,
    );
    viewModel.addListener(_refresh);
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

  void _addContact() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final wasAdded = viewModel.addContact(
      name: _nameController.text,
      phoneNumber: _phoneController.text,
      relationship: _relationshipController.text,
    );
    if (!wasAdded) {
      return;
    }

    _nameController.clear();
    _phoneController.clear();
    _relationshipController.clear();
    FocusScope.of(context).unfocus();
  }

  Future<void> _editContact(int index, EmergencyContact contact) async {
    final updatedContact = await showModalBottomSheet<EmergencyContact>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _EditContactSheet(contact: contact),
    );

    if (updatedContact == null) {
      return;
    }

    viewModel.updateContact(
      index,
      name: updatedContact.name,
      phoneNumber: updatedContact.phoneNumber,
      relationship: updatedContact.relationship,
    );
  }

  Future<void> _deleteContact(int index, EmergencyContact contact) async {
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
      viewModel.deleteContact(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ContactsColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Header(),
                  const SizedBox(height: 16),
                  _SummaryCard(
                    count: viewModel.contacts.length,
                    max: EmergencyContactsViewModel.maxContacts,
                  ),
                  const SizedBox(height: 18),
                  _ContactsList(
                    contacts: viewModel.contacts,
                    onEditContact: _editContact,
                    onDeleteContact: _deleteContact,
                  ),
                  const SizedBox(height: 18),
                  _AddContactForm(
                    formKey: _formKey,
                    nameController: _nameController,
                    phoneController: _phoneController,
                    relationshipController: _relationshipController,
                    canAddContact: viewModel.canAddContact,
                    remainingSlots: viewModel.remainingSlots,
                    onAddContact: _addContact,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
      child: Row(
        children: [
          Tooltip(
            message: 'Back',
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size.square(36),
              onPressed: () => Navigator.of(context).pop(),
              child: Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  CupertinoIcons.chevron_back,
                  color: _ContactsColors.green,
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
                    color: _ContactsColors.text,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Add up to 5 people for SOS alerts',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _ContactsColors.secondaryText,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.count, required this.max});

  final int count;
  final int max;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const _Glyph(icon: Icons.contacts_rounded),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$count/$max contacts added',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: _ContactsColors.text,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'These contacts receive emergency SOS messages first.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _ContactsColors.secondaryText,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactsList extends StatelessWidget {
  const _ContactsList({
    required this.contacts,
    required this.onEditContact,
    required this.onDeleteContact,
  });

  final List<EmergencyContact> contacts;
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
                color: _ContactsColors.secondaryText,
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
    required this.onEditContact,
    required this.onDeleteContact,
  });

  final int index;
  final EmergencyContact contact;
  final Future<void> Function(int index, EmergencyContact contact)
  onEditContact;
  final Future<void> Function(int index, EmergencyContact contact)
  onDeleteContact;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('${contact.name}-${contact.phoneNumber}-$index'),
      confirmDismiss: (direction) async {
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
      secondaryBackground: const _SwipeActionBackground(
        alignment: Alignment.centerRight,
        color: _ContactsColors.destructive,
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
                    color: _ContactsColors.text,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${contact.relationship} • ${contact.phoneNumber}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _ContactsColors.secondaryText,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(
            CupertinoIcons.chevron_forward,
            color: _ContactsColors.chevron,
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
  final VoidCallback onAddContact;

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
                  color: _ContactsColors.text,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                canAddContact
                    ? '$remainingSlots slots remaining'
                    : 'Maximum of 5 contacts reached',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _ContactsColors.secondaryText,
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
                validator: _requiredValidator,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: relationshipController,
                enabled: canAddContact,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Relationship',
                  prefixIcon: Icon(Icons.group_outlined),
                ),
                validator: _requiredValidator,
                onFieldSubmitted: (_) {
                  if (canAddContact) {
                    onAddContact();
                  }
                },
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: canAddContact ? onAddContact : null,
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
                decoration: const BoxDecoration(color: Colors.white),
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
                                      color: _ContactsColors.text,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0,
                                    ),
                              ),
                            ),
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size.square(32),
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Icon(
                                CupertinoIcons.xmark,
                                color: _ContactsColors.secondaryText,
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
                          validator: _AddContactForm._requiredValidator,
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _relationshipController,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            labelText: 'Relationship',
                            prefixIcon: Icon(Icons.group_outlined),
                          ),
                          validator: _AddContactForm._requiredValidator,
                          onFieldSubmitted: (_) => _save(),
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
      borderRadius: BorderRadius.circular(8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
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
    return const Divider(
      height: 1,
      thickness: 0.7,
      color: _ContactsColors.separator,
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
}
