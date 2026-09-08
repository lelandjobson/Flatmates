/// When false, per-floor program icons stay up in interior / plan / focus
/// viewers instead of fading after the camera rests. Map3d is unchanged.
const bool kProgramIconAutohideInInterior = false;

/// Mass-level alert / possession chips sit above a volume or region from
/// the outside. They hide in Create mode and whenever that structure's
/// interior is open (ceiling down, plan, focus, or volume-interior viewer).
bool massProgramHudVisible({
  required bool createMode,
  required bool lookingInside,
}) =>
    !createMode && !lookingInside;

enum VolumeAlertKind { unprogrammed, noEntry, bedroomAccess }

/// Alerts for one mass. Unprogrammed, missing door, then isolated bedrooms.
///
/// Missing entry is volume-level: any exterior door clears it. Circulation
/// does not have to touch that door.
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
