String asciiPhoneDigits(String value) => value.replaceAllMapped(
  RegExp('[၀-၉]'),
  (m) => (m[0]!.codeUnitAt(0) - 0x1040).toString(),
);
String normalizeOtpPhone(String input) {
  var value = asciiPhoneDigits(input).trim().replaceAll(RegExp(r'[\s()-]'), '');
  if (value.startsWith('09')) {
    value = '+95${value.substring(1)}';
  } else if (value.startsWith('959')) {
    value = '+$value';
  }
  if (!RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(value)) {
    throw const FormatException(
      'Enter a valid phone number (09… or +959…). / ဖုန်းနံပါတ်မှန် ထည့်ပါ (09… သို့မဟုတ် +959…)။',
    );
  }
  return value;
}

String normalizeSmsCode(String input) {
  final value = asciiPhoneDigits(input).replaceAll(RegExp(r'\s'), '');
  if (!RegExp(r'^[0-9]{6,10}$').hasMatch(value)) {
    throw const FormatException(
      'Enter the SMS code you received. / SMS မှရရှိသော ကုဒ်ကို ထည့်ပါ။',
    );
  }
  return value;
}

String? otpErrorMessage(String? code, bool my) {
  switch (code) {
    case 'phone_provider_disabled':
    case 'otp_disabled':
    case 'sms_send_failed':
      return my
          ? 'SMS ဝန်ဆောင်မှု ချိတ်ဆက်မှုကို စစ်ဆေးရန်လိုပါသည်။ ယာယီ Email ဖြင့် ဝင်နိုင်ပါသည်။'
          : 'SMS service needs configuration or provider checks. You can use email for now.';
    case 'otp_expired':
      return my
          ? 'ကုဒ် သက်တမ်းကုန် သို့မဟုတ် မမှန်ပါ။ နောက်ဆုံးရရှိသောကုဒ်ကို သုံးပါ၊ လိုအပ်လျှင် ပြန်တောင်းပါ။'
          : 'The code is expired or invalid. Use the latest code or request another.';
    case 'over_sms_send_rate_limit':
    case 'over_request_rate_limit':
      return my
          ? 'ကုဒ်တောင်းဆိုမှုများနေပါသည်။ ခဏစောင့်ပြီး ပြန်စမ်းပါ။'
          : 'Too many requests. Wait before trying again.';
    default:
      return null;
  }
}
