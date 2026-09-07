import 'volume.dart';

/// Story clipping. Ground is datum 0.
///
/// Map3d zoom hides stories above [currentDatum] only while zoomed in.
/// Volume floor plan view hides them outright, plus every ceiling at that
/// datum, so the camera can pan a roof-off plan of the focused story.

bool volumeAboveCurrentDatum({
  required int volumeDatum,
  required int currentDatum,
  required bool zoomedIn,
}) =>
    zoomedIn && volumeDatum > currentDatum;

bool volumeAtCurrentDatum({
  required int volumeDatum,
  required int currentDatum,
}) =>
    volumeDatum == currentDatum;

bool volumeBelowCurrentDatum({
  required int volumeDatum,
  required int currentDatum,
}) =>
    volumeDatum < currentDatum;

/// True when a mass sits strictly above the focused story.
bool volumeHiddenAboveDatum({
  required int volumeDatum,
  required int currentDatum,
}) =>
    volumeDatum > currentDatum;

/// Masses on stories above [datum]. Used by floor plan view (no zoom gate).
Set<int> hiddenVolumeIdsAboveDatum({
  required Iterable<Volume> volumes,
  required int datum,
}) =>
    {
      for (final volume in volumes)
        if (volumeHiddenAboveDatum(
          volumeDatum: volume.datum,
          currentDatum: datum,
        ))
          volume.id,
    };

/// Masses whose roofs come off in a plan view of [datum].
Set<int> hideCeilingVolumeIdsAtDatum({
  required Iterable<Volume> volumes,
  required int datum,
}) =>
    {
      for (final volume in volumes)
        if (volumeAtCurrentDatum(
          volumeDatum: volume.datum,
          currentDatum: datum,
        ))
          volume.id,
    };
