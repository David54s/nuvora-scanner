import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv.dart' as cv;

void main() {
  test('OpenCV nativo carga y crea un Mat', () {
    final mat = cv.Mat.zeros(10, 20, cv.MatType.CV_8UC3);
    try {
      expect(mat.rows, 10);
      expect(mat.cols, 20);
      expect(cv.openCvVersion(), startsWith('4.'));
    } finally {
      mat.dispose();
    }
  });
}
