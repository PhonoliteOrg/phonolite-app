import 'dart:io';

int? resolveDownloadBytesTotal({
  required String? contentRange,
  required int? contentLength,
  required int statusCode,
  required int startByte,
}) {
  final rangeTotal = parseDownloadContentRangeTotal(contentRange);
  if (rangeTotal != null) {
    return rangeTotal;
  }

  if (contentLength == null || contentLength <= 0) {
    return null;
  }

  if (statusCode == HttpStatus.partialContent) {
    return startByte + contentLength;
  }

  return contentLength;
}

int? parseDownloadContentRangeTotal(String? header) {
  if (header == null) {
    return null;
  }

  final slashIndex = header.lastIndexOf('/');

  if (slashIndex < 0 || slashIndex == header.length - 1) {
    return null;
  }

  final total = header.substring(slashIndex + 1).trim();

  if (total == '*') {
    return null;
  }

  return int.tryParse(total);
}
