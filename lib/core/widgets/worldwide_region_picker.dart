import 'package:country_state_city/country_state_city.dart' as csc;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'loading_toast.dart';

class WorldwideRegion {
  const WorldwideRegion({
    required this.country,
    required this.countryCode,
    required this.state,
    required this.stateCode,
  });

  final String country;
  final String countryCode;
  final String state;
  final String stateCode;
}

abstract final class WorldwideRegionCatalog {
  static Future<List<csc.Country>>? _countriesFuture;
  static final Map<String, Future<List<csc.State>>> _statesFutures = {};

  static const Map<String, ({String name, String code})> _malaysiaStates = {
    'johor': (name: 'Johor', code: '01'),
    'kedah': (name: 'Kedah', code: '02'),
    'kelantan': (name: 'Kelantan', code: '03'),
    'malacca': (name: 'Malacca', code: '04'),
    'melaka': (name: 'Malacca', code: '04'),
    'negerisembilan': (name: 'Negeri Sembilan', code: '05'),
    'pahang': (name: 'Pahang', code: '06'),
    'penang': (name: 'Penang', code: '07'),
    'pulaupinang': (name: 'Penang', code: '07'),
    'perak': (name: 'Perak', code: '08'),
    'perlis': (name: 'Perlis', code: '09'),
    'selangor': (name: 'Selangor', code: '10'),
    'terengganu': (name: 'Terengganu', code: '11'),
    'sabah': (name: 'Sabah', code: '12'),
    'sarawak': (name: 'Sarawak', code: '13'),
    'kualalumpur': (name: 'Kuala Lumpur', code: '14'),
    'wilayahpersekutuankualalumpur': (name: 'Kuala Lumpur', code: '14'),
    'labuan': (name: 'Labuan', code: '15'),
    'wilayahpersekutuanlabuan': (name: 'Labuan', code: '15'),
    'putrajaya': (name: 'Putrajaya', code: '16'),
    'wilayahpersekutuanputrajaya': (name: 'Putrajaya', code: '16'),
  };

  static Future<WorldwideRegion?> normalize({
    required String country,
    required String state,
  }) async {
    final countryKey = _key(country);
    final stateKey = _key(state);
    final malaysiaState = _malaysiaStates[stateKey];
    if (malaysiaState != null &&
        (countryKey.isEmpty ||
            countryKey == 'malaysia' ||
            countryKey == 'my')) {
      return WorldwideRegion(
        country: 'Malaysia',
        countryCode: 'MY',
        state: malaysiaState.name,
        stateCode: malaysiaState.code,
      );
    }

    final countries = await (_countriesFuture ??= csc.getAllCountries());
    final matchedCountry = countries.cast<csc.Country?>().firstWhere(
      (item) =>
          item != null &&
          (_key(item.name) == countryKey ||
              item.isoCode.toLowerCase() == country.trim().toLowerCase()),
      orElse: () => null,
    );
    if (matchedCountry == null) return null;
    final states = await (_statesFutures[matchedCountry.isoCode] ??= csc
        .getStatesOfCountry(matchedCountry.isoCode));
    if (stateKey.isEmpty) return null;
    final matchedState = states.cast<csc.State?>().firstWhere(
      (item) =>
          item != null &&
          (_key(item.name) == stateKey ||
              _key(item.name).contains(stateKey) ||
              stateKey.contains(_key(item.name))),
      orElse: () => null,
    );
    if (matchedState == null) return null;
    return WorldwideRegion(
      country: matchedCountry.name,
      countryCode: matchedCountry.isoCode,
      state: matchedState.name,
      stateCode: matchedState.isoCode,
    );
  }

  static String _key(String value) => value
      .toLowerCase()
      .replaceAll('&', 'and')
      .replaceAll(
        RegExp(r'\b(federal territory of|state of|province of|region of)\b'),
        '',
      )
      .replaceAll(RegExp(r'[^a-z0-9]'), '');
}

abstract final class WorldwideRegionPicker {
  static Future<WorldwideRegion?> show(
    BuildContext context, {
    String initialCountry = '',
    String initialState = '',
  }) {
    return showModalBottomSheet<WorldwideRegion>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _WorldwideRegionSheet(
        initialCountry: initialCountry,
        initialState: initialState,
      ),
    );
  }
}

class _WorldwideRegionSheet extends StatefulWidget {
  const _WorldwideRegionSheet({
    required this.initialCountry,
    required this.initialState,
  });

  final String initialCountry;
  final String initialState;

  @override
  State<_WorldwideRegionSheet> createState() => _WorldwideRegionSheetState();
}

class _WorldwideRegionSheetState extends State<_WorldwideRegionSheet> {
  List<csc.Country> _countries = const [];
  List<csc.State> _states = const [];
  csc.Country? _country;
  csc.State? _state;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCountries();
  }

  Future<void> _loadCountries() async {
    try {
      final countries = await csc.getAllCountries();
      countries.sort((a, b) => a.name.compareTo(b.name));
      final wanted = widget.initialCountry.trim().toLowerCase();
      final country = countries.cast<csc.Country?>().firstWhere(
        (item) => item?.name.toLowerCase() == wanted,
        orElse: () => countries.cast<csc.Country?>().firstWhere(
          (item) => item?.isoCode.toLowerCase() == wanted,
          orElse: () => countries.isEmpty ? null : countries.first,
        ),
      );
      if (!mounted) return;
      setState(() {
        _countries = countries;
        _country = country;
      });
      await _loadStates(country, preferName: widget.initialState);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Worldwide locations could not be loaded.';
      });
    }
  }

  Future<void> _loadStates(
    csc.Country? country, {
    String preferName = '',
  }) async {
    if (country == null) {
      setState(() {
        _states = const [];
        _state = null;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final states = await csc.getStatesOfCountry(country.isoCode);
      states.sort((a, b) => a.name.compareTo(b.name));
      final wanted = preferName.trim().toLowerCase();
      final selected = states.cast<csc.State?>().firstWhere(
        (item) => item?.name.toLowerCase() == wanted,
        orElse: () => states.isEmpty ? null : states.first,
      );
      if (!mounted || _country?.isoCode != country.isoCode) return;
      setState(() {
        _states = states;
        _state = selected;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _states = const [];
        _state = null;
        _loading = false;
        _error = 'States could not be loaded for ${country.name}.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return FractionallySizedBox(
      heightFactor: 0.72,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Choose a state',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'Country and state names use one worldwide catalogue across trail discovery and trail editing.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(color: colorScheme.error)),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: _loading && _countries.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          HikerCircleMinorLoadingIndicator(
                            size: 82,
                            semanticsLabel: 'Loading worldwide regions',
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Loading worldwide regions…',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: _RegionWheel<csc.Country>(
                            label: 'Country',
                            values: _countries,
                            selected: _country,
                            textFor: (value) => value.name,
                            onSelected: (value) {
                              setState(() {
                                _country = value;
                                _state = null;
                                _states = const [];
                              });
                              _loadStates(value);
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _RegionWheel<csc.State>(
                            label: 'State',
                            values: _states,
                            selected: _state,
                            textFor: (value) => value.name,
                            onSelected: (value) =>
                                setState(() => _state = value),
                            loading: _loading,
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _country == null || _state == null
                  ? null
                  : () => Navigator.of(context).pop(
                      WorldwideRegion(
                        country: _country!.name,
                        countryCode: _country!.isoCode,
                        state: _state!.name,
                        stateCode: _state!.isoCode,
                      ),
                    ),
              child: const Text('Use this state'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RegionWheel<T> extends StatelessWidget {
  const _RegionWheel({
    required this.label,
    required this.values,
    required this.selected,
    required this.textFor,
    required this.onSelected,
    this.loading = false,
  });

  final String label;
  final List<T> values;
  final T? selected;
  final String Function(T value) textFor;
  final ValueChanged<T> onSelected;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final initialIndex = selected == null ? 0 : values.indexOf(selected as T);
    return Column(
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Expanded(
          child: loading
              ? const Center(child: HikerCircleMinorLoadingIndicator())
              : values.isEmpty
              ? Center(child: Text('No $label available'))
              : CupertinoPicker(
                  key: ValueKey('$label-${values.length}-${selected.hashCode}'),
                  itemExtent: 46,
                  scrollController: FixedExtentScrollController(
                    initialItem: initialIndex < 0 ? 0 : initialIndex,
                  ),
                  onSelectedItemChanged: (index) => onSelected(values[index]),
                  children: [
                    for (final value in values)
                      Center(
                        child: Text(
                          textFor(value),
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
