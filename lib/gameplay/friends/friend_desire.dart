import 'emotion_tone.dart';

/// Something a friend wants to tell you. Percolates until hover opens a cloud.
class Desire {
  const Desire({
    required this.id,
    required this.name,
    required this.icon,
    required this.tone,
  });

  final String id;
  final String name;
  final String icon;
  final EmotionTone tone;
}

const kDesires = <Desire>[
  Desire(id: 'snack', name: 'Snack', icon: '🍪', tone: EmotionTone.happy),
  Desire(id: 'nap', name: 'Nap', icon: '😴', tone: EmotionTone.sleepy),
  Desire(id: 'walk', name: 'Walk', icon: '🚶', tone: EmotionTone.curious),
  Desire(id: 'chat', name: 'Chat', icon: '💬', tone: EmotionTone.happy),
  Desire(id: 'garden', name: 'Garden', icon: '🌱', tone: EmotionTone.curious),
  Desire(id: 'music', name: 'Music', icon: '🎵', tone: EmotionTone.love),
  Desire(id: 'bath', name: 'Bath', icon: '🛁', tone: EmotionTone.neutral),
  Desire(id: 'gift', name: 'Gift', icon: '🎁', tone: EmotionTone.love),
  Desire(id: 'company', name: 'Company', icon: '👋', tone: EmotionTone.love),
  Desire(id: 'explore', name: 'Explore', icon: '🧭', tone: EmotionTone.curious),
];

final kDesiresById = {
  for (final desire in kDesires) desire.id: desire,
};

Desire? desireById(String? id) => id == null ? null : kDesiresById[id];
