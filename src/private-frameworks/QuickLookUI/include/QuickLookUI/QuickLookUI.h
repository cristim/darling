/*
	QuickLookUI.private

	Apple's private framework behind the Quick Look preview UI. Nine of the local
	apps link it, binding seven classes.

	Declared so the classes can be compiled, and so callers building against this
	framework see the same interfaces. The apps reach these classes through the
	Objective-C runtime rather than the linker for the class objects themselves, so
	the header is here for the build.

	Subclass fidelity is limited by the headers on this system. NSView.h, NSPanel.h
	and NSFont.h all pull in ApplicationServices, which has no headers here, so
	QLPreviewView and QLPreviewPanel are declared over NSObject rather than NSView
	and NSPanel. The class symbols are emitted either way. Every app linking this
	framework is itself blocked on AppKit, so the superclass only becomes
	observable once AppKit exists; at that point these two should move onto their
	real bases.
*/

#import <Foundation/Foundation.h>

@class QLPreviewDocument;

@interface QLPreviewDocument : NSObject
- (instancetype)initWithFileURL:(NSURL*)url;
@property (readonly, copy) NSURL* fileURL;
@property (readonly) BOOL isReadable;
@end

@interface QLPreviewView : NSObject
- (void)setPreviewDocument:(QLPreviewDocument*)document;
- (QLPreviewDocument*)previewDocument;
@end

@interface QLPreviewPanel : NSObject
+ (QLPreviewPanel*)sharedPreviewPanel;
- (void)makeKeyAndOrderFront:(id)sender;
- (void)orderOut:(id)sender;
@end

@interface QLSeamlessDocumentOpener : NSObject
+ (id)openerForDocument:(QLPreviewDocument*)document;
- (BOOL)openDocument:(NSError**)error;
@end

@interface QLSeamlessDocumentCloser : NSObject
+ (id)closerForDocument:(QLPreviewDocument*)document;
- (BOOL)closeDocument:(NSError**)error;
@end

@interface QLSeamlessOpener : NSObject
@end

@interface QLWarpingWindowEffect : NSObject
@end
