import 'dart:math' as math;

import '../models/app_models.dart';
import 'rating_utils.dart';

enum SalonSort {
  recommended('Recommended'),
  nearest('Nearest'),
  highestRated('Highest rated');

  final String label;
  const SalonSort(this.label);
}

typedef SalonCoordinates = ({double latitude, double longitude});

bool validSalonCoordinates(double? latitude, double? longitude) =>
    latitude != null &&
    longitude != null &&
    latitude.isFinite &&
    longitude.isFinite &&
    latitude.abs() <= 90 &&
    longitude.abs() <= 180;

SalonCoordinates? salonCoordinates(Salon salon) {
  if (validSalonCoordinates(salon.latitude, salon.longitude)) {
    return (latitude: salon.latitude!, longitude: salon.longitude!);
  }
  final uri = Uri.tryParse(salon.directionsUrl);
  if (uri == null ||
      !['https', 'http'].contains(uri.scheme) ||
      ![
        'google.com',
        'google.co.in',
        'maps.apple.com',
      ].any((host) => uri.host == host || uri.host.endsWith('.$host'))) {
    return null;
  }
  SalonCoordinates? parse(String? value) {
    final match = RegExp(
      r'^\s*(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)\s*$',
    ).firstMatch(value ?? '');
    final latitude = double.tryParse(match?.group(1) ?? '');
    final longitude = double.tryParse(match?.group(2) ?? '');
    return validSalonCoordinates(latitude, longitude)
        ? (latitude: latitude!, longitude: longitude!)
        : null;
  }

  // A destination pin is useful; the map's @latitude,longitude viewport may
  // be centred somewhere else and must not be used as the salon's location.
  String decoded;
  try {
    for (final key in ['destination', 'query', 'q', 'll']) {
      final pin = parse(uri.queryParameters[key]);
      if (pin != null) return pin;
    }
    decoded = Uri.decodeFull(salon.directionsUrl);
  } on FormatException {
    return null;
  }
  final pins = RegExp(
    r'!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)',
  ).allMatches(decoded).map((m) => '${m[1]},${m[2]}').toSet();
  return pins.length == 1 ? parse(pins.single) : null;
}

double? salonDistanceMeters(Salon salon, SalonCoordinates? customer) {
  final pin = salonCoordinates(salon);
  if (pin == null ||
      customer == null ||
      !validSalonCoordinates(customer.latitude, customer.longitude)) {
    return null;
  }
  double radians(double value) => value * math.pi / 180;
  final latitudeDelta = radians(pin.latitude - customer.latitude);
  final longitudeDelta = radians(pin.longitude - customer.longitude);
  final a =
      math.pow(math.sin(latitudeDelta / 2), 2) +
      math.cos(radians(customer.latitude)) *
          math.cos(radians(pin.latitude)) *
          math.pow(math.sin(longitudeDelta / 2), 2);
  return 6371000 * 2 * math.asin(math.sqrt(a.clamp(0, 1)));
}

/// Sort an already filtered list. Searching and service filtering remain in the
/// caller; sorting never removes a salon because its location is unavailable.
List<Salon> sortSalons(
  Iterable<Salon> salons, {
  required SalonSort sort,
  required int Function(Salon) availabilityPriority,
  SalonCoordinates? customer,
  String query = '',
}) {
  final needle = query.trim().toLowerCase();
  int relevance(Salon salon) {
    if (needle.isEmpty) return 0;
    final name = salon.displayName.toLowerCase();
    if (name == needle) return 0;
    if (name.startsWith(needle)) return 1;
    if (name.contains(needle)) return 2;
    if (salon.availableServices.any(
      (s) =>
          s.name.toLowerCase().contains(needle) ||
          s.category.toLowerCase().contains(needle),
    )) {
      return 3;
    }
    return 4;
  }

  int recommended(Salon a, Salon b) {
    var order = relevance(a).compareTo(relevance(b));
    if (order != 0) return order;
    order = availabilityPriority(a).compareTo(availabilityPriority(b));
    return order != 0 ? order : compareSalonsByRating(a, b);
  }

  final distances = {
    if (sort == SalonSort.nearest)
      for (final salon in salons)
        salon.id: salonDistanceMeters(salon, customer),
  };
  return salons.toList()..sort((a, b) {
    int order;
    if (sort == SalonSort.nearest && customer != null) {
      final left = distances[a.id];
      final right = distances[b.id];
      if (left != null && right == null) return -1;
      if (left == null && right != null) return 1;
      order = left != null && right != null ? left.compareTo(right) : 0;
      if (order != 0) return order;
      order = recommended(a, b);
    } else if (sort == SalonSort.highestRated) {
      order = compareSalonsByRating(a, b);
      if (order == 0) {
        order = availabilityPriority(a).compareTo(availabilityPriority(b));
      }
    } else {
      order = recommended(a, b);
    }
    if (order != 0) return order;
    order = a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    return order != 0 ? order : a.id.compareTo(b.id);
  });
}
