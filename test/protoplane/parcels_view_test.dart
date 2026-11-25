import 'dart:ui' as ui;
import 'package:flatmates/rendering/scene/camera.dart';
import 'package:flatmates/protoplane/dev_settings.dart';
import 'package:flatmates/protoplane/storage.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/parcels.dart';
import 'package:flatmates/protoplane/parcel_overlay.dart';
import 'package:flatmates/rendering/scene_view.dart';
import 'package:flatmates/screens/protoplane_concept_view.dart';

void main() {
  testWidgets(
    'unowned parcels are empty outside shopping and outline-only inside it',
    (tester) async {
      final repaint = ChangeNotifier();
      addTearDown(repaint.dispose);
      final parcels = WorldParcels();
      const id = ParcelId(1, 0);
      final center = parcels.bounds(id).center;
      final camera = Camera(
        name: 'parcel-test',
        position: Vector3(center.dx, 10, -center.dy),
        target: Vector3(center.dx, 0, -center.dy),
        up: Vector3(0, 0, -1),
      );
      for (final shopping in [false, true]) {
        final painter = ParcelPainter(
          parcels: parcels,
          available: {id},
          camera: camera,
          shopping: shopping,
          hovered: null,
          repaint: repaint,
        );
        final recorder = ui.PictureRecorder();
        painter.paint(Canvas(recorder), const Size(400, 400));
        final picture = recorder.endRecording();
        await tester.runAsync(() async {
          final image = await picture.toImage(400, 400);
          final bytes = (await image.toByteData())!.buffer.asUint8List();
          expect(bytes[(200 * 400 + 200) * 4 + 3], 0, reason: 'No parcel fill');
          final hasPaint = [
            for (var i = 3; i < bytes.length; i += 4) bytes[i],
          ].any((alpha) => alpha > 0);
          expect(
            hasPaint,
            shopping,
            reason: 'Outlines only appear while shopping',
          );
          image.dispose();
        });
        picture.dispose();
      }
    },
  );

  testWidgets('devtools parcel slider resizes the starting parcel on release', (
    tester,
  ) async {
    final model = ProtoplaneController();
    final settings = ProtoplaneSettings();
    addTearDown(model.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProtoplaneDevToolsPanel(
            settings: settings,
            store: ProtoplaneStorage(),
            changed: () => model.setParcelSize(settings.parcelSize),
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.tap(find.text('Camera'));
    await tester.pumpAndSettle();
    final slider = find.byKey(const ValueKey('Parcel size'));
    await tester.ensureVisible(slider);
    await tester.drag(slider, const Offset(120, 0));
    await tester.pumpAndSettle();
    expect(model.parcels.size, greaterThan(3));
    expect(model.parcels.size, settings.parcelSize);
    expect(
      model.parcels.bounds(const ParcelId(0, 0)).width,
      settings.parcelSize.toDouble(),
    );
    await tester.pumpWidget(const SizedBox());
  });

  for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
    testWidgets(
      'zoom range exposes parcels, hover price, tap purchase, and zoom exits ($kind)',
      (tester) async {
        final model = ProtoplaneController();
        tester.view.physicalSize = const Size(1000, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          model.dispose();
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        await tester.pumpWidget(
          MaterialApp(
            home: ProtoplaneConceptView(controller: model, animateFog: false),
          ),
        );
        await tester.pumpAndSettle();
        ParcelPainter overlay() =>
            tester
                    .widget<CustomPaint>(
                      find.byKey(const ValueKey('parcel-overlay')),
                    )
                    .painter!
                as ParcelPainter;
        expect(overlay().shopping, isFalse);
        final scene = tester
            .widget<SceneView>(find.byType(SceneView).first)
            .scene;
        final visibleTerrain = scene.meshes.where(
          (mesh) => model.landscape.terrain.tiles.containsKey(mesh.id),
        );
        expect(visibleTerrain, isNotEmpty);
        expect(
          visibleTerrain.every((mesh) => model.ownsTerrainTile(mesh.id)),
          isTrue,
        );
        expect(overlay().available, isNot(contains(const ParcelId(1, 1))));
        Future<void> scroll(double amount) async {
          await tester.sendEventToBinding(
            PointerScrollEvent(
              position: const Offset(700, 400),
              scrollDelta: Offset(0, amount),
            ),
          );
          await tester.pumpAndSettle();
        }

        await scroll(1000);
        expect(overlay().shopping, isTrue);
        final camera = tester
            .widget<SceneView>(find.byType(SceneView).first)
            .scene
            .camera!;
        const id = ParcelId(1, 0);
        final center = model.parcels.bounds(id).center;
        final screen = camera.projectToScreen(
          Vector3(center.dx, 0, -center.dy),
          const Size(1000, 800),
        )!;
        final mouse = await tester.createGesture(kind: kind);
        await mouse.addPointer(location: screen);
        if (kind == PointerDeviceKind.mouse) {
          await mouse.moveTo(screen);
        } else {
          await mouse.down(screen);
        }
        await tester.pump();
        expect(overlay().hovered, id);
        expect(overlay().parcels.price, 900);
        if (kind == PointerDeviceKind.mouse) await mouse.down(screen);
        await mouse.up();
        await tester.pumpAndSettle();
        expect(model.parcels.purchased.contains(id), isTrue);
        expect(overlay().available, contains(const ParcelId(1, 1)));
        expect(
          scene.meshes
              .where(
                (mesh) => model.landscape.terrain.tiles.containsKey(mesh.id),
              )
              .every((mesh) => model.ownsTerrainTile(mesh.id)),
          isTrue,
        );
        expect(model.activePlaneId, isNull);
        await scroll(-1000);
        expect(overlay().shopping, isFalse);
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
