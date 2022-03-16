import 'dart:math';

import 'package:ensemble/layout/box_layout.dart';
import 'package:ensemble/layout/templated.dart';
import 'package:ensemble/page_model.dart';
import 'package:ensemble/screen_controller.dart';
import 'package:ensemble/util/layout_utils.dart';
import 'package:ensemble/util/utils.dart';
import 'package:ensemble/widget/widget_builder.dart' as ensemble;
import 'package:ensemble/widget/widget_registry.dart';
import 'package:flutter/material.dart';

class ColumnBuilder extends BoxLayout {
  static const type = 'Column';
  ColumnBuilder({
    mainAxis,
    crossAxis,
    width,
    height,
    margin,
    padding,
    gap,

    backgroundColor,
    borderColor,
    borderRadius,
    fontFamily,
    fontSize,

    shadowColor,
    shadowOffset,
    shadowBlur,

    expanded,
    autoFit,

    scrollable,
    onTap,


  }) : super(
    mainAxis: mainAxis,
    crossAxis: crossAxis,
    width: width,
    height: height,
    margin: margin,
    padding: padding,
    gap: gap,

    backgroundColor: backgroundColor,
    borderColor: borderColor,
    borderRadius: borderRadius,
    fontFamily: fontFamily,
    fontSize: fontSize,

    shadowColor: shadowColor,
    shadowOffset: shadowOffset,
    shadowBlur: shadowBlur,

    scrollable: scrollable,
    onTap: onTap,
    expanded: expanded,
    autoFit: autoFit,
  );


  static ColumnBuilder fromDynamic(Map<String, dynamic> props, Map<String, dynamic> styles, {WidgetRegistry? registry})
  {
    return ColumnBuilder(
        // props
        onTap: props['onTap'],

        // styles
        scrollable: styles['scrollable'] is bool ? styles['scrollable'] : false,
        expanded: styles['expanded'] is bool ? styles['expanded'] : false,
        autoFit: styles['autoFit'] is bool ? styles['autoFit'] : false,
        mainAxis: styles['mainAxis'],
        crossAxis: styles['crossAxis'],
        width: styles['width'] is int ? styles['width'] : null,
        height: styles['height'] is int ? styles['height'] : null,
        margin: styles['margin'] is int ? styles['margin'] : null,
        padding: styles['padding'] is int ? styles['padding'] : null,
        gap: styles['gap'] is int ? styles['gap'] : null,

        backgroundColor: styles['backgroundColor'] is int ? styles['backgroundColor'] : null,
        borderColor: styles['borderColor'] is int ? styles['borderColor'] : null,
        borderRadius: styles['borderRadius'] is int ? styles['borderRadius'] : null,
        fontFamily: styles['fontFamily'],
        fontSize: styles['fontSize'] is int ? styles['fontSize'] : null,

        //shadowColor: shadowColor,
        //shadowOffset: shadowOffset,
        //shadowBlur: shadowBlur,

    );
  }


  @override
  Widget buildWidget({
    required BuildContext context,
    List<Widget>? children,
    ItemTemplate? itemTemplate}) {
    return EnsembleColumn(builder: this, children: children, itemTemplate: itemTemplate);
  }

}

class EnsembleColumn extends StatefulWidget {
  const EnsembleColumn({
    required this.builder,
    this.children,
    this.itemTemplate,
    Key? key
  }) : super(key: key);

  final ColumnBuilder builder;
  final List<Widget>? children;
  final ItemTemplate? itemTemplate;

  @override
  State<StatefulWidget> createState() => ColumnState();
}

class ColumnState extends State<EnsembleColumn> {
  // data exclusively for item template (e.g api result)
  Map<String, dynamic>? itemTemplateData;

  @override
  void initState() {
    super.initState();

    // register listener for item template's data changes.
    // Only work with API for now e.g. data: ${apiName.*}
    if (widget.itemTemplate != null) {
      String dataVar = widget.itemTemplate!.data.substring(2, widget.itemTemplate!.data.length-1);
      String apiName = dataVar.split('.').first;

      ScreenController().registerDataListener(context, apiName, (Map<String, dynamic> data) {
        itemTemplateData = data;
        setState(() {

        });
      });
    }


  }

  @override
  void dispose() {
    super.dispose();
    itemTemplateData = null;
  }




  @override
  Widget build(BuildContext context) {

    List<Widget> children = widget.children ?? [];

    // itemTemplate widgets will be rendered after our children
    if (widget.itemTemplate != null) {
      List? rendererItems;
      // if our itemTemplate's dataList has already been resolved
      if (widget.itemTemplate!.localizedDataList != null && widget.itemTemplate!.localizedDataList!.isNotEmpty) {
        rendererItems = widget.itemTemplate!.localizedDataList;
      }
      // else attempt to resolve via itemTemplate and itemTemplateData, which is updated by API response
      else if (itemTemplateData != null) {
        // Example format:
        // data: $(apiName.*)
        // name: item

        // hack for now, reconstructing the dataPath
        String dataNode = widget.itemTemplate!.data;
        List<String> dataTokens = dataNode
            .substring(2, dataNode.length - 1)
            .split(".");
        // we need to have at least 2+ tokens e.g apiName.key1
        if (dataTokens.length >= 2) {
          // exclude the apiName and reconstruct the variable
          dynamic dataList = Utils.evalVariable(dataTokens.sublist(1).join('.'), itemTemplateData);
          if (dataList is List) {
            rendererItems = dataList;
          }
        }
      }


      // now loop through each and render the content
      if (rendererItems != null) {
        for (Map<String, dynamic> dataMap in rendererItems) {
          // our dataMap needs to have a prefix using item-template's name
          Map<String, dynamic> updatedDataMap = {widget.itemTemplate!.name: dataMap};

          // Unfortunately we need to get the SubView as we are building the template.
          // TODO: refactor this. Widget shouldn't need to know about this
          WidgetModel model = PageModel.buildModel(
              widget.itemTemplate!.template,
              updatedDataMap,
              ScreenController().getSubViewDefinitionsFromRootView(context));
          Widget templatedWidget = ScreenController().buildWidget(context, model);

          // wraps each templated widget under Templated so we can
          // constraint the data scope
          children.add(Templated(localDataMap: updatedDataMap, child: templatedWidget));
        }
      }


    }


    MainAxisAlignment mainAxis = widget.builder.mainAxis != null ?
    LayoutUtils.getMainAxisAlignment(widget.builder.mainAxis!) :
    MainAxisAlignment.start;


    CrossAxisAlignment crossAxis = widget.builder.crossAxis != null ?
    LayoutUtils.getCrossAxisAlignment(widget.builder.crossAxis!) :
    CrossAxisAlignment.start;

    // if gap is specified, insert SizeBox between children
    if (widget.builder.gap != null) {
      List<Widget> updatedChildren = [];
      for (var i=0; i<children.length; i++) {
        updatedChildren.add(children[i]);
        if (i != children.length-1) {
          updatedChildren.add(SizedBox(height: widget.builder.gap!.toDouble()));
        }
      }
      children = updatedChildren;
    }

    Widget column = DefaultTextStyle.merge(
      style: TextStyle(
          fontFamily: widget.builder.fontFamily,
          fontSize: widget.builder.fontSize != null ? widget.builder.fontSize!.toDouble() : null
      ), child: Column(
        mainAxisAlignment: mainAxis,
        crossAxisAlignment: crossAxis,
        children: children)
    );

    Widget rtn = Container(
      width: widget.builder.width != null ? widget.builder.width!.toDouble() : null,
      height: widget.builder.height != null ? widget.builder.height!.toDouble() : null,
      margin: EdgeInsets.all((widget.builder.margin ?? 0).toDouble()),
      decoration: BoxDecoration(
        border: widget.builder.borderColor != null ? Border.all(color: Color(widget.builder.borderColor!)) : null,
        borderRadius: widget.builder.borderRadius != null ? BorderRadius.all(Radius.circular(widget.builder.borderRadius!.toDouble())) : null,
        color: widget.builder.backgroundColor != null ? Color(widget.builder.backgroundColor!) : null
      ),
      child: InkWell(
        splashColor: Colors.transparent,
        onTap: widget.builder.onTap == null ? null : () =>
            ScreenController().executeAction(context, widget.builder.onTap),
        child: Padding(
            padding: EdgeInsets.all((widget.builder.padding ?? 0).toDouble()),
            child: widget.builder.autoFit ? IntrinsicWidth(child: column) : column
        )
      )
    );

    Widget rtnWrapper = widget.builder.scrollable ?
        SingleChildScrollView(child: rtn) :
        rtn;

    if (widget.builder.expanded) {
      // TODO: need to check, as only valid within a HStack/VStack/Flex otherwise exception
      return Expanded(child: rtnWrapper);
    }
    return rtnWrapper;
  }



}