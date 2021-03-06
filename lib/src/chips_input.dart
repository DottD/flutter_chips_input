import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chips_input/src/suggestions_box_controller.dart';

typedef ChipsInputSuggestions<T> = FutureOr<List<T>> Function(String query);
typedef ChipSelected<T> = void Function(T data, bool selected);
typedef ChipsBuilder<T> = Widget Function(
    BuildContext context, ChipsInputState<T> state, T data);

class ChipsInput<T> extends StatefulWidget {
  ChipsInput({
    Key key,
    this.initialValue = const [],
    this.decoration = const InputDecoration(),
    this.enabled = true,
    @required this.chipBuilder,
    @required this.suggestionBuilder,
    @required this.findSuggestions,
    @required this.onChanged,
    this.onChipTapped,
    this.maxChips,
    this.textStyle,
    this.suggestionsBoxMaxHeight,
    this.inputType = TextInputType.text,
    this.textOverflow = TextOverflow.clip,
    this.obscureText = false,
    this.autocorrect = true,
    this.actionLabel,
    this.inputAction = TextInputAction.done,
    this.keyboardAppearance = Brightness.light,
    this.textCapitalization = TextCapitalization.none,
  })  : assert(maxChips == null || initialValue.length <= maxChips),
        super(key: key);

  final InputDecoration decoration;
  final TextStyle textStyle;
  final bool enabled;
  final ChipsInputSuggestions findSuggestions;
  final ValueChanged<List<T>> onChanged;
  @Deprecated("Will be removed in the next major version")
  final ValueChanged<T> onChipTapped;
  final ChipsBuilder<T> chipBuilder;
  final ChipsBuilder<T> suggestionBuilder;
  final List<T> initialValue;
  final int maxChips;
  final double suggestionsBoxMaxHeight;
  final TextInputType inputType;
  final TextOverflow textOverflow;
  final bool obscureText;
  final bool autocorrect;
  final String actionLabel;
  final TextInputAction inputAction;
  final Brightness keyboardAppearance;

  // final Color cursorColor;

  final TextCapitalization textCapitalization;

  @override
  ChipsInputState<T> createState() => ChipsInputState<T>(textOverflow);
}

class ChipsInputState<T> extends State<ChipsInput<T>>
    implements TextInputClient {
  static const kObjectReplacementChar = 0xFFFC;
  Set<T> _chips = Set<T>();
  List<T> _suggestions;
  StreamController<List<T>> _suggestionsStreamController;
  int _searchId = 0;
  double _suggestionBoxHeight;
  FocusNode _focusNode;
  TextEditingValue _value = TextEditingValue();
  TextInputConnection _connection;
  SuggestionsBoxController _suggestionsBoxController;
  LayerLink _layerLink = LayerLink();
  Size size;
  TextOverflow textOverflow;
  bool _previousEnabled;
  ScrollController _suggestionScrollController;

  ChipsInputState(TextOverflow textOverflow) {
    this.textOverflow = textOverflow;
  }

  String get text => String.fromCharCodes(
        _value.text.codeUnits.where((ch) => ch != kObjectReplacementChar),
      );

  bool get _hasInputConnection => _connection != null && _connection.attached;

  @override
  AutofillScope get currentAutofillScope => null;

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {
    //TODO
  }

  @override
  void initState() {
    super.initState();
    _chips.addAll(widget.initialValue);
    _updateTextInputState();
    this._suggestionsBoxController = SuggestionsBoxController(context);
    this._suggestionsStreamController = StreamController<List<T>>.broadcast();
    this._suggestionScrollController = ScrollController();
    _initFocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _initOverlayEntry();
    });
    this._previousEnabled = widget.enabled;
  }

  _initFocusNode() {
    if (widget.enabled &&
        (widget.maxChips == null || _chips.length < widget.maxChips)) {
      // this._suggestionsBoxController.close();
      if (_focusNode == null ||
          _focusNode.runtimeType == AlwaysDisabledFocusNode) {
        this._focusNode = FocusNode();
        this._focusNode.addListener(_onFocusChanged);
      }
      this._focusNode.requestFocus();
    } else {
      if (_focusNode.runtimeType != AlwaysDisabledFocusNode)
        this._focusNode = AlwaysDisabledFocusNode();
    }
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      _openInputConnection();
      this._suggestionsBoxController.open();
    } else {
      _closeInputConnectionIfNeeded(true);
      this._suggestionsBoxController.close();
    }
    setState(() {
      /*rebuild so that _TextCursor is hidden.*/
    });
  }

  _recalculateSuggestionsBoxHeight() {
    setState(() {
      _suggestionBoxHeight = MediaQuery.of(context).size.height -
          MediaQuery.of(context).viewInsets.bottom;
    });
  }

  RenderBox _getRenderBox() {
    return context.findRenderObject();
  }

  void _initOverlayEntry() {
    // this._suggestionsBoxController.close();
    this._suggestionsBoxController.overlayEntry = OverlayEntry(
      builder: (context) {
        RenderBox renderBox = _getRenderBox();
        var size = renderBox.size;
        var offset = renderBox.localToGlobal(Offset.zero);
        var top = offset.dy + size.height + 5.0;

        return Positioned(
          left: offset.dx,
          top: top,
          width: size.width,
          child: StreamBuilder(
            stream: _suggestionsStreamController.stream,
            builder: (
              BuildContext context,
              AsyncSnapshot<List<dynamic>> snapshot,
            ) {
              if (snapshot.hasData && snapshot.data?.length != 0) {
                return CompositedTransformFollower(
                  link: this._layerLink,
                  showWhenUnlinked: false,
                  offset: Offset(0.0, size.height + 5.0),
                  child: Material(
                    elevation: 4.0,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: widget.suggestionsBoxMaxHeight ??
                            (_suggestionBoxHeight - top > 0
                                ? _suggestionBoxHeight - top
                                : 400),
                      ),
                      child: Scrollbar(
                        isAlwaysShown: true,
                        controller: _suggestionScrollController,
                        child: ListView.builder(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          controller: _suggestionScrollController,
                          itemCount: snapshot.data?.length ?? 0,
                          itemBuilder: (BuildContext context, int index) {
                            return widget.suggestionBuilder(
                              context,
                              this,
                              _suggestions[index],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                );
              }
              return Container();
            },
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _focusNode?.dispose();
    _closeInputConnectionIfNeeded(false);
    _suggestionsStreamController.close();
    _suggestionsBoxController.close();
    _suggestionScrollController.dispose();
    super.dispose();
  }

  void requestKeyboard() {
    if (_focusNode.hasFocus) {
      _openInputConnection();
    } else {
      FocusScope.of(context).requestFocus(_focusNode);
    }
    _recalculateSuggestionsBoxHeight();
  }

  void selectSuggestion(T data) {
    setState(() {
      if (widget.maxChips == null || widget.maxChips > _chips.length) {
        _chips.add(data);
        _initFocusNode();
        _updateTextInputState();
        _suggestions = null;
        _suggestionsStreamController.add(_suggestions);
        if (widget.maxChips == _chips.length) _suggestionsBoxController.close();
      } else
        _suggestionsBoxController.close();
    });
    widget.onChanged(_chips.toList(growable: false));
  }

  void deleteChip(T data) {
    if (widget.enabled) {
      setState(() {
        _chips.remove(data);
        _updateTextInputState();
      });
      _initFocusNode();
      widget.onChanged(_chips.toList(growable: false));
    }
  }

  void updateChip(T oldData, T data) {
    if (widget.enabled) {
      setState(() {
        _chips.remove(oldData);
        _chips.add(data);
        _updateTextInputState();
      });
      _initFocusNode();
      widget.onChanged(_chips.toList(growable: false));
    }
  }

  void _openInputConnection() {
    if (!_hasInputConnection) {
      _connection = TextInput.attach(
          this,
          TextInputConfiguration(
            inputType: widget.inputType,
            obscureText: widget.obscureText,
            autocorrect: widget.autocorrect,
            actionLabel: widget.actionLabel,
            inputAction: widget.inputAction,
            keyboardAppearance: widget.keyboardAppearance,
            textCapitalization: widget.textCapitalization,
          ));
      _connection.setEditingState(_value);
    }
    _connection.show();
    _recalculateSuggestionsBoxHeight();

    Future.delayed(Duration(milliseconds: 100), () {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        RenderBox renderBox = context.findRenderObject();
        Scrollable.of(context)?.position?.ensureVisible(renderBox);
      });
    });
  }

  void _closeInputConnectionIfNeeded(bool recalculate) {
    if (_hasInputConnection) {
      _connection.close();
      _connection = null;
    }
    if (recalculate) _recalculateSuggestionsBoxHeight();
  }

  @override
  Widget build(BuildContext context) {
    if (this._previousEnabled != widget.enabled) {
      this._initFocusNode();
      this._previousEnabled = widget.enabled;
    }

    var chipsChildren = _chips
        .map<Widget>((data) => widget.chipBuilder(context, this, data))
        .toList();

    final theme = Theme.of(context);

    chipsChildren.add(
      Container(
        height: 32.0,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Flexible(
              flex: 1,
              child: Text(
                text,
                maxLines: 1,
                overflow: this.textOverflow,
                style: widget.textStyle ??
                    theme.textTheme.subhead.copyWith(height: 1.5),
              ),
            ),
            Flexible(
              flex: 0,
              child: _TextCaret(
                resumed: _focusNode.hasFocus,
              ),
            ),
          ],
        ),
      ),
    );

    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (SizeChangedLayoutNotification val) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          _suggestionsBoxController.overlayEntry.markNeedsBuild();
        });
        return true;
      },
      child: SizeChangedLayoutNotifier(
        child: CompositedTransformTarget(
          link: this._layerLink,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: requestKeyboard,
            child: InputDecorator(
              decoration: widget.decoration,
              isFocused: _focusNode.hasFocus,
              isEmpty: _value.text.length == 0 && _chips.length == 0,
              child: Wrap(
                children: chipsChildren,
                spacing: 4.0,
                runSpacing: 4.0,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void updateEditingValue(TextEditingValue value) {
    final oldCount = _countReplacements(_value);
    final newCount = _countReplacements(value);
    setState(() {
      if (newCount < oldCount) {
        _chips = Set.from(_chips.take(newCount));
        widget.onChanged(_chips.toList(growable: false));
      }
      _value = value;
    });
    _onSearchChanged(text);
  }

  int _countReplacements(TextEditingValue value) {
    return value.text.codeUnits
        .where((ch) => ch == kObjectReplacementChar)
        .length;
  }

  @override
  void performAction(TextInputAction action) {
    _focusNode.unfocus();
  }

  void _updateTextInputState() {
    final text =
        String.fromCharCodes(_chips.map((_) => kObjectReplacementChar));
    _value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
      //composing: TextRange(start: 0, end: text.length),
    );
    if (_connection == null) {
      _connection = TextInput.attach(
          this,
          TextInputConfiguration(
            inputType: widget.inputType,
            obscureText: widget.obscureText,
            autocorrect: widget.autocorrect,
            actionLabel: widget.actionLabel,
            inputAction: widget.inputAction,
            keyboardAppearance: widget.keyboardAppearance,
            textCapitalization: widget.textCapitalization,
          ));
    }
    if (_connection.attached) _connection.setEditingState(_value);
  }

  void _onSearchChanged(String value) async {
    final localId = ++_searchId;
    final results = await widget.findSuggestions(value);
    if (_searchId == localId && mounted) {
      setState(() => _suggestions = results
          .where((profile) => !_chips.contains(profile))
          .toList(growable: false));
    }
    _suggestionsStreamController.add(_suggestions);
  }

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {
    print(point);
  }

  @override
  void connectionClosed() {
    print('TextInputClient.connectionCLosed()');
  }

  @override
  TextEditingValue get currentTextEditingValue => _value;

  @override
  void showAutocorrectionPromptRect(int start, int end) {}
}

class AlwaysDisabledFocusNode extends FocusNode {
  @override
  bool get hasFocus => false;
}

class _TextCaret extends StatefulWidget {
  const _TextCaret({
    Key key,
    this.duration = const Duration(milliseconds: 500),
    this.resumed = false,
  }) : super(key: key);

  final Duration duration;
  final bool resumed;

  @override
  _TextCursorState createState() => _TextCursorState();
}

class _TextCursorState extends State<_TextCaret>
    with SingleTickerProviderStateMixin {
  bool _displayed = false;
  Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.duration, _onTimer);
  }

  void _onTimer(Timer timer) {
    setState(() => _displayed = !_displayed);
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FractionallySizedBox(
      heightFactor: 0.7,
      child: Opacity(
        opacity: _displayed && widget.resumed ? 1.0 : 0.0,
        child: Container(
          width: 2.0,
          color: theme.cursorColor,
        ),
      ),
    );
  }
}
