#!/bin/sh
# Build the portbridge-ffi Rust crate and (re)generate its Swift bindings.
#
# Runs as the FIRST build phase of the PortBridge target (before Compile
# Sources). Produces, in apps/macos/Generated/ (gitignored — never checked in,
# inheriting #58's "generated artifacts stay out of git" philosophy):
#
#   Generated/portbridge_ffi.swift        compiled into the PortBridge target
#   Generated/ffimod/portbridge_ffiFFI.h  C FFI header
#   Generated/ffimod/module.modulemap     so `import portbridge_ffiFFI` resolves
#
# The staticlib (libportbridge_ffi.a) is produced by cargo at the repo-root
# target/debug and linked via LIBRARY_SEARCH_PATHS + OTHER_LDFLAGS.
#
# These outputs are declared as outputPaths of this phase so XCBuild schedules
# it before Compile Sources, which consumes Generated/portbridge_ffi.swift.

set -eu

# Xcode Run Script PATH does not include ~/.cargo/bin; add it so cargo resolves.
export PATH="$HOME/.cargo/bin:$PATH"

# Repo root holds the cargo workspace (portbridge-ffi is a workspace member, so
# its artifacts land in the repo-root target/, not a crate-local one). Capture
# the absolute path: uniffi's library-mode bindgen shells out to
# `cargo metadata`, which must run with the CWD inside the workspace — Xcode
# runs this script with CWD = $SRCROOT (apps/macos), outside the workspace.
REPO_ROOT="$(cd "$SRCROOT/../.." && pwd)"
TARGET_DIR="$REPO_ROOT/target/debug"
GEN_DIR="$SRCROOT/Generated"
FFIMOD_DIR="$GEN_DIR/ffimod"

mkdir -p "$FFIMOD_DIR"
cd "$REPO_ROOT"

# 1) Build the Rust crate (cdylib + staticlib). Host arch (arm64) only.
cargo build -p portbridge-ffi

# 2) Generate Swift bindings from the freshly built dylib via the embedded
#    uniffi-bindgen bin (uniffi-bindgen is not on PATH).
cargo run -p portbridge-ffi --bin uniffi-bindgen -- \
  generate --library "$TARGET_DIR/libportbridge_ffi.dylib" \
  --language swift --out-dir "$GEN_DIR"

# 3) Wire the C FFI module for swiftc: the header + a module map named
#    module.modulemap (auto-discovery in SWIFT_INCLUDE_PATHS requires that name;
#    uniffi emits it as portbridge_ffiFFI.modulemap).
cp "$GEN_DIR/portbridge_ffiFFI.h" "$FFIMOD_DIR/portbridge_ffiFFI.h"
cp "$GEN_DIR/portbridge_ffiFFI.modulemap" "$FFIMOD_DIR/module.modulemap"

echo "build-ffi: bindings generated in $GEN_DIR"
