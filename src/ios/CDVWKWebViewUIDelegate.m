/*
 Licensed to the Apache Software Foundation (ASF) under one
 or more contributor license agreements.  See the NOTICE file
 distributed with this work for additional information
 regarding copyright ownership.  The ASF licenses this file
 to you under the Apache License, Version 2.0 (the
 "License"); you may not use this file except in compliance
 with the License.  You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing,
 software distributed under the License is distributed on an
 "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 KIND, either express or implied.  See the License for the
 specific language governing permissions and limitations
 under the License.
 */

#import "CDVWKWebViewUIDelegate.h"

static NSString* const CDV_TRUSTED_MEDIA_CAPTURE_SITES_STORAGE_KEY = @"trustedMediaCaptureSitesByType";
static NSString* const CDV_TRUSTED_MEDIA_CAPTURE_MAIN_FRAME_STORAGE_KEY = @"trustedMediaCaptureMainFrameByType";

@implementation CDVWKWebViewUIDelegate

- (instancetype)initWithTitle:(NSString*)title
{
    return [self initWithTitle:title presentingViewController:nil];
}

- (instancetype)initWithTitle:(NSString*)title presentingViewController:(UIViewController*)presentingViewController
{
    self = [super init];
    if (self) {
        self.title = title;
        self.presentingViewController = presentingViewController;
    }

    return self;
}

- (BOOL)respondsToSelector:(SEL)aSelector
{
    if ([super respondsToSelector:aSelector]) {
        return YES;
    }

    return [self.fallbackUIDelegate respondsToSelector:aSelector];
}

- (id)forwardingTargetForSelector:(SEL)aSelector
{
    if ([self.fallbackUIDelegate respondsToSelector:aSelector]) {
        return self.fallbackUIDelegate;
    }

    return [super forwardingTargetForSelector:aSelector];
}

- (UIViewController*)presentationControllerForWebView:(WKWebView*)webView
{
    UIViewController* controller = self.presentingViewController;
    if (!controller) {
        controller = webView.window.rootViewController;
    }

    while (controller.presentedViewController) {
        controller = controller.presentedViewController;
    }

    return controller;
}

- (void)     webView:(WKWebView*)webView runJavaScriptAlertPanelWithMessage:(NSString*)message
    initiatedByFrame:(WKFrameInfo*)frame completionHandler:(void (^)(void))completionHandler
{
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:self.title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction* ok = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"OK")
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction* action)
        {
            completionHandler();
            [alert dismissViewControllerAnimated:YES completion:nil];
        }];

    [alert addAction:ok];

    UIViewController* presenter = [self presentationControllerForWebView:webView];
    if (presenter) {
        [presenter presentViewController:alert animated:YES completion:nil];
    } else {
        completionHandler();
    }
}

- (void)     webView:(WKWebView*)webView runJavaScriptConfirmPanelWithMessage:(NSString*)message
    initiatedByFrame:(WKFrameInfo*)frame completionHandler:(void (^)(BOOL result))completionHandler
{
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:self.title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction* ok = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"OK")
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction* action)
        {
            completionHandler(YES);
            [alert dismissViewControllerAnimated:YES completion:nil];
        }];

    [alert addAction:ok];

    UIAlertAction* cancel = [UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"Cancel")
                                                     style:UIAlertActionStyleDefault
                                                   handler:^(UIAlertAction* action)
        {
            completionHandler(NO);
            [alert dismissViewControllerAnimated:YES completion:nil];
        }];
    [alert addAction:cancel];

    UIViewController* presenter = [self presentationControllerForWebView:webView];
    if (presenter) {
        [presenter presentViewController:alert animated:YES completion:nil];
    } else {
        completionHandler(NO);
    }
}

- (void)      webView:(WKWebView*)webView runJavaScriptTextInputPanelWithPrompt:(NSString*)prompt
          defaultText:(NSString*)defaultText initiatedByFrame:(WKFrameInfo*)frame
    completionHandler:(void (^)(NSString* result))completionHandler
{
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:self.title
                                                                   message:prompt
                                                            preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction* ok = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"OK")
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction* action)
        {
            completionHandler(((UITextField*)alert.textFields[0]).text);
            [alert dismissViewControllerAnimated:YES completion:nil];
        }];

    [alert addAction:ok];

    UIAlertAction* cancel = [UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"Cancel")
                                                     style:UIAlertActionStyleDefault
                                                   handler:^(UIAlertAction* action)
        {
            completionHandler(nil);
            [alert dismissViewControllerAnimated:YES completion:nil];
        }];
    [alert addAction:cancel];

    [alert addTextFieldWithConfigurationHandler:^(UITextField* textField) {
        textField.text = defaultText;
    }];

    UIViewController* presenter = [self presentationControllerForWebView:webView];
    if (presenter) {
        [presenter presentViewController:alert animated:YES completion:nil];
    } else {
        completionHandler(nil);
    }
}

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 150000
- (void)webView:(WKWebView*)webView
    requestMediaCapturePermissionForOrigin:(WKSecurityOrigin*)origin
                          initiatedByFrame:(WKFrameInfo*)frame
                                      type:(WKMediaCaptureType)type
                           decisionHandler:(void (^)(WKPermissionDecision decision))decisionHandler API_AVAILABLE(ios(15.0))
{
    if (@available(iOS 15.0, *)) {
        NSArray* mediaCaptureTypeKeys = [self mediaCaptureTypeKeysForType:type];

        if (mediaCaptureTypeKeys.count == 0) {
            decisionHandler(WKPermissionDecisionPrompt);

            return;
        }

        BOOL isMainFrame = [frame isMainFrame];
        NSString* siteURL = !isMainFrame ? [self trustedSiteURLForFrame:frame] : nil;

        if (isMainFrame && [self isTrustedMainFrameMediaCaptureTypeKeys:mediaCaptureTypeKeys]) {
            decisionHandler(WKPermissionDecisionGrant);

            return;
        }

        if (!isMainFrame && siteURL.length > 0 && [self isTrustedSiteURL:siteURL mediaCaptureTypeKeys:mediaCaptureTypeKeys]) {
            decisionHandler(WKPermissionDecisionGrant);

            return;
        }

        NSString* host = isMainFrame ? [self getAppName] : [self displayHostForFrame:frame origin:origin webView:webView];
        NSString* mediaName = [self mediaCapturePromptMediaNameForType:type];
        NSString* message = [NSString stringWithFormat:@"\"%@\" would like to access the %@.", host, mediaName];

        [self presentMediaCapturePromptForWebView:webView message:message
            allowHandler:^{
                if (isMainFrame) {
                    [self addTrustedMainFrameMediaCaptureTypeKeys:mediaCaptureTypeKeys];
                } else if (siteURL.length > 0) {
                    [self addTrustedSiteURL:siteURL mediaCaptureTypeKeys:mediaCaptureTypeKeys];
                }

                decisionHandler(WKPermissionDecisionGrant);
            }
            denyHandler:^{
                decisionHandler(WKPermissionDecisionDeny);
            }];

        return;
    }

    decisionHandler(WKPermissionDecisionPrompt);
}

/**
 * Builds a normalized site URL used to persist trust decisions for subframe media capture.
 *
 * The URL is sanitized by dropping fragment values, removing volatile/sensitive query
 * parameters, and normalizing tokenpluginfile path segments before storage.
 *
 * @param frame Frame that initiated the media capture request.
 * @return Normalized absolute frame URL for trust matching, or nil when it is unavailable.
 */
- (NSString*)trustedSiteURLForFrame:(WKFrameInfo*)frame API_AVAILABLE(ios(15.0))
{
    NSURL* frameURL = frame.request.URL;
    if (frameURL.absoluteString.length > 0) {
        NSURLComponents* components = [NSURLComponents componentsWithURL:frameURL resolvingAgainstBaseURL:NO];
        components.fragment = nil;

        // Remove some parameters that are not relevant to the URL and could be sensitive.
        // This could be improved in the future by allowing JS code to specify the parameters, or provide a callback to filter them.
        NSArray* ignoredQueryParamNames = @[@"lang", @"token", @"wstoken", @"privatetoken"];
        NSMutableArray* filteredQueryItems = [NSMutableArray array];

        for (NSURLQueryItem* queryItem in components.queryItems) {
            NSString* queryItemName = [queryItem.name lowercaseString];
            if (queryItemName.length > 0 && [ignoredQueryParamNames containsObject:queryItemName]) {
                continue;
            }

            [filteredQueryItems addObject:queryItem];
        }

        components.queryItems = filteredQueryItems.count > 0 ? filteredQueryItems : nil;

        NSRegularExpression* tokenPluginFilePathRegex = [NSRegularExpression regularExpressionWithPattern:@"(/tokenpluginfile\\.php/)[^/]+(/|$)"
            options:NSRegularExpressionCaseInsensitive
            error:nil];

        if (components.path.length > 0 && tokenPluginFilePathRegex != nil) {
            components.path = [tokenPluginFilePathRegex stringByReplacingMatchesInString:components.path
                options:0
                range:NSMakeRange(0, components.path.length)
                withTemplate:@"$1secret$2"];
        }

        NSString* absoluteURL = components.URL.absoluteString;
        if (absoluteURL.length > 0) {
            return absoluteURL;
        }
    }

    return nil;
}

/**
 * Resolves the security origin associated with a frame.
 *
 * WKFrameInfo's request URL can be unavailable for subframes on older iOS versions.
 * Prefer the frame's security origin, falling back to the origin supplied by WebKit.
 *
 * @param frame Frame whose security origin should be resolved.
 * @param origin Security origin supplied with the media capture request.
 * @return Frame security origin when available, otherwise the supplied origin.
 */
- (WKSecurityOrigin*)securityOriginForFrame:(WKFrameInfo*)frame fallbackOrigin:(WKSecurityOrigin*)origin API_AVAILABLE(ios(15.0))
{
    WKSecurityOrigin* frameOrigin = frame.securityOrigin;

    return frameOrigin.protocol.length > 0 && frameOrigin.host.length > 0 ? frameOrigin : origin;
}

- (BOOL)doesHost:(NSString*)host protocol:(NSString*)protocol matchWebViewURL:(NSURL*)webViewURL API_AVAILABLE(ios(15.0))
{
    NSString* webViewHost = webViewURL.host;
    NSString* webViewProtocol = webViewURL.scheme;

    return host.length > 0 && protocol.length > 0 && webViewHost.length > 0 && webViewProtocol.length > 0
        && [host caseInsensitiveCompare:webViewHost] == NSOrderedSame
        && [protocol caseInsensitiveCompare:webViewProtocol] == NSOrderedSame;
}

/**
 * Resolves a human-friendly host name for media permission prompts.
 *
 * @param frame Frame that initiated the request.
 * @param origin Security origin associated with the request.
 * @param webView Web view associated with the request.
 * @return App name when frame origin matches the current web view URL, otherwise frame/origin host, then title, then a generic fallback.
 */
- (NSString*)displayHostForFrame:(WKFrameInfo*)frame origin:(WKSecurityOrigin*)origin webView:(WKWebView*)webView API_AVAILABLE(ios(15.0))
{
    NSURL* frameURL = frame.request.URL;
    NSString* host = frameURL.host;
    if (host.length > 0) {
        if ([self doesHost:host protocol:frameURL.scheme matchWebViewURL:webView.URL]) {
            return [self getAppName];
        }

        return host;
    }

    WKSecurityOrigin* frameOrigin = [self securityOriginForFrame:frame fallbackOrigin:origin];
    if (frameOrigin.host.length > 0) {
        if ([self doesHost:frameOrigin.host protocol:frameOrigin.protocol matchWebViewURL:webView.URL]) {
            return [self getAppName];
        }

        return frameOrigin.host;
    }

    if (self.title.length > 0) {
        return self.title;
    }

    return @"this site";
}

/**
 * Resolves the best available app display name for user-facing prompt text.
 *
 * @return Title when set, otherwise bundle display name, bundle name, or "this app".
 */
- (NSString*)getAppName API_AVAILABLE(ios(15.0))
{
    if (self.title.length > 0) {
        return self.title;
    }

    NSString* displayName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"];
    if ([displayName isKindOfClass:[NSString class]] && displayName.length > 0) {
        return displayName;
    }

    NSString* bundleName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
    if ([bundleName isKindOfClass:[NSString class]] && bundleName.length > 0) {
        return bundleName;
    }

    return @"this app";
}

/**
 * Maps a WebKit media capture type to persistent capability keys.
 *
 * @param type Requested WebKit media capture type.
 * @return Capability keys used in user defaults, or an empty array for unsupported values.
 */
- (NSArray*)mediaCaptureTypeKeysForType:(WKMediaCaptureType)type API_AVAILABLE(ios(15.0))
{
    switch (type) {
        case WKMediaCaptureTypeMicrophone:
            return @[@"microphone"];
        case WKMediaCaptureTypeCamera:
            return @[@"camera"];
        case WKMediaCaptureTypeCameraAndMicrophone:
            return @[@"camera", @"microphone"];
        default:
            return @[];
    }
}

/**
 * Maps a WebKit media capture type to a user-facing label for permission prompts.
 *
 * @param type Requested WebKit media capture type.
 * @return Readable media name shown to the user.
 */
- (NSString*)mediaCapturePromptMediaNameForType:(WKMediaCaptureType)type API_AVAILABLE(ios(15.0))
{
    switch (type) {
        case WKMediaCaptureTypeMicrophone:
            return @"microphone";
        case WKMediaCaptureTypeCamera:
            return @"camera";
        case WKMediaCaptureTypeCameraAndMicrophone:
            return @"camera and microphone";
        default:
            return @"media devices";
    }
}

/**
 * Checks whether a subframe site URL has already been trusted for all required capture capabilities.
 *
 * @param siteURL Normalized site URL for the requesting subframe.
 * @param mediaCaptureTypeKeys Persistent keys representing the required capture capabilities.
 * @return YES when the URL is trusted for every required media capability; otherwise NO.
 */
- (BOOL)isTrustedSiteURL:(NSString*)siteURL mediaCaptureTypeKeys:(NSArray*)mediaCaptureTypeKeys API_AVAILABLE(ios(15.0))
{
    // In sub frames (e.g. iframes), request once per permission capability and URL. If URL is different, it will be asked again.
    NSDictionary* trustedSitesByType = [[NSUserDefaults standardUserDefaults] dictionaryForKey:CDV_TRUSTED_MEDIA_CAPTURE_SITES_STORAGE_KEY];
    if (![trustedSitesByType isKindOfClass:[NSDictionary class]]) {
        return NO;
    }

    for (NSString* mediaCaptureTypeKey in mediaCaptureTypeKeys) {
        NSArray* trustedSites = [trustedSitesByType objectForKey:mediaCaptureTypeKey];
        if (![trustedSites isKindOfClass:[NSArray class]]) {
            return NO;
        }

        if (![trustedSites containsObject:siteURL]) {
            return NO;
        }
    }

    return YES;
}

/**
 * Checks whether the main frame has already been trusted for all required capture capabilities.
 *
 * @param mediaCaptureTypeKeys Persistent keys representing the required capture capabilities.
 * @return YES when main-frame trust is stored for every required media capability; otherwise NO.
 */
- (BOOL)isTrustedMainFrameMediaCaptureTypeKeys:(NSArray*)mediaCaptureTypeKeys API_AVAILABLE(ios(15.0))
{
    // In main frame, only request once per permission capability. If permission is granted, it won't be asked again.
    NSDictionary* trustedMainFrameByType = [[NSUserDefaults standardUserDefaults] dictionaryForKey:CDV_TRUSTED_MEDIA_CAPTURE_MAIN_FRAME_STORAGE_KEY];
    if (![trustedMainFrameByType isKindOfClass:[NSDictionary class]]) {
        return NO;
    }

    for (NSString* mediaCaptureTypeKey in mediaCaptureTypeKeys) {
        NSNumber* isTrusted = [trustedMainFrameByType objectForKey:mediaCaptureTypeKey];
        if (![isTrusted isKindOfClass:[NSNumber class]]) {
            return NO;
        }

        if (![isTrusted boolValue]) {
            return NO;
        }
    }

    return YES;
}

/**
 * Persists trust for required media capture capabilities in main-frame requests.
 *
 * @param mediaCaptureTypeKeys Persistent keys representing the capture capabilities to trust.
 */
- (void)addTrustedMainFrameMediaCaptureTypeKeys:(NSArray*)mediaCaptureTypeKeys API_AVAILABLE(ios(15.0))
{
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    NSDictionary* trustedMainFrameByType = [userDefaults dictionaryForKey:CDV_TRUSTED_MEDIA_CAPTURE_MAIN_FRAME_STORAGE_KEY];

    NSMutableDictionary* mutableTrustedMainFrameByType = [trustedMainFrameByType isKindOfClass:[NSDictionary class]] ?
        [trustedMainFrameByType mutableCopy] :
        [NSMutableDictionary dictionary];

    BOOL hasChanges = NO;

    for (NSString* mediaCaptureTypeKey in mediaCaptureTypeKeys) {
        NSNumber* isTrusted = [mutableTrustedMainFrameByType objectForKey:mediaCaptureTypeKey];
        if ([isTrusted isKindOfClass:[NSNumber class]] && [isTrusted boolValue]) {
            continue;
        }

        [mutableTrustedMainFrameByType setObject:@(YES) forKey:mediaCaptureTypeKey];
        hasChanges = YES;
    }

    if (!hasChanges) {
        return;
    }

    [userDefaults setObject:mutableTrustedMainFrameByType forKey:CDV_TRUSTED_MEDIA_CAPTURE_MAIN_FRAME_STORAGE_KEY];
    [userDefaults synchronize];
}

/**
 * Persists trust for a specific subframe site URL and required media capture capabilities.
 *
 * @param siteURL Normalized site URL to trust.
 * @param mediaCaptureTypeKeys Persistent keys representing the capture capabilities to trust.
 */
- (void)addTrustedSiteURL:(NSString*)siteURL mediaCaptureTypeKeys:(NSArray*)mediaCaptureTypeKeys API_AVAILABLE(ios(15.0))
{

    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    NSDictionary* trustedSitesByType = [userDefaults dictionaryForKey:CDV_TRUSTED_MEDIA_CAPTURE_SITES_STORAGE_KEY];

    NSMutableDictionary* mutableTrustedSitesByType = [trustedSitesByType isKindOfClass:[NSDictionary class]] ?
        [trustedSitesByType mutableCopy] :
        [NSMutableDictionary dictionary];

    BOOL hasChanges = NO;

    for (NSString* mediaCaptureTypeKey in mediaCaptureTypeKeys) {
        NSArray* trustedSites = [mutableTrustedSitesByType objectForKey:mediaCaptureTypeKey];
        NSMutableArray* mutableTrustedSites = [trustedSites isKindOfClass:[NSArray class]] ?
            [trustedSites mutableCopy] :
            [NSMutableArray array];

        if ([mutableTrustedSites containsObject:siteURL]) {
            continue;
        }

        [mutableTrustedSites addObject:siteURL];
        [mutableTrustedSitesByType setObject:mutableTrustedSites forKey:mediaCaptureTypeKey];
        hasChanges = YES;
    }

    if (!hasChanges) {
        return;
    }

    [userDefaults setObject:mutableTrustedSitesByType forKey:CDV_TRUSTED_MEDIA_CAPTURE_SITES_STORAGE_KEY];
    [userDefaults synchronize];
}

/**
 * Presents the native media-capture confirmation prompt and invokes the selected callback.
 *
 * @param webView Web view requesting media access.
 * @param message Prompt message shown to the user.
 * @param allowHandler Callback invoked when the user allows access.
 * @param denyHandler Callback invoked when the user denies access or no presenter is available.
 */
- (void)presentMediaCapturePromptForWebView:(WKWebView*)webView
                                    message:(NSString*)message
                               allowHandler:(void (^)(void))allowHandler
                                denyHandler:(void (^)(void))denyHandler API_AVAILABLE(ios(15.0))
{
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:nil
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];

        UIAlertAction* deny = [UIAlertAction actionWithTitle:NSLocalizedString(@"Don't Allow", @"Don't Allow")
            style:UIAlertActionStyleCancel
            handler:^(UIAlertAction* action)
            {
                denyHandler();
                [alert dismissViewControllerAnimated:YES completion:nil];
            }];

        [alert addAction:deny];

        UIAlertAction* allow = [UIAlertAction actionWithTitle:NSLocalizedString(@"Allow", @"Allow")
            style:UIAlertActionStyleDefault
            handler:^(UIAlertAction* action)
            {
                allowHandler();
                [alert dismissViewControllerAnimated:YES completion:nil];
            }];

        [alert addAction:allow];

        UIViewController* presenter = [self presentationControllerForWebView:webView];
        if (presenter) {
            [presenter presentViewController:alert animated:YES completion:nil];
        } else {
            denyHandler();
        }
    });
}
#endif

@end
