import 'dart:convert';
import 'dart:typed_data';

/// Binary format constants for the brarchive format.
///
/// Format layout (little-endian):
///   Header:
///     magic    : uint64  (0x267052A0B125277D)
///     entries  : uint32
///     version  : uint32
///   Entry descriptors (repeated `entries` times):
///     nameLen  : uint8
///     name     : 247 bytes (UTF-8, zero-padded)
///     offset   : uint32  (relative to content section start)
///     length   : uint32
///   Content section:
///     concatenated file contents in descriptor order
class BrarchiveCodec {
  static const int _magic = 0x267052A0B125277D;
  static const int _version = 1;
  static const int _entryNameLenMax = 247;

  /// Serializes a map of filename -> content into brarchive binary format.
  ///
  /// Entries are sorted by filename for deterministic output.
  /// Throws [ArgumentError] if [entries] is empty or a filename exceeds
  /// the maximum length.
  static Uint8List serialize(Map<String, Uint8List> entries) {
    if (entries.isEmpty) {
      throw ArgumentError('no entries to encode');
    }

    final sortedKeys = entries.keys.toList()..sort();

    // Validate name lengths
    for (final name in sortedKeys) {
      final nameBytes = utf8.encode(name);
      if (nameBytes.length > _entryNameLenMax) {
        throw ArgumentError(
          'filename "$name" exceeds max length of $_entryNameLenMax bytes',
        );
      }
    }

    // Calculate content offsets
    final descriptors = <_EntryDescriptor>[];
    var currentOffset = 0;
    for (final key in sortedKeys) {
      final content = entries[key]!;
      descriptors.add(_EntryDescriptor(
        name: key,
        contentsOffset: currentOffset,
        contentsLen: content.length,
      ));
      currentOffset += content.length;
    }

    final builder = BytesBuilder();

    // Header
    _writeUint64(builder, _magic);
    _writeUint32(builder, descriptors.length);
    _writeUint32(builder, _version);

    // Entry descriptors
    for (final desc in descriptors) {
      final nameBytes = utf8.encode(desc.name);
      builder.addByte(nameBytes.length);
      final nameBuf = Uint8List(_entryNameLenMax);
      nameBuf.setRange(0, nameBytes.length, nameBytes);
      builder.add(nameBuf);
      _writeUint32(builder, desc.contentsOffset);
      _writeUint32(builder, desc.contentsLen);
    }

    // Content section
    for (final key in sortedKeys) {
      builder.add(entries[key]!);
    }

    return builder.takeBytes();
  }

  /// Deserializes brarchive binary data back into a map of filename -> content.
  ///
  /// Throws [FormatException] if the magic number is invalid or the data is
  /// truncated.
  static Map<String, Uint8List> deserialize(Uint8List data) {
    if (data.length < 16) {
      throw FormatException('data too short for header: ${data.length} bytes');
    }

    final bd = ByteData.sublistView(data);
    var pos = 0;

    final magic = bd.getUint64(pos, Endian.little);
    pos += 8;
    if (magic != _magic) {
      throw FormatException(
        'invalid magic: 0x${magic.toRadixString(16)} '
        '(expected 0x${_magic.toRadixString(16)})',
      );
    }

    final entryCount = bd.getUint32(pos, Endian.little);
    pos += 4;
    final version = bd.getUint32(pos, Endian.little);
    pos += 4;
    if (version != _version) {
      throw FormatException('unsupported version: $version');
    }

    final descriptors = <_EntryDescriptor>[];
    final entryHeaderSize = 1 + _entryNameLenMax + 4 + 4;
    for (var i = 0; i < entryCount; i++) {
      if (pos + entryHeaderSize > data.length) {
        throw FormatException('truncated data reading entry $i header');
      }
      final nameLen = data[pos];
      pos += 1;
      if (nameLen > _entryNameLenMax) {
        throw FormatException(
          'entry $i name length $nameLen exceeds max $_entryNameLenMax',
        );
      }
      final nameBytes = data.sublist(pos, pos + nameLen);
      pos += _entryNameLenMax;
      final name = utf8.decode(nameBytes);

      final offset = bd.getUint32(pos, Endian.little);
      pos += 4;
      final length = bd.getUint32(pos, Endian.little);
      pos += 4;

      descriptors.add(_EntryDescriptor(
        name: name,
        contentsOffset: offset,
        contentsLen: length,
      ));
    }

    // Content section starts here
    final contentStart = pos;
    final result = <String, Uint8List>{};
    for (final desc in descriptors) {
      final start = contentStart + desc.contentsOffset;
      final end = start + desc.contentsLen;
      if (end > data.length) {
        throw FormatException(
          'truncated content for "${desc.name}": '
          'need bytes [$start, $end) but data length is ${data.length}',
        );
      }
      // Create an independent copy, not a view. Views break when the
      // underlying buffer crosses isolate boundaries (compute()) or is
      // reused by ArchiveFile, causing 0-byte output for binary entries.
      result[desc.name] = Uint8List.fromList(
        data.sublist(start, end),
      );
    }

    return result;
  }

  static void _writeUint64(BytesBuilder builder, int value) {
    final bd = ByteData(8);
    bd.setUint64(0, value, Endian.little);
    builder.add(bd.buffer.asUint8List());
  }

  static void _writeUint32(BytesBuilder builder, int value) {
    final bd = ByteData(4);
    bd.setUint32(0, value, Endian.little);
    builder.add(bd.buffer.asUint8List());
  }
}

class _EntryDescriptor {
  final String name;
  final int contentsOffset;
  final int contentsLen;

  const _EntryDescriptor({
    required this.name,
    required this.contentsOffset,
    required this.contentsLen,
  });
}
