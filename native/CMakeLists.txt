cmake_minimum_required(VERSION 3.24)
project(AppWindowTitleBarBridge LANGUAGES CXX)

if(APPLE)
    enable_language(OBJCXX)
    add_library(macos_window_bridge SHARED macos_window_bridge.mm)
    target_compile_features(macos_window_bridge PRIVATE cxx_std_17)
    target_compile_options(macos_window_bridge PRIVATE -fobjc-arc)
    target_link_libraries(macos_window_bridge PRIVATE "-framework AppKit")
    set_target_properties(macos_window_bridge PROPERTIES
        OUTPUT_NAME "macos_window_bridge"
    )
    install(TARGETS macos_window_bridge
        LIBRARY DESTINATION lib/native
        RUNTIME DESTINATION lib/native
    )
    return()
endif()

if(NOT WIN32 OR NOT MSVC)
    message(FATAL_ERROR "Build this Windows App SDK bridge with MSVC on Windows.")
endif()

set(WINDOWS_SDK_VERSION "" CACHE STRING "Windows SDK version (optional; newest installed SDK is used by default)")
set(WINDOWS_KITS_ROOT "" CACHE PATH "Windows Kits/10 root (optional; inferred from the host by default)")
set(WINDOWS_NATIVE_INPUT_ROOT "" CACHE PATH "Prepared Windows App SDK and C++/WinRT input root")
if(NOT WINDOWS_NATIVE_INPUT_ROOT OR NOT IS_DIRECTORY "${WINDOWS_NATIVE_INPUT_ROOT}")
    message(FATAL_ERROR "WINDOWS_NATIVE_INPUT_ROOT is missing. Run the build through python -m tools.build_windows_bridge or python -m tools.build_app.")
endif()

set(FOUNDATION_ROOT "${WINDOWS_NATIVE_INPUT_ROOT}/packages/foundation")
set(INTERACTIVE_ROOT "${WINDOWS_NATIVE_INPUT_ROOT}/packages/interactive")
set(RUNTIME_ROOT "${WINDOWS_NATIVE_INPUT_ROOT}/packages/runtime")
set(GENERATED_ROOT "${WINDOWS_NATIVE_INPUT_ROOT}/generated")

set(CPPWINRT_INCLUDE_DIR "")
if(WINDOWS_KITS_ROOT AND WINDOWS_SDK_VERSION)
    set(CPPWINRT_INCLUDE_DIR "${WINDOWS_KITS_ROOT}/Include/${WINDOWS_SDK_VERSION}/cppwinrt")
else()
    file(GLOB _cppwinrt_candidates
        "$ENV{ProgramFiles}/../Program Files (x86)/Windows Kits/10/Include/*/cppwinrt"
        "$ENV{ProgramFiles}/Windows Kits/10/Include/*/cppwinrt"
    )
    list(SORT _cppwinrt_candidates COMPARE NATURAL ORDER DESCENDING)
    if(_cppwinrt_candidates)
        list(GET _cppwinrt_candidates 0 CPPWINRT_INCLUDE_DIR)
    endif()
endif()
if(NOT CPPWINRT_INCLUDE_DIR OR NOT EXISTS "${CPPWINRT_INCLUDE_DIR}/winrt/base.h")
    message(FATAL_ERROR "Unable to locate the Windows SDK cppwinrt headers. Set WINDOWS_KITS_ROOT and WINDOWS_SDK_VERSION to override detection.")
endif()

add_library(appwindow_titlebar_bridge SHARED appwindow_titlebar_bridge.cpp)
target_compile_features(appwindow_titlebar_bridge PRIVATE cxx_std_20)
target_compile_definitions(appwindow_titlebar_bridge PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN)
target_include_directories(appwindow_titlebar_bridge PRIVATE
    "${GENERATED_ROOT}"
    "${FOUNDATION_ROOT}/include"
    "${INTERACTIVE_ROOT}/include"
    "${RUNTIME_ROOT}/include"
    "${CPPWINRT_INCLUDE_DIR}"
)
target_link_directories(appwindow_titlebar_bridge PRIVATE
    "${FOUNDATION_ROOT}/lib/native/x64"
)
set(BOOTSTRAP_LIB "${FOUNDATION_ROOT}/lib/native/x64/Microsoft.WindowsAppRuntime.Bootstrap.lib")
if(NOT EXISTS "${BOOTSTRAP_LIB}")
    message(FATAL_ERROR "Windows App Runtime bootstrap import library not found: ${BOOTSTRAP_LIB}")
endif()
target_link_libraries(appwindow_titlebar_bridge PRIVATE
    Microsoft.WindowsAppRuntime.Bootstrap
    ole32
    runtimeobject
)
set_target_properties(appwindow_titlebar_bridge PROPERTIES
    OUTPUT_NAME "appwindow_titlebar_bridge"
)

set(BOOTSTRAP_DLL "${FOUNDATION_ROOT}/runtimes/win-x64/native/Microsoft.WindowsAppRuntime.Bootstrap.dll")
if(NOT EXISTS "${BOOTSTRAP_DLL}")
    message(FATAL_ERROR "Windows App Runtime bootstrap DLL not found: ${BOOTSTRAP_DLL}")
endif()
install(TARGETS appwindow_titlebar_bridge
    RUNTIME DESTINATION lib/native
    LIBRARY DESTINATION lib/native
)
install(FILES "${BOOTSTRAP_DLL}" DESTINATION lib/native)
