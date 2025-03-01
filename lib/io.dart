import 'dart:io';

import 'package:minio/src/minio.dart';
import 'package:minio/src/minio_errors.dart';
import 'package:minio/src/minio_helpers.dart';
import 'package:path/path.dart' show dirname;

extension MinioX on Minio {
  // Uploads the object using contents from a file
  Future<String> fPutObject(
    String bucket,
    String object,
    String filePath, [
    Map<String, String>? metadata,
  ]) async {
    MinioInvalidBucketNameError.check(bucket);
    MinioInvalidObjectNameError.check(object);

    metadata ??= {};
    metadata = insertContentType(metadata, filePath);
    metadata = prependXAMZMeta(metadata);

    final file = File(filePath);
    final stat = await file.stat();
    if (stat.size > maxObjectSize) {
      throw MinioError(
        '$filePath size : ${stat.size}, max allowed size : 5TB',
      );
    }

    return putObject(
      bucket,
      object,
      file.openRead(),
      size: stat.size,
      metadata: metadata,
    );
  }

  Future<String> fPutPart(
    String bucket,
    String object,
    String uploadId,
    int partSize,
    int partNumber,
    String filePath, [
    Map<String, String>? metadata,
  ]) async {
    MinioInvalidBucketNameError.check(bucket);
    MinioInvalidObjectNameError.check(object);

    metadata ??= {};
    metadata = insertContentType(metadata, filePath);
    metadata = prependXAMZMeta(metadata);

    final file = File(filePath);
    final stat = await file.stat();
    if (stat.size > maxObjectSize) {
      throw MinioError(
        '$filePath size : ${stat.size}, max allowed size : 5TB',
      );
    }

    return putPart(
      bucket,
      object,
      uploadId,
      partSize,
      partNumber,
      file.openRead(),
      size: stat.size,
      metadata: metadata,
    );
  }

  /// Downloads and saves the object as a file in the local filesystem.
  Future<void> fGetObject(
    String bucket,
    String object,
    String filePath,
  ) async {
    MinioInvalidBucketNameError.check(bucket);
    MinioInvalidObjectNameError.check(object);

    final stat = await statObject(bucket, object);
    final dir = dirname(filePath);
    await Directory(dir).create(recursive: true);

    final partFileName = '$filePath.${stat.etag}.part.minio';
    final partFile = File(partFileName);
    IOSink partFileStream;
    var offset = 0;

    final rename = () {
      partFile.rename(filePath);
    };

    if (await partFile.exists()) {
      final localStat = await partFile.stat();
      if (stat.size == localStat.size) return rename();
      offset = localStat.size;
      partFileStream = partFile.openWrite(mode: FileMode.append);
    } else {
      partFileStream = partFile.openWrite(mode: FileMode.write);
    }

    final dataStream = await getPartialObject(bucket, object, offset);
    await dataStream.pipe(partFileStream);

    final localStat = await partFile.stat();
    if (localStat.size != stat.size) {
      throw MinioError('Size mismatch between downloaded file and the object');
    }

    return rename();
  }
}
