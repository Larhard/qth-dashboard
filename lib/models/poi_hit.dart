/// One nearby point of interest, of any category (city, port, or ham reference),
/// with its distance and bearing from the query point. Pure Dart.
library;

import '../utils/geo_utils.dart';
import 'city.dart';
import 'ham_ref.dart';
import 'poi_category.dart';

class PoiHit {
  final PoiCategory category;
  final double distKm;
  final double bearingDeg;

  /// Set for city / port categories.
  final City? city;

  /// Set for amateur-radio reference categories.
  final HamRef? ref;

  const PoiHit._(this.category, this.distKm, this.bearingDeg, this.city, this.ref);

  factory PoiHit.city(PoiCategory c, City city, double fromLat, double fromLon,
          {double? distKm}) =>
      PoiHit._(c, distKm ?? haversineKm(fromLat, fromLon, city.lat, city.lon),
          bearing(fromLat, fromLon, city.lat, city.lon), city, null);

  factory PoiHit.ref(PoiCategory c, HamRef ref, double fromLat, double fromLon,
          {double? distKm}) =>
      PoiHit._(c, distKm ?? haversineKm(fromLat, fromLon, ref.lat, ref.lon),
          bearing(fromLat, fromLon, ref.lat, ref.lon), null, ref);

  bool get isRef => ref != null;
  String get name => ref?.name ?? city!.name;
  double get lat => ref?.lat ?? city!.lat;
  double get lon => ref?.lon ?? city!.lon;

  /// Short one-line label: "SP/BZ-005 Turbacz" for references, the name otherwise.
  String get label => isRef ? '${ref!.ref} ${ref!.name}' : name;

  /// "lat, lon" with 5 decimals — pasteable into Google Maps / hiking maps.
  String get coordsText => '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}';
}
