// LOCAL OBSERVATION PROBE, never published.
#include "probe.h"
#import <AppKit/NSToolbarItem.h>
#import <AppKit/NSCollectionViewLayout.h>
#define PROBE_CLASS(n, s) @interface n : s @end @implementation n PROBE_FORWARDING @end
PROBE_CLASS(NSCollectionLayoutDimension, NSObject)
PROBE_CLASS(NSCollectionLayoutSize, NSObject)
PROBE_CLASS(NSCollectionLayoutItem, NSObject)
PROBE_CLASS(NSCollectionLayoutGroup, NSCollectionLayoutItem)
PROBE_CLASS(NSCollectionLayoutSection, NSObject)
PROBE_CLASS(NSCollectionViewCompositionalLayout, NSCollectionViewLayout)
PROBE_CLASS(NSSearchToolbarItem, NSToolbarItem)
