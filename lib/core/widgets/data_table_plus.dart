import 'dart:async';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../strings.dart';
import '../theme/app_colors.dart';

class DataTablePlusRow {
  const DataTablePlusRow({required this.cells, this.actions = const []});

  final List<String> cells;
  final List<Widget> actions;
}

/// Searchable, sortable, filterable, paginated table with CSV export.
class DataTablePlus extends StatefulWidget {
  const DataTablePlus({
    super.key,
    required this.columns,
    required this.rows,
    this.filterChips,
    this.selectedFilter,
    this.onFilterChanged,
    this.onExportCsv,
    this.searchHint,
    this.rowsPerPage = 10,
    this.exportFileName = 'yusra-export.csv',
  });

  final List<String> columns;
  final List<DataTablePlusRow> rows;
  final List<String>? filterChips;
  final String? selectedFilter;
  final ValueChanged<String?>? onFilterChanged;
  final Future<void> Function(String csv)? onExportCsv;
  final String? searchHint;
  final int rowsPerPage;
  final String exportFileName;

  @override
  State<DataTablePlus> createState() => _DataTablePlusState();
}

class _DataTablePlusState extends State<DataTablePlus> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  int _sortColumn = -1;
  bool _ascending = true;
  int _page = 0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<DataTablePlusRow> get _filtered {
    final rows = widget.rows.where((row) {
      if (_query.isEmpty) return true;
      return row.cells.join(' ').toLowerCase().contains(_query.toLowerCase());
    }).toList();
    if (_sortColumn < 0 || _sortColumn >= widget.columns.length) return rows;
    rows.sort((a, b) {
      final left = a.cells[_sortColumn];
      final right = b.cells[_sortColumn];
      final comparison = left.compareTo(right);
      return _ascending ? comparison : -comparison;
    });
    return rows;
  }

  void _export() {
    final rows = <List<dynamic>>[widget.columns];
    for (final row in _filtered) {
      rows.add(row.cells);
    }
    final csv = CsvCodec().encoder.convert(rows);
    if (widget.onExportCsv != null) {
      unawaited(widget.onExportCsv!(csv));
    } else {
      unawaited(Share.share(csv, subject: widget.exportFileName));
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final pageCount =
        (filtered.length / widget.rowsPerPage).ceil().clamp(1, 1 << 30).toInt();
    if (_page >= pageCount) _page = pageCount - 1;
    final start = _page * widget.rowsPerPage;
    final pageRows = filtered.skip(start).take(widget.rowsPerPage).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 260,
              child: TextField(
                controller: _search,
                decoration: InputDecoration(
                  hintText: widget.searchHint ?? '${S.search}…',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                ),
                onChanged: (value) => setState(() {
                  _query = value;
                  _page = 0;
                }),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.filterChips != null)
                  ...widget.filterChips!.map(
                    (chip) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(chip),
                        selected: widget.selectedFilter == chip,
                        onSelected: (_) => widget.onFilterChanged
                            ?.call(widget.selectedFilter == chip ? null : chip),
                      ),
                    ),
                  ),
                IconButton(
                  tooltip: S.exportCsv,
                  onPressed: _export,
                  icon: const Icon(Icons.file_download_outlined,
                      color: AppColors.gold700),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (filtered.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text(S.noData)),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [
                for (var i = 0; i < widget.columns.length; i++)
                  DataColumn(
                    label: Text(widget.columns[i]),
                    numeric: false,
                    onSort: (_, __) => setState(() {
                      if (_sortColumn == i) {
                        _ascending = !_ascending;
                      } else {
                        _sortColumn = i;
                        _ascending = true;
                      }
                    }),
                  ),
                if (pageRows.any((row) => row.actions.isNotEmpty))
                  const DataColumn(label: Text('')),
              ],
              rows: [
                for (final row in pageRows)
                  DataRow(cells: [
                    ...row.cells.map((cell) => DataCell(Text(cell))),
                    if (row.actions.isNotEmpty)
                      DataCell(Row(
                        mainAxisSize: MainAxisSize.min,
                        children: row.actions,
                      )),
                  ]),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('${filtered.length} ${S.view.toLowerCase()}'),
            const SizedBox(width: 16),
            IconButton(
              onPressed: _page > 0 ? () => setState(() => _page--) : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Text('${_page + 1} / $pageCount'),
            IconButton(
              onPressed:
                  _page + 1 < pageCount ? () => setState(() => _page++) : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ],
    );
  }
}
