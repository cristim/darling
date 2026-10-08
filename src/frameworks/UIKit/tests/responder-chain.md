# Bounded public UIResponder chain regression

This component implements an NSObject-based UIResponder with four public methods:
nextResponder, canBecomeFirstResponder, canResignFirstResponder and
canPerformAction:withSender:. It does not establish first-responder ownership,
window attachment, action dispatch or a UIKit application/window chain.

Provenance: licensed BSD Chameleon84605ede274bd82b330d72dd6ac41e64eb925fd7
UIKit/Classes/UIResponder.h/.m supplies the reused functional subset, with full
notices retained. Apple public documentation (clean-room rung 3) specifies:

- [next responder](https://developer.apple.com/documentation/uikit/uiresponder/next?language=objc): base returns nil and does not set/store the chain; subclasses override.
- [becoming eligible](https://developer.apple.com/documentation/uikit/uiresponder/canbecomefirstresponder): default NO, also specified by becomeFirstResponder documentation.
- [resignation eligibility](https://developer.apple.com/documentation/uikit/uiresponder/canresignfirstresponder): default YES.
- [action validation](https://developer.apple.com/documentation/uikit/uiresponder/canperformaction(_:withsender:)): default enables actions implemented by the responder class, otherwise asks the next responder.

Authored dynamic subclasses use public Objective-C runtime APIs so the same
executable can test a baseline UIKit without statically linking its missing
UIResponder class. The test defines its own nextResponder chain and action method;
these are synthetic inputs, not fabricated UIKit hierarchy. BOOL runtime method
encodings come from @encode(BOOL), not a guessed architecture encoding.

Checks: base defaults, subclass chain links, inherited action detection, nil
termination for unhandled commands, sender/selector preservation across multiple
nodes, state-dependent override validation and eligibility overrides. Validation
must not execute the action. Chain mutation is in the authored subclass only;
UIResponder gains no automatic nextResponder setter/storage.

Run the executable with an explicit dlopen artifact argument in an offscreen
synthetic guest (it does not initialize NSApplication or interpret documents):

```
darling shell /Volumes/SystemRoot/<responder-chain> /Volumes/SystemRoot/<UIKit-artifact>
```

Compile with pinned Foundation/Objective-C headers and Darwin linker/runtime
mapping using the focused UIKit harness recipe. All compilation is serial under
shared heavy-build flock and defers to full-runtime priority. Use a fresh private
prefix, bootstrap shell true, replace host-home symlinks with empty directories,
and shut down only that prefix. No history/account/service calls are needed.

Prove missing UIResponder against a clean baseline first, then run the identical
executable against the implementation. Build and re-run reviewed clean committed
source before integration. Keep binary, commands/dependencies/hashes and guest
logs in private scratch; no compiled output or symbol dumps enter source control.

First-responder query/transitions are deliberately not declared or implemented:
UIWindow/UIView/scene ownership and active hierarchy are not available. AppKit's
NSWindow.makeFirstResponder calls NSResponder become/resign callbacks; UIKit's
becomeFirstResponder is a request to UIKit. UIResponder inherits NSObject, so
simply substituting NSResponder or passing it as an AppKit first responder would
invent the attachment/ownership contract. No global focus default is supplied.

Target lookup and dispatch are a separate integration concern. canPerformAction
can delegate validation upward; targetForAction documentation says it uses that
validation and returns itself when enabled. An invocable target/forwarding route
for a receiver without the action needs coherent UIApplication integration,
not an invented forwardingTargetForSelector/methodSignature chain. No
UIApplication.sendAction or targetForAction is claimed by this component.
