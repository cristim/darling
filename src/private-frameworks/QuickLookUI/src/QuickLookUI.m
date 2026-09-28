/*
	QuickLookUI.private

	Apple's private framework behind the Quick Look preview UI. Nine of the local
	apps link it, binding seven classes.

	These are view and controller classes, and the honest implementation of a view
	controller here is a real NSViewController that shows nothing: the class
	exists so the caller's window and delegate wiring resolves, and a controller
	with no view hierarchy is a state every caller already handles (an empty
	preview). Returning a fabricated preview would be worse: the caller would
	present a document it cannot actually render.
*/

#import <Cocoa/Cocoa.h>

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

/* Whether the URL names something this process can read. YES when the file is
   there, NO otherwise, which is the question being asked. */
- (BOOL)isReadable
{
	return _fileURL != nil && [[NSFileManager defaultManager] isReadableFileAtPath:[_fileURL path]];
}
@end

/* ---- QLPreviewView ----------------------------------------------------------- */

@interface QLPreviewView : NSView
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
	[self setNeedsDisplay:YES];
}
- (QLPreviewDocument*)previewDocument
{
	return _document;
}
- (void)drawRect:(NSRect)dirtyRect
{
	(void)dirtyRect;
}
@end

/* ---- QLPreviewPanel ---------------------------------------------------------- */

@interface QLPreviewPanel : NSPanel
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
	/* A panel that orders front and immediately orders itself back is still a panel
	   that took the order-front call, which is what the caller needs to have
	   happened; it just has nothing to show. */
	[super makeKeyAndOrderFront:sender];
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
@interface QLWarpingWindowEffect : NSView
@end

@implementation QLWarpingWindowEffect
- (void)drawRect:(NSRect)dirtyRect
{
	(void)dirtyRect;
}
@end
