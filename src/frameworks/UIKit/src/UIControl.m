#import <UIKit/UIControl.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSException.h>
#import <Foundation/NSNull.h>
#import <objc/message.h>

// One registered target/action pair and the events it responds to. The target is not
// retained (rung 3: addTarget page, "The control does not retain the object in the target parameter").
@interface DarlingUIControlAction : NSObject {
@public
    __unsafe_unretained id target;
    SEL action;
    UIControlEvents events;
}
@end

@implementation DarlingUIControlAction
@end

@implementation UIControl {
    BOOL _disabled;
    BOOL _selected;
    BOOL _highlighted;
    NSMutableArray<DarlingUIControlAction *> *_actions;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        // Rung 3 (isenabled, isselected, ishighlighted pages): enabled defaults to YES, selected
        // and highlighted to NO.
        _actions = [[NSMutableArray alloc] init];
    }
    return self;
}

// Rung 3 (state page): bitmask of UIControlState; enabled NO adds Disabled, and likewise
// Selected and Highlighted for the other two properties.
- (UIControlState)state
{
    UIControlState state = UIControlStateNormal;
    if (_highlighted) state |= UIControlStateHighlighted;
    if (_disabled) state |= UIControlStateDisabled;
    if (_selected) state |= UIControlStateSelected;
    return state;
}

- (BOOL)isEnabled { return !_disabled; }
- (void)setEnabled:(BOOL)enabled { _disabled = !enabled; }
- (BOOL)isSelected { return _selected; }
- (void)setSelected:(BOOL)selected { _selected = selected; }
- (BOOL)isHighlighted { return _highlighted; }
- (void)setHighlighted:(BOOL)highlighted { _highlighted = highlighted; }

- (void)addTarget:(id)target action:(SEL)action forControlEvents:(UIControlEvents)controlEvents
{
    // Rung 6: a NULL action raises, so a registration that could never be delivered is not
    // silently accepted.
    if (action == NULL)
        [NSException raise:NSInvalidArgumentException format:@"UIControl addTarget: action must not be NULL"];
    // Rung 6: registering zero events has nothing to deliver, so no record is made (the page only
    // says that 0 does not stop delivery to an existing registration).
    if (controlEvents == 0)
        return;
    // Rung 3: calling again with the same target and action is safe; the events accumulate.
    for (DarlingUIControlAction *entry in _actions) {
        if (entry->target == target && entry->action == action) {
            entry->events |= controlEvents;
            return;
        }
    }
    DarlingUIControlAction *entry = [[DarlingUIControlAction alloc] init];
    entry->target = target;
    entry->action = action;
    entry->events = controlEvents;
    [_actions addObject:entry];
}

// Rung 3 (removetarget page): the action argument is not considered; a nil target matches every
// target. A registration left with no events is dropped.
- (void)removeTarget:(id)target action:(SEL)action forControlEvents:(UIControlEvents)controlEvents
{
    NSMutableArray *kept = [[NSMutableArray alloc] init];
    for (DarlingUIControlAction *entry in _actions) {
        if (target == nil || entry->target == target)
            entry->events &= ~controlEvents;
        if (entry->events != 0)
            [kept addObject:entry];
    }
    _actions = kept;
}

- (NSSet *)allTargets
{
    NSMutableSet *targets = [[NSMutableSet alloc] init];
    for (DarlingUIControlAction *entry in _actions)
        [targets addObject:entry->target ? entry->target : (id)[NSNull null]];
    return targets;
}

- (UIControlEvents)allControlEvents
{
    UIControlEvents all = 0;
    for (DarlingUIControlAction *entry in _actions)
        all |= entry->events;
    return all;
}

// Rung 3 (sendactions page): iterates the registered targets and actions and calls the action
// of each one associated with an event in controlEvents. Rung 3 (sendaction(_:to:for:) page): a
// nil target means the responder chain is searched, and a nil event is allowed for programmatic
// calls. Rung 6: the control is the sender; the chain is searched from the control because the
// pages say nothing about the starting point (UIApplication.sendAction page would not fetch);
// the iteration is over a snapshot so actions may change registrations.
- (void)sendActionsForControlEvents:(UIControlEvents)controlEvents
{
    for (DarlingUIControlAction *entry in [_actions copy]) {
        if ((entry->events & controlEvents) == 0)
            continue;
        id receiver = entry->target;
        if (receiver == nil) {
            UIResponder *responder = self;
            while (responder != nil && ![responder respondsToSelector:entry->action])
                responder = [responder nextResponder];
            receiver = responder;
        }
        ((void (*)(id, SEL, id, id))objc_msgSend)(receiver, entry->action, self, nil);
    }
}

@end
