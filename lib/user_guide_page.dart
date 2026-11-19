import 'desktop_ui.dart';

import 'package:flutter/material.dart';

import 'app_language.dart';
import 'user_guide_data.dart';

String _section(String key, bool my) => my
    ? const {
            'general': 'စတင်အသုံးပြုခြင်း',
            'sale': 'အရောင်း',
            'inventory': 'အဝယ်နှင့် ပစ္စည်းလက်ကျန်',
            'expense': 'အသုံးစရိတ်',
            'ledger': 'စာရင်းချုပ်',
            'account': 'အကောင့်၊ သက်တမ်းနှင့် Backup',
          }[key] ??
          key
    : const {
            'general': 'Getting started',
            'sale': 'Sale',
            'inventory': 'Inventory',
            'expense': 'Expense',
            'ledger': 'Ledger',
            'account': 'Account, Subscription & Backup',
          }[key] ??
          key;

class UserGuidePage extends StatefulWidget {
  const UserGuidePage({super.key});
  @override
  State<UserGuidePage> createState() => _UserGuidePageState();
}

class _UserGuidePageState extends State<UserGuidePage> {
  String search = '';
  bool my = AppLanguage.current.value == 'my';
  @override
  Widget build(BuildContext context) {
    final query = search.trim().toLowerCase();
    final results = userGuideTopics
        .where(
          (g) =>
              '${g.en} ${g.my} ${g.stepsEn.join(' ')} ${g.stepsMy.join(' ')} ${g.noteEn} ${g.noteMy}'
                  .toLowerCase()
                  .contains(query),
        )
        .toList();
    return DesktopScaffold(
      appBar: AppBar(title: Text(my ? 'အသုံးပြုနည်းလမ်းညွှန်' : 'User Guide')),
      body: DesktopListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            my
                ? 'အပိုင်းရွေးပြီး ဖတ်လိုသော သင်ခန်းစာကို တစ်ခုချင်း ဝင်ကြည့်နိုင်ပါသည်။ Internet မလိုပါ။'
                : 'Choose a section, then open a topic to read its steps. All guides work offline.',
          ),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('English'),
                selected: !my,
                onSelected: (_) => setState(() => my = false),
              ),
              ChoiceChip(
                label: const Text('မြန်မာ'),
                selected: my,
                onSelected: (_) => setState(() => my = true),
              ),
            ],
          ),
          TextField(
            onChanged: (v) => setState(() => search = v),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              labelText: my ? 'သင်ခန်းစာရှာရန်' : 'Search guides',
            ),
          ),
          const SizedBox(height: 16),
          if (query.isEmpty)
            for (final section in [
              'general',
              'sale',
              'inventory',
              'expense',
              'ledger',
              'account',
            ])
              Card(
                child: DesktopListTile(
                  leading: const Icon(Icons.menu_book_outlined),
                  title: Text(_section(section, my)),
                  subtitle: Text(
                    my
                        ? 'သင်ခန်းစာ ${userGuideTopics.where((g) => g.section == section).length} ခု'
                        : '${userGuideTopics.where((g) => g.section == section).length} topics',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          _GuideSectionPage(section: section, my: my),
                    ),
                  ),
                ),
              ),
          if (query.isNotEmpty) ...[
            for (final guide in results) _topicTile(context, guide, my),
            if (results.isEmpty)
              Text(my ? 'ကိုက်ညီသော သင်ခန်းစာမရှိပါ။' : 'No matching guides.'),
          ],
        ],
      ),
    );
  }
}

class _GuideSectionPage extends StatelessWidget {
  const _GuideSectionPage({required this.section, required this.my});
  final String section;
  final bool my;
  @override
  Widget build(BuildContext context) {
    return DesktopScaffold(
      appBar: AppBar(title: Text(_section(section, my))),
      body: DesktopListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final g in userGuideTopics.where((g) => g.section == section))
            _topicTile(context, g, my),
        ],
      ),
    );
  }
}

Widget _topicTile(BuildContext context, GuideTopic g, bool my) => Card(
  child: DesktopListTile(
    title: Text(my ? g.my : g.en),
    subtitle: Text(_section(g.section, my)),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _GuideTopicPage(topic: g, my: my),
      ),
    ),
  ),
);

class _GuideTopicPage extends StatelessWidget {
  const _GuideTopicPage({required this.topic, required this.my});
  final GuideTopic topic;
  final bool my;
  @override
  Widget build(BuildContext context) {
    final steps = my ? topic.stepsMy : topic.stepsEn;
    final note = my ? topic.noteMy : topic.noteEn;
    return DesktopScaffold(
      appBar: AppBar(title: Text(my ? topic.my : topic.en)),
      body: DesktopListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            _section(topic.section, my),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: SelectableText(
                '${i + 1}. ${steps[i]}',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          if (note.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(note),
            ),
        ],
      ),
    );
  }
}
