#import "SpotifyContentBridge.h"
#import <UIKit/UIKit.h>

static NSError *HarborSpotifyContentError(void) {
    return [NSError errorWithDomain:@"HarborSpotify" code:1 userInfo:nil];
}

void HarborSpotifyContent(SPTAppRemote *remote, NSString *uri, HarborSpotifyContentReply completion) {
    NSCAssert([NSThread isMainThread], @"App Remote is owned by the main actor");
    id<SPTAppRemoteContentAPI> api = remote.contentAPI;
    if (!remote.connected || !api) { completion(nil, HarborSpotifyContentError()); return; }
    SPTAppRemoteCallback reply = ^(id result, NSError *error) {
        if (error || ![result isKindOfClass:NSArray.class]) { completion(nil, error ?: HarborSpotifyContentError()); return; }
        NSMutableArray *rows = [NSMutableArray array];
        for (id<SPTAppRemoteContentItem> item in (NSArray *)result) {
            [rows addObject:@{@"id":item.identifier, @"uri":item.URI, @"title":item.title ?: @"",
                              @"subtitle":item.subtitle ?: @"", @"playable":@(item.playable),
                              @"container":@(item.container), @"offline":@(item.availableOffline)}];
        }
        NSError *encodingError = nil;
        NSData *data = [NSJSONSerialization dataWithJSONObject:rows options:0 error:&encodingError];
        completion(data, encodingError);
    };
    if (uri == nil) {
        [api fetchRecommendedContentItemsForType:SPTAppRemoteContentTypeDefault flattenContainers:NO callback:reply];
    } else {
        [api fetchContentItemForURI:uri callback:^(id result, NSError *error) {
            if (error || ![result conformsToProtocol:@protocol(SPTAppRemoteContentItem)]) { completion(nil, error ?: HarborSpotifyContentError()); return; }
            id<SPTAppRemoteContentItem> item = result;
            if (item.container) { [api fetchChildrenOfContentItem:item callback:reply]; }
            else { reply(@[item], nil); }
        }];
    }
}

void HarborSpotifyArtwork(SPTAppRemote *remote, NSString *uri, HarborSpotifyContentReply completion) {
    NSCAssert([NSThread isMainThread], @"App Remote is owned by the main actor");
    if (!remote.connected || !remote.contentAPI || !remote.imageAPI) { completion(nil, HarborSpotifyContentError()); return; }
    [remote.contentAPI fetchContentItemForURI:uri callback:^(id result, NSError *error) {
        if (error || ![result conformsToProtocol:@protocol(SPTAppRemoteImageRepresentable)]) { completion(nil, error ?: HarborSpotifyContentError()); return; }
        [remote.imageAPI fetchImageForItem:result withSize:CGSizeMake(360, 360) callback:^(id image, NSError *imageError) {
            if (imageError || ![image isKindOfClass:UIImage.class]) { completion(nil, imageError ?: HarborSpotifyContentError()); return; }
            completion(UIImagePNGRepresentation(image), nil);
        }];
    }];
}
