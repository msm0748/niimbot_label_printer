import 'package:flutter_test/flutter_test.dart';
import 'package:niimbot_lib/niimbot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('renders a 12x22 label at D11H dot dimensions', () async {
    final document = LabelDocument(
      size: LabelSize.d11h12x22,
      elements: <LabelElement>[
        LabelText(
          text: 'Hello',
          xMm: 1,
          yMm: 1,
          widthMm: 20,
          heightMm: 10,
          fontSizePt: 18,
        ),
      ],
    );

    final raster = await const TextLabelRenderer().render(document);

    expect(raster.width, 176);
    expect(raster.height, 96);
    expect(raster.pixels, contains(1));
    expect(raster.pixels, contains(0));
  });

  test('renders a 12x30 label at D11H dot dimensions', () async {
    final document = LabelDocument(
      size: LabelSize.d11h12x30,
      elements: <LabelElement>[
        LabelText(text: '30 mm', xMm: 1, yMm: 1, widthMm: 28, heightMm: 10),
      ],
    );

    final raster = await const TextLabelRenderer().render(document);

    expect((raster.width, raster.height), (240, 96));
  });

  test('rotated orientation swaps raster dimensions', () async {
    final document = LabelDocument(
      size: LabelSize.d11h12x22,
      orientation: LabelOrientation.rotated90,
      elements: <LabelElement>[
        LabelText(text: 'Rotate', xMm: 1, yMm: 1, widthMm: 20, heightMm: 10),
      ],
    );

    final raster = await const TextLabelRenderer().render(document);

    expect((raster.width, raster.height), (96, 176));
    expect(raster.pixels, contains(1));
  });

  test('places text at physical horizontal positions', () async {
    Future<MonochromeRaster> render(LabelHorizontalPosition position) {
      return const TextLabelRenderer().render(
        LabelDocument(
          size: LabelSize.d11h12x22,
          elements: <LabelElement>[
            LabelText(
              text: 'Position',
              xMm: 1,
              yMm: 1,
              widthMm: 20,
              heightMm: 10,
              fontSizePt: 12,
              horizontalPosition: position,
              wrap: false,
            ),
          ],
        ),
      );
    }

    final left = _blackHorizontalBounds(
      await render(LabelHorizontalPosition.left),
    );
    final center = _blackHorizontalBounds(
      await render(LabelHorizontalPosition.center),
    );
    final right = _blackHorizontalBounds(
      await render(LabelHorizontalPosition.right),
    );

    expect(left.left, lessThan(center.left));
    expect(center.left, lessThan(right.left));
  });

  test('keeps physical horizontal positions after rotation', () async {
    Future<MonochromeRaster> render(LabelHorizontalPosition position) {
      return const TextLabelRenderer().render(
        LabelDocument(
          size: LabelSize.d11h12x22,
          orientation: LabelOrientation.rotated90,
          elements: <LabelElement>[
            LabelText(
              text: 'Position',
              xMm: 1,
              yMm: 1,
              widthMm: 20,
              heightMm: 10,
              fontSizePt: 12,
              horizontalPosition: position,
              wrap: false,
            ),
          ],
        ),
      );
    }

    final left = _blackHorizontalBounds(
      await render(LabelHorizontalPosition.left),
    );
    final center = _blackHorizontalBounds(
      await render(LabelHorizontalPosition.center),
    );
    final right = _blackHorizontalBounds(
      await render(LabelHorizontalPosition.right),
    );

    expect(left.left, lessThan(center.left));
    expect(center.left, lessThan(right.left));
  });
}

({int left, int right}) _blackHorizontalBounds(MonochromeRaster raster) {
  var left = raster.width;
  var right = -1;
  for (var y = 0; y < raster.height; y++) {
    for (var x = 0; x < raster.width; x++) {
      if (raster.isBlack(x, y)) {
        left = x < left ? x : left;
        right = x > right ? x : right;
      }
    }
  }
  if (right < 0) {
    throw StateError('Raster contains no black pixels.');
  }
  return (left: left, right: right);
}
