import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLanguage {
  static final current = ValueNotifier<String>('en');
  static final _storage = SharedPreferencesAsync();

  static Future<void> load() async {
    try {
      final saved = await _storage.getString('app_language');
      current.value = saved == 'my' ? 'my' : 'en';
    } catch (_) {
      current.value = 'en';
    }
  }

  static Future<void> change(String code) async {
    if (code != 'en' && code != 'my') {
      throw ArgumentError('Unsupported language');
    }

    await _storage.setString('app_language', code);
    current.value = code;
  }

  static String text(String english) {
    if (current.value != 'my') return english;

    return _myanmar[english] ?? english;
  }

  static const Map<String, String> _myanmar = {
    'App Updates': 'App Update များ',
    'User Guide': 'အသုံးပြုနည်းလမ်းညွှန်',
    'User guide & tutorials': 'အသုံးပြုနည်းနှင့် သင်ခန်းစာများ',
    'Feedback & Support': 'အကြံပြုချက်နှင့် အကူအညီ',
    'Balance Stock': 'ပစ္စည်းလက်ကျန်',
    'Check stock by category, brand and branch':
        'Category၊ Brand နှင့် ဆိုင်ခွဲအလိုက် လက်ကျန်စစ်ရန်',
    'Account & Business Settings': 'အကောင့်နှင့် လုပ်ငန်းဆက်တင်များ',
    'Log out': 'အကောင့်ထွက်ရန်',
    'Dashboard': 'ပင်မ',
    'Sale': 'အရောင်း',
    'Inventory': 'ကုန်ပစ္စည်း',
    'Expense': 'အသုံးစရိတ်',
    'Ledger': 'စာရင်းချုပ်',
    'Account': 'အကောင့်',
    'Language': 'ဘာသာစကား',
    'Theme': 'အပြင်အဆင်',

    'Business Profile': 'လုပ်ငန်းအချက်အလက်',
    'Branches': 'ဆိုင်ခွဲများ',
    'Money Accounts': 'ငွေအကောင့်များ',
    'Employees & Users': 'ဝန်ထမ်းနှင့် အသုံးပြုသူများ',
    'Roles & Permissions': 'ရာထူးနှင့် အသုံးပြုခွင့်များ',
    'Customers': 'ဝယ်သူများ',
    'Suppliers': 'ပစ္စည်းပေးသွင်းသူများ',
    'Categories': 'အမျိုးအစားများ',
    'Invoice & Printer': 'ဘောင်ချာနှင့် ပရင်တာ',
    'Subscription': 'ဝန်ဆောင်မှုသက်တမ်း',
    'Sync & Export': 'ဒေတာချိတ်ဆက်ခြင်းနှင့် ထုတ်ယူခြင်း',
    'Activity History': 'လုပ်ဆောင်မှုမှတ်တမ်း',

    'Sale Invoices': 'အရောင်းဘောင်ချာများ',
    'Customer Payments': 'ဝယ်သူထံမှ ငွေလက်ခံခြင်း',
    'Invoice list and new sales': 'ဘောင်ချာစာရင်းနှင့် အရောင်းအသစ်',
    'Receive outstanding payments': 'အကြွေးကျန်ငွေ လက်ခံရန်',

    'Purchase': 'ပစ္စည်းအဝယ်',
    'Create a purchase': 'ပစ္စည်းအဝယ်သွင်းရန်',
    'Purchase History': 'အဝယ်မှတ်တမ်း',
    'Stock & Products': 'ပစ္စည်းနှင့် လက်ကျန်စာရင်း',
    'Products, stock-in and stock history':
        'ပစ္စည်း၊ အဝင်နှင့် လက်ကျန်မှတ်တမ်း',
    'Stock Transfer': 'ဆိုင်ခွဲအချင်းချင်း ပစ္စည်းလွှဲခြင်း',
    'Transfer out and receive stock': 'ပစ္စည်းလွှဲပို့ခြင်းနှင့် လက်ခံခြင်း',
    'Stock Adjustment': 'လက်ကျန်ညှိနှိုင်းခြင်း',
    'Damage and stock corrections': 'ပျက်စီးပစ္စည်းနှင့် လက်ကျန်ပြင်ဆင်ခြင်း',

    'Expenses': 'အသုံးစရိတ်စာရင်း',
    'Expense list and new expenses': 'အသုံးစရိတ်စာရင်းနှင့် အသစ်ထည့်ရန်',
    'Expense History': 'အသုံးစရိတ် မှတ်တမ်း',
    'Expense Summary': 'အသုံးစရိတ်အနှစ်ချုပ်',
    'Monthly and category summaries': 'လနှင့် အမျိုးအစားအလိုက် အနှစ်ချုပ်',

    'Sales Reports': 'အရောင်းအစီရင်ခံစာများ',
    'Cash / Bank / Wallet Ledger': 'ငွေသား၊ ဘဏ်နှင့် ပိုက်ဆံအိတ်စာရင်း',
    'Customer Ledger': 'ဝယ်သူစာရင်း',
    'Supplier Ledger': 'ပစ္စည်းပေးသွင်းသူစာရင်း',
    'Account Transfer': 'ငွေအကောင့်အချင်းချင်း လွှဲခြင်း',
    'Other Money In / Out': 'အခြားငွေအဝင်နှင့် အထွက်',
    'Balance Check': 'ငွေလက်ကျန် တိုက်စစ်ခြင်း',

    'English / Myanmar': 'အင်္ဂလိပ် / မြန်မာ',
    'Light / Dark / System': 'အလင်း / အမှောင် / စက်သတ်မှတ်ချက်',
    'Advanced account management': 'အဆင့်မြင့် အကောင့်စီမံမှု',
    'Get started / continue setup': 'စတင်သုံးရန် / Setup ဆက်လုပ်ရန်',
    'Devices & approval': 'စက်ချိတ်ဆက်ခြင်းနှင့် ခွင့်ပြုခြင်း',
    'Business Overview': 'လုပ်ငန်းအနှစ်ချုပ်',
    'Monthly Sales': 'လစဉ်အရောင်းစုစုပေါင်း',
    'Monthly Expenses': 'လစဉ်အသုံးစရိတ်စုစုပေါင်း',
    'Cash Balance': 'ငွေသားလက်ကျန်',
    'Dashboard data pending':
        'အရောင်း၊ အသုံးစရိတ်နှင့် ငွေအကောင့်များ ချိတ်ဆက်ပြီးလျှင် '
        'ငွေပမာဏနှင့် ဇယားများ ပေါ်လာပါမည်။',
  };
}
