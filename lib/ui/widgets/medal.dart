import 'package:flutter/material.dart';

import '../theme.dart';

/// Gold, silver or bronze medal with a distance label, e.g. "2K", for the
/// runs with the three fastest times ever over that distance.
class Medal extends StatelessWidget {
  const Medal({
    super.key,
    required this.km,
    required this.rank,
    this.size = 28,
  });

  final int km;

  /// 0 gold, 1 silver, 2 bronze.
  final int rank;
  final double size;

  static const _palettes = [
    // (highlight, base, shade, rim, text)
    (
      Color(0xFFFFF1A6),
      Color(0xFFF5C518),
      Color(0xFFC8920A),
      Color(0xFF9A6E00),
      Color(0xFF3D2B00),
    ),
    (
      Color(0xFFFFFFFF),
      Color(0xFFCDD3DA),
      Color(0xFF8E98A3),
      Color(0xFF6B7580),
      Color(0xFF2B3138),
    ),
    (
      Color(0xFFFFD2A8),
      Color(0xFFD9894A),
      Color(0xFF9C5621),
      Color(0xFF7A3F12),
      Color(0xFF3A1D06),
    ),
  ];

  /// Darker tone of each medal, readable as text on a light background.
  static const labelColors = [
    Color(0xFF9A6E00),
    Color(0xFF6B7580),
    Color(0xFF9C5621),
  ];

  static const _names = ['Fastest', '2nd fastest', '3rd fastest'];

  @override
  Widget build(BuildContext context) {
    final (highlight, base, shade, rim, text) = _palettes[rank];
    return Tooltip(
      message: '${_names[rank]} $km km ever',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [highlight, base, shade],
            stops: const [0, 0.45, 1],
          ),
          border: Border.all(color: rim, width: size * 0.06),
          boxShadow: const [
            BoxShadow(
              blurRadius: 4,
              color: Color(0x40000000),
              offset: Offset(0, 1),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text('${km}K', style: numberStyle(size * 0.42, color: text)),
      ),
    );
  }
}
