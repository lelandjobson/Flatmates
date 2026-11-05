import 'dart:ui' as ui;
import 'package:flutter/services.dart';

enum FoldDistribution {
  pockets('Broad pockets'),
  scattered('Scattered patches');

  const FoldDistribution(this.label);
  final String label;
}

/// Immutable application-wide fold data. Each atlas owns its shader instance.
/// The 512² source (1 MiB decoded) is reused across reloads and camera movement.
class CrumpledPaperResources {
  CrumpledPaperResources._(this.program, this.image);
  final ui.FragmentProgram program;
  final ui.Image image;
  static Future<CrumpledPaperResources>? _pending;
  static Future<CrumpledPaperResources> load() => _pending ??= _load();
  static Future<CrumpledPaperResources> _load() async {
    final program = await ui.FragmentProgram.fromAsset(
      'shaders/landscape_crumple.frag',
    );
    final bytes = await rootBundle.load(
      'assets/textures/paper/landscape_crumple.png',
    );
    final codec = await ui.instantiateImageCodec(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    try {
      return CrumpledPaperResources._(
        program,
        (await codec.getNextFrame()).image,
      );
    } finally {
      codec.dispose();
    }
  }
}
