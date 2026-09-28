/*
	QuickLookUI.private

	Apple's private framework behind the Quick Look preview UI. Nine of the local
	apps link it, binding seven classes.

	Declared here so the classes can be compiled and so callers building against
	this framework see the same interfaces. The classes are referenced through the
	Objective-C runtime by the callers that bind them, so the header exists for the
	build rather than for the linker.
*/

#ifndef QUICKLOOKUI_H
#define QUICKLOOKUI_H

#import <Cocoa/Cocoa.h>

@class QLPreviewDocument;

@interface QLPreviewDocument : NSObject
- (instancetype)initWithFileURL:(NSURL*)url;
@property (readonly, copy) NSURL* fileURL;
@property (readonly) BOOL isReadable;
@end

@interface QLPreviewView : NSView
- (void)setPreviewDocument:(QLPreviewDocument*)document;
- (QLPreviewDocument*)previewDocument;
@end

@interface QLPreviewPanel : NSPanel
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

@interface QLWarpingWindowEffect : NSView
@end

#endif
