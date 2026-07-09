// Functional smoke test for the slint vcpkg port: proves the installed package is a
// working library, not just something that compiled. Requires the `interpreter`
// feature. Does not open a window, so it needs no display server.
#include <slint-interpreter.h>

#include <iostream>

int main()
{
    slint::interpreter::ComponentCompiler compiler;
    auto result = compiler.build_from_source(
            "export component App inherits Window { "
            "  width: 300px; height: 200px; "
            "  out property <string> greeting: \"hello from slint\"; "
            "}",
            "memory://smoketest.slint");
    if (!result) {
        std::cerr << "smoketest: compile failed" << std::endl;
        return 1;
    }

    auto instance = result->create();

    auto greeting = instance->get_property("greeting");
    if (!greeting || !greeting->to_string() || *greeting->to_string() != "hello from slint") {
        std::cerr << "smoketest: property round-trip failed" << std::endl;
        return 1;
    }

    std::cout << "smoketest OK: compiled, instantiated, and read back property: "
              << std::string(*greeting->to_string()) << std::endl;
    return 0;
}
