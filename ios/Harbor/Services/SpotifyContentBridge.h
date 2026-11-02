#import <Foundation/Foundation.h>
#import <SpotifyiOS/SpotifyiOS.h>

NS_ASSUME_NONNULL_BEGIN
typedef void (^HarborSpotifyContentReply)(NSData * _Nullable data, NSError * _Nullable error);
void HarborSpotifyContent(SPTAppRemote *remote, NSString * _Nullable uri, HarborSpotifyContentReply completion);
void HarborSpotifyArtwork(SPTAppRemote *remote, NSString *uri, HarborSpotifyContentReply completion);
NS_ASSUME_NONNULL_END
