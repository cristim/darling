# UIButton (buttonWithType:, titles and title colors per state)

Specification, rung 3 (DocC JSON fetched 2026-10-10, Objective-C variants): uibutton,
init(type:), settitle(_:for:), title(for:), settitlecolor(_:for:), titlecolor(for:),
buttontype-swift.property and the UIButtonType constants. Declarations:
`+ (instancetype)buttonWithType:(UIButtonType)`, `- (void)setTitle:(NSString *)forState:(UIControlState)`,
`- (NSString *)titleForState:`, `- (void)setTitleColor:(UIColor *)forState:`,
`- (UIColor *)titleColorForState:`, `@property (nonatomic, readonly) UIButtonType buttonType`.

Rung 2 (values only): UIButtonType values 0 to 5 come from the BSD Chameleon UIButton.h; the
complete notice is in UIButton.h. UIButtonTypeSystem, Plain and Close are documented without a
value source and are not declared: Messages may pass UIButtonTypeSystem, so a value for it
needs a rung 3 or 4 source before this is useful to it. buttonWithType: itself stores any value.

Documented and tested: a custom button has frame (0, 0, 0, 0); a state without its own title
or title color uses the Normal one; buttonType reports the type given.

Rung 6 (labelled in UIButton.m): states match by exact value; nil removes a value; with no
Normal value the result is nil (the pages say "a system value"); other types also get an empty
frame; titles are copied.

Left out: attributed titles, shadow colors, currentTitle*, titleLabel, imageForState, configuration,
edge insets, behavioralStyle, systemButtonWithImage:, drawing and layout.
