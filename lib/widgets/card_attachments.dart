import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../providers/theme_provider.dart';
import '../services/card_attachment_storage.dart';
import '../theme/app_typography.dart';
import '../utils/image_crop_helper.dart';

import 'package:provider/provider.dart';

class CardAttachmentsEditor extends StatelessWidget {
  final String? cardId;
  final List<String> existingIds;
  final List<File> pendingFiles;
  final ValueChanged<List<String>> onExistingChanged;
  final ValueChanged<List<File>> onPendingChanged;
  final int maxImages;

  const CardAttachmentsEditor({
    super.key,
    required this.cardId,
    required this.existingIds,
    required this.pendingFiles,
    required this.onExistingChanged,
    required this.onPendingChanged,
    this.maxImages = 5,
  });

  int get _totalCount => existingIds.length + pendingFiles.length;

  Future<void> _showPickOptions(BuildContext rootContext) async {
    if (_totalCount >= maxImages) {
      ScaffoldMessenger.of(rootContext).showSnackBar(
        SnackBar(content: Text('You can add up to $maxImages images')),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: rootContext,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take photo'),
                onTap: () {
                  Navigator.pop(context);
                  _pick(rootContext, ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pick(rootContext, ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pick(BuildContext context, ImageSource source) async {
    final picker = ImagePicker();
    final remaining = maxImages - _totalCount;
    if (remaining <= 0) return;

    if (source == ImageSource.gallery && remaining > 1) {
      final images = await picker.pickMultiImage(
        imageQuality: 80,
        maxWidth: 1920,
      );
      if (images.isEmpty) return;

      final cropped = <File>[];
      for (final image in images.take(remaining)) {
        if (!context.mounted) break;
        // Skipping a cancelled crop keeps the rest of the batch intact.
        final file = await cropImageFile(context, image.path);
        if (file != null) cropped.add(file);
      }
      if (cropped.isEmpty) return;
      onPendingChanged([...pendingFiles, ...cropped]);
      return;
    }

    final image = await picker.pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1920,
    );
    if (image == null || !context.mounted) return;

    final file = await cropImageFile(context, image.path);
    if (file == null) return;
    onPendingChanged([...pendingFiles, file]);
  }

  void _removeExisting(int index) {
    final updated = List<String>.from(existingIds)..removeAt(index);
    onExistingChanged(updated);
  }

  void _removePending(int index) {
    final updated = List<File>.from(pendingFiles)..removeAt(index);
    onPendingChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final canAdd = _totalCount < maxImages;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Photos',
          style: AppTypography.caption(
            color: themeProvider.getSecondaryTextColor(),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 88,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              if (canAdd)
                _AddTile(
                  onTap: () => _showPickOptions(context),
                  color: themeProvider.getSecondaryTextColor(),
                  background: themeProvider.isDarkMode
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.grey.shade100,
                ),
              ...List.generate(existingIds.length, (i) {
                return Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: _ExistingThumb(
                    cardId: cardId,
                    attachmentId: existingIds[i],
                    onRemove: () => _removeExisting(i),
                    onTap: () => _openViewer(context, existingIndex: i),
                  ),
                );
              }),
              ...List.generate(pendingFiles.length, (i) {
                return Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: _PendingThumb(
                    file: pendingFiles[i],
                    onRemove: () => _removePending(i),
                    onTap: () => _openViewer(context, pendingIndex: i),
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Optional — statements, QR, or card photos ($_totalCount/$maxImages)',
          style: AppTypography.caption(
            color: themeProvider.getSecondaryTextColor(),
          ),
        ),
      ],
    );
  }

  void _openViewer(
    BuildContext context, {
    int? existingIndex,
    int? pendingIndex,
  }) {
    final items = <_ViewerItem>[
      ...existingIds.map(
        (id) => _ViewerItem.existing(cardId: cardId, attachmentId: id),
      ),
      ...pendingFiles.map((f) => _ViewerItem.pending(f)),
    ];
    var initial = 0;
    if (existingIndex != null) initial = existingIndex;
    if (pendingIndex != null) initial = existingIds.length + pendingIndex;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _AttachmentViewer(items: items, initialIndex: initial),
      ),
    );
  }
}

class CardAttachmentsGallery extends StatelessWidget {
  final String cardId;
  final List<String> attachmentIds;

  const CardAttachmentsGallery({
    super.key,
    required this.cardId,
    required this.attachmentIds,
  });

  @override
  Widget build(BuildContext context) {
    if (attachmentIds.isEmpty) return const SizedBox.shrink();
    final themeProvider = context.watch<ThemeProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(
          'Photos',
          style: AppTypography.sectionTitle(
            color: themeProvider.getPrimaryTextColor(),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: attachmentIds.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              return GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => _AttachmentViewer(
                        items: attachmentIds
                            .map(
                              (id) => _ViewerItem.existing(
                                cardId: cardId,
                                attachmentId: id,
                              ),
                            )
                            .toList(),
                        initialIndex: index,
                      ),
                    ),
                  );
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 100,
                    height: 100,
                    child: _EncryptedImage(
                      cardId: cardId,
                      attachmentId: attachmentIds[index],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AddTile extends StatelessWidget {
  final VoidCallback onTap;
  final Color color;
  final Color background;

  const _AddTile({
    required this.onTap,
    required this.color,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_photo_alternate_outlined, color: color),
              const SizedBox(height: 4),
              Text('Add', style: AppTypography.caption(color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PendingThumb extends StatelessWidget {
  final File file;
  final VoidCallback onRemove;
  final VoidCallback onTap;

  const _PendingThumb({
    required this.file,
    required this.onRemove,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _ThumbShell(
      onTap: onTap,
      onRemove: onRemove,
      child: Image.file(file, fit: BoxFit.cover, width: 88, height: 88),
    );
  }
}

class _ExistingThumb extends StatelessWidget {
  final String? cardId;
  final String attachmentId;
  final VoidCallback onRemove;
  final VoidCallback onTap;

  const _ExistingThumb({
    required this.cardId,
    required this.attachmentId,
    required this.onRemove,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _ThumbShell(
      onTap: onTap,
      onRemove: onRemove,
      child: cardId == null
          ? const ColoredBox(color: Colors.black12)
          : _EncryptedImage(cardId: cardId!, attachmentId: attachmentId),
    );
  }
}

class _ThumbShell extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _ThumbShell({
    required this.child,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
          onTap: onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(width: 88, height: 88, child: child),
          ),
        ),
        Positioned(
          top: 2,
          right: 2,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

class _EncryptedImage extends StatefulWidget {
  final String cardId;
  final String attachmentId;

  const _EncryptedImage({required this.cardId, required this.attachmentId});

  @override
  State<_EncryptedImage> createState() => _EncryptedImageState();
}

class _EncryptedImageState extends State<_EncryptedImage> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _EncryptedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachmentId != widget.attachmentId ||
        oldWidget.cardId != widget.cardId) {
      _load();
    }
  }

  Future<void> _load() async {
    final bytes = await CardAttachmentStorage().loadBytes(
      widget.cardId,
      widget.attachmentId,
    );
    if (!mounted) return;
    setState(() {
      _bytes = bytes;
      _failed = bytes == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const ColoredBox(
        color: Colors.black12,
        child: Center(child: Icon(Icons.broken_image_outlined)),
      );
    }
    if (_bytes == null) {
      return const ColoredBox(
        color: Colors.black12,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return Image.memory(
      _bytes!,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
    );
  }
}

class _ViewerItem {
  final String? cardId;
  final String? attachmentId;
  final File? file;

  const _ViewerItem.existing({required this.cardId, required this.attachmentId})
    : file = null;

  const _ViewerItem.pending(this.file) : cardId = null, attachmentId = null;
}

class _AttachmentViewer extends StatefulWidget {
  final List<_ViewerItem> items;
  final int initialIndex;

  const _AttachmentViewer({required this.items, required this.initialIndex});

  @override
  State<_AttachmentViewer> createState() => _AttachmentViewerState();
}

class _AttachmentViewerState extends State<_AttachmentViewer> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.items.length - 1);
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_index + 1} / ${widget.items.length}'),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.items.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) {
          final item = widget.items[i];
          if (item.file != null) {
            return InteractiveViewer(
              child: Center(child: Image.file(item.file!)),
            );
          }
          return InteractiveViewer(
            child: Center(
              child: _EncryptedImage(
                cardId: item.cardId!,
                attachmentId: item.attachmentId!,
              ),
            ),
          );
        },
      ),
    );
  }
}
