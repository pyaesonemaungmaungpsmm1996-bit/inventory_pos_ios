import 'package:flutter/services.dart';

/// Groups the integer part while preserving decimal text, selection and IME.
class AmountInputFormatter extends TextInputFormatter {
  const AmountInputFormatter();
  static String group(String value) {
    final parts = value.replaceAll(',', '').split('.');
    final whole = parts.first;
    final b = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) b.write(',');
      b.write(whole[i]);
    }
    return '$b${parts.length == 2 ? '.${parts[1]}' : ''}';
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.composing.isValid && !newValue.composing.isCollapsed) {
      return newValue;
    }
    final raw = newValue.text.replaceAll(',', '');
    if (!RegExp(r'^\d*(\.\d*)?$').hasMatch(raw)) return oldValue;
    var value = newValue;
    // Backspace on a separator deletes the preceding digit instead of sticking.
    if (oldValue.selection.isCollapsed &&
        newValue.selection.isCollapsed &&
        oldValue.text.length == newValue.text.length + 1 &&
        oldValue.selection.baseOffset > 0) {
      final at = oldValue.selection.baseOffset - 1;
      if (at < oldValue.text.length &&
          oldValue.text[at] == ',' &&
          newValue.selection.baseOffset > 0) {
        final cut = newValue.selection.baseOffset - 1;
        value = newValue.copyWith(
          text: newValue.text.replaceRange(cut, cut + 1, ''),
          selection: TextSelection.collapsed(offset: cut),
        );
      }
    }
    final formatted = group(value.text);
    int offset(int at) {
      if (at < 0) return formatted.length;
      final end = at.clamp(0, value.text.length).toInt();
      final count = value.text.substring(0, end).replaceAll(',', '').length;
      if (count == 0) return 0;
      var seen = 0;
      for (var i = 0; i < formatted.length; i++) {
        if (formatted[i] != ',') seen++;
        if (seen == count) return i + 1;
      }
      return formatted.length;
    }

    return value.copyWith(
      text: formatted,
      selection: TextSelection(
        baseOffset: offset(value.selection.baseOffset),
        extentOffset: offset(value.selection.extentOffset),
      ),
      composing: TextRange.empty,
    );
  }
}
