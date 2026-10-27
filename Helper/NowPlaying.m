// Loaded by /usr/bin/perl, which macOS still lets read the system's Now Playing (MediaRemote).
// beanotch_stream prints one JSON line per change; beanotch_send runs the command in BEANOTCH_CMD and returns.
#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#include <dlfcn.h>

typedef void (*GetInfoFn)(dispatch_queue_t, void (^)(NSDictionary *));
typedef void (*GetPIDFn)(dispatch_queue_t, void (^)(int));
typedef void (*GetPlayingFn)(dispatch_queue_t, void (^)(Boolean));
typedef void (*RegisterFn)(dispatch_queue_t);
typedef Boolean (*SendFn)(int, NSDictionary *);
typedef void (*SetTimeFn)(double);

static void *mr(const char *name) {
    static void *lib;
    if (!lib) lib = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
    return lib ? dlsym(lib, name) : NULL;
}

static NSString *lastArtworkKey = @"";

static void emit(void) {
    GetInfoFn getInfo = mr("MRMediaRemoteGetNowPlayingInfo");
    GetPIDFn getPID = mr("MRMediaRemoteGetNowPlayingApplicationPID");
    GetPlayingFn getPlaying = mr("MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    if (!getInfo || !getPID || !getPlaying) return;
    dispatch_queue_t q = dispatch_get_main_queue();
    getPID(q, ^(int pid) {
        getPlaying(q, ^(Boolean playing) {
            getInfo(q, ^(NSDictionary *info) {
                NSMutableDictionary *out = [NSMutableDictionary dictionary];
                if (info.count == 0) {
                    out[@"empty"] = @YES;
                } else {
                    NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
                    out[@"app"] = app.localizedName ?: @"";
                    out[@"bundle"] = app.bundleIdentifier ?: @"";
                    out[@"playing"] = @(playing);
                    out[@"title"] = info[@"kMRMediaRemoteNowPlayingInfoTitle"] ?: @"";
                    out[@"artist"] = info[@"kMRMediaRemoteNowPlayingInfoArtist"] ?: @"";
                    out[@"album"] = info[@"kMRMediaRemoteNowPlayingInfoAlbum"] ?: @"";
                    out[@"duration"] = info[@"kMRMediaRemoteNowPlayingInfoDuration"] ?: @0;
                    out[@"elapsed"] = info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"] ?: @0;
                    NSDate *stamp = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
                    out[@"timestamp"] = @(stamp ? stamp.timeIntervalSince1970 : NSDate.date.timeIntervalSince1970);
                    NSData *art = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
                    NSString *key = [NSString stringWithFormat:@"%@|%@|%lu", out[@"title"], out[@"artist"], (unsigned long)art.length];
                    // Artwork only when it changes: it is the bulk of every line.
                    if (art.length && ![key isEqualToString:lastArtworkKey]) {
                        out[@"artwork"] = [art base64EncodedStringWithOptions:0];
                    }
                    lastArtworkKey = key;
                }
                NSData *json = [NSJSONSerialization dataWithJSONObject:out options:0 error:nil];
                if (!json) return;
                fwrite(json.bytes, 1, json.length, stdout);
                fputc('\n', stdout);
                fflush(stdout);
            });
        });
    });
}

void beanotch_stream(void *perl, void *cv) {
    RegisterFn reg = mr("MRMediaRemoteRegisterForNowPlayingNotifications");
    if (!reg) return;
    reg(dispatch_get_main_queue());
    for (NSString *name in @[@"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                             @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
                             @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification"]) {
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *n) { emit(); }];
    }
    emit();
    // Exits with the app: stdin closes when Beanotch quits.
    dispatch_source_t src = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, STDIN_FILENO, 0, dispatch_get_main_queue());
    dispatch_source_set_event_handler(src, ^{
        char buf[64];
        if (read(STDIN_FILENO, buf, sizeof buf) <= 0) exit(0);
        emit();
    });
    dispatch_resume(src);
    CFRunLoopRun();
}

void beanotch_send(void *perl, void *cv) {
    const char *cmd = getenv("BEANOTCH_CMD");
    if (!cmd) return;
    if (strncmp(cmd, "seek:", 5) == 0) {
        SetTimeFn setTime = mr("MRMediaRemoteSetElapsedTime");
        if (setTime) setTime(atof(cmd + 5));
    } else {
        SendFn send = mr("MRMediaRemoteSendCommand");
        if (send) send(atoi(cmd), nil);
    }
    // Commands go out asynchronously; give them a moment before perl exits.
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
}
