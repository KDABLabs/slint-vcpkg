# slint-vcpkg

> **Experimental / work in progress.** This registry is early and not yet battle-tested
> -- expect rough edges, breaking changes, and incomplete feature coverage (see "Known
> limitations" below). Feedback and issues welcome, but don't depend on stability yet.

An unofficial [vcpkg](https://vcpkg.io) registry for [Slint](https://slint.dev/), the
declarative C++/Rust GUI toolkit. Provides `slint` and `corrosion` (the CMake/Rust
integration Slint's C++ API is built with).

There is no official Slint vcpkg port yet -- see
[microsoft/vcpkg#33824](https://github.com/microsoft/vcpkg/issues/33824) and
[slint-ui/slint#6085](https://github.com/slint-ui/slint/discussions/6085). The blocker
has always been that vcpkg's CI forbids network access during builds, and a normal
Slint build needs the network twice: once for CMake to fetch Corrosion, once for
`cargo` to fetch crates.io dependencies. This registry resolves both:

- **Corrosion** is, as of v0.6, pure CMake with no Rust component of its own to build --
  `ports/corrosion` installs it with zero network access and zero cargo invocations.
- **Slint's own crate graph** is vendored ahead of time (see "Adding a new version"
  below) and shipped as a pinned, hashed distfile, so the actual `vcpkg install slint`
  step runs `cargo` with `--offline` against a local vendor directory instead of
  crates.io.

## Using this registry

Add it to your project's `vcpkg-configuration.json`:

```json
{
  "default-registry": {
    "kind": "git",
    "repository": "https://github.com/microsoft/vcpkg",
    "baseline": "<a recent microsoft/vcpkg commit>"
  },
  "registries": [
    {
      "kind": "git",
      "repository": "<URL of this repository>",
      "baseline": "<a commit of this repository>",
      "packages": ["slint", "corrosion"]
    }
  ]
}
```

Then depend on `slint` from your `vcpkg.json` as usual. In your `CMakeLists.txt`:

```cmake
find_package(Slint CONFIG REQUIRED)
target_link_libraries(main PRIVATE Slint::Slint)
```

### Prerequisites

- A Rust toolchain (`cargo`/`rustc` 1.92+) on `PATH`. vcpkg does not manage Rust
  toolchains -- install one from <https://rustup.rs>.
- CMake 3.21+.
- Network access is **not** required at install time for the default feature set
  (`interpreter`, `backend-winit`, `renderer-femtovg`, `accessibility`, `testing`),
  thanks to the vendored-crates mechanism above.

`slint` is always built as a **shared library**, regardless of the triplet's default
linkage (see "Implementation notes" below for why).

### Known limitations

- `backend-qt`: requires Qt 5.15+ or 6.2+ separately installed and discoverable via
  `CMAKE_PREFIX_PATH`. Not provided by this registry.
- `renderer-skia` / `renderer-skia-opengl` / `renderer-skia-vulkan`: Skia is fetched by
  the `skia-safe` Rust crate's own build script (typically a prebuilt binary download),
  independently of cargo's normal crate-download mechanism. Vendoring crates.io sources
  does not cover this -- expect these features to still need network access. Not yet
  validated.
- `gettext`: requires gettext installed on the system. Not provided by this registry.
- `backend-linuxkms`: requires `libseat` installed on the system.
- Bare-metal/freestanding builds (`SLINT_FEATURE_FREESTANDING` upstream) are not
  exposed as a feature yet.
- The vendored-crates archive is built from Slint's full workspace `Cargo.lock`
  (includes examples/tests/etc., not just the `api/cpp` dependency graph) for
  simplicity, at the cost of a larger archive than strictly necessary.

## Testing

`test/smoketest` is a minimal interpreter-based program that compiles a trivial
`.slint` snippet, instantiates it, and reads a property back -- proving the installed
package actually works, not just that it configured/compiled/linked. It needs no
display server. CI runs it after every `vcpkg install slint`; to run it yourself
against a local install:

```sh
cmake -S test/smoketest -B test/smoketest/build \
    -DCMAKE_TOOLCHAIN_FILE=<vcpkg-root>/scripts/buildsystems/vcpkg.cmake
cmake --build test/smoketest/build
./test/smoketest/build/slint_vcpkg_smoketest
```

## Implementation notes / gotchas

Things that weren't obvious while building this, kept here so they don't get
rediscovered the hard way:

- **The vendor archive's paths already start with `vendor/...`** (it's produced by
  `tar`-ing the directory `cargo vendor` creates). `portfile.cmake` extracts it into
  `"${SOURCE_PATH}"`, not `"${SOURCE_PATH}/vendor"` -- extracting into the latter
  double-nests it into `vendor/vendor/...` and every crate lookup fails.
- **`cargo vendor` must cover every *optional* dependency, not just the ones actually
  activated.** Cargo needs a manifest for every optional dependency listed in
  `Cargo.toml` to resolve the full feature graph, even ones your enabled features never
  turn on. Slint's `slint-cpp` crate has ESP32-only optional deps (`esp-backtrace`,
  `esp-println`) that are irrelevant to every feature this port exposes, but omitting
  them from the vendor set still breaks `--offline` resolution outright. This is why
  `vendor-crates.sh` vendors the *entire* workspace `Cargo.lock` rather than trying to
  scope it down to just what `api/cpp` needs.
- **vcpkg's default (static) triplet linkage breaks the build for consumers.** Rust
  static libraries don't propagate their transitive system-library dependencies (e.g.
  `fontconfig`, pulled in by the `fontique` crate) through CMake's exported targets the
  way a normal C++ static library would. A consumer linking `Slint::Slint` statically
  gets `undefined reference to Fc*` at *their* link time, not ours. `portfile.cmake`
  forces `VCPKG_LIBRARY_LINKAGE dynamic` to sidestep this, matching Slint's own
  upstream default (`BUILD_SHARED_LIBS=ON`) rather than trying to enumerate every
  transitive system library per enabled feature.
- **Testing the vendoring pipeline before publishing a release asset:** you don't need
  a real remote URL to test `vcpkg_download_distfile` locally. Drop the archive into
  vcpkg's `downloads/` directory under the exact `FILENAME` the portfile expects
  (`slint-<version>-vendor.tar.zst`) -- vcpkg finds it there by hash and skips the
  network fetch entirely, so you can validate the whole offline build against a
  placeholder URL before anything is actually published.

## Adding a new Slint version

1. Generate and inspect the vendored-crates archive:

   ```sh
   ./scripts/vendor-crates.sh 1.18.0
   ```

   This clones the tag, runs `cargo vendor --locked`, and prints the archive's path
   and SHA512.

2. Publish that archive as a release asset on this repository, tagged
   `slint-v1.18.0-assets` -- not `slint-v1.18.0`, to avoid implying the tag itself is
   the Slint release; it only exists to host the vendor archive. This is the one-time
   network cost per version; end users installing from the registry never pay it.

3. Bump the port and regenerate the versions database:

   ```sh
   ./scripts/add-version.sh 1.18.0 \
       --vendor-url https://github.com/<owner>/slint-vcpkg/releases/download/slint-v1.18.0-assets/slint-1.18.0-vendor.tar.zst \
       --vendor-sha512 <printed by vendor-crates.sh>
   ```

   Requires a `vcpkg` binary on `PATH` (or `VCPKG=/path/to/vcpkg`) -- any vcpkg
   checkout works, it's used purely as a generic versioning tool here.

4. Review the diff (`ports/slint/vcpkg.json`, `ports/slint/portfile.cmake`,
   `versions/`), test locally with `--overlay-ports=./ports`, then commit.

Bumping `corrosion` follows the same shape but without any vendoring step (it never
touches cargo), so `vcpkg x-add-version` after updating its `vcpkg.json`/`portfile.cmake`
is enough.

## Upstreaming

Both `ports/corrosion` and `ports/slint` are written to match microsoft/vcpkg's own
port conventions, so they could plausibly be proposed there directly:

- `ports/corrosion` is generic infrastructure, not Slint-specific, and has no
  network-during-build issue at all -- it's a reasonable standalone contribution
  regardless of what happens with `slint`.
- `ports/slint` still has the residual risk noted above around `skia-safe`'s own
  network fetching for the `renderer-skia*` features; the default feature set does not
  hit that path.
