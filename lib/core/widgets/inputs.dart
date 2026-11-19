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
  });

  final String label;
  final Future<List<T>> Function(String query) search;
  final String Function(T value) display;
  final ValueChanged<T> onSelected;
  final T? value;
  final String? Function(T?)? validator;
  final String? hint;

  @override
  State<SearchableSelect<T>> createState() => _SearchableSelectState<T>();
}

class _SearchableSelectState<T> extends State<SearchableSelect<T>> {
  final TextEditingController _query = TextEditingController();
  Future<List<T>>? _results;

  Future<void> _runSearch(String value) async {
    if (!mounted) return;
    setState(() => _results = widget.search(value));
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
    _results = widget.search('');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: SizedBox(
          width: 420,
          height: 480,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                AppTextField(
                  label: S.search,
                  controller: _query,
                  prefixIcon: const Icon(Icons.search),
                  autofocus: true,
                  onChanged: _runSearch,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: FutureBuilder<List<T>>(
                    future: _results,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return const Center(child: Text(S.somethingWrong));
                      }
                      final items = snapshot.data ?? <T>[];
                      if (items.isEmpty) {
                        return const Center(child: Text(S.noData));
                      }
                      return ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (context, index) => ListTile(
                          title: Text(widget.display(items[index])),
                          onTap: () {
                            field.didChange(items[index]);
                            widget.onSelected(items[index]);
                            Navigator.pop(dialogContext);
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
  })  : firstDate = firstDate ?? DateTime.utc(2000),
        lastDate = lastDate ?? DateTime.utc(2100);

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final DateTime firstDate;
  final DateTime lastDate;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
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
              value == null ? S.all : formatDate(value!),
              style: TextStyle(color: value == null ? AppColors.muted : null),
            ),
          ),
        ),
      ),
    );
  }
}
