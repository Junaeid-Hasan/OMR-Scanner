import 'package:flutter/material.dart';

class AnswerOptionPill extends StatelessWidget {
  final String label;
  final String? subLabel;
  final bool isSelected;
  final bool isCorrect;
  final bool isWrong;
  final bool isUncertain;
  final VoidCallback? onTap;

  const AnswerOptionPill({
    super.key,
    required this.label,
    this.subLabel,
    this.isSelected = false,
    this.isCorrect = false,
    this.isWrong = false,
    this.isUncertain = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color bgColor = Colors.white;
    Color textColor = const Color(0xFF334155);
    Color borderColor = const Color(0xFFCBD5E1);

    if (isCorrect) {
      bgColor = const Color(0xFF059669);
      textColor = Colors.white;
      borderColor = const Color(0xFF047857);
    } else if (isWrong) {
      bgColor = const Color(0xFFE11D48);
      textColor = Colors.white;
      borderColor = const Color(0xFFBE123C);
    } else if (isUncertain) {
      bgColor = const Color(0xFFD97706);
      textColor = Colors.white;
      borderColor = const Color(0xFFB45309);
    } else if (isSelected) {
      bgColor = Theme.of(context).primaryColor;
      textColor = Colors.white;
      borderColor = Theme.of(context).primaryColor;
    }

    final hasSub = subLabel != null && subLabel!.isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: hasSub ? 46 : 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(hasSub ? 12 : 19),
          border: Border.all(color: borderColor, width: isSelected ? 2 : 1.2),
          boxShadow: isSelected || isCorrect || isWrong || isUncertain
              ? [
                  BoxShadow(
                    color: bgColor.withValues(alpha: 0.35),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: hasSub
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        subLabel!,
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.85),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  )
                : Text(
                    label,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
