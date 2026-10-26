part of '../../button_debug_entry_card_feature.dart';

/// Shared packet inspector for live capture and locally saved sessions.
class ButtonDebugEntryCard extends StatelessWidget {
  /// Creates button debug entry card.
  const ButtonDebugEntryCard({super.key, required this.row});
  final Map<String, Object?> row;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final characteristic = '${row['characteristic'] ?? ''}';
    final bytes = buttonDebugSafePayload(
      (row['payload'] as List? ?? const []).cast<int>(),
      characteristic,
    );
    final fields = decodeButtonFields(bytes, characteristic);
    final direction = '${row['direction'] ?? 'LOCAL'}';
    final time = DateTime.tryParse('${row['timestamp']}')?.toLocal();

    /// Computes two.
    String two(int value) => value.toString().padLeft(2, '0');
    final stamp = time == null
        ? '${row['timestamp'] ?? ''}'
        : '${two(time.hour)}:${two(time.minute)}:${two(time.second)}.${time.millisecond.toString().padLeft(3, '0')}';
    final accent = direction == 'RX'
        ? AdminUi.blue(context)
        : direction == 'TX'
        ? colors.tertiary
        : AdminUi.muted(context);
    const mono = TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.5);

    /// Computes cell.
    Widget cell(Widget child) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: child,
    );

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: AdminUi.surface(context),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AdminUi.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 3, color: accent.withValues(alpha: .65)),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$direction · ${direction == 'RX'
                            ? 'Received'
                            : direction == 'TX'
                            ? 'Outgoing'
                            : 'App event'}',
                        style: TextStyle(
                          color: accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      '#${row['sequence']} · $stamp',
                      style: theme.textTheme.labelMedium,
                    ),
                    Text(
                      '${bytes.length} bytes',
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  _operationLabel('${row['operation'] ?? 'event'}'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                if ('${row['status'] ?? ''}'.isNotEmpty)
                  AdminTag(
                    label: '${row['status']}'.replaceAll('_', ' '),
                    color: accent,
                  ),
                if (characteristic.isNotEmpty ||
                    '${row['device_id'] ?? ''}'.isNotEmpty)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    shape: const Border(),
                    collapsedShape: const Border(),
                    title: Text(
                      'Connection details',
                      style: TextStyle(
                        color: AdminUi.muted(context),
                        fontSize: 12,
                      ),
                    ),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if ('${row['device_id'] ?? ''}'.isNotEmpty)
                        SelectableText(
                          'Device: ${row['device_id']}',
                          style: theme.textTheme.bodySmall,
                        ),
                      if (characteristic.isNotEmpty)
                        SelectableText(
                          'Characteristic: $characteristic',
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
              ],
            ),
          ),
          if (bytes.isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF142A2C),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'RAW HEX',
                          style: TextStyle(
                            color: Color(0xFFA9CCC6),
                            fontSize: 10,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Copy HEX',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(
                          Icons.copy_rounded,
                          size: 17,
                          color: Color(0xFFCEEBE5),
                        ),
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: buttonPayloadHex(bytes)),
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('HEX copied.')),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                  SelectableText(
                    buttonPayloadHex(bytes),
                    style: mono.copyWith(color: const Color(0xFFE5F4F0)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Decoded fields',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Tooltip(
                    triggerMode: TooltipTriggerMode.tap,
                    message:
                        'Offsets start at 0. Multi-byte numbers use big-endian order. Unknown bytes are preserved.',
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        Icons.info_outline_rounded,
                        size: 17,
                        color: AdminUi.muted(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(.85),
                1: FlexColumnWidth(1.15),
                2: FlexColumnWidth(2.2),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.top,
              border: TableBorder(
                horizontalInside: BorderSide(color: AdminUi.border(context)),
              ),
              children: [
                TableRow(
                  decoration: BoxDecoration(color: AdminUi.background(context)),
                  children: [
                    for (final heading in ['Bytes', 'HEX', 'Meaning / value'])
                      cell(
                        Text(
                          heading,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                for (var i = 0; i < fields.length; i++)
                  TableRow(
                    decoration: BoxDecoration(
                      color: i.isEven
                          ? AdminUi.surface(context)
                          : AdminUi.background(context).withValues(alpha: .5),
                    ),
                    children: [
                      cell(
                        Text(fields[i].range, style: theme.textTheme.bodySmall),
                      ),
                      cell(
                        SelectableText(
                          fields[i].hex,
                          style: mono.copyWith(color: AdminUi.blue(context)),
                        ),
                      ),
                      cell(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              fields[i].name,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            SelectableText(
                              fields[i].value,
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            ExpansionTile(
              title: Text(
                'Capture notes & decimal bytes',
                style: TextStyle(fontSize: 12, color: AdminUi.muted(context)),
              ),
              shape: const Border(),
              collapsedShape: const Border(),
              dense: true,
              childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText('DEC: ${bytes.join(' ')}', style: mono),
                const SizedBox(height: 8),
                SelectableText(
                  '${row['interpretation'] ?? ''}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ] else
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: SelectableText(
                '${row['interpretation'] ?? 'No application payload.'}',
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}
