import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets.dart';

/// Intrinsically sized buttons for narrow layouts.
///
/// The shared [PrimaryButton]/[SecondaryButton] widgets force a fixed width,
/// which leaves too little room for the label once button padding is applied on
/// 360dp screens. These variants let the label size the button and ellipsise it
/// only when a parent imposes a genuinely tight constraint.
class ResponsivePrimaryButton extends StatelessWidget {
  const ResponsivePrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.icon,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final button = ElevatedButton(
      onPressed: loading ? null : onPressed,
      child: loading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            )
          : icon == null
              ? Text(label, overflow: TextOverflow.ellipsis)
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 18),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(label, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
    );
    return expand
        ? SizedBox(width: double.infinity, height: 48, child: button)
        : button;
  }
}

class ResponsiveSecondaryButton extends StatelessWidget {
  const ResponsiveSecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expand = false,
    this.color,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final button = OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: color ?? AppColors.pink600,
        side: BorderSide(color: color ?? AppColors.gold500),
      ),
      child: icon == null
          ? Text(label, overflow: TextOverflow.ellipsis)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(label, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
    );
    return expand
        ? SizedBox(width: double.infinity, height: 48, child: button)
        : button;
  }
}

/// Loading placeholder that can live inside a height-constrained page body.
class ResponsiveLoadingSkeleton extends StatelessWidget {
  const ResponsiveLoadingSkeleton({
    super.key,
    this.lines = 5,
    this.cardHeight = 64,
  });

  final int lines;
  final double cardHeight;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: LoadingSkeleton(lines: lines, cardHeight: cardHeight),
    );
  }
}

/// Wraps [DataTablePlus] so its internal fixed-width filter row never forces a
/// horizontal overflow on phones, and so its content can scroll vertically when
/// the surrounding page is height-constrained.
class ResponsiveDataTablePlus extends StatelessWidget {
  const ResponsiveDataTablePlus({
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
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final chips = filterChips ?? const <String>[];
        final inlineChips = constraints.maxWidth >= 600 || chips.isEmpty;

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!inlineChips)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final chip in chips)
                        ChoiceChip(
                          label: Text(chip),
                          selected: selectedFilter == chip,
                          onSelected: (_) => onFilterChanged?.call(
                            selectedFilter == chip ? null : chip,
                          ),
                        ),
                    ],
                  ),
                ),
              DataTablePlus(
                columns: columns,
                rows: rows,
                filterChips: inlineChips ? filterChips : null,
                selectedFilter: selectedFilter,
                onFilterChanged: onFilterChanged,
                onExportCsv: onExportCsv,
                searchHint: searchHint,
                rowsPerPage: rowsPerPage,
                exportFileName: exportFileName,
              ),
            ],
          ),
        );
      },
    );
  }
}
