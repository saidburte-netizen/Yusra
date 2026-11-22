import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../strings.dart';
import '../theme/app_colors.dart';

enum YusraLogoVariant { full, mark, mono }

/// Brand lockup. `mono` is the receipt-friendly single-colour variant.
class YusraLogo extends StatelessWidget {
  const YusraLogo({
    super.key,
    this.variant = YusraLogoVariant.full,
    this.size = 220,
    this.showTagline = false,
    this.onDark = false,
  });

  final YusraLogoVariant variant;
  final double size;
  final bool showTagline;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    switch (variant) {
      case YusraLogoVariant.mark:
        return SizedBox(width: size, height: size, child: _mark(mono: false));
      case YusraLogoVariant.mono:
        return _wordmark(mono: true, markSize: size * 0.34);
      case YusraLogoVariant.full:
        return _wordmark(mono: false, markSize: size * 0.34);
    }
  }

  Widget _mark({required bool mono}) {
    final Widget svg = SvgPicture.asset(
      mono ? 'assets/brand/logo-mono.svg' : 'assets/brand/logo-mark.svg',
      semanticsLabel: 'Yusra Pharmacy mark',
    );
    if (!mono) return svg;
    return ColorFiltered(
      colorFilter: const ColorFilter.mode(AppColors.ink, BlendMode.srcIn),
      child: SvgPicture.asset(
        'assets/brand/logo-mark.svg',
        semanticsLabel: 'Yusra Pharmacy mark',
      ),
    );
  }

  Widget _wordmark({required bool mono, required double markSize}) {
    final brandColor = mono
        ? AppColors.ink
        : onDark
            ? Colors.white
            : AppColors.pink600;
    final pharmacyColor = mono
        ? AppColors.ink
        : onDark
            ? AppColors.gold300
            : AppColors.gold500;
    final taglineColor = mono
        ? AppColors.ink
        : onDark
            ? AppColors.onDarkMuted
            : AppColors.muted;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                    width: markSize,
                    height: markSize,
                    child: _mark(mono: mono)),
                SizedBox(width: markSize * 0.14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Yusra',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: markSize * 0.64,
                        fontWeight: FontWeight.w700,
                        color: brandColor,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'PHARMACY',
                      style: GoogleFonts.inter(
                        fontSize: markSize * 0.18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: markSize * 0.07,
                        color: pharmacyColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (showTagline) ...[
          const SizedBox(height: 10),
          Text(
            S.tagline,
            style: GoogleFonts.inter(
              fontSize: markSize * 0.19,
              fontWeight: FontWeight.w600,
              color: taglineColor,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }
}
