// Minimal reader for MATLAB Level-5 MAT-files (numeric real arrays only).
//
// Supports little-endian files, miCOMPRESSED (zlib) elements, small data
// element format and numeric classes double/single/int8..uint64. Enough to
// read the public system-identification benchmark files; it is not a
// general MAT-file implementation.

import 'dart:io';
import 'dart:typed_data';

class MatArray {
  final String name;
  final List<int> dims;
  final Float64List data; // column-major, as stored by MATLAB

  MatArray(this.name, this.dims, this.data);

  int get numel => data.length;

  /// Flattened vector (for row/column vectors).
  Float64List get vector => data;
}

const _miINT8 = 1, _miUINT8 = 2, _miINT16 = 3, _miUINT16 = 4, _miINT32 = 5,
    _miUINT32 = 6, _miSINGLE = 7, _miDOUBLE = 9, _miINT64 = 12, _miUINT64 = 13,
    _miMATRIX = 14, _miCOMPRESSED = 15;

Map<String, MatArray> readMat5(String path) {
  final bytes = File(path).readAsBytesSync();
  if (bytes.length < 128) throw FormatException('not a MAT file: $path');
  final header = String.fromCharCodes(bytes.sublist(0, 10));
  if (!header.startsWith('MATLAB 5.0')) {
    throw FormatException('unsupported MAT version (need Level 5): $path');
  }
  final endian = String.fromCharCodes(bytes.sublist(126, 128));
  if (endian != 'IM') throw FormatException('big-endian MAT files are not supported');
  final out = <String, MatArray>{};
  _readElements(ByteData.sublistView(bytes, 128), out);
  return out;
}

void _readElements(ByteData bd, Map<String, MatArray> out) {
  var pos = 0;
  while (pos + 8 <= bd.lengthInBytes) {
    final type = bd.getUint32(pos, Endian.little);
    final size = bd.getUint32(pos + 4, Endian.little);
    final start = pos + 8;
    if (type == _miCOMPRESSED) {
      final raw = Uint8List.sublistView(bd, start, start + size);
      final inflated = Uint8List.fromList(ZLibDecoder().convert(raw));
      _readElements(ByteData.sublistView(inflated), out);
      pos = start + size;
    } else if (type == _miMATRIX) {
      final arr = _readMatrix(ByteData.sublistView(bd, start, start + size));
      if (arr != null) out[arr.name] = arr;
      pos = start + size;
      pos = (pos + 7) & ~7;
    } else {
      pos = start + size;
      pos = (pos + 7) & ~7;
    }
  }
}

/// Reads one sub-element; returns (type, payload view, next offset).
(int, ByteData, int) _subElement(ByteData bd, int pos) {
  final first = bd.getUint32(pos, Endian.little);
  final small = (first >> 16) != 0;
  if (small) {
    final type = first & 0xFFFF;
    final size = first >> 16;
    return (type, ByteData.sublistView(bd, pos + 4, pos + 4 + size), pos + 8);
  }
  final size = bd.getUint32(pos + 4, Endian.little);
  final next = (pos + 8 + size + 7) & ~7;
  return (first, ByteData.sublistView(bd, pos + 8, pos + 8 + size), next);
}

MatArray? _readMatrix(ByteData bd) {
  var pos = 0;
  final (_, flags, p1) = _subElement(bd, pos);
  pos = p1;
  final cls = flags.getUint32(0, Endian.little) & 0xFF;
  final isComplex = (flags.getUint32(0, Endian.little) & 0x800) != 0;
  final (_, dimsData, p2) = _subElement(bd, pos);
  pos = p2;
  final dims = <int>[
    for (var i = 0; i < dimsData.lengthInBytes ~/ 4; i++) dimsData.getInt32(i * 4, Endian.little),
  ];
  final (_, nameData, p3) = _subElement(bd, pos);
  pos = p3;
  final name = String.fromCharCodes(Uint8List.sublistView(nameData));
  // Numeric classes: 6 double, 7 single, 8..15 integers.
  if (cls < 6 || cls > 15) return null;
  final (rtype, real, _) = _subElement(bd, pos);
  if (isComplex) return null;
  return MatArray(name, dims, _toDoubles(rtype, real));
}

Float64List _toDoubles(int type, ByteData d) {
  int n(int w) => d.lengthInBytes ~/ w;
  switch (type) {
    case _miDOUBLE:
      return Float64List.fromList([for (var i = 0; i < n(8); i++) d.getFloat64(i * 8, Endian.little)]);
    case _miSINGLE:
      return Float64List.fromList([for (var i = 0; i < n(4); i++) d.getFloat32(i * 4, Endian.little)]);
    case _miINT8:
      return Float64List.fromList([for (var i = 0; i < n(1); i++) d.getInt8(i).toDouble()]);
    case _miUINT8:
      return Float64List.fromList([for (var i = 0; i < n(1); i++) d.getUint8(i).toDouble()]);
    case _miINT16:
      return Float64List.fromList([for (var i = 0; i < n(2); i++) d.getInt16(i * 2, Endian.little).toDouble()]);
    case _miUINT16:
      return Float64List.fromList([for (var i = 0; i < n(2); i++) d.getUint16(i * 2, Endian.little).toDouble()]);
    case _miINT32:
      return Float64List.fromList([for (var i = 0; i < n(4); i++) d.getInt32(i * 4, Endian.little).toDouble()]);
    case _miUINT32:
      return Float64List.fromList([for (var i = 0; i < n(4); i++) d.getUint32(i * 4, Endian.little).toDouble()]);
    case _miINT64:
      return Float64List.fromList([for (var i = 0; i < n(8); i++) d.getInt64(i * 8, Endian.little).toDouble()]);
    case _miUINT64:
      return Float64List.fromList([for (var i = 0; i < n(8); i++) d.getUint64(i * 8, Endian.little).toDouble()]);
  }
  throw FormatException('unsupported MAT data type $type');
}
