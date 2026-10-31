# flutter_secure_storage_linux

The linux implementation of [`flutter_secure_storage`][1].

## Phonolite customization

This is a local copy of upstream version 1.2.3, selected by the app's
`dependency_overrides`. The upstream BSD license is retained in `LICENSE`.

`linux/include/Secret.hpp` changes the visible credential label to
`PhonoliteSecureStorage` and the helper label to `PhonoliteSecureStorage Control`.
The lookup schema, account attribute, serialized values and method channel remain
unchanged. Existing entries receive the new credential label on their next write.

The bundled `linux/include/json.hpp` also uses the current literal-operator
declaration spelling so Clang can compile it without deprecation errors. Its
JSON behavior and upstream license are unchanged.

## Usage

This package is [endorsed][2], which means you can simply use `flutter_secure_storage`
normally. This package will be automatically included in your app when you do.

[1]: https://pub.dev/packages/flutter_secure_storage
[2]: https://flutter.dev/docs/development/packages-and-plugins/developing-packages#endorsed-federated-plugin
