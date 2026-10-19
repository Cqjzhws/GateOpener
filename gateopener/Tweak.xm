#import <UIKit/UIKit.h>
#import <WebKit/WKWebView.h>
#import <objc/runtime.h>
#import <CommonCrypto/CommonCrypto.h>

static UIButton *floatingButton = nil;
static UIWindow *keyWindow = nil;

@interface GateOpenerManager : NSObject
+ (instancetype)shared;
- (void)showDoorSelector;
- (void)handlePan:(UIPanGestureRecognizer *)pan;
@end

@implementation GateOpenerManager

+ (instancetype)shared {
    static GateOpenerManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[GateOpenerManager alloc] init];
    });
    return instance;
}

- (NSString*)getCurrentTimestamp {
    NSTimeInterval interval = [[NSDate date] timeIntervalSince1970];
    return [NSString stringWithFormat:@"%.0f", interval * 1000];
}

- (NSString*)generateRandomString:(int)length {
    NSString *letters = @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    NSMutableString *randomString = [NSMutableString stringWithCapacity:length];
    for (int i = 0; i < length; i++) {
        [randomString appendFormat:@"%C", [letters characterAtIndex:arc4random_uniform([letters length])]];
    }
    return randomString;
}

- (NSString*)sha256:(NSString *)input {
    const char *str = [input UTF8String];
    unsigned char result[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(str, (CC_LONG)strlen(str), result);
    NSMutableString *hash = [NSMutableString string];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [hash appendFormat:@"%02x", result[i]];
    }
    return hash;
}

- (NSString*)base64Encode:(NSString *)input {
    NSData *data = [input dataUsingEncoding:NSUTF8StringEncoding];
    return [data base64EncodedStringWithOptions:0];
}

- (void)showToast:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = [UIApplication sharedApplication].keyWindow;
        if (!window) return;

        UILabel *label = [[UILabel alloc] init];
        label.text = message;
        label.textColor = [UIColor whiteColor];
        label.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.85];
        label.textAlignment = NSTextAlignmentCenter;
        label.font = [UIFont systemFontOfSize:14];
        label.numberOfLines = 0;
        label.layer.cornerRadius = 8;
        label.clipsToBounds = YES;

        CGSize size = [label sizeThatFits:CGSizeMake(300, CGFLOAT_MAX)];
        label.frame = CGRectMake((window.bounds.size.width - size.width - 24) / 2,
                                 window.bounds.size.height - 160,
                                 size.width + 24,
                                 size.height + 16);
        [window addSubview:label];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.3 animations:^{
                label.alpha = 0;
            } completion:^(BOOL finished) {
                [label removeFromSuperview];
            }];
        });
    });
}

- (WKWebView*)findWebViewInView:(UIView *)view {
    if ([view isKindOfClass:[WKWebView class]]) {
        return (WKWebView *)view;
    }
    for (UIView *subview in view.subviews) {
        WKWebView *found = [self findWebViewInView:subview];
        if (found) return found;
    }
    return nil;
}

- (void)showDoorSelector {
    keyWindow = [UIApplication sharedApplication].keyWindow;
    if (!keyWindow) {
        [self showToast:@"无法获取窗口"];
        return;
    }

    WKWebView *webView = nil;
    for (UIView *view in keyWindow.subviews) {
        webView = [self findWebViewInView:view];
        if (webView) break;
    }

    if (!webView) {
        [self showToast:@"未找到网页，请打开门禁页面"];
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"选择门禁"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:@"1单元1楼"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [self showToast:@"正在开门..."];
        [self fetchDataAndOpenDoor:webView deviceId:@"569458" source:@"" completion:^(NSString *result) {
            [self showToast:result];
        }];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"负3楼"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [self showToast:@"正在开门..."];
        [self fetchDataAndOpenDoor:webView deviceId:@"120614585" source:@"PAAS" completion:^(NSString *result) {
            [self showToast:result];
        }];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    UIViewController *topController = keyWindow.rootViewController;
    while (topController.presentedViewController) {
        topController = topController.presentedViewController;
    }

    if (alert.popoverPresentationController) {
        alert.popoverPresentationController.sourceView = floatingButton;
        alert.popoverPresentationController.sourceRect = floatingButton.bounds;
    }

    [topController presentViewController:alert animated:YES completion:nil];
}

- (void)fetchDataAndOpenDoor:(WKWebView *)webView deviceId:(NSString *)deviceId source:(NSString *)source completion:(void (^)(NSString *))completion {

    [webView evaluateJavaScript:@"document.cookie" completionHandler:^(id result, NSError *error) {
        NSString *cookieStr = (NSString *)result;
        if (!cookieStr || cookieStr.length == 0) {
            completion(@"无法读取Cookie，请确保已登录");
            return;
        }

        NSMutableDictionary *cookies = [NSMutableDictionary dictionary];
        NSArray *pairs = [cookieStr componentsSeparatedByString:@"; "];
        for (NSString *pair in pairs) {
            NSArray *kv = [pair componentsSeparatedByString:@"="];
            if (kv.count >= 2) {
                NSString *key = kv[0];
                NSString *value = [[kv subarrayWithRange:NSMakeRange(1, kv.count - 1)] componentsJoinedByString:@"="];
                cookies[key] = value;
            }
        }

        NSString *accessToken = cookies[@"accessToken"];
        NSString *appKey = cookies[@"appKey"];
        NSString *localId = cookies[@"localId"];

        if (!accessToken || !appKey || !localId) {
            completion(@"Cookie信息不完整，请重新登录");
            return;
        }

        NSString *cookieId = [self generateRandomString:32];
        NSDictionary *getCookieBody = @{@"cookieId": cookieId};
        NSError *jsonError;
        NSData *bodyData = [NSJSONSerialization dataWithJSONObject:getCookieBody options:0 error:&jsonError];

        NSURL *url = [NSURL URLWithString:@"https://w.shequ.189.cn/route/menu/getCookie"];
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
        [request setHTTPMethod:@"POST"];
        [request setHTTPBody:bodyData];
        [request setValue:@"application/json;charset=UTF-8" forHTTPHeaderField:@"Content-Type"];
        [request setValue:cookieStr forHTTPHeaderField:@"Cookie"];
        [request setValue:@"https://w.shequ.189.cn/communityFw/h5/index.html" forHTTPHeaderField:@"Referer"];
        [request setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 16_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 MicroMessenger/8.0.58(0x18003a25) NetType/WIFI Language/zh_CN" forHTTPHeaderField:@"User-Agent"];

        NSURLSession *session = [NSURLSession sharedSession];
        NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                                completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (error) {
                    completion([NSString stringWithFormat:@"网络错误: %@", error.localizedDescription]);
                    return;
                }

                NSError *jsonError2;
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError2];
                if (jsonError2) {
                    completion(@"解析响应失败");
                    return;
                }

                NSDictionary *dataDict = json[@"data"];
                NSString *hashKey = dataDict[@"hashKey"];
                if (!hashKey) {
                    completion(@"未获取到hashKey");
                    return;
                }

                [self openDoorWithToken:accessToken appKey:appKey localId:localId hashKey:hashKey deviceId:deviceId source:source completion:completion];
            });
        }];
        [task resume];
    }];
}

- (void)openDoorWithToken:(NSString *)accessToken appKey:(NSString *)appKey localId:(NSString *)localId hashKey:(NSString *)hashKey deviceId:(NSString *)deviceId source:(NSString *)source completion:(void (^)(NSString *))completion {

    NSString *timestamp = [self getCurrentTimestamp];
    NSString *randomStr = [self generateRandomString:32];

    NSString *tokenAppKey = [NSString stringWithFormat:@"%@@%@", accessToken, appKey];
    NSString *base64TokenAppKey = [self base64Encode:tokenAppKey];

    NSString *signRaw = [NSString stringWithFormat:@"%@%@%@%@%@%@",
                         base64TokenAppKey, timestamp, randomStr, accessToken, @"client", hashKey];
    NSString *sign = [self sha256:signRaw];

    NSString *authorization = [NSString stringWithFormat:@"6e0044e0040de0020b6%@%@%@%@%@accessTokenclient",
                               base64TokenAppKey, sign, timestamp, randomStr, accessToken];

    NSMutableDictionary *bodyDict = [NSMutableDictionary dictionary];
    bodyDict[@"deviceId"] = @([deviceId intValue]);
    bodyDict[@"communityId"] = @([localId intValue]);
    if (source && source.length > 0) {
        bodyDict[@"source"] = source;
    }

    NSError *error;
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:bodyDict options:0 error:&error];
    if (error) {
        completion(@"构造请求失败");
        return;
    }

    NSURL *url = [NSURL URLWithString:@"https://w.shequ.189.cn/aiot/wechat_accounts/device-entity/open/v1"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:bodyData];
    [request setValue:@"application/json;charset=UTF-8" forHTTPHeaderField:@"Content-Type"];
    [request setValue:authorization forHTTPHeaderField:@"Authorization"];
    [request setValue:@"wxd71326872df0d3e5" forHTTPHeaderField:@"wx-appid"];
    [request setValue:@"client" forHTTPHeaderField:@"type"];
    [request setValue:@"https://w.shequ.189.cn/communityFw/h5/index.html" forHTTPHeaderField:@"Referer"];
    [request setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 16_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 MicroMessenger/8.0.58(0x18003a25) NetType/WIFI Language/zh_CN" forHTTPHeaderField:@"User-Agent"];

    NSString *cookieStr = [NSString stringWithFormat:@"accessToken=%@; appKey=%@; localId=%@; type=client",
                           accessToken, appKey, localId];
    [request setValue:cookieStr forHTTPHeaderField:@"Cookie"];

    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                completion([NSString stringWithFormat:@"请求失败: %@", error.localizedDescription]);
                return;
            }

            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            NSString *result = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

            if (httpResponse.statusCode == 200) {
                NSError *jsonError;
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
                if (!jsonError && json) {
                    NSString *msg = json[@"msg"] ?: @"未知";
                    if ([msg isEqualToString:@"成功"]) {
                        completion(@"✅ 开门成功！");
                    } else {
                        completion([NSString stringWithFormat:@"开门结果: %@", msg]);
                    }
                } else {
                    completion(@"✅ 开门成功！");
                }
            } else {
                completion([NSString stringWithFormat:@"HTTP %ld: %@", (long)httpResponse.statusCode, result]);
            }
        });
    }];
    [task resume];
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    if (!floatingButton || !keyWindow) return;

    CGPoint translation = [pan translationInView:keyWindow];
    CGPoint center = floatingButton.center;
    center.x += translation.x;
    center.y += translation.y;

    CGFloat halfWidth = floatingButton.bounds.size.width / 2;
    CGFloat halfHeight = floatingButton.bounds.size.height / 2;
    center.x = MAX(halfWidth + 10, MIN(keyWindow.bounds.size.width - halfWidth - 10, center.x));
    center.y = MAX(halfHeight + 60, MIN(keyWindow.bounds.size.height - halfHeight - 60, center.y));

    floatingButton.center = center;
    [pan setTranslation:CGPointZero inView:keyWindow];

    if (pan.state == UIGestureRecognizerStateEnded) {
        [UIView animateWithDuration:0.2 animations:^{
            CGPoint center = floatingButton.center;
            if (center.x < keyWindow.bounds.size.width / 2) {
                center.x = 38;
            } else {
                center.x = keyWindow.bounds.size.width - 38;
            }
            floatingButton.center = center;
        }];
    }
}

@end

static void createFloatingButton() {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (floatingButton) return;

        keyWindow = [UIApplication sharedApplication].keyWindow;
        if (!keyWindow) return;

        floatingButton = [UIButton buttonWithType:UIButtonTypeCustom];
        floatingButton.frame = CGRectMake(keyWindow.bounds.size.width - 76, keyWindow.bounds.size.height - 220, 56, 56);
        floatingButton.backgroundColor = [UIColor colorWithRed:0.15 green:0.6 blue:1.0 alpha:0.9];
        floatingButton.layer.cornerRadius = 28;
        floatingButton.layer.shadowColor = [UIColor blackColor].CGColor;
        floatingButton.layer.shadowOffset = CGSizeMake(0, 2);
        floatingButton.layer.shadowOpacity = 0.3;
        floatingButton.layer.shadowRadius = 6;

        [floatingButton setTitle:@"🚪" forState:UIControlStateNormal];
        floatingButton.titleLabel.font = [UIFont systemFontOfSize:26];

        [floatingButton addTarget:[GateOpenerManager shared] action:@selector(showDoorSelector) forControlEvents:UIControlEventTouchUpInside];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:[GateOpenerManager shared] action:@selector(handlePan:)];
        [floatingButton addGestureRecognizer:pan];

        [keyWindow addSubview:floatingButton];
    });
}

%hook AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    BOOL result = %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        createFloatingButton();
    });
    return result;
}

%end

%hook UIWindowScene

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        createFloatingButton();
    });
}

%end
