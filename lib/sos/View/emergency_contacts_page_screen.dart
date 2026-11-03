part of '../emergency_contacts_page_feature.dart';

/// Displays the emergency contacts page.
class EmergencyContactsPage extends StatefulWidget {
  /// Creates emergency contacts page.
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

  /// Creates the presentation state for this widget.
  @override
  State<EmergencyContactsPage> createState() => _EmergencyContactsPageState();
}

/// Manages the emergency contacts page presentation and lifecycle.
class _EmergencyContactsPageState extends State<EmergencyContactsPage> {
  /// Returns view model.
  EmergencyContactsViewModel get viewModel => _screenModel.stateViewModel;

  /// Updates view model.
  set viewModel(EmergencyContactsViewModel value) =>
      _screenModel.stateViewModel = value;

  /// Returns is completing onboarding.
  bool get _isCompletingOnboarding => _screenModel.stateIsCompletingOnboarding;

  /// Returns onboarding error message.
  String? get _onboardingErrorMessage =>
      _screenModel.stateOnboardingErrorMessage;

  late final _EmergencyContactsPageStateViewModel _screenModel;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _relationshipController = TextEditingController();
  final SosDeviceAlertService _deviceAlertService =
      const SosDeviceAlertService();

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _EmergencyContactsPageStateViewModel(
      effectPickDeviceContact: _pickDeviceContact,
      effectSelectDeviceContact: _selectDeviceContact,
    )..addListener(_renderScreenModel);
    _screenModel.readOnboardingRequired = () => widget.onboardingRequired;
    _screenModel.readOnOnboardingCompleted = () => widget.onOnboardingCompleted;
    _screenModel.effectPresentCloseEffect1 = _presentCloseEffect1;
    _screenModel.effectPresentEditContactEffect1 = _presentEditContactEffect1;
    _screenModel.effectPresentDeleteContactEffect1 =
        _presentDeleteContactEffect1;

    viewModel = EmergencyContactsViewModel(
      session: widget.session,
      initialContacts: widget.initialContacts,
      repository: widget.repository,
    );
    viewModel.addListener(_refresh);
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    viewModel.removeListener(_refresh);
    viewModel.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _relationshipController.dispose();

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Delegates refresh to the ViewModel.
  void _refresh() => _screenModel.commandRefresh();

  /// Finish the contact editor through its result flow instead of abandoning the current save state.
  Future<void> _close() => _screenModel.commandClose();

  /// Adds contact.
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

  /// Delegates edit contact to the ViewModel.
  Future<void> _editContact(int index, EmergencyContact contact) =>
      _screenModel.commandEditContact(index, contact);

  /// Delegates delete contact to the ViewModel.
  Future<void> _deleteContact(int index, EmergencyContact contact) =>
      _screenModel.commandDeleteContact(index, contact);

  /// Computes pick device contact.
  Future<EmergencyContactCandidate?> _pickDeviceContact({
    EmergencyContact? excluding,
  }) {
    FocusManager.instance.primaryFocus?.unfocus();
    final contacts = _deviceAlertService.loadDeviceContacts();
    return showModalBottomSheet<EmergencyContactCandidate>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: _ContactsColors.surfaceFor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => SafeArea(
        top: false,
        child: FutureBuilder<List<EmergencyContactCandidate>>(
          future: contacts,
          builder: (context, snapshot) => _DeviceContactsPicker(
            contacts: snapshot.data ?? const [],
            ownerPhoneNumber: widget.session.phoneNumber,
            savedContacts: viewModel.contacts
                .where((contact) => contact != excluding)
                .toList(),
            isLoading: snapshot.connectionState != ConnectionState.done,
            message: snapshot.hasError
                ? 'Unable to load contacts. You can still enter a number manually.'
                : 'No contacts available. Check Contacts permission in your phone settings, or enter a number manually.',
            canSelect: true,
            onSelectContact: (contact) => Navigator.of(context).pop(contact),
          ),
        ),
      ),
    );
  }

  /// Import only the device contact explicitly selected by the hiker.
  Future<void> _importDeviceContact() =>
      _screenModel.commandImportDeviceContact();

  /// Selects device contact.
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

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final isBusy = viewModel.isSaving || _isCompletingOnboarding;
    return PopScope(
      canPop: !widget.onboardingRequired && !isBusy,
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
                        'Step 3 of 3. Add at least one contact, then tap Continue.',
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
                    _AddContactForm(
                      formKey: _formKey,
                      ownerPhoneNumber: widget.session.phoneNumber,
                      nameController: _nameController,
                      phoneController: _phoneController,
                      relationshipController: _relationshipController,
                      canAddContact: viewModel.canAddContact && !isBusy,
                      remainingSlots: viewModel.remainingSlots,
                      onAddContact: _addContact,
                      onPickContact: _importDeviceContact,
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

  /// Presents the close effect1 UI.
  void _presentCloseEffect1() => Navigator.of(context).pop(viewModel.contacts);

  /// Presents the edit contact effect1 UI.
  Future<EmergencyContact?> _presentEditContactEffect1(
    EmergencyContact contact,
  ) => showModalBottomSheet<EmergencyContact>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _EditContactSheet(
      contact: contact,
      ownerPhoneNumber: widget.session.phoneNumber,
      pickContact: () => _pickDeviceContact(excluding: contact),
    ),
  );

  /// Presents the delete contact effect1 UI.
  Future<bool?> _presentDeleteContactEffect1(EmergencyContact contact) =>
      showCupertinoDialog<bool>(
        context: context,
        builder: (context) {
          if (viewModel.contacts.length <=
              EmergencyContactsRepository.minContacts) {
            return CupertinoAlertDialog(
              title: const Text('Keep an emergency contact'),
              content: const Text(
                EmergencyContactsRepository.minimumContactsMessage,
              ),
              actions: [
                CupertinoDialogAction(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('OK'),
                ),
              ],
            );
          }
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
}

/// Displays the device contacts picker.
class _DeviceContactsPicker extends StatelessWidget {
  /// Creates device contacts picker.
  const _DeviceContactsPicker({
    required this.contacts,
    required this.ownerPhoneNumber,
    required this.savedContacts,
    required this.isLoading,
    required this.message,
    required this.canSelect,
    required this.onSelectContact,
  });

  final List<EmergencyContactCandidate> contacts;
  final String ownerPhoneNumber;
  final List<EmergencyContact> savedContacts;
  final bool isLoading;
  final String? message;
  final bool canSelect;
  final ValueChanged<EmergencyContactCandidate> onSelectContact;

  /// Builds this widget from its current presentation state.
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
          mainAxisSize: MainAxisSize.min,
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
                        'Phone contacts',
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
              const Center(child: HikerCircleMinorLoadingIndicator(size: 24)),
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
                height: MediaQuery.sizeOf(context).height * 0.45,
                child: ListView.separated(
                  itemCount: candidates.length,
                  separatorBuilder: (context, index) =>
                      const _HorizontalSeparator(),
                  itemBuilder: (context, index) {
                    final contact = candidates[index];
                    final isOwnNumber =
                        EmergencyContactsRepository.isOwnPhoneNumber(
                          contact.primaryPhoneNumber,
                          ownerPhoneNumber,
                        );
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
                      trailing: isOwnNumber
                          ? _StatusPill(
                              label: 'Your number',
                              color: _ContactsColors.secondaryTextFor(context),
                            )
                          : isAdded
                          ? const _StatusPill(
                              label: 'Added',
                              color: _ContactsColors.green,
                            )
                          : FilledButton(
                              onPressed: canSelect
                                  ? () => onSelectContact(contact)
                                  : null,
                              child: const Text('Select'),
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

/// Displays the contacts list.
class _ContactsList extends StatelessWidget {
  /// Creates contacts list.
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

  /// Builds this widget from its current presentation state.
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

/// Displays the swipe contact cell.
class _SwipeContactCell extends StatelessWidget {
  /// Creates swipe contact cell.
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

  /// Builds this widget from its current presentation state.
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

/// Displays the contact cell.
class _ContactCell extends StatelessWidget {
  /// Creates contact cell.
  const _ContactCell({required this.contact});

  final EmergencyContact contact;

  /// Builds this widget from its current presentation state.
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

/// Displays the swipe action background.
class _SwipeActionBackground extends StatelessWidget {
  /// Creates swipe action background.
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

  /// Builds this widget from its current presentation state.
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

/// Displays the relationship dropdown.
class _RelationshipDropdown extends StatelessWidget {
  /// Creates relationship dropdown.
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

  /// Builds this widget from its current presentation state.
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

/// Displays the add contact form.
class _AddContactForm extends StatelessWidget {
  /// Creates add contact form.
  const _AddContactForm({
    required this.formKey,
    required this.ownerPhoneNumber,
    required this.nameController,
    required this.phoneController,
    required this.relationshipController,
    required this.canAddContact,
    required this.remainingSlots,
    required this.onAddContact,
    required this.onPickContact,
  });

  final GlobalKey<FormState> formKey;
  final String ownerPhoneNumber;
  final TextEditingController nameController;
  final TextEditingController phoneController;
  final TextEditingController relationshipController;
  final bool canAddContact;
  final int remainingSlots;
  final Future<void> Function() onAddContact;
  final VoidCallback onPickContact;

  /// Builds this widget from its current presentation state.
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
                decoration: InputDecoration(
                  labelText: 'Phone number',
                  prefixIcon: const Icon(Icons.phone_iphone_rounded),
                  suffixIcon: IconButton(
                    tooltip: 'Choose from phone contacts',
                    icon: const Icon(CupertinoIcons.person_crop_rectangle),
                    onPressed: canAddContact ? onPickContact : null,
                  ),
                ),
                validator: (value) => _phoneValidator(value, ownerPhoneNumber),
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

  /// Computes required validator.
  static String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Required';
    }
    return null;
  }

  /// Computes phone validator.
  static String? _phoneValidator(String? value, String ownerPhoneNumber) {
    final required = _requiredValidator(value);
    if (required != null) {
      return required;
    }
    if (!PhoneNumberFormatter.isValid(value!)) {
      return 'Use country code, for example +60123456789';
    }
    if (EmergencyContactsRepository.isOwnPhoneNumber(value, ownerPhoneNumber)) {
      return EmergencyContactsRepository.ownNumberMessage;
    }
    return null;
  }
}

/// Displays the edit contact sheet.
class _EditContactSheet extends StatefulWidget {
  /// Creates edit contact sheet.
  const _EditContactSheet({
    required this.contact,
    required this.ownerPhoneNumber,
    required this.pickContact,
  });

  final EmergencyContact contact;
  final String ownerPhoneNumber;
  final Future<EmergencyContactCandidate?> Function() pickContact;

  /// Creates the presentation state for this widget.
  @override
  State<_EditContactSheet> createState() => _EditContactSheetState();
}

/// Manages the edit contact sheet presentation and lifecycle.
class _EditContactSheetState extends State<_EditContactSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _relationshipController;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.contact.name);
    _phoneController = TextEditingController(text: widget.contact.phoneNumber);
    _relationshipController = TextEditingController(
      text: widget.contact.relationship,
    );
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _relationshipController.dispose();
    super.dispose();
  }

  /// Saves.
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

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.zero,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _ContactsColors.surfaceFor(context),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: _ContactsColors.separatorFor(context),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Edit contact',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(
                                      color: _ContactsColors.textFor(context),
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0,
                                    ),
                              ),
                            ),
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size.square(44),
                              onPressed: () => Navigator.of(context).pop(),
                              child: Icon(
                                CupertinoIcons.xmark_circle_fill,
                                color: _ContactsColors.secondaryTextFor(
                                  context,
                                ),
                                size: 28,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'Keep this person’s details up to date for SOS alerts.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: _ContactsColors.secondaryTextFor(
                                  context,
                                ),
                              ),
                        ),
                        const SizedBox(height: 24),
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
                          decoration: InputDecoration(
                            labelText: 'Phone number',
                            prefixIcon: const Icon(Icons.phone_iphone_rounded),
                            suffixIcon: IconButton(
                              tooltip: 'Choose from phone contacts',
                              icon: const Icon(
                                CupertinoIcons.person_crop_rectangle,
                              ),
                              onPressed: () async {
                                final contact = await widget.pickContact();
                                if (contact == null || !mounted) return;
                                _nameController.text = contact.displayName;
                                _phoneController.text =
                                    PhoneNumberFormatter.normalize(
                                      contact.primaryPhoneNumber,
                                    );
                              },
                            ),
                          ),
                          validator: (value) => _AddContactForm._phoneValidator(
                            value,
                            widget.ownerPhoneNumber,
                          ),
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
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
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

/// Displays the glyph.
class _Glyph extends StatelessWidget {
  /// Creates glyph.
  const _Glyph({required this.icon});

  final IconData icon;

  /// Builds this widget from its current presentation state.
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

/// Displays the inset group.
class _InsetGroup extends StatelessWidget {
  /// Creates inset group.
  const _InsetGroup({required this.child});

  final Widget child;

  /// Builds this widget from its current presentation state.
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

/// Displays the horizontal separator.
class _HorizontalSeparator extends StatelessWidget {
  /// Creates horizontal separator.
  const _HorizontalSeparator();

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 0.7,
      color: _ContactsColors.separatorFor(context),
    );
  }
}

/// Represents contacts colors.
abstract final class _ContactsColors {
  static const Color background = Color(0xFFF2F2F7);
  static const Color green = Color(0xFF34A853);
  static const Color separator = Color(0xFFD9E1DC);
  static const Color text = Color(0xFF111111);
  static const Color secondaryText = Color(0xFF6E6E73);
  static const Color chevron = Color(0xFFC7C7CC);
  static const Color edit = Color(0xFF2F8E50);
  static const Color destructive = Color(0xFFFF3B30);

  /// Checks whether dark.
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// Computes background for.
  static Color backgroundFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF0C120F) : background;

  /// Computes surface for.
  static Color surfaceFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF141C17) : Colors.white;

  /// Computes separator for.
  static Color separatorFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF2B3A31) : separator;

  /// Computes text for.
  static Color textFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFEAF4EE) : text;

  /// Computes secondary text for.
  static Color secondaryTextFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFA8B8AE) : secondaryText;

  /// Computes chevron for.
  static Color chevronFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF6F8175) : chevron;

  /// Computes destructive for.
  static Color destructiveFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFFF6B61) : destructive;
}
