sealed class LabelElement {
  const LabelElement();
}

enum LabelOrientation { normal, rotated90 }

enum LabelTextAlignment { start, center, end }

final class LabelSize {
  const LabelSize._({required this.widthMm, required this.heightMm});

  factory LabelSize({required double widthMm, required double heightMm}) {
    if (!widthMm.isFinite || widthMm <= 0) {
      throw ArgumentError.value(widthMm, 'widthMm', 'Must be positive.');
    }
    if (!heightMm.isFinite || heightMm <= 0) {
      throw ArgumentError.value(heightMm, 'heightMm', 'Must be positive.');
    }
    return LabelSize._(widthMm: widthMm, heightMm: heightMm);
  }

  static const d11h12x22 = LabelSize._(widthMm: 22, heightMm: 12);
  static const d11h12x30 = LabelSize._(widthMm: 30, heightMm: 12);

  final double widthMm;
  final double heightMm;
}

final class LabelText extends LabelElement {
  const LabelText._({
    required this.text,
    required this.xMm,
    required this.yMm,
    required this.widthMm,
    required this.heightMm,
    required this.fontSizePt,
    required this.alignment,
    required this.wrap,
    required this.bold,
  });

  factory LabelText({
    required String text,
    required double xMm,
    required double yMm,
    required double widthMm,
    required double heightMm,
    double fontSizePt = 18,
    LabelTextAlignment alignment = LabelTextAlignment.center,
    bool wrap = true,
    bool bold = false,
  }) {
    if (xMm < 0 || !xMm.isFinite) {
      throw ArgumentError.value(xMm, 'xMm', 'Must be finite and non-negative.');
    }
    if (yMm < 0 || !yMm.isFinite) {
      throw ArgumentError.value(yMm, 'yMm', 'Must be finite and non-negative.');
    }
    if (widthMm <= 0 || !widthMm.isFinite) {
      throw ArgumentError.value(widthMm, 'widthMm', 'Must be positive.');
    }
    if (heightMm <= 0 || !heightMm.isFinite) {
      throw ArgumentError.value(heightMm, 'heightMm', 'Must be positive.');
    }
    if (fontSizePt <= 0 || !fontSizePt.isFinite) {
      throw ArgumentError.value(fontSizePt, 'fontSizePt', 'Must be positive.');
    }
    return LabelText._(
      text: text,
      xMm: xMm,
      yMm: yMm,
      widthMm: widthMm,
      heightMm: heightMm,
      fontSizePt: fontSizePt,
      alignment: alignment,
      wrap: wrap,
      bold: bold,
    );
  }

  final String text;
  final double xMm;
  final double yMm;
  final double widthMm;
  final double heightMm;
  final double fontSizePt;
  final LabelTextAlignment alignment;
  final bool wrap;
  final bool bold;
}

final class LabelDocument {
  LabelDocument({
    required this.size,
    this.orientation = LabelOrientation.normal,
    required List<LabelElement> elements,
  }) : elements = List<LabelElement>.unmodifiable(elements) {
    for (final element in elements) {
      if (element case final LabelText text) {
        if (text.xMm + text.widthMm > size.widthMm ||
            text.yMm + text.heightMm > size.heightMm) {
          throw ArgumentError.value(
            element,
            'elements',
            'Text bounds must fit inside the label.',
          );
        }
      }
    }
  }

  static const int dotsPerMillimeter = 8;

  final LabelSize size;
  final LabelOrientation orientation;
  final List<LabelElement> elements;

  int get widthDots => switch (orientation) {
    LabelOrientation.normal => (size.widthMm * dotsPerMillimeter).round(),
    LabelOrientation.rotated90 => (size.heightMm * dotsPerMillimeter).round(),
  };

  int get heightDots => switch (orientation) {
    LabelOrientation.normal => (size.heightMm * dotsPerMillimeter).round(),
    LabelOrientation.rotated90 => (size.widthMm * dotsPerMillimeter).round(),
  };
}
