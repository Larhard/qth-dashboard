class City {
  final String name;
  final String country;
  final double lat;
  final double lon;

  // ── City enrichment (populated by fetch_cities.py) ──────────────────────
  /// GeoNames population estimate, 0 if unavailable.
  final int population;
  /// IANA timezone name, empty string if unavailable (e.g. "Europe/Warsaw").
  final String timezone;

  // ── Port-specific fields (populated by fetch_ports.py) ──────────────────
  /// GeoNames feature code: PRT / HBR / MRNA / LDNG / ANCH.
  final String portType;
  /// WPI harbour size: L (Large) / M (Medium) / S (Small) / VS (Very Small).
  final String harbourSize;
  /// Primary VHF working channel(s), semicolon-separated if multiple, e.g. "12;74".
  final String vhf;
  /// Port operations phone / harbour-master number.
  final String phone;
  /// ITU radio call sign.
  final String callSign;

  const City({
    required this.name,
    required this.country,
    required this.lat,
    required this.lon,
    this.population = 0,
    this.timezone = '',
    this.portType = '',
    this.harbourSize = '',
    this.vhf = '',
    this.phone = '',
    this.callSign = '',
  });

  bool get hasPortComms => vhf.isNotEmpty || phone.isNotEmpty || callSign.isNotEmpty;
}
