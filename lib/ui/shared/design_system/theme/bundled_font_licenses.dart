import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Registers the licenses of the bundled typefaces and icon set with [LicenseRegistry], which
/// the SIL Open Font License requires to travel with redistributed fonts.
abstract final class BundledFontLicenses {
  static const _poppinsCopyright = 'Copyright 2020 The Poppins Project Authors (https://github.com/itfoundry/Poppins)';
  static const _rajdhaniCopyright = 'Copyright (c) 2014 Indian Type Foundry (info@indiantypefoundry.com)';

  static void register() {
    LicenseRegistry.addLicense(() async* {
      final ofl = await rootBundle.loadString('assets/fonts/OFL.txt');

      yield LicenseEntryWithLineBreaks(const ['Poppins'], '$_poppinsCopyright\n\n$ofl');
      yield LicenseEntryWithLineBreaks(const ['Rajdhani'], '$_rajdhaniCopyright\n\n$ofl');
      yield LicenseEntryWithLineBreaks(const [
        'Tabler Icons',
      ], await rootBundle.loadString('assets/icons/tabler/LICENSE'));
    });
  }
}
