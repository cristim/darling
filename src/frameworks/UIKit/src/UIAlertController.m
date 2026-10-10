#import <UIKit/UIAlertController.h>
#import <Foundation/NSException.h>

@implementation UIAlertAction {
    NSString *_title;
    UIAlertActionStyle _style;
    void (^_handler)(UIAlertAction *);
}

// Rung 3 (init(title:style:handler:) page): returns a new action with the given title, style and
// handler. Rung 6: a nil title and a nil handler are accepted and the title is copied.
+ (instancetype)actionWithTitle:(NSString *)title style:(UIAlertActionStyle)style
                        handler:(void (^)(UIAlertAction *))handler
{
    UIAlertAction *action = [[self alloc] init];
    action->_title = [title copy];
    action->_style = style;
    action->_handler = [handler copy];
    return action;
}

- (NSString *)title { return _title; }
- (UIAlertActionStyle)style { return _style; }
@end

@implementation UIAlertController {
    UIAlertControllerStyle _preferredStyle;
    NSMutableArray<UIAlertAction *> *_actions;
}

@synthesize title = _title;
@synthesize message = _message;

// Rung 3 (init(title:message:preferredstyle:) page): returns a controller with the given title,
// message and style. Rung 6: nil title or message is accepted.
+ (instancetype)alertControllerWithTitle:(NSString *)title message:(NSString *)message
                          preferredStyle:(UIAlertControllerStyle)preferredStyle
{
    UIAlertController *controller = [[self alloc] init];
    controller->_title = [title copy];
    controller->_message = [message copy];
    controller->_preferredStyle = preferredStyle;
    controller->_actions = [[NSMutableArray alloc] init];
    return controller;
}

- (UIAlertControllerStyle)preferredStyle { return _preferredStyle; }

// Rung 3 (addaction and actions pages): actions keep the order in which they were added.
// Rung 6: nil raises NSInvalidArgumentException, and actions is a copy.
- (void)addAction:(UIAlertAction *)action
{
    if (action == nil)
        [NSException raise:NSInvalidArgumentException format:@"UIAlertController addAction: action must not be nil"];
    [_actions addObject:action];
}

- (NSArray<UIAlertAction *> *)actions { return [_actions copy]; }
@end
