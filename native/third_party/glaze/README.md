# Glaze

This directory contains only the `include/glaze` header tree and license from
upstream Glaze v8.3.0, commit
`dce5e0f7ec572725ec369a0bc59a00eeb2270a9a`.

Source: <https://github.com/stephenberry/glaze>

The project vendors the headers instead of the complete upstream repository
because Glaze is used as a header-only dependency.

The vendored tree also retains the per-file notices for the embedded
fast_float, zmij, and xxh64 implementations. Their source links and applicable
license texts are catalogued in the top-level `THIRD_PARTY_NOTICES.md`.
