import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../geometry/geometry.dart';

class FmThemeData extends ChangeNotifier {
  Color _strokeColor;
  double _strokeWidth;
  Color _fillColor;
  Color _hoverColor;
  Color _pressedColor;
  Color _disabledColor;
  Color _textColor;
  TextStyle _textStyle;
  double _tooltipFontSize;
  Color _ghostColor;
  double _ghostOpacity;

  FmThemeData({
    Color strokeColor = const Color(0xFFCCCCCC),
    double strokeWidth = 1.5,
    Color fillColor = const Color(0x00000000),
    Color hoverColor = const Color(0x33FFFFFF),
    Color pressedColor = const Color(0x55FFFFFF),
    Color disabledColor = const Color(0x44666666),
    Color textColor = const Color(0xFFFFFFFF),
    TextStyle textStyle = const TextStyle(
      color: Color(0xFFFFFFFF),
      fontSize: 14,
    ),
    double tooltipFontSize = 12,
    Color ghostColor = const Color(0xFF9E9E9E),
    double ghostOpacity = 0.5,
  })  : _strokeColor = strokeColor,
        _strokeWidth = strokeWidth,
        _fillColor = fillColor,
        _hoverColor = hoverColor,
        _pressedColor = pressedColor,
        _disabledColor = disabledColor,
        _textColor = textColor,
        _textStyle = textStyle,
        _tooltipFontSize = tooltipFontSize,
        _ghostColor = ghostColor,
        _ghostOpacity = ghostOpacity;

  Color get strokeColor => _strokeColor;
  set strokeColor(Color value) {
    _strokeColor = value;
    notifyListeners();
  }

  double get strokeWidth => _strokeWidth;
  set strokeWidth(double value) {
    _strokeWidth = value;
    notifyListeners();
  }

  Color get fillColor => _fillColor;
  set fillColor(Color value) {
    _fillColor = value;
    notifyListeners();
  }

  Color get hoverColor => _hoverColor;
  set hoverColor(Color value) {
    _hoverColor = value;
    notifyListeners();
  }

  Color get pressedColor => _pressedColor;
  set pressedColor(Color value) {
    _pressedColor = value;
    notifyListeners();
  }

  Color get disabledColor => _disabledColor;
  set disabledColor(Color value) {
    _disabledColor = value;
    notifyListeners();
  }

  Color get textColor => _textColor;
  set textColor(Color value) {
    _textColor = value;
    notifyListeners();
  }

  TextStyle get textStyle => _textStyle;
  set textStyle(TextStyle value) {
    _textStyle = value;
    notifyListeners();
  }

  double get tooltipFontSize => _tooltipFontSize;
  set tooltipFontSize(double value) {
    _tooltipFontSize = value;
    notifyListeners();
  }

  /// Placeholder / uncrafted mesh fill (grey ghost).
  Color get ghostColor => _ghostColor;
  set ghostColor(Color value) {
    _ghostColor = value;
    notifyListeners();
  }

  double get ghostOpacity => _ghostOpacity;
  set ghostOpacity(double value) {
    _ghostOpacity = value.clamp(0.0, 1.0);
    notifyListeners();
  }

  /// Convenience material for uncrafted / preview meshes.
  MaterialModel get ghostMaterial => MaterialModel(
        color: _ghostColor,
        opacity: _ghostOpacity,
        doubleSided: true,
      );

  static FmThemeData of(BuildContext context) {
    return context.read<FmThemeData>();
  }

  static FmThemeData watch(BuildContext context) {
    return context.watch<FmThemeData>();
  }
}
