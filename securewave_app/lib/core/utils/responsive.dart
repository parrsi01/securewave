import 'package:flutter/material.dart';

class Responsive {
  static bool isDesktop(BuildContext context) => MediaQuery.of(context).size.width >= 900;
  static bool isTablet(BuildContext context) => MediaQuery.of(context).size.width >= 700;
}
