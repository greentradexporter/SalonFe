import 'package:flutter/material.dart';
import '../../models/app_models.dart';
import '../../models/service_catalog.dart';
import '../../state/app_state.dart';
import '../../state/app_state_scope.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/app_error_dialog.dart';

class SalonBarberForm extends StatefulWidget {
  final Barber? barber;

  const SalonBarberForm({super.key, this.barber});

  @override
  State<SalonBarberForm> createState() => SalonBarberFormState();
}

class SalonBarberFormState extends State<SalonBarberForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _experienceController;
  late final TextEditingController _resumeController;
  final _serviceSearchController = TextEditingController();
  final Set<String> _selectedServices = {};
  late String _speciality;
  String _serviceQuery = '';
  bool _servicesExpanded = false;
  bool _isSaving = false;
  String? _saveError;

  bool get _isEditing => widget.barber != null;

  @override
  void initState() {
    super.initState();
    final barber = widget.barber;
    _nameController = TextEditingController(text: barber?.name ?? '');
    _phoneController = TextEditingController(text: barber?.phone ?? '');
    _experienceController = TextEditingController(
      text: '${barber?.experienceYears ?? 2}',
    );
    _resumeController = TextEditingController(
      text: barber?.resumeSummary ?? '',
    );
    _speciality = barber?.speciality.trim().isNotEmpty == true
        ? barber!.speciality.trim()
        : _barberSpecialities.first;
    _selectedServices.addAll(barber?.serviceIds ?? const <String>[]);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _experienceController.dispose();
    _resumeController.dispose();
    _serviceSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppStateScope.watch(context);
    final services = appState.ownerSalon.services;
    final specialityServices = services
        .where(
          (service) => serviceMatchesBarberSpeciality(service, _speciality),
        )
        .toList();
    final visibleServices = specialityServices.where((service) {
      final query = _serviceQuery.trim().toLowerCase();
      return query.isEmpty ||
          service.name.toLowerCase().contains(query) ||
          service.category.toLowerCase().contains(query);
    }).toList();

    return FractionallySizedBox(
      heightFactor: 0.92,
      child: Padding(
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _isEditing ? 'Edit barber' : 'Add barber',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  children: [
                    TextFormField(
                      key: const ValueKey('barber-name-field'),
                      controller: _nameController,
                      decoration: const InputDecoration(labelText: 'Name'),
                      validator: _required,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      key: const ValueKey('barber-phone-field'),
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone number (optional)',
                      ),
                      validator: _phone,
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: _speciality,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Speciality',
                      ),
                      items: [
                        for (final item in {
                          _speciality,
                          ..._barberSpecialities,
                        })
                          DropdownMenuItem(value: item, child: Text(item)),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _speciality = value;
                            _selectedServices.removeWhere((serviceId) {
                              final service = services
                                  .where((item) => item.id == serviceId)
                                  .firstOrNull;
                              return service == null ||
                                  !serviceMatchesBarberSpeciality(
                                    service,
                                    value,
                                  );
                            });
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      key: const ValueKey('barber-experience-field'),
                      controller: _experienceController,
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        final years = int.tryParse(value ?? '');
                        return years == null || years < 0 || years > 80
                            ? 'Enter years of experience from 0 to 80'
                            : null;
                      },
                      decoration: const InputDecoration(
                        labelText: 'Years of experience',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      key: const ValueKey('barber-resume-field'),
                      controller: _resumeController,
                      minLines: 2,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Barber resume summary',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.line),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          ListTile(
                            title: const Text('Assigned services'),
                            subtitle: Text(
                              _selectedServices.isEmpty
                                  ? 'All services by default'
                                  : '${_selectedServices.length} selected',
                            ),
                            trailing: Icon(
                              _servicesExpanded
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                            ),
                            onTap: () => setState(
                              () => _servicesExpanded = !_servicesExpanded,
                            ),
                          ),
                          if (_servicesExpanded)
                            Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    8,
                                    12,
                                    4,
                                  ),
                                  child: TextField(
                                    controller: _serviceSearchController,
                                    onChanged: (value) =>
                                        setState(() => _serviceQuery = value),
                                    decoration: const InputDecoration(
                                      labelText: 'Search services',
                                      prefixIcon: Icon(Icons.search),
                                    ),
                                  ),
                                ),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxHeight: 220,
                                  ),
                                  child: ListView.builder(
                                    shrinkWrap: true,
                                    itemCount: visibleServices.length,
                                    itemBuilder: (context, index) {
                                      final service = visibleServices[index];
                                      return CheckboxListTile(
                                        dense: true,
                                        value: _selectedServices.contains(
                                          service.id,
                                        ),
                                        title: Text(service.name),
                                        subtitle: Text(service.category),
                                        onChanged: (selected) {
                                          setState(() {
                                            if (selected == true) {
                                              _selectedServices.add(service.id);
                                            } else {
                                              _selectedServices.remove(
                                                service.id,
                                              );
                                            }
                                          });
                                        },
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
              if (_saveError != null) ...[
                Text(
                  _saveError!,
                  key: const ValueKey('barber-save-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 8),
              ],
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: ValueKey(
                    _isEditing ? 'save-barber-changes' : 'add-barber-submit',
                  ),
                  onPressed: _isSaving ? null : () => _save(appState),
                  icon: _isSaving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _isEditing
                              ? Icons.save_outlined
                              : Icons.person_add_alt,
                        ),
                  label: Text(
                    _isSaving
                        ? _isEditing
                              ? 'Saving...'
                              : 'Adding...'
                        : _isEditing
                        ? 'Save changes'
                        : 'Add barber',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _required(String? value) {
    return value == null || value.trim().isEmpty ? 'Required' : null;
  }

  String? _phone(String? value) {
    final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return null;
    }
    final localDigits = digits.length == 12 && digits.startsWith('91')
        ? digits.substring(2)
        : digits;
    return localDigits.length == 10 ? null : 'Enter a 10-digit phone number';
  }

  Future<void> _save(AppState appState) async {
    if (!_formKey.currentState!.validate()) {
      setState(
        () => _saveError = 'Check the name and years of experience above.',
      );
      return;
    }
    setState(() {
      _isSaving = true;
      _saveError = null;
    });
    try {
      final barber = widget.barber;
      if (barber == null) {
        await appState.addOwnerBarber(
          name: _nameController.text,
          phone: _phoneController.text,
          speciality: _speciality,
          experienceYears: int.tryParse(_experienceController.text) ?? 1,
          resumeSummary: _resumeController.text,
          serviceIds: _selectedServices.toList(),
        );
      } else {
        await appState.updateOwnerBarber(
          barberId: barber.id,
          name: _nameController.text,
          phone: _phoneController.text,
          speciality: _speciality,
          experienceYears: int.tryParse(_experienceController.text) ?? 1,
          resumeSummary: _resumeController.text,
          serviceIds: _selectedServices.toList(),
        );
      }
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _saveError = friendlyErrorMessage(
            error,
            fallback: 'The barber details could not be saved. Try again.',
          );
        });
      }
    }
  }
}

const _barberSpecialities = [
  'Haircut specialist',
  'Fade specialist',
  'Beard and shave expert',
  'Hair styling expert',
  'Hair color specialist',
  'Hair spa specialist',
  'Skin and cleanup expert',
  'Kids haircut specialist',
  'All-round grooming expert',
];

class SalonBarberCard extends StatelessWidget {
  final Barber barber;

  const SalonBarberCard({super.key, required this.barber});

  @override
  Widget build(BuildContext context) {
    final appState = AppStateScope.watch(context);
    final serviceNames = barber.serviceIds
        .map((id) => appState.getService(barber.salonId, id)?.name)
        .whereType<String>()
        .join(', ');

    return GlassCard(
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.mint,
            foregroundColor: AppColors.primary,
            child: Text(
              barber.name.characters.first,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  barber.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '${barber.experienceYears} yrs exp - ${serviceNames.isEmpty ? barber.speciality : serviceNames}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  barber.phone.isEmpty
                      ? 'Staff profile'
                      : 'Staff profile · ${barber.phone}',
                  style: const TextStyle(
                    color: AppColors.success,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: ValueKey('edit-barber-${barber.id}'),
            onPressed: () => _showEditBarberDialog(context),
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit barber',
          ),
          IconButton(
            onPressed: () => _confirmRemove(context, barber),
            icon: const Icon(Icons.person_remove_outlined),
            tooltip: 'Remove barber',
          ),
        ],
      ),
    );
  }

  void _showEditBarberDialog(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SalonBarberForm(barber: barber),
    );
  }

  void _confirmRemove(BuildContext context, Barber barber) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Remove ${barber.name}?'),
          content: Text(
            'This removes the barber from active staff and future slot availability.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await AppStateScope.read(context).removeBarber(barber.id);
                  if (context.mounted) {
                    Navigator.pop(context);
                  }
                } catch (error) {
                  if (!context.mounted) {
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        friendlyErrorMessage(
                          error,
                          fallback:
                              'The barber could not be removed. Try again.',
                        ),
                      ),
                    ),
                  );
                }
              },
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );
  }
}
