import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../dates.dart';
import '../money.dart';
import '../strings.dart';
import '../theme/app_colors.dart';

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.validator,
    this.obscureText = false,
    this.keyboardType,
    this.hint,
    this.prefixIcon,
    this.suffixIcon,
    this.maxLines = 1,
    this.enabled = true,
    this.onChanged,
    this.autofocus = false,
    this.textInputAction,
    this.inputFormatters = const [],
  });

  final String label;
  final TextEditingController? controller;
  final String? Function(String?)? validator;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? hint;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final int maxLines;
  final bool enabled;
  final void Function(String)? onChanged;
  final bool autofocus;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter> inputFormatters;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      obscureText: obscureText,
      keyboardType: keyboardType,
      maxLines: maxLines,
      enabled: enabled,
      onChanged: onChanged,
      autofocus: autofocus,
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
      ),
    );
  }
}

class MoneyField extends StatelessWidget {
  const MoneyField({
    super.key,
    required this.label,
    required this.controller,
    this.validator,
    this.enabled = true,
    this.hint,
  });

  final String label;
  final TextEditingController controller;
  final String? Function(double?)? validator;
  final bool enabled;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      label: label,
      controller: controller,
      enabled: enabled,
      hint: hint ?? '0.00',
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      ],
      validator: (value) {
        final parsed = parseMoney(value ?? '');
        if (parsed == null) return S.required;
        return validator?.call(parsed);
      },
    );
  }
}

class AppDropdown<T> extends StatelessWidget {
  const AppDropdown({
    super.key,
    required this.label,
    required this.items,
    this.value,
    this.onChanged,
    this.validator,
    this.hint,
  });

  final String label;
  final List<DropdownMenuItem<T>> items;
  final T? value;
  final ValueChanged<T?>? onChanged;
  final String? Function(T?)? validator;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: value,
      items: items,
      onChanged: onChanged,
      validator: validator,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, hintText: hint),
    );
  }
}

/// Async, searchable single-select. `search` is called with the current query;
/// results render with loading, empty and error states.
class SearchableSelect<T> extends StatefulWidget {
  const SearchableSelect({
    super.key,
    required this.label,
    required this.search,
    required this.display,
    required this.onSelected,
    this.value,
    this.validator,
    this.hint,
    this.onAddNew,
    this.addNewLabel = '+ Add new',
  });

  final String label;
  final Future<List<T>> Function(String query) search;
  final String Function(T value) display;
  final ValueChanged<T> onSelected;
  final T? value;
  final String? Function(T?)? validator;
  final String? hint;

  /// Optional "create then select" flow. The callback is shown as the last
  /// option in the picker; a returned value is selected immediately.
  final Future<T?> Function(BuildContext context)? onAddNew;
  final String addNewLabel;

  @override
  State<SearchableSelect<T>> createState() => _SearchableSelectState<T>();
}

class _SearchableSelectState<T> extends State<SearchableSelect<T>> {
  final TextEditingController _query = TextEditingController();
  Future<List<T>>? _results;

  void _runSearch(String value) {
    if (!mounted) return;
    setState(() {
      _results = widget.search(value);
    });
  }

  @override
  void initState() {
    super.initState();
    _results = widget.search('');
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FormField<T>(
      initialValue: widget.value,
      validator: widget.validator,
      builder: (field) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InputDecorator(
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: widget.hint,
              errorText: field.errorText,
            ),
            child: InkWell(
              onTap: () => _openPicker(field),
              child: SizedBox(
                height: 24,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.value == null
                        ? (widget.hint ?? S.search)
                        : widget.display(widget.value as T),
                    style: TextStyle(
                      color: widget.value == null ? AppColors.muted : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openPicker(FormFieldState<T> field) async {
    _query.clear();
    // Fetch the first page on tap so results are already on their way even
    // when the user never types anything into the search box.
    _runSearch('');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final screen = MediaQuery.sizeOf(dialogContext);
        return Dialog(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: screen.width < 480 ? screen.width - 32 : 420,
              maxHeight: screen.height * 0.85,
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppTextField(
                    label: S.search,
                    controller: _query,
                    prefixIcon: const Icon(Icons.search),
                    autofocus: true,
                    onChanged: _runSearch,
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: FutureBuilder<List<T>>(
                      future: _results,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        if (snapshot.hasError) {
                          return const Center(child: Text(S.somethingWrong));
                        }
                        final items = snapshot.data ?? <T>[];
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: items.isEmpty
                                  ? const Center(child: Text(S.noData))
                                  : ListView.builder(
                                      shrinkWrap: true,
                                      itemCount: items.length,
                                      itemBuilder: (context, index) => ListTile(
                                        title:
                                            Text(widget.display(items[index])),
                                        onTap: () {
                                          field.didChange(items[index]);
                                          widget.onSelected(items[index]);
                                          Navigator.pop(dialogContext);
                                        },
                                      ),
                                    ),
                            ),
                            if (widget.onAddNew != null) ...[
                              const Divider(height: 1),
                              ListTile(
                                leading: const Icon(Icons.add),
                                title: Text(widget.addNewLabel),
                                onTap: () async {
                                  final created =
                                      await widget.onAddNew!(dialogContext);
                                  if (created == null) return;
                                  field.didChange(created);
                                  widget.onSelected(created);
                                  if (dialogContext.mounted) {
                                    Navigator.pop(dialogContext);
                                  }
                                },
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class DatePickerField extends StatelessWidget {
  DatePickerField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    DateTime? firstDate,
    DateTime? lastDate,
    this.emptyText = S.all,
  })  : firstDate = firstDate ?? DateTime.utc(2000),
        lastDate = lastDate ?? DateTime.utc(2100);

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final DateTime firstDate;
  final DateTime lastDate;

  /// Filters show "All" when no date is chosen; form fields override this with
  /// an explicit prompt such as "Select expiry date".
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          // A tomorrow-only firstDate is common for expiry fields; the picker
          // asserts that initialDate is not earlier than firstDate.
          initialDate: value ?? (firstDate.isAfter(now) ? firstDate : now),
          firstDate: firstDate,
          lastDate: lastDate,
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: SizedBox(
          height: 24,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              value == null ? emptyText : formatDate(value!),
              style: TextStyle(color: value == null ? AppColors.muted : null),
            ),
          ),
        ),
      ),
    );
  }
}
