# Slint's Rust core is a static/cdylib archive that doesn't propagate its transitive
# system-library dependencies (e.g. fontconfig) through CMake for consumers when built
# static. Force shared, matching Slint's own upstream default (BUILD_SHARED_LIBS=ON),
# to sidestep that class of problem entirely.
set(VCPKG_LIBRARY_LINKAGE dynamic)

find_program(CARGO_EXECUTABLE cargo)
find_program(RUSTC_EXECUTABLE rustc)
if(NOT CARGO_EXECUTABLE OR NOT RUSTC_EXECUTABLE)
    message(FATAL_ERROR
        "Slint requires a Rust toolchain (cargo + rustc, 1.92 or newer) on PATH to build. "
        "vcpkg does not manage Rust toolchains -- install one from https://rustup.rs and try again.")
endif()

vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO slint-ui/slint
    REF "v${VERSION}"
    SHA512 50cf450292e5e56241a13078df8b579fa7e3a60ce10e73988f0da8c0c4b9aca9135bb7aeaf53a4bd0d11f226f4c6269130dae2cc4b6fb48a0cccbf329e66f10d
    HEAD_REF release/1
)

# The vendored-crates archive lets the actual build run fully offline: it's produced once
# per version by scripts/vendor-crates.sh (a `cargo vendor` snapshot of Slint's own
# Cargo.lock) and published as a release asset on this registry. See README.md for details
# and the "Vendoring Slint's cargo dependencies" note in the plan/design docs.
# TODO: replace with the real published URL once this registry has a GitHub remote.
vcpkg_download_distfile(VENDOR_ARCHIVE
    URLS "https://github.com/REPLACE_ME/slint-vcpkg/releases/download/slint-v${VERSION}/slint-${VERSION}-vendor.tar.zst"
    FILENAME "slint-${VERSION}-vendor.tar.zst"
    SHA512 0abe89ea5b828c4b9eb83a4adf0b89ca56fbd01a1dbe17d28a01cc44e1471117d6026ab8ee43f04d6bd887e914a09a7eb5c2ab2efcb3eab8c33502cc91e85f38
)

# The archive's paths already start with "vendor/...", so extract into SOURCE_PATH itself.
file(ARCHIVE_EXTRACT INPUT "${VENDOR_ARCHIVE}" DESTINATION "${SOURCE_PATH}")

file(MAKE_DIRECTORY "${SOURCE_PATH}/.cargo")
file(COPY_FILE "${CMAKE_CURRENT_LIST_DIR}/cargo-config.toml" "${SOURCE_PATH}/.cargo/config.toml")

vcpkg_check_features(OUT_FEATURE_OPTIONS FEATURE_OPTIONS
    FEATURES
        interpreter               SLINT_FEATURE_INTERPRETER
        live-preview              SLINT_FEATURE_LIVE_PREVIEW
        backend-winit             SLINT_FEATURE_BACKEND_WINIT
        backend-winit-x11         SLINT_FEATURE_BACKEND_WINIT_X11
        backend-winit-wayland     SLINT_FEATURE_BACKEND_WINIT_WAYLAND
        backend-qt                SLINT_FEATURE_BACKEND_QT
        backend-linuxkms          SLINT_FEATURE_BACKEND_LINUXKMS
        backend-linuxkms-noseat   SLINT_FEATURE_BACKEND_LINUXKMS_NOSEAT
        renderer-femtovg          SLINT_FEATURE_RENDERER_FEMTOVG
        renderer-femtovg-wgpu     SLINT_FEATURE_RENDERER_FEMTOVG_WGPU
        renderer-skia             SLINT_FEATURE_RENDERER_SKIA
        renderer-skia-opengl      SLINT_FEATURE_RENDERER_SKIA_OPENGL
        renderer-skia-vulkan      SLINT_FEATURE_RENDERER_SKIA_VULKAN
        sdf-fonts                 SLINT_FEATURE_SDF_FONTS
        software-renderer-path    SLINT_FEATURE_SOFTWARE_RENDERER_PATH
        gettext                   SLINT_FEATURE_GETTEXT
        accessibility             SLINT_FEATURE_ACCESSIBILITY
        testing                   SLINT_FEATURE_TESTING
        system-testing            SLINT_FEATURE_SYSTEM_TESTING
        experimental              SLINT_FEATURE_EXPERIMENTAL
        mcp                       SLINT_FEATURE_MCP
)

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}/api/cpp"
    OPTIONS
        ${FEATURE_OPTIONS}
        -DSLINT_LIBRARY_CARGO_FLAGS=--offline
)

vcpkg_cmake_install()
vcpkg_cmake_config_fixup(PACKAGE_NAME Slint CONFIG_PATH lib/cmake/Slint)
vcpkg_copy_pdbs()

file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include")
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/share")

vcpkg_install_copyright(FILE_LIST
    "${SOURCE_PATH}/LICENSE.md"
    "${SOURCE_PATH}/LICENSES/GPL-3.0-only.txt"
    "${SOURCE_PATH}/LICENSES/LicenseRef-Slint-Royalty-free-2.0.md"
    "${SOURCE_PATH}/LICENSES/LicenseRef-Slint-Software-3.0.md"
)

file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/usage" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")
