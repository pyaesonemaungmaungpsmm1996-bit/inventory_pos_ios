import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'business_logo_page.dart';

/// Shares the saved business identity across account entry points.
class BusinessLogoAvatar extends StatefulWidget {
  const BusinessLogoAvatar({super.key, this.size = 44});
  final double size;

  @override
  State<BusinessLogoAvatar> createState() => _BusinessLogoAvatarState();
}

class _BusinessLogoAvatarState extends State<BusinessLogoAvatar> {
  late Future<Uint8List?> logo;

  @override
  void initState() {
    super.initState();
    logo = BusinessLogoStore.read();
    BusinessLogoStore.revision.addListener(reload);
  }

  void reload() => setState(() => logo = BusinessLogoStore.read());

  @override
  void dispose() {
    BusinessLogoStore.revision.removeListener(reload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.size,
    height: widget.size,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: FutureBuilder<Uint8List?>(
        future: logo,
        builder: (context, snapshot) {
          final fallback = Icon(Icons.store_outlined, size: widget.size * .75);
          final bytes = snapshot.data;
          if (bytes == null) return fallback;
          return Image.memory(
            bytes,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stack) => fallback,
          );
        },
      ),
    ),
  );
}
