import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api_client.dart';
import '../theme/barbora_theme.dart';

/// La foto elegida en un formulario (servicio, producto): la nueva del
/// teléfono, o «quitar la actual». Se sube aparte, al guardar.
class PhotoChoice {
  String? pickedPath;
  bool remove = false;

  bool get changed => pickedPath != null || remove;

  /// Sube o quita la foto en `path` (p. ej. `/services/5/photo`) y devuelve
  /// lo que responde la API. Solo llamarla si [changed].
  Future<Map<String, dynamic>> upload(ApiClient api, String path) => api.upload(
        path,
        fields: {if (pickedPath == null) 'remove_photo': '1'},
        fileField: pickedPath == null ? null : 'photo',
        filePath: pickedPath,
      );
}

/// Recuadro con la foto (la elegida, la actual o un hueco) y los botones
/// «Elegir / Cambiar» y «Quitar».
class PhotoPickerField extends StatefulWidget {
  const PhotoPickerField({
    super.key,
    required this.choice,
    this.currentUrl,
    this.help = 'Sale en el catálogo público.',
    this.error,
  });

  final PhotoChoice choice;

  /// La foto que ya tiene (null en un alta).
  final String? currentUrl;
  final String help;
  final String? error;

  @override
  State<PhotoPickerField> createState() => _PhotoPickerFieldState();
}

class _PhotoPickerFieldState extends State<PhotoPickerField> {
  /// De la galería, reducida en el teléfono: el servidor acepta hasta 2 MB.
  Future<void> _pick() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1000,
      maxHeight: 1000,
      imageQuality: 85,
    );
    if (picked == null) return;
    setState(() {
      widget.choice.pickedPath = picked.path;
      widget.choice.remove = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.choice;
    final current = c.remove ? null : widget.currentUrl;
    final ImageProvider? image = c.pickedPath != null
        ? FileImage(File(c.pickedPath!))
        : (current != null ? NetworkImage(current) : null);

    return Row(
      children: [
        GestureDetector(
          onTap: _pick,
          child: Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: BarboraTheme.canvas,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: BarboraTheme.border),
              image: image == null ? null : DecorationImage(image: image, fit: BoxFit.cover),
            ),
            child: image == null ? const Icon(Icons.add_a_photo_outlined, color: BarboraTheme.titanium) : null,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Foto', style: TextStyle(fontWeight: FontWeight.w700)),
              Text(widget.help, style: const TextStyle(fontSize: 12.5, color: BarboraTheme.textMuted)),
              Wrap(
                spacing: 4,
                children: [
                  TextButton(onPressed: _pick, child: Text(image == null ? 'Elegir foto' : 'Cambiar')),
                  if (image != null)
                    TextButton(
                      onPressed: () => setState(() {
                        c.pickedPath = null;
                        c.remove = widget.currentUrl != null;
                      }),
                      style: TextButton.styleFrom(foregroundColor: BarboraTheme.textMuted),
                      child: const Text('Quitar'),
                    ),
                ],
              ),
              if (widget.error != null)
                Text(widget.error!, style: const TextStyle(color: BarboraTheme.copperDark, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }
}
