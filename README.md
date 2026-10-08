# Private SwiftUI source build interface

Entrypoint: `python3 build.py --inputs inputs.json --runtime-root /private/image/usr/local/libexec/darling --workspace /private/swiftui-build --jobs 2`.

The runtime root is read-only input. All generated/install artifacts belong in the separate workspace. The entrypoint serializes Ninja with the shared Darling heavy-build flock. It supports Darwin arm64 only, and rejects other architectures.

Input schema 1: `architecture`, `sources` (path, exact commit, optional allow_recorded_changes), and `targets` (name, argv, inputs, outputs, optional env). Arguments may contain `{runtime_root}` and `{workspace}`. Each target must declare actual source/header/module/library dependencies and output artifacts. Pinned toolchain/resource/SDK paths appear explicitly in argv and inputs. Link targets must use strict undefined-symbol resolution, not dynamic lookup. Installation targets copy into workspace/image, never the input runtime.

Result contract: workspace/result.json records input-manifest SHA256, runtime root, source commits/status, build exit, log, artifact hashes and sizes, and whether Ninja reported no work. `actual_app_verified` is false until separate native guest evidence exists. A compile-only manifest does not attest link/install success.

Current integration is under development: successful Swift object compilation is established; link/install closure and fresh actual-app validation are not established yet. Prefix tooling should fail if the supplied manifest lacks those required targets rather than silently omit SwiftUI.

## Full integration manifest and default target

`full-source-inputs.json` declares 123 source/link/install targets. `integration.link_targets` lists every required strict link; `integration.install_targets` lists the final installation. Installation waits for every linked binary, writes only workspace/image, checks arm64, and creates canonical framework symlinks. The manifest is private-input-specific and records all pinned source paths; it does not promise portability to arbitrary SDK/runtime versions. `make_manifest.py` regenerates it from the recovered exact commands.

CMake builds target `SwiftUI` in ALL by default. Configure with DARLING_SWIFTUI_INPUTS and DARLING_SWIFTUI_RUNTIME_ROOT; missing inputs fail configuration. The target delegates incremental work to Ninja. All expensive commands share a serial pool (a Swift driver may use two jobs), under the shared flock. An inherited lock fd is supported when necessary; ordinary callers should release the runtime-build lock before invocation.

Full fresh verification currently compiles all source objects and links all seven support libraries, then fails the final SwiftUI link on 87 missing runtime APIs. No install target runs and result integration_ready remains false. Repeating completed source/support targets reports no work. A default gate must preserve this failure rather than report a complete SwiftUI runtime.

`adaptations/` retains the recovered stage/SDK compatibility patches, including the generic transition descriptor emission fix. The stage script uses private historical paths; it is a recovery recipe, not a portable package builder. The full manifest fingerprints staged files. Retained SDK resources and host macro tools remain provenance limitations; successful source compilation does not establish Apple binary ABI compatibility.
