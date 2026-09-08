/// Drop alerts hidden by Create mode or an open interior.
List<T> visibleWorldAlerts<T>({
  required List<T> alerts,
  required bool createMode,
  required bool Function(T alert) lookingInside,
}) {
  if (createMode) return const [];
  return [for (final alert in alerts) if (!lookingInside(alert)) alert];
}
