#include <xpc/xpc.h>
#include <xpc/connection.h>
#include <dispatch/dispatch.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <png.h>
#include <setjmp.h>
#include <pwd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#define SCREENSHOT_SERVICE "com.apple.systemuiserver.screencapture"

static unsigned int capture_number;

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

static int capture_display(uid_t client_uid)
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

    XImage *image = XGetImage(display, root, 0, 0, width, height, AllPlanes, ZPixmap);
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
    // This initial implementation captures the current X11 display to PNG.
    // An interactive selection UI and recording remain separate work.
    if (xpc_dictionary_get_uint64(request, "message") != 1)
        return;

    int capture_status = capture_display(xpc_connection_get_euid(peer));

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
