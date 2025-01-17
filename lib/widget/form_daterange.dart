import 'package:ensemble/ensemble_theme.dart';
import 'package:ensemble/framework/action.dart';
import 'package:ensemble/page_model.dart';
import 'package:ensemble/util/utils.dart';
import 'package:ensemble/widget/form_helper.dart';
import 'package:ensemble/widget/widget_registry.dart';
import 'package:ensemble_ts_interpreter/invokables/invokable.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:ensemble/util/extensions.dart';

class DateRange extends StatefulWidget with Invokable, HasController<DateRangeController, DateRangeState> {
  static const type = 'DateRange';
  DateRange({Key? key}) : super(key: key);

  // textController manages 'value', while _controller manages the rest
  final TextEditingController textController = TextEditingController();
  final DateRangeController _controller = DateRangeController();


  @override
  DateRangeController get controller => _controller;

  @override
  State<StatefulWidget> createState() => DateRangeState();

  @override
  Map<String, Function> getters() {
    return {
      'startDate': () => _controller.startDate?.toIso8601DateString(),
      'endDate': () => _controller.endDate?.toIso8601DateString(),
    };
  }

  @override
  Map<String, Function> methods() {
    return {};
  }

  @override
  Map<String, Function> setters() {
    return {
      'fontSize': (value) => _controller.fontSize = Utils.optionalInt(value),
      'onChange': (definition) => _controller.onChange = Utils.getAction(definition, initiator: this)
    };
  }


}

class DateRangeController extends FormFieldController {
  int? fontSize;
  EnsembleAction? onChange;

  DateTime? startDate;
  DateTime? endDate;
}

class DateRangeState extends FormFieldWidgetState<DateRange> {

  String? validationText;




  @override
  Widget buildWidget(BuildContext context) {
    return TextFormField(
      key: validatorKey,
      validator: (value) {
        if (widget._controller.required) {
          if (value == null || value.isEmpty) {
            return Utils.translateWithFallback('ensemble.input.required', 'This field is required');
          }
        }
        return null;
      },
      readOnly: true,
      controller: widget.textController,
      enabled: isEnabled(),
      onChanged: (String txt) {
      },
      style: widget._controller.fontSize != null ?
        TextStyle(fontSize: widget._controller.fontSize!.toDouble()) :
        null,
      cursorColor: EnsembleTheme.buildLightTheme().primaryColor,
      decoration: inputDecoration.copyWith(
        suffixIcon: IconButton(
            icon: const Icon(FontAwesomeIcons.calendarAlt),
            onPressed: () {
              _selectDate(context);
            }
        ))
    );

  }


  void _selectDate(BuildContext context) async {
    final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime.now(),
        lastDate: DateTime(2030));
    if (picked != null) {
      setState(() {
        widget._controller.startDate = picked.start;
        widget._controller.endDate = picked.end;
        setState(() {
          final df = DateFormat('MMM dd');
            widget.textController.text =
                df.format(picked.start) + " - " + df.format(picked.end);
        });
        onDateChange();
      });
    }
  }

  void onDateChange() {
    /*if (widget.widgetData['events'] != null) {
      for (int i=0; i<(widget.widgetData['events'] as List).length; i++) {
        var event = widget.widgetData['events'][i];
        if (event['event'] == 'onchange') {
          for (int j=0; j<(event['expressions'] as List).length; j++) {
            String expression = event['expressions'][i];
            setState(() {

            });
          }
        }
      }
    }*/
  }

  String formatDate(DateTime? selectedDate) {
    if (selectedDate != null) {
      return (selectedDate.month < 10 ? "0" + selectedDate.month.toString() : selectedDate.month.toString()) + "/" +
          (selectedDate.day < 10 ? "0" + selectedDate.day.toString() : selectedDate.day.toString()) + "/" +
          (selectedDate.year.toString());
    }
    return '';
  }

  void validate() {
    bool hasValidation = false;

    // required
    if (widget._controller.required) {
      if (widget.textController.text.isEmpty) {
        validationText = "This field is required";
      } else {
        validationText = null;
      }
      hasValidation = true;
    }

    if (hasValidation) {
      setState(() {});
    }
  }


}