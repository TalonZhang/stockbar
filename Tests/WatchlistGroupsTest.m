#import <Foundation/Foundation.h>
#import "WatchlistStore.h"

static void Check(BOOL condition, NSString *message) {
    if (!condition) {
        fprintf(stderr, "%s\n", message.UTF8String);
        exit(1);
    }
}

int main(void) {
    @autoreleasepool {
        // Isolated preferences: the tests never read or modify the app domain.
        NSString *suite = [@"dev.talon.stockbar.test." stringByAppendingString:NSUUID.UUID.UUIDString];
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
        [defaults setObject:@[@"512890", @"000001", @"510310"] forKey:@"watchlist.codes.v1"];
        WatchlistStore *store = [[WatchlistStore alloc] initWithDefaults:defaults];
        Check(store.groups.count == 1, @"Migration created unexpected groups");
        Check([store.selectedGroupIdentifier isEqualToString:WatchlistDefaultGroupIdentifier], @"Default group not selected");
        Check([store.codes isEqualToArray:@[@"512890", @"000001", @"510310"]], @"Migration lost codes or order");

        NSError *error = nil;
        NSString *technology = [store createGroupWithName:@"  科技  " error:&error];
        Check(technology != nil && error == nil, @"Valid group rejected");
        Check([store.selectedGroupName isEqualToString:@"科技"] && store.codes.count == 0, @"New group not empty/selected");
        Check([store addCode:@"000001"] && [store addCode:@"159915"], @"Group add failed");
        Check(![store addCode:@"159915"], @"Duplicate membership accepted");
        Check(store.allCodes.count == 4, @"Cross-group quote requests not deduplicated");
        Check([store moveCode:@"159915" toIndex:0], @"Group reorder failed");
        Check([store removeCode:@"000001"], @"Group remove failed");
        [store selectGroup:WatchlistDefaultGroupIdentifier];
        Check([store containsCode:@"000001"], @"Removing from one group removed another membership");
        Check([store.codes isEqualToArray:@[@"512890", @"000001", @"510310"]], @"Other group's order changed");
        Check([store addCode:@"510310" toGroup:technology], @"Captured group add failed");
        Check([store.selectedGroupIdentifier isEqualToString:WatchlistDefaultGroupIdentifier], @"Background add changed selection");

        for (NSString *invalid in @[@"", @"  ", @"自选", @"科技", @"一二三四五六七八九十一", @"科\n技"]) {
            error = nil;
            Check([store createGroupWithName:invalid error:&error] == nil && error != nil,
                  [NSString stringWithFormat:@"Invalid/duplicate name accepted: %@", invalid]);
        }
        NSString *longGroup = [store createGroupWithName:@"一二三四五六七八九十" error:nil];
        Check(longGroup != nil, @"Ten-character name rejected");
        Check([[WatchlistStore displayNameForGroupName:@"一二三四五六七八九十"] isEqualToString:@"一二三四"], @"Tab not limited to four characters");
        Check([[WatchlistStore displayNameForGroupName:@"👨‍👩‍👧‍👦科技医药"] isEqualToString:@"👨‍👩‍👧‍👦科技医"], @"Tab split a composed character");
        Check([store createGroupWithName:@"😀😀😀😀😀😀😀😀😀😀" error:nil] != nil, @"Emoji counted as UTF-16 units");
        Check([store createGroupWithName:@"😀😀😀😀😀😀😀😀😀😀😀" error:nil] == nil, @"More than ten characters accepted");
        Check(![store renameGroup:WatchlistDefaultGroupIdentifier name:@"Other" error:nil], @"Default group rename allowed");
        Check(![store removeGroup:WatchlistDefaultGroupIdentifier], @"Default group deletion allowed");
        Check([store renameGroup:technology name:@"科技与基金" error:nil], @"Rename failed");
        Check(![store renameGroup:technology name:@"自选" error:&error], @"Duplicate rename allowed");

        [store selectGroup:technology];
        WatchlistStore *reloaded = [[WatchlistStore alloc] initWithDefaults:defaults];
        Check([reloaded.selectedGroupIdentifier isEqualToString:technology], @"Selected group did not persist");
        Check([reloaded.selectedGroupName isEqualToString:@"科技与基金"], @"Group name did not persist");
        Check([reloaded.codes isEqualToArray:@[@"159915", @"510310"]], @"Membership/order did not persist");
        Check([reloaded removeGroup:technology], @"Delete custom group failed");
        Check([reloaded.selectedGroupIdentifier isEqualToString:WatchlistDefaultGroupIdentifier], @"Delete did not fall back to default");
        Check([reloaded containsCode:@"510310"], @"Delete removed another group's code");
        Check(![reloaded selectGroup:@"missing"] && ![reloaded addCode:@"512890" toGroup:@"missing"], @"Missing group accepted");
        Check([[defaults arrayForKey:@"watchlist.codes.v1"] isEqualToArray:reloaded.codes], @"Downgrade key not preserved");

        [defaults removePersistentDomainForName:suite];
        [defaults setObject:@[] forKey:@"watchlist.codes.v1"];
        WatchlistStore *empty = [[WatchlistStore alloc] initWithDefaults:defaults];
        Check(empty.codes.count == 0 && empty.groups.count == 1, @"Empty legacy list replaced with defaults");
        [defaults removePersistentDomainForName:suite];
        puts("Groups: migration, membership isolation, ordering, names, selection and persistence passed");
    }
    return 0;
}
