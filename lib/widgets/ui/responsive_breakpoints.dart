import 'package:flutter/widgets.dart';

const double obsidianCompactListBreakpoint = 640;

bool isCompactListWidth(BuildContext context) {
  return MediaQuery.sizeOf(context).width < obsidianCompactListBreakpoint;
}
