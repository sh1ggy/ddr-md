/// Name: SettingCard
/// Parent: SettingsPage
/// Description: Settings card field for re-use in settings_page where
/// [setValue] is a value initialised with shared_preferences and [textValue]
/// is the actual new value that it's being set to after the form is saved.
/// [field] is the text title and [maxLength] is the form validation.
library;

import 'package:ddr_md/helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SettingCard<T> extends StatefulWidget {
  final Future<void> Function(String) setValue;
  final T chosenValue;
  final String field;
  final int maxLength;

  const SettingCard({
    super.key,
    required this.setValue,
    required this.chosenValue,
    required this.field,
    required this.maxLength,
  });



  @override
  State<SettingCard> createState() => _SettingCardState();
}

class _SettingCardState<T> extends State<SettingCard> {
  String textValue = "";
  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(widget.field),
        trailing: SizedBox(
          width: MediaQuery.of(context).size.width * 0.4,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: TextField(
                  maxLength: widget.maxLength,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  onChanged: (value) => {
                    if (value != "") {setState(() {
                      textValue = value;
                    })}
                  },
                  decoration: InputDecoration(
                    counterText: "",
                    border: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    hintText: widget.chosenValue.toString(),
                  ),
                ),
              ),
              IconButton(
                  icon: const Icon(
                    Icons.save,
                  ),
                  tooltip: "Save ${widget.field}",
                  onPressed: () {
                    if (textValue == "") {
                      showToast(context, "Invalid ${widget.field}");
                      return;
                    }
                    widget.setValue(textValue);
                    showToast(context, "Saved ${widget.field} to $textValue");
                  }),
            ],
          ),
        ),
      ),
    );
  }
}
