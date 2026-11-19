part of 'transfer_vouchers_page.dart';

extension _DesktopTransferHistory on _TransferVouchersPageState {
  Widget transferDesktop() {
    final found = rows.where((v) {
      final state = v['status'] == 'void'
          ? 'void'
          : v['received_at'] == null
          ? 'pending'
          : 'received';
      final date = v['transfer_date'].toString();
      return (filterStatus == 'all' || filterStatus == state) &&
          (filterFrom == null || date.compareTo(filterFrom!) >= 0) &&
          (filterTo == null || date.compareTo(filterTo!) <= 0) &&
          ('TRV-${v['id']} ${v['source_name']} ${v['destination_name']}'
              .toLowerCase()
              .contains(filterQuery.toLowerCase()));
    }).toList();
    Future<void> chooseDate(bool from) async {
      final d = await showDatePicker(
        context: context,
        initialDate: AppDateTime.today(),
        firstDate: DateTime(1900),
        lastDate: DateTime(2200),
      );
      if (d != null && mounted) {
        updateHistory(() {
          if (from) {
            filterFrom = d.toIso8601String().substring(0, 10);
          } else {
            filterTo = d.toIso8601String().substring(0, 10);
          }
        });
      }
    }

    return DesktopScaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<int>(
                    key: ValueKey(branch),
                    initialValue: branch,
                    decoration: InputDecoration(
                      labelText: tt('Branch', 'ဆိုင်ခွဲ'),
                    ),
                    items: [
                      for (final b in branches)
                        DropdownMenuItem(
                          value: b['id'] as int,
                          child: Text(b['name'].toString()),
                        ),
                    ],
                    onChanged: busy
                        ? null
                        : (v) {
                            updateHistory(() => branch = v);
                            load();
                          },
                  ),
                ),
                SizedBox(
                  width: 300,
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Voucher / Branch',
                    ),
                    onChanged: (v) => updateHistory(() => filterQuery = v),
                  ),
                ),
                SizedBox(
                  width: 170,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(filterStatus),
                    initialValue: filterStatus,
                    items: [
                      for (final v in ['all', 'pending', 'received', 'void'])
                        DropdownMenuItem(value: v, child: Text(v)),
                    ],
                    onChanged: (v) =>
                        updateHistory(() => filterStatus = v ?? 'all'),
                  ),
                ),
                OutlinedButton(
                  onPressed: () => chooseDate(true),
                  child: Text(filterFrom ?? 'From date'),
                ),
                OutlinedButton(
                  onPressed: () => chooseDate(false),
                  child: Text(filterTo ?? 'To date'),
                ),
                TextButton(
                  onPressed: () => updateHistory(() {
                    filterFrom = null;
                    filterTo = null;
                    filterStatus = 'all';
                  }),
                  child: const Text('Clear dates/status'),
                ),
                FilledButton.icon(
                  onPressed: busy || branches.length < 2 ? null : create,
                  icon: const Icon(Icons.add, size: 17),
                  label: Text(tt('New Transfer', 'အသစ်လွှဲရန်')),
                ),
              ],
            ),
          ),
          if (busy) const LinearProgressIndicator(),
          if (error != null) SelectableText(error!),
          Expanded(
            child: DesktopGrid(
              minWidth: 1000,
              columns: const [
                'Voucher No.',
                'Date',
                'From Branch',
                'To Branch',
                'Items',
                'Total Qty',
                'Status',
                'Actions',
              ],
              rows: [
                for (final v in found)
                  [
                    Text('TRV-${v['id']}'),
                    Text(v['transfer_date'].toString()),
                    Text(v['source_name'].toString()),
                    Text(v['destination_name'].toString()),
                    Text(v['line_count'].toString()),
                    Text(v['total_qty'].toString()),
                    Text(
                      v['status'] == 'void'
                          ? 'Void'
                          : v['received_at'] == null
                          ? 'Pending receipt'
                          : 'Received',
                    ),
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Open voucher',
                          onPressed: () => detail(v),
                          icon: const Icon(Icons.open_in_new, size: 17),
                        ),
                        if (v['status'] == 'posted')
                          IconButton(
                            tooltip: 'Void (Owner)',
                            onPressed: () => voidVoucher(v),
                            icon: const Icon(Icons.undo, size: 17),
                          ),
                        if (v['status'] == 'posted' &&
                            v['received_at'] == null &&
                            v['destination_branch_id'] == branch)
                          IconButton(
                            tooltip: 'Receive all',
                            onPressed: () => receive(v),
                            icon: const Icon(
                              Icons.move_to_inbox_outlined,
                              size: 17,
                            ),
                          ),
                      ],
                    ),
                  ],
              ],
              onRowTap: (i) => detail(found[i]),
            ),
          ),
        ],
      ),
    );
  }
}
