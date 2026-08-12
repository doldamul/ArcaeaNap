#pragma once

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#define AWTB_EXPORT __declspec(dllexport)
#else
#define AWTB_EXPORT
#endif

extern "C" {

struct AwtbRect {
    int x;
    int y;
    int width;
    int height;
};

struct AwtbMetrics {
    int left;
    int right;
    int height;
};

struct AwtbDiagnostics {
    int window_left;
    int window_top;
    int window_width;
    int window_height;
    int client_origin_x;
    int client_origin_y;
    int client_width;
    int client_height;
    uint64_t style;
    uint64_t ex_style;
    int extends_content;
    int left_inset;
    int right_inset;
    int title_bar_height;
};

AWTB_EXPORT int awtb_prepare();
AWTB_EXPORT void* awtb_initialize(void* hwnd);
AWTB_EXPORT int awtb_set_theme(void* ctx, int theme);
AWTB_EXPORT int awtb_set_drag_rectangles(void* ctx, const AwtbRect* rects, size_t count);
AWTB_EXPORT int awtb_get_metrics(void* ctx, AwtbMetrics* metrics);
AWTB_EXPORT int awtb_get_diagnostics(void* ctx, AwtbDiagnostics* diagnostics);
AWTB_EXPORT const wchar_t* awtb_last_attach_error();
AWTB_EXPORT const wchar_t* awtb_last_error(void* ctx);
AWTB_EXPORT void awtb_shutdown(void* ctx);

}
