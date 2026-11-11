import 'package:flutter/material.dart';

abstract final class AppDesignTokens {
  static const primary = Color(0xFF216EAA);
  static const primaryDark = Color(0xFF8FCAFF);
  static const primaryButton = Color(0xFF80C5F6);
  static const onPrimaryButton = Color(0xFF0D2C4B);
  static const lightPrimaryContainer = Color(0xFFDCEFFF);
  static const lightOnPrimaryContainer = Color(0xFF0D2C4B);
  static const darkPrimaryContainer = Color(0xFF103B59);
  static const darkOnPrimaryContainer = Color(0xFFCDE8FF);

  static const lightBackground = Color(0xFFFFFFFF);
  static const lightSidebar = Color(0xFFF7F8FA);
  static const lightInput = Color(0xFFF3F4F6);
  static const lightText = Color(0xFF202124);
  static const lightSecondaryText = Color(0xFF666B73);
  static const lightBorder = Color(0xFFE7E9EE);

  static const darkBackground = Color(0xFF171717);
  static const darkSidebar = Color(0xFF202020);
  static const darkInput = Color(0xFF2B2B2B);
  static const darkText = Color(0xFFECECEC);
  static const darkSecondaryText = Color(0xFFA8ADB7);
  static const darkBorder = Color(0xFF383838);

  static const controlRadius = 12.0;
  static const inputRadius = 16.0;
  static const panelRadius = 14.0;
  static const userMessageRadius = 20.0;
  static const composerRadius = 26.0;
  static const conversationContentMaxWidth = 800.0;

  static const pageTransition = Duration(milliseconds: 200);
  static const contentTransition = Duration(milliseconds: 180);
  static const overlayTransition = Duration(milliseconds: 260);
  static const tapTransition = Duration(milliseconds: 110);
}
