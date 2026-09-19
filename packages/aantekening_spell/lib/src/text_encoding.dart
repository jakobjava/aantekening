// Ported to Dart from Hunspell 1.7.3 and modified for aantekening; see
// LICENSE in this package, which has MySpell's notice as well.
//
// ***** BEGIN LICENSE BLOCK *****
// Version: MPL 1.1/GPL 2.0/LGPL 2.1
//
// Copyright (C) 2002-2022 Németh László
//
// The contents of this file are subject to the Mozilla Public License Version
// 1.1 (the "License"); you may not use this file except in compliance with
// the License. You may obtain a copy of the License at
// http://www.mozilla.org/MPL/
//
// Software distributed under the License is distributed on an "AS IS" basis,
// WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License
// for the specific language governing rights and limitations under the
// License.
//
// Hunspell is based on MySpell which is Copyright (C) 2002 Kevin Hendricks.
//
// Alternatively, the contents of this file may be used under the terms of
// either the GNU General Public License Version 2 or later (the "GPL"), or
// the GNU Lesser General Public License Version 2.1 or later (the "LGPL"),
// in which case the provisions of the GPL or the LGPL are applicable instead
// of those above. If you wish to allow use of your version of this file only
// under the terms of either the GPL or the LGPL, and not to allow others to
// use your version of this file under the terms of the MPL, indicate your
// decision by deleting the provisions above and replace them with the notice
// and other provisions required by the GPL or the LGPL. If you do not delete
// the provisions above, a recipient may use your version of this file under
// the terms of any one of the MPL, the GPL or the LGPL.
//
// ***** END LICENSE BLOCK *****

/// Reading dictionary files in the encoding their affix file names.
library;

import 'dart:convert';

/// Decodes dictionary files: UTF-8, or one of the single-byte encodings
/// older dictionaries use.
abstract final class DictionaryEncoding {
  /// The encoding [affixFile] names on its SET line, or ISO8859-1, which
  /// Hunspell assumes without one.
  static String of(List<int> affixFile) {
    final text = latin1.decode(affixFile, allowInvalid: true);
    final match = RegExp(r'^SET[ \t]+(\S+)', multiLine: true).firstMatch(text);
    return match?.group(1)?.toUpperCase() ?? 'ISO8859-1';
  }

  /// [bytes] read as [encoding].
  static String decode(List<int> bytes, String encoding) {
    switch (encoding.replaceAll('_', '-')) {
      case 'UTF-8' || 'UTF8':
        final text = utf8.decode(bytes, allowMalformed: true);
        return text.startsWith('﻿') ? text.substring(1) : text;
      case 'ISO8859-15' || 'ISO-8859-15':
        return String.fromCharCodes(<int>[
          for (final byte in bytes) _latin9[byte] ?? byte,
        ]);
      case 'ISO8859-2' || 'ISO-8859-2':
        return String.fromCharCodes(<int>[
          for (final byte in bytes) byte < 0xA0 ? byte : _latin2[byte - 0xA0],
        ]);
      default:
        return latin1.decode(bytes, allowInvalid: true);
    }
  }

  /// Where ISO 8859-15 differs from ISO 8859-1.
  static const Map<int, int> _latin9 = <int, int>{
    0xA4: 0x20AC,
    0xA6: 0x0160,
    0xA8: 0x0161,
    0xB4: 0x017D,
    0xB8: 0x017E,
    0xBC: 0x0152,
    0xBD: 0x0153,
    0xBE: 0x0178,
  };

  /// ISO 8859-2 from 0xA0 on.
  static const List<int> _latin2 = <int>[
    0x00A0, 0x0104, 0x02D8, 0x0141, 0x00A4, 0x013D, 0x015A, 0x00A7, //
    0x00A8, 0x0160, 0x015E, 0x0164, 0x0179, 0x00AD, 0x017D, 0x017B,
    0x00B0, 0x0105, 0x02DB, 0x0142, 0x00B4, 0x013E, 0x015B, 0x02C7,
    0x00B8, 0x0161, 0x015F, 0x0165, 0x017A, 0x02DD, 0x017E, 0x017C,
    0x0154, 0x00C1, 0x00C2, 0x0102, 0x00C4, 0x0139, 0x0106, 0x00C7,
    0x010C, 0x00C9, 0x0118, 0x00CB, 0x011A, 0x00CD, 0x00CE, 0x010E,
    0x0110, 0x0143, 0x0147, 0x00D3, 0x00D4, 0x0150, 0x00D6, 0x00D7,
    0x0158, 0x016E, 0x00DA, 0x0170, 0x00DC, 0x00DD, 0x0162, 0x00DF,
    0x0155, 0x00E1, 0x00E2, 0x0103, 0x00E4, 0x013A, 0x0107, 0x00E7,
    0x010D, 0x00E9, 0x0119, 0x00EB, 0x011B, 0x00ED, 0x00EE, 0x010F,
    0x0111, 0x0144, 0x0148, 0x00F3, 0x00F4, 0x0151, 0x00F6, 0x00F7,
    0x0159, 0x016F, 0x00FA, 0x0171, 0x00FC, 0x00FD, 0x0163, 0x02D9,
  ];
}
