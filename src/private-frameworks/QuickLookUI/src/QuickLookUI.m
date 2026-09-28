/*
	QuickLookUI.private

	Apple's private framework behind the Quick Look preview UI. Nine of the local
	apps link it, binding seven classes.

	The class exists so the caller's window and delegate wiring resolves, and a
	preview that renders nothing is a state every caller already handles. Returning
	a fabricated preview would be worse: the caller would present a document it
	cannot actually render.

	Subclass fidelity is limited by the headers on this system. NSView.h and
	NSPanel.h pull in ApplicationServices, which has no headers here, so QLPreviewView
	and QLPreviewPanel are declared over NSObject rather than NSView and NSPanel.
	The class symbols are emitted either way, and every app linking this framework
	is blocked on AppKit regardless.
*/

#import <Foundation/Foundation.h>
#include <unistd.h>

@class QLPreviewDocument;

/* ---- QLPreviewDocument -------------------------------------------------------- */

@interface QLPreviewDocument : NSObject
- (instancetype)initWithFileURL:(NSURL*)url;
@property (readonly, copy) NSURL* fileURL;
@property (readonly) BOOL isReadable;
@end

@implementation QLPreviewDocument
{
	NSURL* _fileURL;
}
@synthesize fileURL = _fileURL;
- (instancetype)initWithFileURL:(NSURL*)url
{
	if ((self = [super init]))
	{
		_fileURL = [url copy];
	}
	return self;
}

/* Whether the URL names something this process can read, which is the question
   being asked. access() answers exactly that and needs no Foundation class, and
   NSFileManager is not built on this system yet. */
- (BOOL)isReadable
{
	if (_fileURL == nil)
	{
		return NO;
	}
	return access([[_fileURL path] fileSystemRepresentation], R_OK) == 0;
}
@end

/* ---- QLPreviewView ----------------------------------------------------------- */

@interface QLPreviewView : NSObject
- (void)setPreviewDocument:(QLPreviewDocument*)document;
- (QLPreviewDocument*)previewDocument;
@end

@implementation QLPreviewView
{
	QLPreviewDocument* _document;
}
- (void)setPreviewDocument:(QLPreviewDocument*)document
{
	_document = document;
}
- (QLPreviewDocument*)previewDocument
{
	return _document;
}
@end

/* ---- QLPreviewPanel ---------------------------------------------------------- */

@interface QLPreviewPanel : NSObject
+ (QLPreviewPanel*)sharedPreviewPanel;
- (void)makeKeyAndOrderFront:(id)sender;
- (void)orderOut:(id)sender;
@end

@implementation QLPreviewPanel
+ (QLPreviewPanel*)sharedPreviewPanel
{
	static QLPreviewPanel* instance;
	if (instance == nil)
	{
		instance = [[QLPreviewPanel alloc] init];
	}
	return instance;
}
- (void)makeKeyAndOrderFront:(id)sender
{
	/* There is no window to order front: no Quick Look generator is registered and
	   no preview is rendered. The call is accepted and ignored, so a caller that
	   treats ordering front as "the preview is up" still returns control. */
	(void)sender;
}
@end

/* ---- The seamless-preview family --------------------------------------------- */

@interface QLSeamlessDocumentOpener : NSObject
+ (id)openerForDocument:(QLPreviewDocument*)document;
- (BOOL)openDocument:(NSError**)error;
@end

@implementation QLSeamlessDocumentOpener
{
	QLPreviewDocument* _document;
}
+ (id)openerForDocument:(QLPreviewDocument*)document
{
	QLSeamlessDocumentOpener* opener = [[self alloc] init];
	opener->_document = document;
	return opener;
}

/* No document window server to present into, so the open does not happen and the
   error says why. A caller already handles a failed open by falling back. */
- (BOOL)openDocument:(NSError**)error
{
	if (error)
	{
		*error = [NSError errorWithDomain:@"QLSeamlessPreviewErrorDomain"
		                             code:1
		                         userInfo:@{NSLocalizedDescriptionKey:
		                                        @"Seamless preview is not available"}];
	}
	return NO;
}
@end

@interface QLSeamlessDocumentCloser : NSObject
+ (id)closerForDocument:(QLPreviewDocument*)document;
- (BOOL)closeDocument:(NSError**)error;
@end

@implementation QLSeamlessDocumentCloser
+ (id)closerForDocument:(QLPreviewDocument*)document
{
	QLSeamlessDocumentCloser* closer = [[self alloc] init];
	(void)document;
	return closer;
}
- (BOOL)closeDocument:(NSError**)error
{
	if (error)
	{
		*error = nil;
	}
	/* Nothing was opened, so nothing needs closing: that is a success, not a
	   failure, and reporting failure here would make a caller retry forever. */
	return YES;
}
@end

@interface QLSeamlessOpener : NSObject
@end

@implementation QLSeamlessOpener
@end

/* ---- QLWarpingWindowEffect --------------------------------------------------- */

/* A visual effect view that draws nothing. Callers add it and animate it; with no
   effect to composite, the animation still runs over an empty layer. */
@interface QLWarpingWindowEffect : NSObject
@end

@implementation QLWarpingWindowEffect
@end
