import 'dart:io';
import 'dart:typed_data';

import 'package:minio/io.dart';
import 'package:minio/minio.dart';
import 'package:minio/src/minio_models_generated.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  testConstruct();
  testListBuckets();
  testBucketExists();
  testFPutObject();
  testGetObjectACL();
  testSetObjectACL();
  testGetObject();
  testPutObject();
  testGetBucketNotification();
  testSetBucketNotification();
  testRemoveAllBucketNotification();
  testListenBucketNotification();
  testStatObject();
  testMakeBucket();
  testRemoveBucket();
  testRemoveObject();
}

void testConstruct() {
  test('Minio() implies http port', () {
    final client = getMinioClient(port: null, useSSL: false);
    expect(client.port, equals(80));
  });

  test('Minio() implies https port', () {
    final client = getMinioClient(port: null, useSSL: true);
    expect(client.port, equals(443));
  });

  test('Minio() overrides port with http', () {
    final client = getMinioClient(port: 1234, useSSL: false);
    expect(client.port, equals(1234));
  });

  test('Minio() overrides port with https', () {
    final client = getMinioClient(port: 1234, useSSL: true);
    expect(client.port, equals(1234));
  });

  test('Minio() throws when endPoint is url', () {
    expect(
      () => getMinioClient(endpoint: 'http://play.min.io'),
      throwsA(isA<MinioError>()),
    );
  });

  test('Minio() throws when port is invalid', () {
    expect(
      () => getMinioClient(port: -1),
      throwsA(isA<MinioError>()),
    );

    expect(
      () => getMinioClient(port: 65536),
      throwsA(isA<MinioError>()),
    );
  });
}

void testListBuckets() {
  test('listBuckets() succeeds', () async {
    final minio = getMinioClient();

    expect(() async => await minio.listBuckets(), returnsNormally);
  });

  test('listBuckets() can list buckets', () async {
    final minio = getMinioClient();
    final bucketName1 = DateTime.now().millisecondsSinceEpoch.toString();
    await minio.makeBucket(bucketName1);

    final bucketName2 = DateTime.now().millisecondsSinceEpoch.toString();
    await minio.makeBucket(bucketName2);

    final buckets = await minio.listBuckets();
    expect(buckets.any((b) => b.name == bucketName1), isTrue);
    expect(buckets.any((b) => b.name == bucketName2), isTrue);

    await minio.removeBucket(bucketName1);
    await minio.removeBucket(bucketName2);
  });

  test('listBuckets() fails due to wrong access key', () async {
    final minio = getMinioClient(accessKey: 'incorrect-access-key');

    expect(
      () async => await minio.listBuckets(),
      throwsA(
        isA<MinioError>().having(
          (e) => e.message,
          'message',
          'The Access Key Id you provided does not exist in our records.',
        ),
      ),
    );
  });

  test('listBuckets() fails due to wrong secret key', () async {
    final minio = getMinioClient(secretKey: 'incorrect-secret-key');

    expect(
      () async => await minio.listBuckets(),
      throwsA(
        isA<MinioError>().having(
          (e) => e.message,
          'message',
          'The request signature we calculated does not match the signature you provided. Check your key and signing method.',
        ),
      ),
    );
  });
}

void testBucketExists() {
  group('bucketExists', () {
    final bucketName = DateTime.now().millisecondsSinceEpoch.toString();

    setUpAll(() async {
      final minio = getMinioClient();
      await minio.makeBucket(bucketName);
    });

    tearDownAll(() async {
      final minio = getMinioClient();
      await minio.removeBucket(bucketName);
    });

    test('bucketExists() returns true for an existing bucket', () async {
      final minio = getMinioClient();
      expect(await minio.bucketExists(bucketName), equals(true));
    });

    test('bucketExists() returns false for a non-existent bucket', () async {
      final minio = getMinioClient();
      expect(
          await minio.bucketExists('non-existing-bucket-name'), equals(false));
    });

    test('bucketExists() fails due to wrong access key', () async {
      final minio = getMinioClient(accessKey: 'incorrect-access-key');
      expect(
        () async => await minio.bucketExists(bucketName),
        throwsA(
          isA<MinioError>().having(
            (e) => e.message,
            'message',
            'Forbidden',
          ),
        ),
      );
    });

    test('bucketExists() fails due to wrong secret key', () async {
      final minio = getMinioClient(secretKey: 'incorrect-secret-key');
      expect(
        () async => await minio.bucketExists(bucketName),
        throwsA(
          isA<MinioError>().having(
            (e) => e.message,
            'message',
            'Forbidden',
          ),
        ),
      );
    });
  });
}

void testFPutObject() {
  group('fPutObject', () {
    final bucketName = DateTime.now().millisecondsSinceEpoch.toString();
    late Directory tempDir;
    late File testFile;
    final objectName = 'a.jpg';

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp();
      testFile = await File('${tempDir.path}/$objectName').create();
      await testFile.writeAsString('random bytes');

      final minio = getMinioClient();
      await minio.makeBucket(bucketName);
    });

    tearDownAll(() async {
      final minio = getMinioClient();
      await minio.removeObject(bucketName, objectName);
      await tempDir.delete(recursive: true);
    });

    test('fPutObject() inserts content-type to metadata', () async {
      final minio = getMinioClient();
      await minio.fPutObject(bucketName, objectName, testFile.path);

      final stat = await minio.statObject(bucketName, objectName);
      expect(stat.metaData!['content-type'], equals('image/jpeg'));
    });

    test('fPutObject() adds user-defined object metadata w/ prefix', () async {
      final prefix = 'x-amz-meta-';
      final userDefinedMetadataKey = '${prefix}user-defined-metadata-key-1';
      final userDefinedMetadataValue = 'custom value 1';
      final metadata = {
        userDefinedMetadataKey: userDefinedMetadataValue,
      };

      final minio = getMinioClient();
      await minio.fPutObject(bucketName, objectName, testFile.path, metadata);

      final stat = await minio.statObject(bucketName, objectName);
      expect(
        stat.metaData![userDefinedMetadataKey.substring(prefix.length)],
        equals(userDefinedMetadataValue),
      );
    });

    test('fPutObject() adds user-defined object metadata w/o prefix', () async {
      final userDefinedMetadataKey = 'user-defined-metadata-key-2';
      final userDefinedMetadataValue = 'custom value 2';
      final metadata = {
        userDefinedMetadataKey: userDefinedMetadataValue,
      };

      final minio = getMinioClient();
      await minio.fPutObject(bucketName, objectName, testFile.path, metadata);

      final stat = await minio.statObject(bucketName, objectName);
      expect(stat.metaData![userDefinedMetadataKey],
          equals(userDefinedMetadataValue));
    });

    test('fPutObject() with empty file', () async {
      final objectName = 'empty.txt';
      final emptyFile = await File('${tempDir.path}/$objectName').create();
      await emptyFile.writeAsString('');

      final minio = getMinioClient();
      await minio.fPutObject(bucketName, objectName, emptyFile.path);

      final stat = await minio.statObject(bucketName, objectName);
      expect(stat.size, equals(0));
    });
  });
}

void testSetObjectACL() {
  group('setObjectACL', () {
    late String bucketName;
    late Directory tempDir;
    File testFile;
    final objectName = 'a.jpg';

    setUpAll(() async {
      bucketName = DateTime.now().millisecondsSinceEpoch.toString();

      tempDir = await Directory.systemTemp.createTemp();
      testFile = await File('${tempDir.path}/$objectName').create();
      await testFile.writeAsString('random bytes');

      final minio = getMinioClient();
      await minio.makeBucket(bucketName);

      await minio.fPutObject(bucketName, objectName, testFile.path);
    });

    tearDownAll(() async {
      await tempDir.delete(recursive: true);
    });

    test('setObjectACL() set objects acl', () async {
      final minio = getMinioClient();
      await minio.setObjectACL(bucketName, objectName, 'public-read');
    });
  });
}

void testGetObjectACL() {
  group('getObjectACL', () {
    late String bucketName;
    late Directory tempDir;
    File testFile;
    final objectName = 'a.jpg';

    setUpAll(() async {
      bucketName = DateTime.now().millisecondsSinceEpoch.toString();

      tempDir = await Directory.systemTemp.createTemp();
      testFile = await File('${tempDir.path}/$objectName').create();
      await testFile.writeAsString('random bytes');

      final minio = getMinioClient();
      await minio.makeBucket(bucketName);

      await minio.fPutObject(bucketName, objectName, testFile.path);
    });

    tearDownAll(() async {
      await tempDir.delete(recursive: true);
    });

    test('getObjectACL() fetch objects acl', () async {
      final minio = getMinioClient();
      var acl = await minio.getObjectACL(bucketName, objectName);
      expect(acl.grants!.permission, equals(null));
    });
  });
}

void testGetObject() {
  group('getObject()', () {
    final minio = getMinioClient();
    final bucketName = DateTime.now().millisecondsSinceEpoch.toString();
    final objectName = DateTime.now().microsecondsSinceEpoch.toString();
    final objectData = Uint8List.fromList([1, 2, 3]);

    setUpAll(() async {
      await minio.makeBucket(bucketName);
      await minio.putObject(bucketName, objectName, Stream.value(objectData));
    });

    tearDownAll(() async {
      await minio.removeObject(bucketName, objectName);
      await minio.removeBucket(bucketName);
    });

    test('succeeds', () async {
      final stream = await minio.getObject(bucketName, objectName);
      final buffer = BytesBuilder();
      await stream.forEach((data) => buffer.add(data));
      expect(stream.contentLength, equals(objectData.length));
      expect(buffer.takeBytes(), equals(objectData));
    });

    test('fails on invalid bucket', () {
      expect(
        () async => await minio.getObject('$bucketName-invalid', objectName),
        throwsA(isA<MinioError>()),
      );
    });

    test('fails on invalid object', () {
      expect(
        () async => await minio.getObject(bucketName, '$objectName-invalid'),
        throwsA(isA<MinioError>()),
      );
    });
  });
}

void testPutObject() {
  group('putObject()', () {
    final minio = getMinioClient();
    final bucketName = DateTime.now().millisecondsSinceEpoch.toString();
    final objectData = Uint8List.fromList([1, 2, 3]);

    setUpAll(() async {
      await minio.makeBucket(bucketName);
    });

    tearDownAll(() async {
      await minio.removeBucket(bucketName);
    });

    test('succeeds', () async {
      final objectName = DateTime.now().microsecondsSinceEpoch.toString();
      await minio.putObject(bucketName, objectName, Stream.value(objectData));
      final stat = await minio.statObject(bucketName, objectName);
      expect(stat.size, equals(objectData.length));
      await minio.removeObject(bucketName, objectName);
    });

    test('works with object names with symbols', () async {
      final objectName =
          DateTime.now().microsecondsSinceEpoch.toString() + r'-._~,!@#$%^&*()';
      await minio.putObject(bucketName, objectName, Stream.value(objectData));
      final stat = await minio.statObject(bucketName, objectName);
      expect(stat.size, equals(objectData.length));
      await minio.removeObject(bucketName, objectName);
    });
  });
}

void testGetBucketNotification() {
  group('getBucketNotification()', () {
    final minio = getMinioClient();
    final bucketName = DateTime.now().millisecondsSinceEpoch.toString();

    setUpAll(() async {
      await minio.makeBucket(bucketName);
    });

    tearDownAll(() async {
      await minio.removeBucket(bucketName);
    });

    test('succeeds', () async {
      await minio.getBucketNotification(bucketName);
    });
  });
}

void testSetBucketNotification() {
  group('setBucketNotification()', () {
    final minio = getMinioClient();
    final bucketName = DateTime.now().millisecondsSinceEpoch.toString();

    setUpAll(() async {
      await minio.makeBucket(bucketName);
    });

    tearDownAll(() async {
      await minio.removeBucket(bucketName);
    });

    test('succeeds', () async {
      await minio.setBucketNotification(
        bucketName,
        NotificationConfiguration(null, null, null),
      );
    });
  });
}

void testRemoveAllBucketNotification() {
  group('removeAllBucketNotification()', () {
    final minio = getMinioClient();
    final bucketName = DateTime.now().millisecondsSinceEpoch.toString();

    setUpAll(() async {
      await minio.makeBucket(bucketName);
    });

    tearDownAll(() async {
      await minio.removeBucket(bucketName);
    });

    test('succeeds', () async {
      await minio.removeAllBucketNotification(bucketName);
    });
  });
}

void testListenBucketNotification() {
  group('listenBucketNotification()', () {
    final minio = getMinioClient();
    final bucketName = DateTime.now().millisecondsSinceEpoch.toString();
    // final objectName = DateTime.now().microsecondsSinceEpoch.toString();

    setUpAll(() async {
      await minio.makeBucket(bucketName);
    });

    tearDownAll(() async {
      await minio.removeBucket(bucketName);
    });

    test('succeeds', () async {
      final poller = minio.listenBucketNotification(bucketName);
      expect(poller.isStarted, isTrue);
      poller.stop();
    });

    // test('can receive notification', () async {
    //   final poller = minio.listenBucketNotification(
    //     bucketName,
    //     events: ['s3:ObjectCreated:*'],
    //   );

    //   final receivedEvents = [];
    //   poller.stream.listen((event) => receivedEvents.add(event));
    //   expect(receivedEvents, isEmpty);

    //   await minio.putObject(bucketName, objectName, Stream.value([0]));
    //   await minio.removeObject(bucketName, objectName);

    //   // FIXME: Needs sleep here
    //   expect(receivedEvents, isNotEmpty);

    //   poller.stop();
    // });
  });
}

void testStatObject() {
  group('statObject()', () {
    final minio = getMinioClient();
    final bucketName = DateTime.now().millisecondsSinceEpoch.toString();
    final objectName = DateTime.now().microsecondsSinceEpoch.toString();
    final data = [1, 2, 3, 4, 5];

    setUpAll(() async {
      await minio.makeBucket(bucketName);
      await minio.putObject(bucketName, objectName, Stream.value(data));
    });

    tearDownAll(() async {
      await minio.removeObject(bucketName, objectName);
      await minio.removeBucket(bucketName);
    });

    test('succeeds', () async {
      final stats = await minio.statObject(bucketName, objectName);
      expect(stats.lastModified, isNotNull);
      expect(stats.lastModified!.isBefore(DateTime.now()), isTrue);
      expect(stats.size, isNotNull);
      expect(stats.size, equals(data.length));
    });

    test('fails on invalid bucket', () {
      expect(
        () async => await minio.statObject('$bucketName-invalid', objectName),
        throwsA(isA<MinioError>()),
      );
    });

    test('fails on invalid object', () {
      expect(
        () async => await minio.statObject(bucketName, '$objectName-invalid'),
        throwsA(isA<MinioError>()),
      );
    });
  });
}

void testMakeBucket() {
  group('makeBucket()', () {
    final minio = getMinioClient();
    final bucketName = DateTime.now().millisecondsSinceEpoch.toString();

    setUpAll(() async {
      await minio.makeBucket(bucketName);
    });

    tearDownAll(() async {
      await minio.removeBucket(bucketName);
    });

    test('succeeds', () async {
      final buckets = await minio.listBuckets();
      final bucketNames = buckets.map((b) => b.name).toList();
      expect(bucketNames, contains(bucketName));
    });
  });
}

void testRemoveBucket() {
  group('removeBucket()', () {
    final minio = getMinioClient();
    final bucketName = DateTime.now().millisecondsSinceEpoch.toString();

    test('succeeds', () async {
      await minio.makeBucket(bucketName);
      await minio.removeBucket(bucketName);
    });

    test('fails on invalid bucket name', () {
      expect(
        () async => await minio.removeBucket('$bucketName-invalid'),
        throwsA(isA<MinioError>()),
      );
    });
  });
}

void testRemoveObject() {
  group('removeObject()', () {
    final minio = getMinioClient();
    final bucketName = DateTime.now().millisecondsSinceEpoch.toString();
    final objectName = DateTime.now().microsecondsSinceEpoch.toString();
    final data = [1, 2, 3, 4, 5];

    setUpAll(() async {
      await minio.makeBucket(bucketName);
    });

    tearDownAll(() async {
      await minio.removeBucket(bucketName);
    });

    test('succeeds', () async {
      await minio.putObject(bucketName, objectName, Stream.value(data));
      await minio.removeObject(bucketName, objectName);

      await for (var chunk in minio.listObjects(bucketName)) {
        expect(chunk.objects.contains(objectName), isFalse);
      }
    });

    test('fails on invalid bucket', () {
      expect(
        () async => await minio.removeObject('$bucketName-invalid', objectName),
        throwsA(isA<MinioError>()),
      );
    });

    test('does not throw on invalid object', () async {
      await minio.removeObject(bucketName, '$objectName-invalid');
    });
  });
}
