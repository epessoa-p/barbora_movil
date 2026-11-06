import 'package:barbora_movil/models/service.dart';
import 'package:barbora_movil/widgets/service_gallery_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Escribir el comentario de una foto y tocar «Listo» no tiene que romper la
/// app (antes se liberaba el campo mientras la hoja se cerraba).
void main() {
  testWidgets('el comentario de una foto se guarda al tocar Listo', (tester) async {
    final draft = GalleryDraft(const [ServicePhoto(id: 1, url: 'https://x/a.jpg')]);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: ServiceGalleryField(draft: draft))),
    ));
    await tester.pump();

    await tester.tap(find.text('Portada'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Comentario'), 'Corte XXTT');
    await tester.tap(find.text('Listo'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(draft.items.first.caption, 'Corte XXTT');
    expect(draft.changed, isTrue);
    expect(find.text('Corte XXTT'), findsOneWidget);
  });
}
