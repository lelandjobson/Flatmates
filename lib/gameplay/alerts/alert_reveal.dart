/// Drop alerts hidden by Create mode or an open interior.
///
/// [showInCreate] keeps path-connection region alerts visible while the
/// path tool is out, so connecting a gate can clear the marker in place.
List<T> visibleWorldAlerts<T>({
  required List<T> alerts,
  required bool createMode,
  required bool Function(T alert) lookingInside,
  bool Function(T alert)? showInCreate,
}) {
  return [
    for (final alert in alerts)
      if (!lookingInside(alert) &&
          (!createMode || (showInCreate?.call(alert) ?? false)))
        alert,
  ];
}
