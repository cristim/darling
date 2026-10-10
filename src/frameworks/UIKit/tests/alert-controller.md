# UIAlertController and UIAlertAction (data model, no presentation)

Specification, rung 3 (DocC JSON fetched 2026-10-10, Objective-C variants): uialertcontroller,
init(title:message:preferredstyle:), title, message, preferredstyle, addaction(_:), actions,
style constants; uialertaction, init(title:style:handler:), style constants. Declarations:
`+alertControllerWithTitle:message:preferredStyle:`, `(copy, nullable) NSString *title/message`,
`(readonly) UIAlertControllerStyle preferredStyle`, `-addAction:`, `(readonly) NSArray<UIAlertAction *> *actions`,
`+actionWithTitle:style:handler:`.

Documented and tested: preferredStyle is the value given at creation; actions are kept in the
order added; actionWithTitle:style:handler: returns an action with that title and style.

Rung 6 (labelled in the source):
- ABI RISK: the numeric values of UIAlertActionStyle and UIAlertControllerStyle constants. The
  pages and Chameleon do not give them; they are declared in listing order and need a rung 3 or
  4 source before binary clients rely on them.
- UIAlertController derives from UIResponder, not UIViewController (missing in the tree);
  presentViewController:animated:completion: cannot be used with it.
- UIAlertAction title and style are readonly (their attribute pages could not be fetched); nil
  title and nil handler are accepted; titles and messages are copied.
- addAction:nil raises NSInvalidArgumentException; actions is a snapshot copy.
- When UIViewController lands: it declares its own title, so `@synthesize title` in UIAlertController.m
  must go; the factory must use its initializer.
- A plain alloc/init controller works (empty action list, zero preferredStyle).
- The handler is stored but cannot run: selecting an action needs presentation.

Left out: presentation, UIAlertAction.enabled (the page states the default YES but the property
attributes could not be fetched), addTextFieldWithConfigurationHandler: / textFields,
preferredAction, severity, image, shouldDismiss and other later properties.
