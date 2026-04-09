import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'dart:convert';

import '../theme/app_theme.dart';
import '../state/app_state.dart';
import '../../data/data_loader.dart';

/// Data loading and preview screen.
class DataScreen extends ConsumerStatefulWidget {
  const DataScreen({super.key});

  @override
  ConsumerState<DataScreen> createState() => _DataScreenState();
}

class _DataScreenState extends ConsumerState<DataScreen> {
  bool _hasHeader = false;
  String _separator = 'auto';
  final Set<int> _selectedInputs = {};
  int? _selectedOutput;
  String? _fileName;
  DataLoadResult? _preview;

  @override
  Widget build(BuildContext context) {
    final loadedData = ref.watch(loadedDataProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Data Configuration'),
        actions: [
          if (loadedData != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Chip(
                avatar: const Icon(
                  LucideIcons.checkCircle,
                  size: 16,
                  color: AppColors.success,
                ),
                label: Text('${loadedData.numRows} × ${loadedData.numCols}'),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildUploadSection(),
                if (_preview != null) ...[
                  const SizedBox(height: 24),
                  _buildOptionsSection(),
                  const SizedBox(height: 24),
                  _buildVariableSelection(),
                  const SizedBox(height: 24),
                  _buildPreviewTable(),
                  const SizedBox(height: 24),
                  _buildConfirmButton(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUploadSection() {
    return _SectionCard(
      icon: LucideIcons.upload,
      title: 'Load Data File',
      child: Column(
        children: [
          InkWell(
            onTap: _pickFile,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 48),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.gray700,
                  style: BorderStyle.solid,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    _fileName != null
                        ? LucideIcons.fileCheck
                        : LucideIcons.filePlus,
                    size: 40,
                    color: _fileName != null
                        ? AppColors.success
                        : AppColors.gray500,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _fileName ?? 'Click to select CSV, TSV, or TXT file',
                    style: TextStyle(
                      color: _fileName != null
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                  if (_preview != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${_preview!.numRows} rows × ${_preview!.numCols} columns',
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionsSection() {
    return _SectionCard(
      icon: LucideIcons.settings2,
      title: 'Import Options',
      child: Row(
        children: [
          Expanded(
            child: SwitchListTile(
              title: const Text('Header row', style: TextStyle(fontSize: 14)),
              value: _hasHeader,
              onChanged: (v) {
                setState(() => _hasHeader = v);
                _reparse();
              },
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _separator,
              decoration: const InputDecoration(
                labelText: 'Separator',
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              items: const [
                DropdownMenuItem(value: 'auto', child: Text('Auto-detect')),
                DropdownMenuItem(value: ',', child: Text('Comma (,)')),
                DropdownMenuItem(value: '\t', child: Text('Tab')),
                DropdownMenuItem(value: ';', child: Text('Semicolon (;)')),
                DropdownMenuItem(value: ' ', child: Text('Space')),
              ],
              onChanged: (v) {
                setState(() => _separator = v ?? 'auto');
                _reparse();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVariableSelection() {
    if (_preview == null) return const SizedBox.shrink();

    return _SectionCard(
      icon: LucideIcons.variable,
      title: 'Variable Assignment',
      subtitle: 'Select inputs and one output',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: List.generate(_preview!.numCols, (i) {
          final isInput = _selectedInputs.contains(i);
          final isOutput = _selectedOutput == i;
          final name = _preview!.headers[i];

          Color bgColor;
          Color borderColor;
          Color textColor;
          IconData icon;

          if (isOutput) {
            bgColor = AppColors.accentSubtle;
            borderColor = AppColors.accent;
            textColor = AppColors.accent;
            icon = LucideIcons.arrowRightFromLine;
          } else if (isInput) {
            bgColor = AppColors.surfaceElevated;
            borderColor = AppColors.info;
            textColor = AppColors.info;
            icon = LucideIcons.arrowLeftToLine;
          } else {
            bgColor = AppColors.surfaceVariant;
            borderColor = AppColors.gray700;
            textColor = AppColors.textTertiary;
            icon = LucideIcons.circle;
          }

          return InkWell(
            onTap: () {
              setState(() {
                if (isOutput) {
                  _selectedOutput = null;
                } else if (isInput) {
                  _selectedInputs.remove(i);
                  _selectedOutput = i;
                } else {
                  _selectedInputs.add(i);
                }
              });
            },
            borderRadius: BorderRadius.circular(8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 14, color: textColor),
                  const SizedBox(width: 8),
                  Text(
                    name,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildPreviewTable() {
    if (_preview == null) return const SizedBox.shrink();

    final rows = _preview!.numRows.clamp(0, 10);
    return _SectionCard(
      icon: LucideIcons.table,
      title: 'Data Preview',
      subtitle: 'Showing first $rows of ${_preview!.numRows} rows',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(AppColors.surfaceVariant),
          dataRowColor: WidgetStateProperty.all(Colors.transparent),
          columnSpacing: 24,
          headingTextStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
          dataTextStyle: const TextStyle(
            fontSize: 12,
            fontFamily: 'monospace',
            color: AppColors.textPrimary,
          ),
          columns: List.generate(
            _preview!.numCols,
            (c) => DataColumn(label: Text(_preview!.headers[c])),
          ),
          rows: List.generate(rows, (r) {
            return DataRow(
              cells: List.generate(_preview!.numCols, (c) {
                return DataCell(
                  Text(_preview!.data.get(r, c).toStringAsFixed(4)),
                );
              }),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildConfirmButton() {
    final canConfirm = _selectedInputs.isNotEmpty && _selectedOutput != null;
    return ElevatedButton.icon(
      onPressed: canConfirm ? _confirmData : null,
      icon: const Icon(LucideIcons.check, size: 18),
      label: const Text('Confirm & Proceed'),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 18),
        disabledBackgroundColor: AppColors.gray750,
        disabledForegroundColor: AppColors.gray500,
      ),
    );
  }

  String? _rawContent;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'tsv', 'txt', 'dat'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;

    _rawContent = utf8.decode(bytes);
    _fileName = file.name;
    _reparse();
  }

  void _reparse() {
    if (_rawContent == null) return;
    setState(() {
      _preview = DataLoader.parse(
        _rawContent!,
        separator: _separator == 'auto' ? null : _separator,
        hasHeader: _hasHeader,
      );
      // Auto-select: all but last as inputs, last as output
      if (_selectedInputs.isEmpty &&
          _selectedOutput == null &&
          _preview != null) {
        for (var i = 0; i < _preview!.numCols - 1; i++) {
          _selectedInputs.add(i);
        }
        _selectedOutput = _preview!.numCols - 1;
      }
    });
  }

  void _confirmData() {
    if (_preview == null || _selectedOutput == null) return;
    ref.read(loadedDataProvider.notifier).state = _preview;
    ref.read(variableNamesProvider.notifier).state = _preview!.headers;
    ref.read(inputIndicesProvider.notifier).state = _selectedInputs.toList()
      ..sort();
    ref.read(outputIndexProvider.notifier).state = _selectedOutput!;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              LucideIcons.checkCircle,
              color: AppColors.success,
              size: 18,
            ),
            const SizedBox(width: 12),
            Text(
              'Data loaded: ${_preview!.numRows} samples, ${_selectedInputs.length} inputs, 1 output',
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Reusable section card ─────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;

  const _SectionCard({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: AppColors.accent),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 28),
                child: Text(
                  subtitle!,
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}
