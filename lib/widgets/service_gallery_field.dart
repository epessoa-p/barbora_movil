import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api_client.dart';
import '../models/service.dart';
import '../theme/barbora_theme.dart';

/// Una foto en el borrador: una que ya está (con id) o una nueva del teléfono.
class GalleryItem {
  GalleryItem.existing(ServicePhoto photo)
      : id = photo.id,
        url = photo.url,
        localPath = null,
        caption = photo.caption ?? '',
        _savedCaption = photo.caption ?? '';

  GalleryItem.picked(String path)
      : id = null,
        url = null,
        localPath = path,
        caption = '',
        _savedCaption = '';

  final int? id;
  final String? url;
  final String? localPath;
  String caption;
  final String _savedCaption;

  bool get isNew => id == null;
  bool get captionChanged => caption.trim() != _savedCaption.trim();

  ImageProvider get image => localPath != null ? FileImage(File(localPath!)) : NetworkImage(url!) as ImageProvider;
}

/// La galería de un servicio mientras se edita: quitar, agregar, comentar y
/// ordenar quedan en borrador y se mandan juntos al guardar ([apply]).
class GalleryDraft {
  GalleryDraft(List<ServicePhoto> photos)
      : items = [for (final p in photos) GalleryItem.existing(p)],
        _initialOrder = [for (final p in photos) p.id];

  /// Tope del servidor (ServiceGallery::MAX).
  static const max = 30;

  final List<GalleryItem> items;
  final Set<int> removed = {};
  final List<int> _initialOrder;

  bool get changed =>
      removed.isNotEmpty ||
      items.any((i) => i.isNew || i.captionChanged) ||
      !_sameOrder;

  bool get _sameOrder {
    final ids = [for (final i in items) if (!i.isNew) i.id!];
    return ids.join(',') == _initialOrder.join(',');
  }

  /// Lo manda a la API en orden: quitar, subir las nuevas (de a una, con su
  /// comentario), comentarios cambiados y el orden final. Devuelve el
  /// servicio como quedó, o null si no hubo nada que mandar.
  Future<Service?> apply(ApiClient api, int serviceId) async {
    if (!changed) return null;
    final base = '/services/$serviceId/photos';
    Map<String, dynamic>? last;

    for (final id in removed) {
      last = await api.delete('$base/$id');
    }

    final ids = <int>[];
    for (final item in items) {
      if (item.isNew) {
        last = await api.upload(
          base,
          fields: {if (item.caption.trim().isNotEmpty) 'captions[0]': item.caption.trim()},
          fileField: 'photos[]',
          filePath: item.localPath,
        );
        final photos = ((last['data'] as Map<String, dynamic>)['photos'] as List).cast<Map<String, dynamic>>();
        ids.add((photos.last['id'] as num).toInt());
      } else {
        if (item.captionChanged) {
          last = await api.patch('$base/${item.id}', body: {'caption': item.caption.trim()});
        }
        ids.add(item.id!);
      }
    }

    if (ids.isNotEmpty) {
      last = await api.put('$base/order', body: {'ids': ids});
    }

    return last == null ? null : Service.fromJson(last['data'] as Map<String, dynamic>);
  }
}

/// Cuadrícula de fotos de cortes: «+ Agregar» (varias de la galería o una con
/// la cámara); al tocar una, su comentario, «Hacer portada», moverla o quitarla.
/// La primera es la portada.
class ServiceGalleryField extends StatefulWidget {
  const ServiceGalleryField({super.key, required this.draft, this.error});

  final GalleryDraft draft;
  final String? error;

  @override
  State<ServiceGalleryField> createState() => _ServiceGalleryFieldState();
}

class _ServiceGalleryFieldState extends State<ServiceGalleryField> {
  List<GalleryItem> get _items => widget.draft.items;

  Future<void> _add(ImageSource source) async {
    final room = GalleryDraft.max - _items.length;
    if (room <= 0) return;

    // Reducidas en el teléfono: el servidor acepta hasta 2 MB.
    final picker = ImagePicker();
    final picked = source == ImageSource.camera
        ? [?await picker.pickImage(source: source, maxWidth: 1200, maxHeight: 1200, imageQuality: 85)]
        : await picker.pickMultiImage(maxWidth: 1200, maxHeight: 1200, imageQuality: 85, limit: room > 1 ? room : null);

    if (picked.isEmpty || !mounted) return;
    setState(() => _items.addAll(picked.take(room).map((f) => GalleryItem.picked(f.path))));
  }

  void _addMenu() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Elegir de la galería'),
              subtitle: const Text('Puedes marcar varias'),
              onTap: () {
                Navigator.pop(ctx);
                _add(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tomar foto'),
              onTap: () {
                Navigator.pop(ctx);
                _add(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _move(GalleryItem item, int to) {
    setState(() {
      _items.remove(item);
      _items.insert(to.clamp(0, _items.length), item);
    });
  }

  void _remove(GalleryItem item) {
    setState(() {
      _items.remove(item);
      if (item.id != null) widget.draft.removed.add(item.id!);
    });
  }

  Future<void> _edit(GalleryItem item) async {
    final caption = TextEditingController(text: item.caption);
    final index = _items.indexOf(item);

    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image(image: item.image, height: 220, fit: BoxFit.cover),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: caption,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'Comentario', hintText: 'Ej.: 1, Corte XXTT'),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (index > 0)
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(ctx, 'cover'),
                    icon: const Icon(Icons.star_outline, size: 18),
                    label: const Text('Hacer portada'),
                  ),
                if (index > 0)
                  IconButton.outlined(
                    tooltip: 'Mover antes',
                    onPressed: () => Navigator.pop(ctx, 'left'),
                    icon: const Icon(Icons.arrow_back),
                  ),
                if (index < _items.length - 1)
                  IconButton.outlined(
                    tooltip: 'Mover después',
                    onPressed: () => Navigator.pop(ctx, 'right'),
                    icon: const Icon(Icons.arrow_forward),
                  ),
                TextButton.icon(
                  onPressed: () => Navigator.pop(ctx, 'remove'),
                  style: TextButton.styleFrom(foregroundColor: BarboraTheme.copperDark),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Quitar'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'ok'), child: const Text('Listo')),
          ],
        ),
      ),
    );

    if (!mounted) return;
    setState(() => item.caption = caption.text);
    caption.dispose();

    switch (action) {
      case 'cover':
        _move(item, 0);
      case 'left':
        _move(item, index - 1);
      case 'right':
        _move(item, index + 1);
      case 'remove':
        _remove(item);
    }
  }

  @override
  Widget build(BuildContext context) {
    final full = _items.length >= GalleryDraft.max;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Fotos de cortes (${_items.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
        const Text(
          'Cada una con su comentario. La primera es la portada. Salen en el catálogo público.',
          style: TextStyle(fontSize: 12.5, color: BarboraTheme.textMuted),
        ),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [
            for (final (i, item) in _items.indexed) _Thumb(item: item, cover: i == 0, onTap: () => _edit(item)),
            if (!full)
              InkWell(
                onTap: _addMenu,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  decoration: BoxDecoration(
                    color: BarboraTheme.canvas,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: BarboraTheme.border),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_a_photo_outlined, color: BarboraTheme.titanium),
                      SizedBox(height: 4),
                      Text('Agregar', style: TextStyle(fontSize: 12, color: BarboraTheme.textMuted)),
                    ],
                  ),
                ),
              ),
          ],
        ),
        if (widget.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(widget.error!, style: const TextStyle(color: BarboraTheme.copperDark, fontSize: 12)),
          ),
      ],
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.item, required this.cover, required this.onTap});

  final GalleryItem item;
  final bool cover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final caption = item.caption.trim();

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image(image: item.image, fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(color: BarboraTheme.canvas)),
            if (cover)
              Positioned(
                top: 6,
                left: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: BarboraTheme.ink, borderRadius: BorderRadius.circular(6)),
                  child: const Text('Portada', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                ),
              ),
            if (item.isNew)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFF16A34A), borderRadius: BorderRadius.circular(6)),
                  child: const Text('Nueva', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                ),
              ),
            if (caption.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(6, 10, 6, 4),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black54],
                    ),
                  ),
                  child: Text(caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
