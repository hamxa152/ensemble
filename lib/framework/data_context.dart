import 'dart:convert';
import 'dart:developer';
import 'package:ensemble/framework/app_config.dart';
import 'package:ensemble/framework/device.dart';
import 'package:ensemble/framework/error_handling.dart';
import 'package:ensemble/page_model.dart';
import 'package:ensemble/util/extensions.dart';
import 'package:ensemble_ts_interpreter/invokables/invokablecontroller.dart';
import 'package:get_storage/get_storage.dart';
import 'package:jsparser/jsparser.dart';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:ensemble/ensemble.dart';
import 'package:ensemble/framework/action.dart';
import 'package:ensemble/screen_controller.dart';
import 'package:ensemble/util/http_utils.dart';
import 'package:ensemble/util/utils.dart';
import 'package:ensemble_ts_interpreter/invokables/invokableprimitives.dart';
import 'package:ensemble_ts_interpreter/parser/newjs_interpreter.dart';
import 'package:flutter/cupertino.dart';
import 'package:ensemble_ts_interpreter/invokables/invokable.dart';
import 'package:ensemble_ts_interpreter/parser/ast.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:yaml/yaml.dart';

/// manages Data and Invokables within the current data scope.
/// This class can evaluate expressions based on the data scope
class DataContext {
  final Map<String, dynamic> _contextMap = {};
  final BuildContext buildContext;

  DataContext({required this.buildContext, Map<String, dynamic>? initialMap}) {
    if (initialMap != null) {
      _contextMap.addAll(initialMap);
    }
    _contextMap['app'] = AppConfig();
    _contextMap['ensemble'] = NativeInvokable(buildContext);
    // device is a common name. If user already uses that, don't override it
    if (_contextMap['device'] == null) {
      _contextMap['device'] = Device();
    }
  }

  DataContext clone({BuildContext? newBuildContext}) {
    return DataContext(buildContext: newBuildContext ?? buildContext, initialMap: _contextMap);
  }

  /// copy over the additionalContext,
  /// skipping over duplicate keys if replaced is false
  void copy(DataContext additionalContext, {bool replaced = false}) {
    // copy all fields if replaced is true
    if (replaced) {
      _contextMap.addAll(additionalContext._contextMap);
    }
    // iterate and skip duplicate
    else {
      additionalContext._contextMap.forEach((key, value) {
        if (_contextMap[key] == null) {
          _contextMap[key] = value;
        }
      });
    }
  }


  // raw data (data map, api result), traversable with dot and bracket notations
  void addDataContext(Map<String, dynamic> data) {
    _contextMap.addAll(data);
  }
  void addDataContextById(String id, dynamic value) {
    if (value != null) {
      _contextMap[id] = value;
    }
  }
  /// invokable widget, traversable with getters, setters & methods
  /// Note that this will change a reference to the object, meaning the
  /// parent scope will not get the changes to this.
  /// Make sure the scope is finalized before creating child scope, or
  /// should we just travel up the parents and update their references??
  void addInvokableContext(String id, Invokable widget) {
    _contextMap[id] = widget;
  }

  bool hasContext(String id) {
    return _contextMap[id] != null;
  }

  /// return the data context value given the ID
  dynamic getContextById(String id) {
    return _contextMap[id];
  }


  /// evaluate single inline binding expression (getters only) e.g ${myVar.text}.
  /// Note that this expects the variable to be surrounded by ${...}
  dynamic eval(dynamic expression) {
    if (expression is YamlMap) {
      return _evalMap(expression);
    }
    if ( expression is List ) {
      return _evalList(expression);
    }
    if (expression is! String) {
      return expression;
    }

    // execute as code if expression is AST
    if (expression.startsWith("//@code")) {
      return evalCode(expression);
    }

    // if just have single standalone expression, return the actual type (e.g integer)
    RegExpMatch? simpleExpression = Utils.onlyExpression.firstMatch(expression);
    if (simpleExpression != null) {
      return evalVariable(simpleExpression.group(1)!);
    }
    // if we have multiple expressions, or mixing with text, return as String
    // greedy match anything inside a $() with letters, digits, period, square brackets.
    return expression.replaceAllMapped(Utils.containExpression,
            (match) => evalVariable("${match[1]}").toString());

    /*return replaceAllMappedAsync(
        expression,
        RegExp(r'\$\(([a-z_-\d."\(\)\[\]]+)\)', caseSensitive: false),
        (match) async => (await evalVariable("${match[1]}")).toString()
    );*/

  }
  List _evalList(List list) {
    List value = [];
    for (var i in list) {
      value.add(eval(i));
    }
    return value;
  }
  Map<String, dynamic> _evalMap(YamlMap yamlMap) {
    Map<String, dynamic> map = {};
    yamlMap.forEach((k, v) {
      dynamic value;
      if (v is YamlMap) {
        value = _evalMap(v);
      } else if (v is YamlList) {
        value = _evalList(v);
      } else {
        value = eval(v);
      }
      map[k] = value;
    });
    return map;
  }


  Future<String> replaceAllMappedAsync(String string, Pattern exp, Future<String> Function(Match match) replace) async {
    StringBuffer replaced = StringBuffer();
    int currentIndex = 0;
    for(Match match in exp.allMatches(string)) {
      String prefix = match.input.substring(currentIndex, match.start);
      currentIndex = match.end;
      replaced
        ..write(prefix)
        ..write(await replace(match));
    }
    replaced.write(string.substring(currentIndex));
    return replaced.toString();
  }

  /// evaluate Typescript code block
  dynamic evalCode(String codeBlock) {
    // code can have //@code <expression>
    // We don't use that here but we need to strip
    // that out before parsing the content as JSON
    String? codeWithoutComments = Utils.codeAfterComment.firstMatch(codeBlock)?.group(1);
    if (codeWithoutComments != null) {
      codeBlock = codeWithoutComments;
    }

    try {
      _contextMap['getStringValue'] = Utils.optionalString;
      return JSInterpreter.fromCode(codeBlock, _contextMap).evaluate();
    } catch (error) {
      /// not all JS errors are actual errors. API binding resolving to null
      /// may be considered a normal condition as binding may not resolved
      /// until later e.g myAPI.value.prettyDateTime()
      FlutterError.reportError(FlutterErrorDetails(
        exception: CodeError(error),
        library: 'Javascript',
        context: ErrorSummary('Javascript error when running code block - $codeBlock'),
      ));
      return null;
    }
  }

  /// eval single line Typescript surrounded by $(...)
  dynamic evalSingleLineCode(String codeWithNotation) {
    RegExpMatch? simpleExpression = Utils.onlyExpression.firstMatch(codeWithNotation);
    if (simpleExpression != null) {
      String code = evalVariable(simpleExpression.group(1)!);
      return evalCode(code);
    }
    return null;
  }

  dynamic evalToken(List<String> tokens, int index, dynamic data) {
    // can't go further, return data
    if (index == tokens.length) {
      return data;
    }

    if (data is Map) {
      return evalToken(tokens, index+1, data[tokens[index]]);
    } else {
        String token = tokens[index];
        if (InvokableController.getGettableProperties(data).contains(token)) {
          return evalToken(tokens, index + 1, data.getProperty(token));
        } else {
          // only support methods with 0 or 1 argument for now
          RegExpMatch? match = RegExp(
              r'''([a-zA-Z_-\d]+)\s*\(["']?([a-zA-Z_-\d:.]*)["']?\)''')
              .firstMatch(token);
          if (match != null) {
            // first group is the method name, second is the argument
            Function? method = InvokableController.getMethods(data)[match.group(1)];
            if (method != null) {
              // our match will always have 2 groups. Second group is the argument
              // which could be empty since we use ()*
              List<String> args = [];
              if (match.group(2)!.isNotEmpty) {
                args.add(match.group(2)!);
              }
              dynamic nextData = Function.apply(method, args);
              return evalToken(tokens, index + 1, nextData);
            }
          }
          // return null since we can't find any matching methods/getters on this Invokable
          return null;
        }
      }

    return data;
  }


  /// evaluate a single variable expression e.g myVariable.value.
  /// Note: use eval() if your variable are surrounded by ${...}
  dynamic evalVariable(String variable) {
    try {
      return JSInterpreter.fromCode(variable, _contextMap).evaluate() ?? '';
    } catch (error) {
      log('JS Parsing Error: $error');
    }
    return null;

    // legacy expression parsing
    /*List<String> tokens = variable.split('.');
    dynamic result = evalToken(tokens, 1, _contextMap[tokens[0]]);
    return result;*/
  }

  /// token format: result
  static dynamic _parseToken(List<String> tokens, int index, Map<String, dynamic> map) {
    if (index == tokens.length-1) {
      return map[tokens[index]];
    }
    if (map[tokens[index]] == null) {
      return null;
    }
    return _parseToken(tokens, index+1, map[tokens[index]]);
  }


}

/// built-in helpers/utils accessible to all DataContext
class NativeInvokable with Invokable {
  final BuildContext _buildContext;
  NativeInvokable(this._buildContext);

  @override
  Map<String, Function> getters() {
    return {
      'storage': () => EnsembleStorage(_buildContext),
      'formatter': () => Formatter(_buildContext),
    };
  }

  @override
  Map<String, Function> methods() {
    return {
      ActionType.navigateScreen.name: navigateToScreen,
      ActionType.navigateModalScreen.name: navigateToModalScreen,
      ActionType.showDialog.name: showDialog,
      ActionType.invokeAPI.name: invokeAPI,
      ActionType.stopTimer.name: stopTimer,
      'debug': (value) => log('Debug: $value')
    };
  }

  @override
  Map<String, Function> setters() {
    return {};
  }

  void navigateToScreen(String screenName, [dynamic inputs]) {
    Map<String, dynamic>? inputMap = Utils.getMap(inputs);
    ScreenController().navigateToScreen(
      _buildContext,
      screenName: screenName,
      pageArgs: inputMap,
      asModal: false);
  }
  void navigateToModalScreen(String screenName, [dynamic inputs]) {
    Map<String, dynamic>? inputMap = Utils.getMap(inputs);
    ScreenController().navigateToScreen(
      _buildContext,
      screenName: screenName,
      pageArgs: inputMap,
      asModal: true);
    // how do we handle onModalDismiss in Typescript?
  }
  void showDialog(dynamic content) {
    ScreenController().executeAction(_buildContext, ShowDialogAction(
        content: content)
    );
  }
  void invokeAPI(String apiName, [dynamic inputs]) {
    Map<String, dynamic>? inputMap = Utils.getMap(inputs);
    ScreenController().executeAction(_buildContext, InvokeAPIAction(
      apiName: apiName,
      inputs: inputMap
    ));
  }
  void stopTimer(String timerId) {
    ScreenController().executeAction(_buildContext, StopTimerAction(timerId));
  }

}

/// Singleton handling user storage
class EnsembleStorage with Invokable {
  static final EnsembleStorage _instance = EnsembleStorage._internal();
  EnsembleStorage._internal();
  factory EnsembleStorage(BuildContext buildContext) {
    context = buildContext;
    return _instance;
  }
  static late BuildContext context;
  final storage = GetStorage();

  @override
  void setProperty(prop, val) {
    if (prop is String) {
      if (val == null) {
        storage.remove(prop);
      } else {
        storage.write(prop, val);
      }
      // dispatch changes
      ScreenController().dispatchStorageChanges(context, prop, val);
    }
  }

  @override
  getProperty(prop) {
    return prop is String ? storage.read(prop) : null;
  }


  @override
  Map<String, Function> getters() {
    throw UnimplementedError();
  }

  @override
  Map<String, Function> methods() {
    return {
      'get': (String key) => storage.read(key),
      'set': (String key, dynamic value) => value == null ? storage.remove(key) : storage.write(key, value),
      'delete': (key) => storage.remove(key)
    };
  }

  @override
  Map<String, Function> setters() {
    throw UnimplementedError();
  }

}

class Formatter with Invokable {
  final BuildContext _buildContext;
  Formatter(this._buildContext);

  @override
  Map<String, Function> getters() {
    return {};
  }

  @override
  Map<String, Function> methods() {
    Locale? locale = Localizations.localeOf(Utils.globalAppKey.currentContext!);
    return {
      'now': () => UserDateTime(),
      'prettyDate': (input) => InvokablePrimitive.prettyDate(input),
      'prettyDateTime': (input) => InvokablePrimitive.prettyDateTime(input),
      'prettyCurrency': (input) => InvokablePrimitive.prettyCurrency(input),
      'prettyDuration': (input) => InvokablePrimitive.prettyDuration(input, locale: locale)
    };
  }

  @override
  Map<String, Function> setters() {
    return {};
  }

}

class UserDateTime with Invokable {
  DateTime? _dateTime;
  DateTime get dateTime => _dateTime ??= DateTime.now();

  @override
  Map<String, Function> getters() {
    return {};
  }

  @override
  Map<String, Function> methods() {
    return {
      'getDate': () => dateTime.toIso8601DateString(),
      'getDateTime': () => dateTime.toIso8601String(),
      'prettyDate': () => DateFormat.yMMMd().format(dateTime),
      'prettyDateTime': () => DateFormat.yMMMd().format(dateTime) + ' ' + DateFormat.jm().format(dateTime),
      'getMonth': () => dateTime.month,
      'getDay': () => dateTime.day,
      'getDayOfWeek': () => dateTime.weekday,
      'getYear': () => dateTime.year,
      'getHour': () => dateTime.hour,
      'getMinute': () => dateTime.minute,
      'getSecond': () => dateTime.second,
    };
  }

  @override
  Map<String, Function> setters() {
  return {};
  }

}

class APIResponse with Invokable {
  Response? _response;
  APIResponse({Response? response}) {
    if (response != null) {
      setAPIResponse(response);
    }
  }

  setAPIResponse(Response response) {
    _response = response;
  }

  Response? getAPIResponse() {
    return _response;
  }

  @override
  Map<String, Function> getters() {
    return {
      'body': () => _response?.body,
      'headers': () => _response?.headers
    };
  }

  @override
  Map<String, Function> methods() {
    return {};
  }

  @override
  Map<String, Function> setters() {
    return {};
  }

}

class ModifiableAPIResponse extends APIResponse {
  ModifiableAPIResponse({required Response response}) : super (response: response);

  @override
  Map<String, Function> setters() {
    return {
      'body': (newBody) => _response!.body = HttpUtils.parseResponsePayload(newBody),
      'headers': (newHeaders) => _response!.headers = HttpUtils.parseResponsePayload(newHeaders)
    };
  }

  @override
  Map<String, Function> methods() {
    return {
      'addHeader': (key, value) {
        Map<String, dynamic> headers = (_response!.headers ?? {});
        headers[key] = value;
        _response!.headers = headers;
      }
    };
  }
}