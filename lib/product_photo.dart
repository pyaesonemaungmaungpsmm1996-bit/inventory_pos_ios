import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'app_database.dart';

/// Normalize one camera/gallery image to a bounded JPEG before saving it in SQLite.
Future<Uint8List> prepareProductPhoto(Uint8List source) async {
  if (source.isEmpty || source.length > 10000000) {
    throw FormatException('Choose a photo smaller than 10 MB.');
  }
  return compute(_resizeProductPhoto, source);
}

Uint8List _resizeProductPhoto(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('This photo format cannot be opened.');
  }
  var oriented = img.bakeOrientation(decoded);
  for (final side in [960, 720, 480, 320]) {
    final longest = oriented.width > oriented.height
        ? oriented.width
        : oriented.height;
    final scale = longest > side ? side / longest : 1.0;
    final width = (oriented.width * scale).round().clamp(1, side).toInt();
    final height = (oriented.height * scale).round().clamp(1, side).toInt();
    final sized = scale < 1
        ? img.copyResize(
            oriented,
            width: width,
            height: height,
            interpolation: img.Interpolation.linear,
          )
        : oriented;
    final result = Uint8List.fromList(img.encodeJpg(sized, quality: 70));
    if (result.length <= 750000) return result;
    oriented = sized;
  }
  throw const FormatException(
    'Photo is too detailed. Choose a simpler or smaller photo.',
  );
}

/// Reads only visible photos; product list queries never load image blobs.
class ProductPhoto extends StatefulWidget {
  const ProductPhoto({
    super.key,
    required this.productId,
    required this.hasImage,
    this.size = 48,
  });
  final int productId;
  final bool hasImage;
  final double size;

  @override
  State<ProductPhoto> createState() => _ProductPhotoState();
}

class _ProductPhotoState extends State<ProductPhoto> {
  Future<Uint8List?>? image;

  @override
  void initState() {
    super.initState();
    if (widget.hasImage) {
      image = AppDatabase.instance.getProductImage(widget.productId);
    }
  }

  @override
  void didUpdateWidget(covariant ProductPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.productId != widget.productId ||
        oldWidget.hasImage != widget.hasImage) {
      image = widget.hasImage
          ? AppDatabase.instance.getProductImage(widget.productId)
          : null;
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget placeholder() =>
        Icon(Icons.inventory_2_outlined, size: widget.size * 0.55);
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: image == null
              ? Center(child: placeholder())
              : FutureBuilder<Uint8List?>(
                  future: image,
                  builder: (context, snapshot) {
                    final bytes = snapshot.data;
                    return bytes == null
                        ? Center(child: placeholder())
                        : Image.memory(
                            bytes,
                            fit: BoxFit.cover,
                            cacheWidth: (widget.size * 3).round(),
                            errorBuilder: (context, error, stackTrace) =>
                                Center(child: placeholder()),
                          );
                  },
                ),
        ),
      ),
    );
  }
}
