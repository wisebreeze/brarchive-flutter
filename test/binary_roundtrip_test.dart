import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:archive/archive.dart';
import 'package:brarchive/core/brarchive/brarchive_codec.dart';

void main() {
  group('Binary round-trip through zip', () {
    test('binary content survives serialize -> deserialize -> zip -> unzip', () {
      final binaryContent = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        ...List.generate(1000, (i) => (i * 37 + 13) % 256),
      ]);

      final brarchiveBytes = BrarchiveCodec.serialize({
        'texture.png': binaryContent,
      });

      final restored = BrarchiveCodec.deserialize(brarchiveBytes);
      expect(restored['texture.png']!.length, binaryContent.length);
      expect(restored['texture.png'], binaryContent);

      final archive = Archive();
      final content = List<int>.from(restored['texture.png']!);
      archive.addFile(ArchiveFile('texture.png', content.length, content));

      final zipBytes = ZipEncoder().encode(archive)!;

      final decodedArchive = ZipDecoder().decodeBytes(zipBytes);
      final decodedFile = decodedArchive.files.first;
      expect(decodedFile.isFile, true);
      final decodedContent = decodedFile.content as List<int>;
      expect(decodedContent.length, binaryContent.length);
      for (var i = 0; i < binaryContent.length; i++) {
        expect(decodedContent[i], binaryContent[i],
            reason: 'byte $i mismatch');
      }
    });

    test('multiple binary files with edge cases survive full round-trip', () {
      final files = <String, Uint8List>{
        'empty.bin': Uint8List(0),
        'large.bin': Uint8List.fromList(List.generate(5000, (i) => i % 256)),
        'all_zeros.bin': Uint8List(100),
        'all_ff.bin': Uint8List.fromList(List.filled(100, 0xFF)),
      };

      final brarchiveBytes = BrarchiveCodec.serialize(files);
      final restored = BrarchiveCodec.deserialize(brarchiveBytes);

      for (final entry in files.entries) {
        expect(restored[entry.key]!.length, entry.value.length,
            reason: '${entry.key} length mismatch');
        expect(restored[entry.key], entry.value,
            reason: '${entry.key} content mismatch');
      }

      final archive = Archive();
      for (final entry in restored.entries) {
        final content = List<int>.from(entry.value);
        archive.addFile(ArchiveFile(entry.key, content.length, content));
      }
      final zipBytes = ZipEncoder().encode(archive)!;
      final decoded = ZipDecoder().decodeBytes(zipBytes);

      for (final file in decoded) {
        if (!file.isFile) continue;
        final original = files[file.name]!;
        final content = file.content as List<int>;
        expect(content.length, original.length,
            reason: '${file.name} zip round-trip length mismatch');
        for (var i = 0; i < original.length; i++) {
          expect(content[i], original[i],
              reason: '${file.name} byte $i mismatch after zip');
        }
      }
    });
  });
}
