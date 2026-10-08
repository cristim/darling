# UIResponder chain regression

Covers the four public UIResponder methods implemented in `src/UIResponder.m`:
`nextResponder`, `canBecomeFirstResponder`, `canResignFirstResponder` and
`canPerformAction:withSender:`. First-responder ownership, window attachment and
action dispatch are not implemented: they need UIWindow/UIView/scene ownership
that does not exist yet.

## Provenance

- Specification, clean-room rung 3 (Apple public documentation):
  - [nextResponder](https://developer.apple.com/documentation/uikit/uiresponder/next?language=objc): base returns nil
  - [canBecomeFirstResponder](https://developer.apple.com/documentation/uikit/uiresponder/canbecomefirstresponder): default NO
  - [canResignFirstResponder](https://developer.apple.com/documentation/uikit/uiresponder/canresignfirstresponder): default YES
  - [canPerformAction:withSender:](https://developer.apple.com/documentation/uikit/uiresponder/canperformaction(_:withsender:)): YES for actions the responder class implements, otherwise ask the next responder
- Source: the BSD-licensed Chameleon project (https://github.com/BigZaphod/Chameleon)
  at 84605ede274bd82b330d72dd6ac41e64eb925fd7, `UIKit/Classes/UIResponder.h/.m`, with
  its notices retained. This is reused open-source code, not a ladder rung.

## What is checked

The test builds its own responder subclasses with the Objective-C runtime, so one
executable runs against a UIKit without `UIResponder` (expected: exit 1) and
against one with it (expected: exit 0). It checks the defaults, subclass chain
links, inherited action detection, nil termination, sender and selector
preservation across nodes, and eligibility overrides. Validation never executes
the action.

## Build and run

```
python3 build-responder-chain.py --source-root <repo> --runtime-root <runtime>/libexec/darling \
  --build-dir <out> --linker <darwin ld64>
darling shell <out>/responder-chain <out>/UIKitResponder
```

Run it in a fresh private prefix with the host-home symlinks replaced by empty
directories. The second argument is the UIKit artifact the test `dlopen`s.
