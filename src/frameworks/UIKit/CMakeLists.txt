project(UIKit)

remove_sdk_framework(UIKit)
generate_sdk_framework(UIKit VERSION A HEADER "include/UIKit")

add_framework(UIKit
    IOSSUPPORT
    CURRENT_VERSION
    FAT
    VERSION A
    SOURCES src/UICollectionViewCompositionalLayout.m src/UIGeometry.m src/UIGraphicsContext.m src/UIColor.m src/UIImage.m src/UIGraphicsImageContext.m src/UISceneConfiguration.m
    DEPENDENCIES AppKit CoreFoundation CoreGraphics Foundation ImageIO objc system
)
target_include_directories(UIKit PRIVATE include)
target_compile_options(UIKit PRIVATE -fobjc-arc)
