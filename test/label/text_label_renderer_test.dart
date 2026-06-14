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
        LabelText(
          text: '30 mm',
          xMm: 1,
          yMm: 1,
          widthMm: 28,
          heightMm: 10,
        ),
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
        LabelText(
          text: 'Rotate',
          xMm: 1,
          yMm: 1,
          widthMm: 20,
          heightMm: 10,
        ),
      ],
    );

    final raster = await const TextLabelRenderer().render(document);

    expect((raster.width, raster.height), (96, 176));
    expect(raster.pixels, contains(1));
  });
}
