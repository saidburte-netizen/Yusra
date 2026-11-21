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
  });

  final YusraLogoVariant variant;
  final double size;
  final bool showTagline;

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
    final color = mono ? AppColors.ink : AppColors.pink600;
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
                SizedBox(width: markSize * 0.12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Yusra',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: markSize * 0.62,
                        fontWeight: FontWeight.w700,
                        color: color,
                        height: 1.05,
                      ),
                    ),
                    Text(
                      'PHARMACY',
                      style: GoogleFonts.inter(
                        fontSize: markSize * 0.17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: markSize * 0.055,
                        color: mono ? AppColors.ink : AppColors.gold700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (showTagline) ...[
          const SizedBox(height: 8),
          Text(
            S.tagline,
            style: GoogleFonts.inter(
              fontSize: markSize * 0.19,
              color: mono ? AppColors.ink : AppColors.muted,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }
}
