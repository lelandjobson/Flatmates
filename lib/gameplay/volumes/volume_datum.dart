/// Story clipping for zoomed-in map3d. Ground is datum 0.

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
