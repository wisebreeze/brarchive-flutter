import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:brarchive/core/brarchive/brarchive_codec.dart';

void main() {
  group('BrarchiveCodec', () {
    test('serialize/deserialize single file round-trip', () {
      final entries = {
        'test.txt': Uint8List.fromList('Hello, World!'.codeUnits),
      };
      final encoded = BrarchiveCodec.serialize(entries);
      expect(encoded, isNotEmpty);

      final decoded = BrarchiveCodec.deserialize(encoded);
      expect(decoded.keys, contains('test.txt'));
      expect(String.fromCharCodes(decoded['test.txt']!), 'Hello, World!');
    });

    test('serialize/deserialize multiple files round-trip', () {
      final entries = {
        'file1.txt': Uint8List.fromList('Content 1'.codeUnits),
        'file2.txt': Uint8List.fromList('Content 2'.codeUnits),
        'file3.txt': Uint8List.fromList('Content 3'.codeUnits),
      };
      final encoded = BrarchiveCodec.serialize(entries);
      final decoded = BrarchiveCodec.deserialize(encoded);

      expect(decoded.length, 3);
      expect(String.fromCharCodes(decoded['file1.txt']!), 'Content 1');
      expect(String.fromCharCodes(decoded['file2.txt']!), 'Content 2');
      expect(String.fromCharCodes(decoded['file3.txt']!), 'Content 3');
    });

    test('serialize throws on empty entries', () {
      expect(
        () => BrarchiveCodec.serialize({}),
        throwsArgumentError,
      );
    });

    test('serialize produces deterministic output (sorted keys)', () {
      final entries1 = {
        'b.txt': Uint8List.fromList([1]),
        'a.txt': Uint8List.fromList([2]),
      };
      final entries2 = {
        'a.txt': Uint8List.fromList([2]),
        'b.txt': Uint8List.fromList([1]),
      };
      expect(
        BrarchiveCodec.serialize(entries1),
        BrarchiveCodec.serialize(entries2),
      );
    });

    test('deserialize rejects invalid magic', () {
      final bad = Uint8List.fromList(List.filled(16, 0));
      expect(
        () => BrarchiveCodec.deserialize(bad),
        throwsA(isA<FormatException>()),
      );
    });

    test('deserialize rejects truncated data', () {
      // Valid magic + entry count 1 + version 1, but no entry data
      final truncated = Uint8List.fromList([
        0x7D, 0x27, 0x25, 0xB1, 0xA0, 0x52, 0x70, 0x26, // magic
        0x01, 0x00, 0x00, 0x00, // entries = 1
        0x01, 0x00, 0x00, 0x00, // version = 1
      ]);
      expect(
        () => BrarchiveCodec.deserialize(truncated),
        throwsA(isA<FormatException>()),
      );
    });

    test('handles binary content correctly', () {
      final binary = Uint8List.fromList(
        List.generate(256, (i) => i % 256),
      );
      final entries = {'data.bin': binary};
      final encoded = BrarchiveCodec.serialize(entries);
      final decoded = BrarchiveCodec.deserialize(encoded);
      expect(decoded['data.bin'], binary);
    });

    test('handles long filename (under 247 bytes)', () {
      final longName = 'a' * 200 + '.txt';
      final entries = {
        longName: Uint8List.fromList('content'.codeUnits),
      };
      final encoded = BrarchiveCodec.serialize(entries);
      final decoded = BrarchiveCodec.deserialize(encoded);
      expect(decoded.keys, contains(longName));
    });

    test('rejects filename exceeding 247 bytes', () {
      final tooLongName = 'a' * 300 + '.txt';
      expect(
        () => BrarchiveCodec.serialize({
          tooLongName: Uint8List.fromList([1]),
        }),
        throwsArgumentError,
      );
    });
  });
}
