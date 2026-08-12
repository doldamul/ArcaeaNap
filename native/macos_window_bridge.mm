#include "macos_window_bridge.h"

#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

#include <algorithm>
#include <string>
#import <objc/runtime.h>

namespace {

struct BwmContext;

// Global error for attachment failures
std::string g_last_attach_error;

void set_attach_error(const char* message) {
    g_last_attach_error = message ? message : "macOS Cocoa window bridge failed.";
}
void set_attach_error(NSString* message) {
    const char* utf8 = message.UTF8String;
    set_attach_error(utf8 ? utf8 : "macOS Cocoa window bridge failed.");
}

} // Close anonymous namespace

@interface BwmFullscreenObserver : NSObject
@property (weak) NSWindow *window;
@end

@implementation BwmFullscreenObserver
- (void)onWindowWillEnterFullScreen:(NSNotification *)notification {
    if (self.window.toolbar) {
        [self.window.toolbar setVisible:NO];
    }
}
- (void)onWindowDidExitFullScreen:(NSNotification *)notification {
    if (self.window.toolbar) {
        [self.window.toolbar setVisible:YES];
    }
}
@end

namespace {

struct BwmContext {
    NSWindow* window = nil;
    BwmFullscreenObserver* observer = nil;
    std::string last_error;
};

void set_error(BwmContext* ctx, const char* message) {
    if (ctx) ctx->last_error = message ? message : "macOS Cocoa window bridge failed.";
}

bool has_window(BwmContext* ctx) {
    if (ctx && ctx->window) {
        return true;
    }
    set_error(ctx, "The Qt Cocoa view is not attached to an NSWindow.");
    return false;
}

void clear_error(BwmContext* ctx) {
    if (ctx) ctx->last_error.clear();
}

double layout_top_inset(NSWindow* window) {
    const NSRect frame = window.frame;
    const NSRect layout = window.contentLayoutRect;
    return std::max(0.0, static_cast<double>(NSHeight(frame) - NSMaxY(layout)));
}

double traffic_light_left_inset(NSWindow* window) {
    NSButton* btn = [window standardWindowButton:NSWindowZoomButton];
    if (!btn) btn = [window standardWindowButton:NSWindowCloseButton];
    if (!btn || !btn.window || !window.contentView) {
        return 0.0;
    }

    const NSRect button = [btn convertRect:btn.bounds
                                    toView:window.contentView];
    if (button.size.width <= 0.0) {
        return 0.0;
    }
    // Keep a small breathing room between the traffic lights and QML content.
    return std::max(0.0, static_cast<double>(NSMaxX(button)) + 12.0);
}

}  // namespace

extern "C" void* bwm_attach(void* raw_view, int toolbar_style) {
    g_last_attach_error.clear();
    if (!raw_view) {
        set_attach_error("Qt did not provide a Cocoa view handle.");
        return nullptr;
    }

    NSView* view = (__bridge NSView*)raw_view;
    NSWindow* window = view.window;
    if (!window) {
        set_attach_error("The Qt Cocoa view has no owning NSWindow yet.");
        return nullptr;
    }

    BwmContext* ctx = new BwmContext();
    ctx->window = window;

    NSWindowStyleMask style = window.styleMask;
    [window setStyleMask:(style | NSWindowStyleMaskFullSizeContentView)];
    [window setTitlebarAppearsTransparent:YES];
    [window setTitleVisibility:NSWindowTitleHidden];

    // Qt가 창 스타일을 강제로 덮어씌우는 것을 방지하기 위해 창 제목을 비웁니다.
    [window setTitle:@""];

    if (toolbar_style > 0) {
        NSString *identifier = [NSString stringWithFormat:@"DummyToolbar_%p", window];
        NSToolbar *dummyToolbar = [[NSToolbar alloc] initWithIdentifier:identifier];
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 110000
        if (@available(macOS 11.0, *)) {
            window.toolbarStyle = (toolbar_style == 2) ? NSWindowToolbarStyleUnifiedCompact : NSWindowToolbarStyleUnified;
        }
#endif
        window.toolbar = dummyToolbar;
    }

    ctx->observer = [[BwmFullscreenObserver alloc] init];
    ctx->observer.window = window;

    [[NSNotificationCenter defaultCenter] addObserver:ctx->observer
                                             selector:@selector(onWindowWillEnterFullScreen:)
                                                 name:NSWindowWillEnterFullScreenNotification
                                               object:window];
    [[NSNotificationCenter defaultCenter] addObserver:ctx->observer
                                             selector:@selector(onWindowDidExitFullScreen:)
                                                 name:NSWindowDidExitFullScreenNotification
                                               object:window];

    [window.contentView setNeedsLayout:YES];
    [window.contentView layoutSubtreeIfNeeded];
    return ctx;
}

extern "C" const char* bwm_last_attach_error(void) {
    return g_last_attach_error.c_str();
}

extern "C" int bwm_get_metrics(void* raw_ctx, BwmMacMetrics* metrics) {
    BwmContext* ctx = static_cast<BwmContext*>(raw_ctx);
    clear_error(ctx);
    if (!metrics || !has_window(ctx)) {
        return 1;
    }

    [ctx->window.contentView setNeedsLayout:YES];
    [ctx->window.contentView layoutSubtreeIfNeeded];
    const NSEdgeInsets safe = ctx->window.contentView.safeAreaInsets;
    const double layout_top = layout_top_inset(ctx->window);

    metrics->top = std::max(static_cast<double>(safe.top), layout_top);
    metrics->left = std::max(
        static_cast<double>(safe.left), traffic_light_left_inset(ctx->window));
    metrics->right = std::max(0.0, static_cast<double>(safe.right));
    metrics->bottom = std::max(0.0, static_cast<double>(safe.bottom));
    clear_error(ctx);
    return 0;
}

extern "C" int bwm_set_theme(void* raw_ctx, int theme) {
    BwmContext* ctx = static_cast<BwmContext*>(raw_ctx);
    clear_error(ctx);
    if (!has_window(ctx)) {
        return 1;
    }
    if (theme == 2) {
        [ctx->window setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]];
    } else if (theme == 1) {
        [ctx->window setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameAqua]];
    } else {
        set_error(ctx, "Unsupported macOS window theme value.");
        return 1;
    }
    clear_error(ctx);
    return 0;
}

extern "C" const char* bwm_last_error(void* raw_ctx) {
    BwmContext* ctx = static_cast<BwmContext*>(raw_ctx);
    if (!ctx) return "Invalid context pointer.";
    return ctx->last_error.c_str();
}

extern "C" void bwm_shutdown(void* raw_ctx) {
    if (!raw_ctx) return;
    BwmContext* ctx = static_cast<BwmContext*>(raw_ctx);
    if (ctx->observer) {
        [[NSNotificationCenter defaultCenter] removeObserver:ctx->observer];
        ctx->observer = nil;
    }
    delete ctx;
}

extern "C" int bwm_window_minimize(void* raw_ctx) {
    BwmContext* ctx = static_cast<BwmContext*>(raw_ctx);
    if (!has_window(ctx)) return 1;
    [ctx->window miniaturize:nil];
    return 0;
}

extern "C" int bwm_window_maximize(void* raw_ctx) {
    BwmContext* ctx = static_cast<BwmContext*>(raw_ctx);
    if (!has_window(ctx)) return 1;
    if (![ctx->window isZoomed]) {
        [ctx->window zoom:nil];
    }
    return 0;
}

extern "C" int bwm_window_toggle_maximize(void* raw_ctx) {
    BwmContext* ctx = static_cast<BwmContext*>(raw_ctx);
    if (!has_window(ctx)) return 1;
    [ctx->window zoom:nil];
    return 0;
}

extern "C" int bwm_window_close(void* raw_ctx) {
    BwmContext* ctx = static_cast<BwmContext*>(raw_ctx);
    if (!has_window(ctx)) return 1;
    [ctx->window close];
    return 0;
}

extern "C" int bwm_window_start_system_move(void* raw_ctx) {
    BwmContext* ctx = static_cast<BwmContext*>(raw_ctx);
    if (!has_window(ctx)) return 1;
    NSEvent *event = [NSApp currentEvent];
    if (event) {
        [ctx->window performWindowDragWithEvent:event];
    }
    return 0;
}
