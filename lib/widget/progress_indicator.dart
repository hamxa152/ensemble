
import 'dart:async';
import 'dart:math';
import 'dart:developer' as dev;

import 'package:ensemble/framework/action.dart';
import 'package:ensemble/framework/extensions.dart';
import 'package:ensemble/framework/widget/widget.dart';
import 'package:ensemble/screen_controller.dart';
import 'package:ensemble/util/utils.dart';
import 'package:flutter/material.dart';
import 'package:ensemble_ts_interpreter/invokables/invokable.dart';

class EnsembleProgressIndicator extends StatefulWidget with Invokable, HasController<ProgressController, ProgressState> {
  static const type = 'Progress';
  EnsembleProgressIndicator({Key? key}) : super(key: key);

  final ProgressController _controller = ProgressController();
  @override
  ProgressController get controller => _controller;

  @override
  Map<String, Function> getters() {
    return {};
  }

  @override
  Map<String, Function> setters() {
    return {
      'display': (display) => _controller.display = Display.values.from(display),
      'size': (size) => _controller.size = Utils.optionalInt(size, min: 10),
      'thickness': (thickness) => _controller.thickness = Utils.optionalInt(thickness, min: 1),
      'color': (color) => _controller.color = Utils.getColor(color),
      'backgroundColor': (color) => _controller.backgroundColor = Utils.getColor(color),
      'countdown': (seconds) => _controller.countdown = Utils.optionalInt(seconds, min: 0),
      'onCountdownComplete': (action) => _controller.onCountdownComplete = Utils.getAction(action, initiator: this)
    };
  }

  @override
  Map<String, Function> methods() {
    return {};
  }


  @override
  ProgressState createState() => ProgressState();

}

class ProgressController extends WidgetController {
  // default for linear indicator
  static const double defaultThicknessLinear = 4;

  // default for circular indicator
  static const double defaultThicknessCircular = 2;

  Display? display;
  int? size;
  int? thickness;
  Color? color;
  Color? backgroundColor;

  int? countdown;
  EnsembleAction? onCountdownComplete;
}

class ProgressState extends WidgetState<EnsembleProgressIndicator> {
  static const interval = 100;
  double _value = 0;

  bool hasCountdown() {
    return widget._controller.countdown != null && widget._controller.countdown! > 0;
  }

  @override
  void initState() {
    super.initState();

    if (hasCountdown()) {
      // status timer that waits up every 500ms and update progress
      final Timer timer = Timer.periodic(
        const Duration(milliseconds: interval),
        (timer) {
          setState(() {
            _value = min(1, timer.tick * interval / (widget._controller.countdown! * 1000));
          });
          if (_value == 1) {
            timer.cancel();
          }
        }
      );

      // main timer that stops upon countdown
      Timer(
        Duration(seconds: widget._controller.countdown!),
        () {
          timer.cancel();
          setState(() {
            _value = 1;
          });
          if (widget._controller.onCountdownComplete != null) {
            ScreenController().executeAction(context, widget._controller.onCountdownComplete!);
          }
        }
      );

    }
  }

  @override
  Widget buildWidget(BuildContext context) {

    if (widget._controller.display == Display.linear) {
      return getLinearProgressIndicator();
    }
    return getCircularProgressIndicator();

  }

  Widget getLinearProgressIndicator() {
    Widget sizedBox = SizedBox(
      width: widget._controller.size?.toDouble(),
      height: widget._controller.thickness?.toDouble() ?? ProgressController.defaultThicknessLinear,
      child: LinearProgressIndicator(
        color: widget._controller.color,
        backgroundColor: widget._controller.backgroundColor,
        value: hasCountdown() ? _value : null,
      )
    );

    /// linear progress indicator takes width from its parent,
    /// cap it so it won't throw layout error inside e.g Row
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: Utils.widgetMaxWidth),
      child: sizedBox);
  }

  Widget getCircularProgressIndicator() {
    return SizedBox(
      width: widget._controller.size?.toDouble(),
      height: widget._controller.size?.toDouble(),
      child: CircularProgressIndicator(
        strokeWidth: widget._controller.thickness?.toDouble() ?? ProgressController.defaultThicknessCircular,
        color: widget._controller.color,
        backgroundColor: widget._controller.backgroundColor,
        value: hasCountdown() ? _value : null,
      )
    ) ;


  }

}



enum Display {
  linear, circular
} 