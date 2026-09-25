#include <xpc/xpc.h>
#include <xpc/connection.h>
#include <dispatch/dispatch.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/cursorfont.h>
#include <X11/keysym.h>
#include <png.h>
#include <errno.h>
#include <setjmp.h>
#include <pwd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/select.h>
#include <time.h>
#include <unistd.h>

#define SCREENSHOT_SERVICE "com.apple.systemuiserver.screencapture"

static unsigned int capture_number;

struct capture_rect {
    int x, y;
    unsigned int width, height;
};

static void draw_selection(Display *display, Window root, GC gc,
                           int x0, int y0, int x1, int y1)
{
    int x = x0 < x1 ? x0 : x1;
    int y = y0 < y1 ? y0 : y1;
    unsigned int width = x0 < x1 ? x1 - x0 : x0 - x1;
    unsigned int height = y0 < y1 ? y1 - y0 : y0 - y1;
    XDrawRectangle(display, root, gc, x, y, width, height);
    XFlush(display);
}

static int select_capture_rect(Display *display, Window root, struct capture_rect *rect)
{
    Cursor cursor = XCreateFontCursor(display, XC_crosshair);
    GC gc = XCreateGC(display, root, 0, NULL);
    if (!cursor || !gc) {
        if (gc) XFreeGC(display, gc);
        if (cursor) XFreeCursor(display, cursor);
        return -7;
    }

    XSetFunction(display, gc, GXxor);
    XSetForeground(display, gc, WhitePixel(display, DefaultScreen(display)) ^
                                BlackPixel(display, DefaultScreen(display)));
    XSetSubwindowMode(display, gc, IncludeInferiors);
    int grabbed = XGrabPointer(display, root, False,
                               ButtonPressMask | ButtonReleaseMask | PointerMotionMask,
                               GrabModeAsync, GrabModeAsync, root, cursor, CurrentTime);
    if (grabbed != GrabSuccess) {
        XFreeGC(display, gc);
        XFreeCursor(display, cursor);
        return -7;
    }
    XGrabKeyboard(display, root, False, GrabModeAsync, GrabModeAsync, CurrentTime);

    int started = 0, drawn = 0, x0 = 0, y0 = 0, x1 = 0, y1 = 0;
    int result = -8;
    for (;;) {
        if (!XPending(display)) {
            fd_set fds;
            FD_ZERO(&fds);
            FD_SET(ConnectionNumber(display), &fds);
            struct timeval timeout = { .tv_sec = 120 };
            int ready = select(ConnectionNumber(display) + 1, &fds, NULL, NULL, &timeout);
            if (ready < 0 && errno == EINTR) continue;
            if (ready <= 0) break;
        }
        XEvent event;
        XNextEvent(display, &event);
        if (event.type == KeyPress && XLookupKeysym(&event.xkey, 0) == XK_Escape)
            break;
        if (event.type == ButtonPress && event.xbutton.button == Button1) {
            if (drawn) draw_selection(display, root, gc, x0, y0, x1, y1);
            x0 = x1 = event.xbutton.x_root;
            y0 = y1 = event.xbutton.y_root;
            started = 1;
            drawn = 0;
        } else if (event.type == MotionNotify && started) {
            if (drawn) draw_selection(display, root, gc, x0, y0, x1, y1);
            x1 = event.xmotion.x_root;
            y1 = event.xmotion.y_root;
            draw_selection(display, root, gc, x0, y0, x1, y1);
            drawn = 1;
        } else if (event.type == ButtonRelease && event.xbutton.button == Button1 && started) {
            if (drawn) draw_selection(display, root, gc, x0, y0, x1, y1);
            x1 = event.xbutton.x_root;
            y1 = event.xbutton.y_root;
            rect->x = x0 < x1 ? x0 : x1;
            rect->y = y0 < y1 ? y0 : y1;
            rect->width = x0 < x1 ? x1 - x0 : x0 - x1;
            rect->height = y0 < y1 ? y1 - y0 : y0 - y1;
            if (rect->width && rect->height) result = 0;
            drawn = 0;
            break;
        }
    }
    if (drawn) draw_selection(display, root, gc, x0, y0, x1, y1);
    XUngrabKeyboard(display, CurrentTime);
    XUngrabPointer(display, CurrentTime);
    XFreeGC(display, gc);
    XFreeCursor(display, cursor);
    XSync(display, False);
    return result;
}

static void write_png(png_structp png, png_bytep data, png_size_t length)
{
    FILE *file = png_get_io_ptr(png);
    if (fwrite(data, 1, length, file) != length)
        png_error(png, "could not write screenshot");
}

static void flush_png(png_structp png)
{
    FILE *file = png_get_io_ptr(png);
    if (fflush(file) != 0)
        png_error(png, "could not flush screenshot");
}

static unsigned char pixel_component(unsigned long pixel, unsigned long mask)
{
    if (!mask)
        return 0;
    unsigned int shift = 0;
    while (!(mask & 1)) {
        mask >>= 1;
        shift++;
    }
    unsigned long component = (pixel >> shift) & mask;
    return (unsigned char)((component * 255 + mask / 2) / mask);
}

static int capture_display(uid_t client_uid, int interactive)
{
    Display *display = XOpenDisplay(NULL);
    if (!display)
        return -1;

    Window root = XDefaultRootWindow(display);
    Window ignored_root;
    int ignored_x, ignored_y;
    unsigned int width, height, ignored_border, ignored_depth;
    if (!XGetGeometry(display, root, &ignored_root, &ignored_x, &ignored_y,
                      &width, &height, &ignored_border, &ignored_depth) ||
        !width || !height || width > 16384 || height > 16384) {
        XCloseDisplay(display);
        return -2;
    }

    struct capture_rect rect = { 0, 0, width, height };
    if (interactive) {
        int selection_status = select_capture_rect(display, root, &rect);
        if (selection_status) {
            XCloseDisplay(display);
            return selection_status;
        }
    }
    width = rect.width;
    height = rect.height;
    XImage *image = XGetImage(display, root, rect.x, rect.y, width, height, AllPlanes, ZPixmap);
    if (!image) {
        XCloseDisplay(display);
        return -3;
    }

    struct passwd *account = getpwuid(client_uid);
    char guest_home[4096];
    const char *home = account && account->pw_dir ? account->pw_dir : getenv("HOME");
    struct stat guest_home_info;
    if (account && account->pw_name &&
        snprintf(guest_home, sizeof(guest_home), "/Users/%s", account->pw_name) < sizeof(guest_home) &&
        stat(guest_home, &guest_home_info) == 0 && S_ISDIR(guest_home_info.st_mode))
        home = guest_home;
    if (!home || !*home)
        home = "/tmp";
    char desktop[4096];
    char filename[4096];
    time_t now = time(NULL);
    struct tm local_time;
    char timestamp[32];
    localtime_r(&now, &local_time);
    strftime(timestamp, sizeof(timestamp), "%Y%m%d-%H%M%S", &local_time);
    if (snprintf(desktop, sizeof(desktop), "%s/Desktop", home) >= sizeof(desktop) ||
        snprintf(filename, sizeof(filename), "%s/Screenshot-%s-%u.png", desktop,
                 timestamp, ++capture_number) >= sizeof(filename)) {
        XDestroyImage(image);
        XCloseDisplay(display);
        return -4;
    }
    mkdir(desktop, 0700);

    FILE *file = fopen(filename, "wb");
    png_structp png = file ? png_create_write_struct(PNG_LIBPNG_VER_STRING, NULL, NULL, NULL) : NULL;
    png_infop info = png ? png_create_info_struct(png) : NULL;
    unsigned char *pixels = NULL;
    png_bytep *rows = NULL;
    int result = file ? -6 : -5;
    if (png && info) {
        pixels = malloc((size_t)width * height * 3);
        rows = malloc((size_t)height * sizeof(*rows));
        if (pixels && rows) {
            for (unsigned int y = 0; y < height; y++) {
                rows[y] = pixels + (size_t)y * width * 3;
                for (unsigned int x = 0; x < width; x++) {
                    unsigned long pixel = XGetPixel(image, x, y);
                    unsigned char *rgb = rows[y] + (size_t)x * 3;
                    rgb[0] = pixel_component(pixel, image->red_mask);
                    rgb[1] = pixel_component(pixel, image->green_mask);
                    rgb[2] = pixel_component(pixel, image->blue_mask);
                }
            }
            if (!setjmp(png_jmpbuf(png))) {
                png_set_write_fn(png, file, write_png, flush_png);
                png_set_IHDR(png, info, width, height, 8, PNG_COLOR_TYPE_RGB,
                             PNG_INTERLACE_NONE, PNG_COMPRESSION_TYPE_DEFAULT,
                             PNG_FILTER_TYPE_DEFAULT);
                png_write_info(png, info);
                png_write_image(png, rows);
                png_write_end(png, info);
                result = 0;
            }
        }
    }
    free(rows);
    free(pixels);
    if (png)
        png_destroy_write_struct(&png, &info);
    if (file)
        fclose(file);
    if (result)
        unlink(filename);
    XDestroyImage(image);
    XCloseDisplay(display);
    return result;
}

static void handle_request(xpc_connection_t peer, xpc_object_t request)
{
    if (xpc_get_type(request) != XPC_TYPE_DICTIONARY)
        return;

    // Screenshot.app sends { message: 1, nowait: true, args: ["-uUpi"] }.
    // The -i option selects an X11 region before saving a PNG.
    // Toolbar controls, window selection, and recording remain separate work.
    if (xpc_dictionary_get_uint64(request, "message") != 1)
        return;

    int interactive = 0;
    xpc_object_t args = xpc_dictionary_get_value(request, "args");
    if (args && xpc_get_type(args) == XPC_TYPE_ARRAY) {
        for (size_t i = 0; i < xpc_array_get_count(args); i++) {
            const char *arg = xpc_array_get_string(args, i);
            if (arg && arg[0] == '-' && strchr(arg, 'i'))
                interactive = 1;
        }
    }
    int capture_status = capture_display(xpc_connection_get_euid(peer), interactive);

    xpc_object_t reply = xpc_dictionary_create_reply(request);
    if (reply) {
        xpc_dictionary_set_int64(reply, "status", capture_status);
        xpc_connection_send_message(peer, reply);
        xpc_release(reply);
    }
}

int main(void)
{
    xpc_connection_t listener = xpc_connection_create_mach_service(
        SCREENSHOT_SERVICE, NULL, XPC_CONNECTION_MACH_SERVICE_LISTENER);
    if (!listener)
        return 1;

    xpc_connection_set_event_handler(listener, ^(xpc_object_t event) {
        if (xpc_get_type(event) != XPC_TYPE_CONNECTION)
            return;

        xpc_connection_t peer = event;
        xpc_connection_set_event_handler(peer, ^(xpc_object_t request) {
            handle_request(peer, request);
        });
        xpc_connection_resume(peer);
    });
    xpc_connection_resume(listener);
    dispatch_main();
}
