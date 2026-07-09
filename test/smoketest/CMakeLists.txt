cmake_minimum_required(VERSION 3.21)
project(slint_vcpkg_smoketest CXX)

find_package(Slint CONFIG REQUIRED)

add_executable(slint_vcpkg_smoketest main.cpp)
target_link_libraries(slint_vcpkg_smoketest PRIVATE Slint::Slint)
