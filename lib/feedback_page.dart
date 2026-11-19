import 'app_capabilities.dart';
import 'desktop_ui.dart';

import 'dart:math';

import 'package:flutter/material.dart';

import 'billing_forms.dart';
import 'online_account_service.dart';
import 'subscription_billing_service.dart';

class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key, this.admin = false});
  final bool admin;
  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  final title = TextEditingController(), message = TextEditingController();
  String section = 'general', key = '', owner = '';
  String? business, error, notice;
  List<Map<String, dynamic>> businesses = [];
  List<dynamic> rows = [];
  bool busy = false;
  int page = 0;
  String newKey() {
    final random = Random.secure();
    final b = List.generate(16, (_) => random.nextInt(256));
    b[6] = (b[6] & 15) | 64;
    b[8] = (b[8] & 63) | 128;
    final h = b.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  @override
  void initState() {
    super.initState();
    key = newKey();
    load();
  }

  @override
  void dispose() {
    title.dispose();
    message.dispose();
    super.dispose();
  }

  Future<void> load() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await OnlineAccounts.initialize();
      final id = OnlineAccounts.client.auth.currentUser?.id;
      if (id == null) {
        throw StateError(
          bt(
            'Sign in before sending feedback.',
            'Feedback ပို့ရန် အကောင့်အရင်ဝင်ပါ။',
          ),
        );
      }
      owner = id;
      final found = widget.admin
          ? <Map<String, dynamic>>[]
          : (await OnlineAccounts.snapshot())
                .where((b) => b['active'] == true)
                .toList();
      final result = await OnlineAccounts.client.rpc(
        widget.admin ? 'tp_feedback_admin_list' : 'tp_feedback_list',
        params: {'p_page': page},
      );
      if (mounted) {
        setState(() {
          businesses = found;
          rows = result as List;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          rows = [];
          businesses = [];
          error = BillingService.friendly(e);
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> deliver(String id) async {
    try {
      BillingService.guard(owner);
      await OnlineAccounts.client.functions.invoke(
        'feedback-mailer',
        body: {'id': id},
      );
    } catch (_) {
      /* Server queue retains feedback. No private recipient/errors are shown. */
    }
  }

  Future<void> send() async {
    if (busy) return;
    if (title.text.trim().length < 3 || message.text.trim().length < 5) {
      setState(
        () => error = bt(
          'Enter a title and a message.',
          'ခေါင်းစဉ်နှင့် အကြောင်းအရာထည့်ပါ။',
        ),
      );
      return;
    }
    setState(() => busy = true);
    try {
      BillingService.guard(owner);
      final id = await OnlineAccounts.client.rpc(
        'tp_feedback_submit',
        params: {
          'p_key': key,
          'p_business': business,
          'p_section': section,
          'p_title': title.text.trim(),
          'p_body': message.text.trim(),
        },
      );
      await deliver(id as String);
      if (mounted) {
        setState(() {
          title.clear();
          message.clear();
          key = newKey();
          notice = bt(
            'Feedback saved. Email delivery status is shown below; queued messages remain in the support inbox.',
            'Feedback သိမ်းပြီးပါပြီ။ Email ပို့သည့်အခြေအနေကို အောက်တွင်ကြည့်ပါ။ စောင့်ဆိုင်းစာများကို Support inbox တွင် ဆက်သိမ်းထားပါသည်။',
          );
          error = null;
          page = 0;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = BillingService.friendly(e));
    } finally {
      if (mounted) {
        setState(() => busy = false);
        await load();
      }
    }
  }

  Future<void> reviewDelivery(String id) async {
    final f = await billingForm(
      context,
      bt('Review email delivery', 'Email ပို့ပြီးမှုစစ်ဆေးရန်'),
      [
        BillingField(
          'result',
          bt('Confirmed mail-service result', 'Email Service မှ အတည်ပြုရလဒ်'),
          initial: 'sent',
          options: const {
            'sent': 'Confirmed sent in email service',
            'retry': 'Confirmed not sent; allow retry',
          },
        ),
        BillingField(
          'reason',
          bt('Reason / evidence', 'အကြောင်းရင်း / အထောက်အထား'),
        ),
      ],
      notice: bt(
        'Check the email service dashboard first. Allowing a retry after an uncertain delivery can create a duplicate; do not guess.',
        'Email Service Dashboard ကို အရင်စစ်ပါ။ မသေချာဘဲ Retry ခွင့်ပေးလျှင် စာထပ်ပို့နိုင်၍ မခန့်မှန်းပါနှင့်။',
      ),
    );
    if (f == null || !mounted) return;
    setState(() => busy = true);
    try {
      BillingService.guard(owner);
      await OnlineAccounts.client.rpc(
        'tp_feedback_resolve_delivery',
        params: {
          'p_id': id,
          'p_sent': f['result'] == 'sent',
          'p_reason': f['reason'],
        },
      );
      if (f['result'] == 'retry') await deliver(id);
    } catch (e) {
      if (mounted) setState(() => error = BillingService.friendly(e));
    } finally {
      if (mounted) {
        setState(() => busy = false);
        await load();
      }
    }
  }

  @override
  Widget build(BuildContext context) => DesktopScaffold(
    appBar: AppBar(
      title: Text(
        widget.admin
            ? bt('Feedback inbox', 'Feedback inbox')
            : bt('Feedback & Support', 'အကြံပြုချက်နှင့် အကူအညီ'),
      ),
      actions: [
        IconButton(
          onPressed: busy ? null : load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: DesktopListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (!widget.admin) ...[
          Text(
            bt(
              'Send a suggestion, report a problem or ask for help. Your message and selected business are shared with the provider. Never include OTPs, passwords or card details.',
              'အကြံပြုချက်၊ အခက်အခဲ သို့မဟုတ် အကူအညီ တောင်းနိုင်ပါသည်။ စာနှင့် ရွေးထားသောလုပ်ငန်းကို Provider ထံ ပို့ပါမည်။ OTP၊ Password နှင့် ကတ်အချက်အလက် မထည့်ပါနှင့်။',
            ),
          ),
          DropdownButtonFormField<String>(
            initialValue: section,
            isExpanded: true,
            decoration: InputDecoration(labelText: bt('Section', 'အပိုင်း')),
            items: [
              for (final s in [
                'general',
                'sale',
                'inventory',
                'expense',
                'ledger',
                'account',
                'backup',
                'subscription',
              ])
                DropdownMenuItem(value: s, child: Text(s.toUpperCase())),
            ],
            onChanged: busy ? null : (v) => setState(() => section = v!),
          ),
          DropdownButtonFormField<String>(
            initialValue: business ?? '',
            isExpanded: true,
            decoration: InputDecoration(
              labelText: bt('Business · optional', 'လုပ်ငန်း · မဖြစ်မနေမဟုတ်'),
            ),
            items: [
              DropdownMenuItem(
                value: '',
                child: Text(bt('Not selected', 'မရွေးထားပါ')),
              ),
              for (final b in businesses)
                DropdownMenuItem(
                  value: b['id'] as String,
                  child: Text('${b['name']}'),
                ),
            ],
            onChanged: busy
                ? null
                : (v) => setState(() => business = v == '' ? null : v),
          ),
          TextField(
            controller: title,
            enabled: !busy,
            maxLength: 150,
            decoration: InputDecoration(labelText: bt('Title', 'ခေါင်းစဉ်')),
          ),
          TextField(
            controller: message,
            enabled: !busy,
            minLines: 5,
            maxLines: 12,
            maxLength: 4000,
            decoration: InputDecoration(
              labelText: bt('Message', 'အကြောင်းအရာ'),
            ),
          ),
          FilledButton.icon(
            onPressed: busy || owner.isEmpty ? null : send,
            icon: const Icon(Icons.send_outlined),
            label: Text(bt('Send feedback', 'Feedback ပို့မည်')),
          ),
        ],
        if (busy) const LinearProgressIndicator(),
        if (error != null) Text(error!),
        if (notice != null) Text(notice!),
        const Divider(height: 32),
        Text(
          widget.admin
              ? bt('All feedback', 'Feedback အားလုံး')
              : bt('Your feedback history', 'သင့် Feedback မှတ်တမ်း'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (AppCapabilities.windows)
          DesktopInlineTable(
            columns: const [
              'Title',
              'Section',
              'Created at',
              'Message',
              'Email delivery',
            ],
            flexes: const [2, 1, 2, 3, 1],
            rows: [
              for (final f in rows)
                DesktopListTile(
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (_) => DesktopDialog(
                      title: Text(f['title'].toString()),
                      content: SingleChildScrollView(
                        child: SelectableText(f['body'].toString()),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () =>
                              Navigator.of(context, rootNavigator: true).pop(),
                          child: Text(bt('Close', 'ပိတ်ရန်')),
                        ),
                      ],
                    ),
                  ),
                  trailing: Wrap(
                    children: [
                      if (f['email_state'] != 'sent' &&
                          f['email_state'] != 'review')
                        TextButton(
                          onPressed: busy
                              ? null
                              : () async {
                                  setState(() => busy = true);
                                  await deliver(f['id'] as String);
                                  if (mounted) {
                                    setState(() => busy = false);
                                    await load();
                                  }
                                },
                          child: Text(
                            bt('Retry email delivery', 'Email ပြန်ပို့ရန်'),
                          ),
                        ),
                      if (widget.admin && f['email_state'] == 'review')
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => reviewDelivery(f['id'] as String),
                          child: Text(
                            bt('Review email result', 'Email ရလဒ်စစ်ဆေးရန်'),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
            cells: [
              for (final f in rows)
                [
                  desktopCellText(f['title']),
                  desktopCellText(f['section']),
                  desktopCellText(billingTime(f['created_at'])),
                  desktopCellText(f['body']),
                  desktopCellText(f['email_state']),
                ],
            ],
          )
        else ...[
          for (final f in rows)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${f['title']}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text('${f['section']} · ${billingTime(f['created_at'])}'),
                    if (widget.admin)
                      Text(
                        '${f['email'] ?? f['phone'] ?? f['user_id']}\n${f['business_name'] ?? ''}',
                      ),
                    SelectableText('${f['body']}'),
                    const SizedBox(height: 8),
                    Text(
                      '${bt('Email delivery', 'Email ပို့ခြင်း')}: ${f['email_state']}',
                    ),
                    if (f['email_state'] != 'sent' &&
                        f['email_state'] != 'review')
                      TextButton(
                        onPressed: busy
                            ? null
                            : () async {
                                setState(() => busy = true);
                                await deliver(f['id'] as String);
                                if (mounted) {
                                  setState(() => busy = false);
                                  await load();
                                }
                              },
                        child: Text(
                          bt('Retry email delivery', 'Email ပြန်ပို့ရန်'),
                        ),
                      ),
                    if (widget.admin && f['email_state'] == 'review')
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => reviewDelivery(f['id'] as String),
                        child: Text(
                          bt('Review email result', 'Email ရလဒ်စစ်ဆေးရန်'),
                        ),
                      ),
                    if (f['email_state'] == 'review')
                      Text(
                        bt(
                          'Manual delivery review is required. The feedback remains saved.',
                          'ပို့ပြီးမပြီးကို Support မှ စစ်ဆေးရန်လိုပါသည်။ Feedback ကို ဆက်သိမ်းထားပါသည်။',
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: page > 0 && !busy
                  ? () {
                      page--;
                      load();
                    }
                  : null,
              child: Text(bt('Previous', 'ရှေ့စာမျက်နှာ')),
            ),
            Text('${page + 1}'),
            TextButton(
              onPressed: rows.length == 30 && !busy
                  ? () {
                      page++;
                      load();
                    }
                  : null,
              child: Text(bt('Next', 'နောက်စာမျက်နှာ')),
            ),
          ],
        ),
      ],
    ),
  );
}
