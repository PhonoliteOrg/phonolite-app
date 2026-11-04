# flutter_secure_storage_macos

Local packaging fork of upstream `flutter_secure_storage_macos` 3.1.3 from
[flutter_secure_storage](https://github.com/mogol/flutter_secure_storage).

The Dart API, method channel, Keychain queries and Swift implementation are
unchanged. This fork adds Swift Package Manager support and relocates the Swift
sources and privacy manifest into its package layout. The CocoaPods podspec
continues to reference those same files for compatibility.

Keep the upstream BSD license and review the packaging override when the parent
secure-storage dependency is upgraded. This fork avoids changing credential
storage behavior as part of the macOS build migration.
