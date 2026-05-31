class City {
  final String name;
  final String country;
  final double lat;
  final double lon;

  // ── City enrichment (populated by fetch_cities.py) ──────────────────────
  /// GeoNames population estimate, 0 if unavailable.
  final int population;
  /// IANA timezone name, empty if unavailable (e.g. "Europe/Warsaw").
  final String timezone;

  // ── Port basic fields (populated by fetch_ports.py) ─────────────────────
  /// GeoNames feature code: PRT / HBR / MRNA / LDNG / ANCH.
  final String portType;
  /// WPI harbour size: L / M / S / VS.
  final String harbourSize;
  /// Primary VHF working channel(s), semicolon-separated, e.g. "12;74".
  final String vhf;
  /// Port operations phone / harbour-master number.
  final String phone;
  /// ITU radio call sign.
  final String callSign;
  /// WPI world port number.
  final String wpiIndex;
  /// Pipe-separated facility flags, e.g. "FUEL_OIL|WATER|PROVISIONS".
  final String facilities;

  // ── Port navigation details (WPI columns, populated by fetch_ports.py) ──
  /// Harbour type: "Natural", "Coastal Breakwater", "River", etc.
  final String harborType;
  /// Primary harbour use: "Public", "Military", "Private", etc.
  final String harborUse;
  /// Shelter quality: E (Excellent) / G (Good) / F (Fair) / P (Poor).
  final String shelter;
  /// Mean tidal range in metres. 0 = unknown.
  final double tidalRangeM;
  /// Navigable channel depth in metres. 0 = unknown.
  final double channelDepthM;
  /// Maximum vessel length in metres. 0 = unknown.
  final double maxVesselLengthM;
  /// Standard nautical chart number.
  final String chart;
  /// IMO NAVAREA designation, e.g. "VIII".
  final String navarea;
  /// Sailing directions / pilot book title.
  final String publication;
  /// URL to the sailing directions or NGA publication page.
  final String publicationLink;
  /// Pilotage status: "Compulsory", "Available", "Advisable", or combinations.
  final String pilotage;
  /// Comma-separated entry restrictions: Tide, Heavy Swell, Ice, Other.
  final String entryRestrictions;
  /// Whether this is a First Port of Entry (customs/immigration): "Y" or "N".
  final String firstPortEntry;

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
    this.wpiIndex = '',
    this.facilities = '',
    this.harborType = '',
    this.harborUse = '',
    this.shelter = '',
    this.tidalRangeM = 0.0,
    this.channelDepthM = 0.0,
    this.maxVesselLengthM = 0.0,
    this.chart = '',
    this.navarea = '',
    this.publication = '',
    this.publicationLink = '',
    this.pilotage = '',
    this.entryRestrictions = '',
    this.firstPortEntry = '',
  });

  bool get hasPortComms =>
      vhf.isNotEmpty || phone.isNotEmpty || callSign.isNotEmpty;

  bool get hasNavDetails =>
      harborType.isNotEmpty || shelter.isNotEmpty ||
      tidalRangeM > 0 || channelDepthM > 0 || publication.isNotEmpty;
}
