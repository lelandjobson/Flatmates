/// Mass-level alert / possession chips sit above a volume or region from
/// the outside. They hide in Create mode and whenever that structure's
/// interior is open (ceiling down, plan, focus, or volume-interior viewer).
bool massProgramHudVisible({
  required bool createMode,
  required bool lookingInside,
}) =>
    !createMode && !lookingInside;

enum VolumeAlertKind { unprogrammed, noEntry, bedroomAccess }

/// Alerts for one mass. Unprogrammed, missing entry, then isolated bedrooms.
List<VolumeAlertKind> volumeAlerts({
  required bool programmed,
  required bool hasEntry,
  bool bedroomNeedsAccess = false,
}) {
  return [
    if (!programmed) VolumeAlertKind.unprogrammed,
    if (!hasEntry) VolumeAlertKind.noEntry,
    if (bedroomNeedsAccess) VolumeAlertKind.bedroomAccess,
  ];
}

/// True when this volume's floors are shown (question marks / floor menus).
bool volumeFloorVisible({
  required bool interiorViewer,
  required bool ceilingHidesFloor,
}) =>
    interiorViewer || !ceilingHidesFloor;
