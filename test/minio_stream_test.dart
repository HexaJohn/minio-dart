import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('MinioByteStream', () {
    final bucketName = DateTime.now().millisecondsSinceEpoch.toString();
    final objectName = 'content-length-test';
    final testData = [1, 2, 3, 4, 5];

    setUpAll(() async {
      final minio = getMinioClient();
      await minio.makeBucket(bucketName);
      await minio.putObject(bucketName, objectName, Stream.value(testData));
    });

    tearDownAll(() async {
      final minio = getMinioClient();
      await minio.removeObject(bucketName, objectName);
      await minio.removeBucket(bucketName);
    });

    test('contains content length', () async {
      final minio = getMinioClient();
      final stream = await minio.getObject(bucketName, objectName);
      expect(stream.contentLength, equals(testData.length));
      await stream.drain();
    });
  });
}
