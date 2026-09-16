# Dart API DL provenance

The Dart API DL source and headers in `native/src` and `native/include` were
copied from Dart SDK 3.13.2, revision
`60a57cd42d64dc03e9f07aa60a2e250755c1ef28`.

Only the files required to call `Dart_InitializeApiDL` and
`Dart_PostCObject_DL` are vendored. They remain under Dart's BSD license in
this directory.
