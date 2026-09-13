import 'package:flutter/material.dart';

/// Shared mood for feelings, desires, and thought-bubble paint.
enum EmotionTone {
  neutral,
  happy,
  sad,
  warning,
  love,
  angry,
  sleepy,
  curious,
}

class EmotionSwatch {
  const EmotionSwatch({
    required this.fill,
    required this.stroke,
    required this.percolate,
  });

  final Color fill;
  final Color stroke;
  final Color percolate;
}

const kEmotionSwatches = <EmotionTone, EmotionSwatch>{
  EmotionTone.neutral: EmotionSwatch(
    fill: Color(0xFFF4F1EA),
    stroke: Color(0xFFB8B2A8),
    percolate: Color(0xFFE8E4DC),
  ),
  EmotionTone.happy: EmotionSwatch(
    fill: Color(0xFFFFF3A8),
    stroke: Color(0xFFE0B000),
    percolate: Color(0xFFFFE566),
  ),
  EmotionTone.sad: EmotionSwatch(
    fill: Color(0xFFD5DEE8),
    stroke: Color(0xFF6F8496),
    percolate: Color(0xFFB7C4D1),
  ),
  EmotionTone.warning: EmotionSwatch(
    fill: Color(0xFFFFE0B0),
    stroke: Color(0xFFE07020),
    percolate: Color(0xFFFF8A4C),
  ),
  EmotionTone.love: EmotionSwatch(
    fill: Color(0xFFFFD6E4),
    stroke: Color(0xFFE05A86),
    percolate: Color(0xFFFF8FB3),
  ),
  EmotionTone.angry: EmotionSwatch(
    fill: Color(0xFFFFC9C2),
    stroke: Color(0xFFC62828),
    percolate: Color(0xFFFF6E5A),
  ),
  EmotionTone.sleepy: EmotionSwatch(
    fill: Color(0xFFE6D8F5),
    stroke: Color(0xFF8A6BB5),
    percolate: Color(0xFFC7B0E8),
  ),
  EmotionTone.curious: EmotionSwatch(
    fill: Color(0xFFD5F5E8),
    stroke: Color(0xFF3D9B74),
    percolate: Color(0xFF8EE0BE),
  ),
};

EmotionSwatch emotionSwatch(EmotionTone tone) =>
    kEmotionSwatches[tone] ?? kEmotionSwatches[EmotionTone.neutral]!;
