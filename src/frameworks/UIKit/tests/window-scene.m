#import <UIKit/UIWindowScene.h>
#include <dlfcn.h>
#include <stdio.h>
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); return 1; } } while (0)

int main(int argc, char **argv)
{
    @autoreleasepool {
        CHECK(argc == 2);
        void *library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
        if (!library) { fprintf(stderr, "dlopen: %s\n", dlerror()); return 2; }
        Class sceneClass = NSClassFromString(@"UIWindowScene");
        CHECK(sceneClass != Nil);
        // The docs forbid creating window scenes directly, so only the class and its
        // selectors are checked here.
        CHECK([sceneClass instancesRespondToSelector:@selector(windows)]);
        CHECK([sceneClass instancesRespondToSelector:@selector(keyWindow)]);
        // Members whose types are not implemented yet must not appear as stubs.
        CHECK(![sceneClass instancesRespondToSelector:@selector(screen)]);
        CHECK(![sceneClass instancesRespondToSelector:@selector(traitCollection)]);
        puts("PASS UIKit UIWindowScene windows and keyWindow");
    }
    return 0;
}
