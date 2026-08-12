#pragma once

#ifdef __cplusplus
extern "C" {
#endif

typedef struct BwmMacMetrics {
    double top;
    double left;
    double right;
    double bottom;
} BwmMacMetrics;

void* bwm_attach(void* ns_view, int toolbar_style);
int bwm_get_metrics(void* ctx, BwmMacMetrics* metrics);
int bwm_set_theme(void* ctx, int theme);
const char* bwm_last_attach_error(void);
const char* bwm_last_error(void* ctx);
void bwm_shutdown(void* ctx);
int bwm_window_minimize(void* ctx);
int bwm_window_maximize(void* ctx);
int bwm_window_toggle_maximize(void* ctx);
int bwm_window_close(void* ctx);
int bwm_window_start_system_move(void* ctx);

#ifdef __cplusplus
}
#endif
