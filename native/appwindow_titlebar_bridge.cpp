#include "appwindow_titlebar_bridge.h"

#include <Windows.h>
#include <roapi.h>
#include <MddBootstrap.h>
#include <WindowsAppSDK-VersionInfo.h>

#include <mutex>
#include <cstring>
#include <iomanip>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

#include <winrt/Microsoft.UI.h>
#include <winrt/Microsoft.UI.Windowing.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Graphics.h>
#include <winrt/Windows.UI.h>

namespace {

struct BridgeContext {
    std::mutex mutex;
    std::wstring last_error;
    HWND hwnd = nullptr;
    winrt::Microsoft::UI::Windowing::AppWindow app_window{nullptr};
    winrt::Microsoft::UI::Windowing::AppWindowTitleBar title_bar{nullptr};
};

std::mutex g_init_mutex;
bool g_bootstrap_initialized = false;
bool g_apartment_initialized = false;
std::wstring g_last_attach_error;

void set_attach_error(std::wstring message) {
    g_last_attach_error = std::move(message);
}

void set_attach_error(HRESULT error, const wchar_t* operation) {
    std::wostringstream message;
    message << operation << L" failed (HRESULT 0x"
            << std::uppercase << std::hex << std::setw(8) << std::setfill(L'0')
            << static_cast<unsigned int>(error) << L").";
    set_attach_error(message.str());
}

void set_error(BridgeContext* ctx, std::wstring message) {
    if (ctx) ctx->last_error = std::move(message);
}

void set_error(BridgeContext* ctx, HRESULT error, const wchar_t* operation) {
    std::wostringstream message;
    message << operation << L" failed (HRESULT 0x"
            << std::uppercase << std::hex << std::setw(8) << std::setfill(L'0')
            << static_cast<unsigned int>(error) << L").";
    set_error(ctx, message.str());
}

void check_operation(BridgeContext* ctx, HRESULT result, const wchar_t* operation) {
    if (FAILED(result)) {
        if (ctx) set_error(ctx, result, operation);
        else set_attach_error(result, operation);
        throw std::runtime_error("Native bridge operation failed");
    }
}

void check_win32_operation(BridgeContext* ctx, BOOL result, const wchar_t* operation) {
    if (!result) {
        if (ctx) set_error(ctx, HRESULT_FROM_WIN32(GetLastError()), operation);
        else set_attach_error(HRESULT_FROM_WIN32(GetLastError()), operation);
        throw std::runtime_error("Native bridge operation failed");
    }
}

void run_operation(BridgeContext* ctx, const wchar_t* operation, const auto& callback) {
    try {
        callback();
    } catch (const winrt::hresult_error& error) {
        if (ctx) set_error(ctx, error.code(), operation);
        else set_attach_error(error.code(), operation);
        throw std::runtime_error("Native bridge operation failed");
    }
}

HRESULT get_window_id(HWND hwnd, winrt::Microsoft::UI::WindowId* window_id) {
    using GetWindowIdFromWindow = HRESULT(STDAPICALLTYPE*)(HWND, winrt::Microsoft::UI::WindowId*);

    auto framework_udk = GetModuleHandleW(L"Microsoft.Internal.FrameworkUdk.dll");
    if (!framework_udk) {
        framework_udk = LoadLibraryW(L"Microsoft.Internal.FrameworkUdk.dll");
    }
    if (!framework_udk) {
        return HRESULT_FROM_WIN32(GetLastError());
    }

    auto function = reinterpret_cast<GetWindowIdFromWindow>(
        GetProcAddress(framework_udk, "Windowing_GetWindowIdFromWindow"));
    if (!function) {
        return HRESULT_FROM_WIN32(GetLastError());
    }
    return function(hwnd, window_id);
}

bool refresh_metrics(BridgeContext* ctx) {
    if (!ctx->title_bar) {
        set_error(ctx, L"AppWindowTitleBar has not been initialized.");
        return false;
    }
    return true;
}

auto color_reference(uint8_t alpha, uint8_t red, uint8_t green, uint8_t blue) {
    return winrt::box_value(winrt::Windows::UI::Color{alpha, red, green, blue})
        .as<winrt::Windows::Foundation::IReference<winrt::Windows::UI::Color>>();
}

void apply_caption_palette(BridgeContext* ctx, bool dark) {
    const auto transparent = color_reference(0, 0, 0, 0);
    const auto foreground = dark
        ? color_reference(255, 243, 243, 243)
        : color_reference(255, 32, 32, 32);
    const auto hover_background = dark
        ? color_reference(0x18, 255, 255, 255)
        : color_reference(0x14, 0, 0, 0);
    const auto hover_foreground = dark
        ? color_reference(255, 255, 255, 255)
        : color_reference(255, 32, 32, 32);
    const auto pressed_background = dark
        ? color_reference(0x28, 255, 255, 255)
        : color_reference(0x1F, 0, 0, 0);
    const auto pressed_foreground = hover_foreground;
    const auto inactive_foreground = dark
        ? color_reference(255, 138, 138, 138)
        : color_reference(255, 118, 118, 118);
    const auto native_theme = dark
        ? winrt::Microsoft::UI::Windowing::TitleBarTheme::Dark
        : winrt::Microsoft::UI::Windowing::TitleBarTheme::Light;

    run_operation(ctx, L"AppWindowTitleBar::PreferredTheme", [&] {
        ctx->title_bar.PreferredTheme(native_theme);
    });
    run_operation(ctx, L"AppWindowTitleBar caption button palette", [&] {
        ctx->title_bar.ButtonBackgroundColor(transparent);
        ctx->title_bar.ButtonForegroundColor(foreground);
        ctx->title_bar.ButtonHoverBackgroundColor(hover_background);
        ctx->title_bar.ButtonHoverForegroundColor(hover_foreground);
        ctx->title_bar.ButtonPressedBackgroundColor(pressed_background);
        ctx->title_bar.ButtonPressedForegroundColor(pressed_foreground);
        ctx->title_bar.ButtonInactiveBackgroundColor(transparent);
        ctx->title_bar.ButtonInactiveForegroundColor(inactive_foreground);
    });
}

void prepare_runtime() {
    std::scoped_lock lock(g_init_mutex);
    if (!g_apartment_initialized) {
        const auto apartment_result = RoInitialize(RO_INIT_SINGLETHREADED);
        if (SUCCEEDED(apartment_result)) {
            g_apartment_initialized = true;
        } else if (apartment_result != RPC_E_CHANGED_MODE) {
            winrt::check_hresult(apartment_result);
        }
    }

    if (!g_bootstrap_initialized) {
        const PACKAGE_VERSION minimum_version{WINDOWSAPPSDK_RUNTIME_VERSION_UINT64};
        const auto bootstrap_result = MddBootstrapInitialize2(
            WINDOWSAPPSDK_RELEASE_MAJORMINOR,
            WINDOWSAPPSDK_RELEASE_VERSION_TAG_W,
            minimum_version,
            MddBootstrapInitializeOptions_None);
        winrt::check_hresult(bootstrap_result);
        g_bootstrap_initialized = true;
    }
}

int guard_call(BridgeContext* ctx, const auto& callback) {
    try {
        callback();
        return 0;
    } catch (const winrt::hresult_error& error) {
        if (ctx) {
            if (ctx->last_error.empty()) set_error(ctx, error.code(), error.message().c_str());
        } else {
            if (g_last_attach_error.empty()) set_attach_error(error.code(), error.message().c_str());
        }
    } catch (const std::exception& error) {
        std::wstring message(error.what(), error.what() + strlen(error.what()));
        if (ctx) {
            if (ctx->last_error.empty()) set_error(ctx, message);
        } else {
            if (g_last_attach_error.empty()) set_attach_error(message);
        }
    }
    return 1;
}

} // namespace

extern "C" int awtb_prepare() {
    return guard_call(nullptr, [] {
        g_last_attach_error.clear();
        prepare_runtime();
    });
}

extern "C" void* awtb_initialize(void* raw_hwnd) {
    g_last_attach_error.clear();
    BridgeContext* ctx = nullptr;
    if (guard_call(nullptr, [&]() {
        prepare_runtime();

        const auto hwnd = static_cast<HWND>(raw_hwnd);
        if (!IsWindow(hwnd)) {
            set_attach_error(L"The Qt window handle is not valid.");
            throw std::runtime_error("Invalid HWND");
        }

        bool customization_supported = false;
        run_operation(nullptr, L"AppWindowTitleBar::IsCustomizationSupported", [&] {
            customization_supported =
                winrt::Microsoft::UI::Windowing::AppWindowTitleBar::IsCustomizationSupported();
        });
        if (!customization_supported) {
            set_attach_error(L"AppWindowTitleBar customization is unavailable on this Windows installation.");
            throw std::runtime_error("AppWindowTitleBar unavailable");
        }

        ctx = new BridgeContext();

        winrt::Microsoft::UI::WindowId window_id{};
        const auto window_id_result = get_window_id(hwnd, &window_id);
        check_operation(ctx, window_id_result, L"Windowing_GetWindowIdFromWindow");

        run_operation(ctx, L"AppWindow::GetFromWindowId", [&] {
            ctx->app_window = winrt::Microsoft::UI::Windowing::AppWindow::GetFromWindowId(window_id);
        });
        run_operation(ctx, L"AppWindow::TitleBar", [&] {
            ctx->title_bar = ctx->app_window.TitleBar();
        });
        run_operation(ctx, L"AppWindowTitleBar::ExtendsContentIntoTitleBar", [&] {
            ctx->title_bar.ExtendsContentIntoTitleBar(true);
        });
        apply_caption_palette(ctx, false);
        run_operation(ctx, L"AppWindowTitleBar::PreferredHeightOption", [&] {
            ctx->title_bar.PreferredHeightOption(
                winrt::Microsoft::UI::Windowing::TitleBarHeightOption::Tall);
        });
        refresh_metrics(ctx);
        ctx->hwnd = hwnd;
        ctx->last_error.clear();
    }) != 0) {
        if (ctx) delete ctx;
        return nullptr;
    }
    return ctx;
}

extern "C" const wchar_t* awtb_last_attach_error() {
    return g_last_attach_error.c_str();
}

extern "C" int awtb_set_theme(void* raw_ctx, int theme) {
    if (!raw_ctx) return 1;
    BridgeContext* ctx = static_cast<BridgeContext*>(raw_ctx);
    std::scoped_lock lock(ctx->mutex);
    return guard_call(ctx, [ctx, theme] {
        if (!refresh_metrics(ctx)) {
            throw std::runtime_error("AppWindowTitleBar unavailable");
        }
        apply_caption_palette(ctx, theme == 2);
        ctx->last_error.clear();
    });
}

extern "C" int awtb_set_drag_rectangles(void* raw_ctx, const AwtbRect* rects, size_t count) {
    if (!raw_ctx) return 1;
    BridgeContext* ctx = static_cast<BridgeContext*>(raw_ctx);
    std::scoped_lock lock(ctx->mutex);
    return guard_call(ctx, [ctx, rects, count] {
        if (!refresh_metrics(ctx)) {
            throw std::runtime_error("AppWindowTitleBar unavailable");
        }

        std::vector<winrt::Windows::Graphics::RectInt32> regions;
        regions.reserve(count);
        for (size_t index = 0; index < count; ++index) {
            regions.push_back({rects[index].x, rects[index].y, rects[index].width, rects[index].height});
        }
        run_operation(ctx, L"AppWindowTitleBar::SetDragRectangles", [&] {
            ctx->title_bar.SetDragRectangles(
                winrt::array_view<winrt::Windows::Graphics::RectInt32 const>{regions});
        });
        ctx->last_error.clear();
    });
}

extern "C" int awtb_get_metrics(void* raw_ctx, AwtbMetrics* metrics) {
    if (!raw_ctx) return 1;
    BridgeContext* ctx = static_cast<BridgeContext*>(raw_ctx);
    std::scoped_lock lock(ctx->mutex);
    return guard_call(ctx, [ctx, metrics] {
        if (!metrics || !refresh_metrics(ctx)) {
            set_error(ctx, L"Metrics output pointers are invalid.");
            throw std::runtime_error("Invalid metrics output");
        }
        metrics->left = ctx->title_bar.LeftInset();
        metrics->right = ctx->title_bar.RightInset();
        metrics->height = ctx->title_bar.Height();
    });
}

extern "C" int awtb_get_diagnostics(void* raw_ctx, AwtbDiagnostics* diagnostics) {
    if (!raw_ctx) return 1;
    BridgeContext* ctx = static_cast<BridgeContext*>(raw_ctx);
    std::scoped_lock lock(ctx->mutex);
    return guard_call(ctx, [ctx, diagnostics] {
        if (!diagnostics || !ctx->hwnd || !refresh_metrics(ctx)) {
            set_error(ctx, L"Diagnostics output or attached HWND is invalid.");
            throw std::runtime_error("Invalid diagnostics state");
        }

        RECT window_rect{};
        RECT client_rect{};
        POINT client_origin{};
        check_win32_operation(ctx, GetWindowRect(ctx->hwnd, &window_rect), L"GetWindowRect");
        check_win32_operation(ctx, GetClientRect(ctx->hwnd, &client_rect), L"GetClientRect");
        check_win32_operation(ctx, ClientToScreen(ctx->hwnd, &client_origin), L"ClientToScreen");

        SetLastError(ERROR_SUCCESS);
        const auto style = GetWindowLongPtrW(ctx->hwnd, GWL_STYLE);
        if (style == 0 && GetLastError() != ERROR_SUCCESS) {
            check_win32_operation(ctx, FALSE, L"GetWindowLongPtrW(GWL_STYLE)");
        }
        SetLastError(ERROR_SUCCESS);
        const auto ex_style = GetWindowLongPtrW(ctx->hwnd, GWL_EXSTYLE);
        if (ex_style == 0 && GetLastError() != ERROR_SUCCESS) {
            check_win32_operation(ctx, FALSE, L"GetWindowLongPtrW(GWL_EXSTYLE)");
        }

        diagnostics->window_left = window_rect.left;
        diagnostics->window_top = window_rect.top;
        diagnostics->window_width = window_rect.right - window_rect.left;
        diagnostics->window_height = window_rect.bottom - window_rect.top;
        diagnostics->client_origin_x = client_origin.x;
        diagnostics->client_origin_y = client_origin.y;
        diagnostics->client_width = client_rect.right - client_rect.left;
        diagnostics->client_height = client_rect.bottom - client_rect.top;
        diagnostics->style = static_cast<uint64_t>(style);
        diagnostics->ex_style = static_cast<uint64_t>(ex_style);
        diagnostics->extends_content = ctx->title_bar.ExtendsContentIntoTitleBar() ? 1 : 0;
        diagnostics->left_inset = ctx->title_bar.LeftInset();
        diagnostics->right_inset = ctx->title_bar.RightInset();
        diagnostics->title_bar_height = ctx->title_bar.Height();
    });
}

extern "C" const wchar_t* awtb_last_error(void* raw_ctx) {
    if (!raw_ctx) return L"Invalid context pointer.";
    BridgeContext* ctx = static_cast<BridgeContext*>(raw_ctx);
    std::scoped_lock lock(ctx->mutex);
    return ctx->last_error.c_str();
}

extern "C" void awtb_shutdown(void* raw_ctx) {
    if (!raw_ctx) return;
    BridgeContext* ctx = static_cast<BridgeContext*>(raw_ctx);
    {
        std::scoped_lock lock(ctx->mutex);
        ctx->title_bar = nullptr;
        ctx->app_window = nullptr;
        ctx->hwnd = nullptr;
        ctx->last_error.clear();
    }
    delete ctx;
}
