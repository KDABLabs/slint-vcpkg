# Corrosion (as of 0.6) installs only CMake scripts/config files, no binaries.
set(VCPKG_BUILD_TYPE release)

vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO corrosion-rs/corrosion
    REF "v${VERSION}"
    SHA512 2b0d1ccafd5472f2938d084995662c586f19cb5cd4ead20fa25e9516d595eb5f756cb2d9abb12dccfa944b52a1f8002c69a1a4d955409c9d194c6d885a6d48ca
    HEAD_REF master
)

# CORROSION_INSTALL_ONLY skips corrosion's own `include(Corrosion)`/`add_subdirectory(test)`,
# so configuring this port never needs a Rust toolchain or network access.
vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        -DCORROSION_INSTALL_ONLY=ON
        -DCORROSION_BUILD_TESTS=OFF
)

vcpkg_cmake_install()
vcpkg_cmake_config_fixup(PACKAGE_NAME Corrosion CONFIG_PATH lib/cmake/Corrosion)

# Corrosion ships only CMake scripts/config files: no headers, no binaries.
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/lib")
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
