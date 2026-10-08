# Private SwiftUI source build interface

Entrypoint: `python3 build.py --inputs inputs.json --runtime-root /private/image/usr/local/libexec/darling --workspace /private/swiftui-build --jobs 2`.

The runtime root is read-only input. All generated/install artifacts belong in the separate workspace. The entrypoint serializes Ninja with the shared Darling heavy-build flock. It supports Darwin arm64 only, and rejects other architectures.

Input schema 1: `architecture`, `sources` (path, exact commit, optional allow_recorded_changes), and `targets` (name, argv, inputs, outputs, optional env). Arguments may contain `{runtime_root}` and `{workspace}`. Each target must declare actual source/header/module/library dependencies and output artifacts. Pinned toolchain/resource/SDK paths appear explicitly in argv and inputs. Link targets must use strict undefined-symbol resolution, not dynamic lookup. Installation targets copy into workspace/image, never the input runtime.

Result contract: workspace/result.json records input-manifest SHA256, runtime root, source commits/status, build exit, log, artifact hashes and sizes, and whether Ninja reported no work. `actual_app_verified` is false until separate native guest evidence exists. A compile-only manifest does not attest link/install success.

Current integration is under development: successful Swift object compilation is established; link/install closure and fresh actual-app validation are not established yet. Prefix tooling should fail if the supplied manifest lacks those required targets rather than silently omit SwiftUI.
