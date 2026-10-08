# UISceneConfiguration value regression

Implements the name/role/sceneClass/delegateClass value object and the three
imported window-scene session role constants. It creates no scenes, sessions,
windows or delegates; UIWindowScene and UIApplicationMain remain absent.

Clean-room rung 3 specifications:

- [UISceneConfiguration](https://developer.apple.com/documentation/uikit/uisceneconfiguration):
  name, role, sceneClass, delegateClass, initializer and factory.
- [UIWindowSceneSessionRoleApplication](https://developer.apple.com/documentation/uikit/uiscenesession/role/windowapplication)
  and the Info.plist UIApplicationSceneManifest documentation, which uses the
  role names as plist keys.

Rung 6, local policy: the ExternalDisplayNonInteractive and
AssistiveAccessApplication string values equal their symbol names (no public
specification of the values found); a nil role raises NSInvalidArgumentException;
the storyboard property is omitted because UIStoryboard does not exist here.
Name and role are copied at initialization; copies duplicate all four values.
