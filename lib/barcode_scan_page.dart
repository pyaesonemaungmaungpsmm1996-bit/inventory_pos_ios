import 'desktop_ui.dart';
import 'app_capabilities.dart';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'app_language.dart';
import 'barcode_rules.dart';

String _t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;

class BarcodeScanPage extends StatefulWidget {
  const BarcodeScanPage({super.key, this.identity = false});
  final bool identity;
  @override
  State<BarcodeScanPage> createState() => _BarcodeScanPageState();
}

class _BarcodeScanPageState extends State<BarcodeScanPage> {
  final code = TextEditingController();
  bool resolved = false;
  String? error;
  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  void finish(String input) {
    if (resolved || !mounted) return;
    final value = input.trim();
    if (widget.identity
        ? (value.isEmpty ||
              value.length > 100 ||
              RegExp(r'[\x00-\x1f\x7f]').hasMatch(value))
        : !BarcodeRules.valid(value)) {
      final message = widget.identity
          ? _t(
              'Enter one Serial / IMEI (maximum 100 characters).',
              'Serial / IMEI တစ်ခုထည့်ပါ (အများဆုံး 100 လုံး)။',
            )
          : _t(
              'Use a product barcode or item code (1–32 English letters, numbers or symbols, without spaces).',
              'ပစ္စည်း Barcode သို့မဟုတ် Item Code ကို ထည့်ပါ။ အင်္ဂလိပ်အက္ခရာ၊ ဂဏန်း၊ သင်္ကေတ ၁–၃၂ လုံးသာ၊ Space မပါဘဲ သုံးပါ။',
            );
      if (error != message) setState(() => error = message);
      return;
    }
    // A camera can emit the same code on every frame; return only once.
    resolved = true;
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.pop(context, value);
  }

  void detect(BarcodeCapture capture) {
    if (resolved || !mounted) return;
    final values = capture.barcodes
        .map((b) => b.rawValue?.trim())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toSet();
    if (values.length > 1) {
      final message = _t(
        'Show only one barcode at a time.',
        'တစ်ကြိမ်လျှင် Barcode တစ်ခုသာ ပြပါ။',
      );
      if (error != message) setState(() => error = message);
    } else if (values.length == 1) {
      finish(values.single);
    }
  }

  @override
  Widget build(BuildContext context) => DesktopScaffold(
    appBar: AppBar(
      title: Text(
        widget.identity
            ? _t('Scan Serial / IMEI', 'Serial / IMEI ဖတ်ရန်')
            : _t('Scan Product Barcode', 'ပစ္စည်း Barcode ဖတ်ရန်'),
      ),
    ),
    body: SafeArea(
      child: Column(
        children: [
          if (AppCapabilities.camera)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _t(
                  'Point the camera at one barcode. You can also type a code below or use a keyboard barcode scanner.',
                  'Barcode တစ်ခုကို Camera ဖြင့်ချိန်ပါ။ အောက်တွင် ကုဒ်ရိုက်ထည့်နိုင်ပြီး Keyboard Scanner လည်း သုံးနိုင်ပါသည်။',
                ),
              ),
            ),
          if (AppCapabilities.camera)
            Expanded(
              child: ClipRect(
                child: MobileScanner(
                  onDetect: detect,
                  // The plugin owns its default controller, camera lifecycle and disposal.
                  errorBuilder: (context, error) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        _t(
                          'Camera unavailable or permission denied. Allow camera access in device settings, then reopen Scan. Manual entry below still works.',
                          'Camera မရနိုင်ပါ သို့မဟုတ် ခွင့်ပြုချက်မရှိပါ။ စက်၏ Settings တွင် Camera ခွင့်ပြုပြီး Scan ပြန်ဖွင့်ပါ။ အောက်တွင် ကုဒ်ရိုက်ထည့်နိုင်ပါသည်။',
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (!AppCapabilities.camera)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _t(
                  'Click the code box, scan with a USB keyboard scanner and press Enter, or type the code. Camera scanning is not available on Windows.',
                  'Code အကွက်ကိုနှိပ်ပြီး USB Keyboard Scanner ဖြင့် Scan လုပ်ကာ Enter နှိပ်ပါ။ Code ကိုရိုက်ထည့်လည်းရသည်။ Windows တွင် Camera Scan မပါသေးပါ။',
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: code,
                  autofocus: !AppCapabilities.camera,
                  maxLength: widget.identity ? 100 : 32,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.search,
                  onSubmitted: finish,
                  decoration: InputDecoration(
                    labelText: widget.identity
                        ? 'Serial / IMEI'
                        : _t('Barcode / Item Code', 'Barcode / Item Code'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => finish(code.text),
                    icon: const Icon(Icons.search),
                    label: Text(_t('Use Code', 'ကုဒ်ဖြင့်ရွေးမည်')),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
