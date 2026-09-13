import 'emotion_tone.dart';

/// A typical mood that pops up as a rounded thought card.
class Feeling {
  const Feeling({
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

const kFeelings = <Feeling>[
  Feeling(id: 'happy', name: 'Happy', icon: '🌞', tone: EmotionTone.happy),
  Feeling(id: 'sad', name: 'Sad', icon: '💔', tone: EmotionTone.sad),
  Feeling(id: 'love', name: 'In love', icon: '❤️', tone: EmotionTone.love),
  Feeling(
    id: 'warning',
    name: 'Worried',
    icon: '⚠️',
    tone: EmotionTone.warning,
  ),
  Feeling(id: 'neutral', name: 'Okay', icon: '😐', tone: EmotionTone.neutral),
  Feeling(id: 'angry', name: 'Angry', icon: '💢', tone: EmotionTone.angry),
  Feeling(id: 'sleepy', name: 'Sleepy', icon: '💤', tone: EmotionTone.sleepy),
  Feeling(
    id: 'curious',
    name: 'Curious',
    icon: '🤔',
    tone: EmotionTone.curious,
  ),
];

final kFeelingsById = {
  for (final feeling in kFeelings) feeling.id: feeling,
};

Feeling? feelingById(String? id) => id == null ? null : kFeelingsById[id];
