import 'desktop_ui.dart';
import 'app_capabilities.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sqflite/sqflite.dart';

import 'app_database.dart';
import 'app_language.dart';
import 'product_photo.dart';

class BusinessLogoStore {
  static final revision = ValueNotifier<int>(0);
  static Future<Uint8List?> read() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'app_settings',
      where: 'key=?',
      whereArgs: ['business_logo_v1'],
    );
    if (rows.isEmpty) return null;
    try {
      return base64Decode(rows.single['value'] as String);
    } on FormatException {
      return null;
    }
  }

  static Future<void> save(Uint8List? bytes) async {
    final db = await AppDatabase.instance.database;
    if (bytes != null && (bytes.isEmpty || bytes.length > 750000)) {
      throw const FormatException('Invalid logo size');
    }
    if (bytes == null) {
      await db.delete(
        'app_settings',
        where: 'key=?',
        whereArgs: ['business_logo_v1'],
      );
    } else {
      await db.insert('app_settings', {
        'key': 'business_logo_v1',
        'value': base64Encode(bytes),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    revision.value++;
  }
}

class BusinessLogoPage extends StatefulWidget {
  const BusinessLogoPage({super.key});
  @override
  State<BusinessLogoPage> createState() => _BusinessLogoPageState();
}

class _BusinessLogoPageState extends State<BusinessLogoPage> {
  Uint8List? photo;
  bool busy = true;
  String? error;
  String t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final bytes = await BusinessLogoStore.read();
      if (mounted) setState(() => photo = bytes);
    } catch (_) {
      if (mounted) {
        setState(() => error = t('Could not load logo.', 'Logo မဖတ်နိုင်ပါ။'));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> pick(ImageSource source) async {
    setState(() => busy = true);
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 960,
        maxHeight: 960,
        imageQuality: 80,
      );
      if (file == null) return;
      final bytes = await prepareProductPhoto(await file.readAsBytes());
      await BusinessLogoStore.save(bytes);
      if (mounted) {
        setState(() {
          photo = bytes;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = t(
            'Could not save image. Choose a JPEG or PNG and retry.',
            'ပုံမသိမ်းနိုင်ပါ။ JPEG/PNG ရွေးပြီး ပြန်စမ်းပါ။',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: DesktopScaffold(
      appBar: AppBar(
        title: Text(t('Business Logo / Photo', 'လုပ်ငန်း Logo / ပုံ')),
      ),
      body: DesktopListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (busy) const LinearProgressIndicator(),
          if (photo != null)
            Image.memory(photo!, height: 150, fit: BoxFit.contain),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: busy ? null : () => pick(ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(
              t('Choose photo (optional)', 'ပုံရွေးရန် (မဖြစ်မနေမလို)'),
            ),
          ),
          if (AppCapabilities.camera)
            OutlinedButton.icon(
              onPressed: busy ? null : () => pick(ImageSource.camera),
              icon: const Icon(Icons.camera_alt_outlined),
              label: Text(t('Take photo', 'ဓာတ်ပုံရိုက်ရန်')),
            ),
          if (photo != null)
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() => busy = true);
                      try {
                        await BusinessLogoStore.save(null);
                        if (mounted) setState(() => photo = null);
                      } catch (_) {
                        if (mounted) {
                          setState(
                            () => error = t(
                              'Could not remove logo. Retry.',
                              'Logo မဖယ်နိုင်ပါ။ ပြန်စမ်းပါ။',
                            ),
                          );
                        }
                      } finally {
                        if (mounted) setState(() => busy = false);
                      }
                    },
              child: Text(t('Remove logo', 'Logo ဖယ်ရန်')),
            ),
          Text(
            t(
              'Control Show business logo in Invoice & Printer. Prints use the current logo; old invoice totals and text remain unchanged.',
              'Invoice & Printer မှ Logo ပြမပြ ရွေးပါ။ Print တွင် လက်ရှိ Logo ကိုသုံးပြီး ဘောင်ချာဟောင်းစာသားနှင့် ငွေပမာဏ မပြောင်းပါ။',
            ),
          ),
          if (error != null) Text(error!),
        ],
      ),
    ),
  );
}
