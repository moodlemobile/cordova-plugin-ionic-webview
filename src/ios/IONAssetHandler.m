#import "IONAssetHandler.h"
#import <MobileCoreServices/MobileCoreServices.h>
#import "CDVWKWebViewEngine.h"

@implementation IONAssetHandler

-(void)setAssetPath:(NSString *)assetPath {
    self.basePath = assetPath;
}

- (instancetype)initWithBasePath:(NSString *)basePath andScheme:(NSString *)scheme {
    self = [super init];
    if (self) {
        _basePath = basePath;
        _scheme = scheme;
    }
    return self;
}

- (void)webView:(WKWebView *)webView startURLSchemeTask:(id <WKURLSchemeTask>)urlSchemeTask {
    NSString * startPath = @""; // Initialize startPath
    NSURL * url = urlSchemeTask.request.URL; // Extract URL from the request
    NSString * stringToLoad = url.path; // Get the path component of the URL
    NSString * scheme = url.scheme; // Get the scheme of the URL
    // Check if the URL's scheme matches the custom scheme
    if ([scheme isEqualToString:self.scheme]) {
        // If the path starts with "/_app_file_", strip this prefix
        if ([stringToLoad hasPrefix:@"/_app_file_"]) {
            startPath = [stringToLoad stringByReplacingOccurrencesOfString:@"/_app_file_" withString:@""];
        } else {
            // Otherwise, build the path relative to self.basePath
            startPath = self.basePath ? self.basePath : @"";
            if ([stringToLoad isEqualToString:@""] || [url.pathExtension isEqualToString:@""]) {
                startPath = [startPath stringByAppendingString:@"/index.html"];
            } else {
                startPath = [startPath stringByAppendingString:stringToLoad];
            }
        }
    }   
    NSError * fileError = nil;
    NSData * data = nil;
    NSString * mimeType = [self getMimeType:url.pathExtension]; // Get MIME type based on file extension
    NSInteger statusCode = 200; // Default to 200 OK status
    NSURL * localUrl = [NSURL URLWithString:url.absoluteString]; // Create a URL object
    id response = nil;

    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:startPath]) {
        // File not found, return 404
        statusCode = 404;
        response = [[NSHTTPURLResponse alloc] initWithURL:localUrl statusCode:statusCode HTTPVersion:nil headerFields:@{ @"Content-Type" : mimeType, @"Cache-Control": @"no-cache" }];
        [urlSchemeTask didReceiveResponse:response];
        [urlSchemeTask didFinish];
        return;
    }

    // Check for Range header
    NSString *rangeHeader = [urlSchemeTask.request valueForHTTPHeaderField:@"Range"];
    NSUInteger fileLength = (NSUInteger)[[fileManager attributesOfItemAtPath:startPath error:nil] fileSize];

    if (rangeHeader) {
        NSRange range = NSMakeRange(NSNotFound, 0);
        if ([rangeHeader hasPrefix:@"bytes="]) {
            NSString *byteRange = [rangeHeader substringFromIndex:6];
            NSArray<NSString *> *rangeParts = [byteRange componentsSeparatedByString:@"-"];
            NSUInteger start = (NSUInteger)[rangeParts[0] integerValue];
            NSUInteger end = rangeParts.count > 1 && ![rangeParts[1] isEqualToString:@""] ? (NSUInteger)[rangeParts[1] integerValue] : fileLength - 1;
            range = NSMakeRange(start, end - start + 1);
        }
  
        if (range.location != NSNotFound) {
            // Ensure range is valid
            if (range.location >= fileLength) {
                statusCode = 416; // Requested Range Not Satisfiable
                response = [[NSHTTPURLResponse alloc] initWithURL:localUrl statusCode:statusCode HTTPVersion:nil headerFields:@{ @"Content-Type" : mimeType, @"Content-Range": [NSString stringWithFormat:@"bytes */%lu", (unsigned long)fileLength], @"Cache-Control": @"no-cache" }];
                [urlSchemeTask didReceiveResponse:response];
                [urlSchemeTask didFinish];
                return;
            }

            NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingAtPath:startPath];
            [fileHandle seekToFileOffset:range.location];
            data = [fileHandle readDataOfLength:range.length];
            [fileHandle closeFile];

            statusCode = 206; // Partial Content
            NSString *contentRange = [NSString stringWithFormat:@"bytes %lu-%lu/%lu", (unsigned long)range.location, (unsigned long)(range.location + range.length - 1), (unsigned long)fileLength];
            response = [[NSHTTPURLResponse alloc] initWithURL:localUrl statusCode:statusCode HTTPVersion:nil headerFields:@{ @"Content-Type" : mimeType, @"Content-Range": contentRange, @"Content-Length": [NSString stringWithFormat:@"%lu", (unsigned long)range.length], @"Cache-Control": @"no-cache" }];
        }
    }

    if (!response) {
        // Load entire file if no range is requested
        data = [NSData dataWithContentsOfFile:startPath options:NSDataReadingMappedIfSafe error:&fileError];
        if (!data || fileError) {
            data =  [[NSData alloc] initWithContentsOfFile:startPath];
        }
        
        if (!data) {
            statusCode = 404;
        }
    
        NSDictionary *headers = @{ @"Content-Type" : mimeType, @"Cache-Control": @"no-cache" };
        response = [[NSHTTPURLResponse alloc] initWithURL:localUrl statusCode:statusCode HTTPVersion:nil headerFields:headers];
    }   // Send response and data to the WKWebView
    [urlSchemeTask didReceiveResponse:response];
    if (data) {
        [urlSchemeTask didReceiveData:data];
    }
    [urlSchemeTask didFinish];
}

- (void)webView:(nonnull WKWebView *)webView stopURLSchemeTask:(nonnull id<WKURLSchemeTask>)urlSchemeTask
{
    NSLog(@"stop");
}

-(NSString *) getMimeType:(NSString *)fileExtension {
    if (fileExtension && ![fileExtension isEqualToString:@""]) {
        NSString *UTI = (__bridge_transfer NSString *)UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)fileExtension, NULL);
        NSString *contentType = (__bridge_transfer NSString *)UTTypeCopyPreferredTagWithClass((__bridge CFStringRef)UTI, kUTTagClassMIMEType);
        return contentType ? contentType : @"application/octet-stream";
    } else {
        return @"text/html";
    }
}

-(BOOL) isMediaExtension:(NSString *) pathExtension {
    NSArray * mediaExtensions = @[@"m4v", @"mov", @"mp4",
                           @"aac", @"ac3", @"aiff", @"au", @"flac", @"m4a", @"mp3", @"wav"];
    if ([mediaExtensions containsObject:pathExtension.lowercaseString]) {
        return YES;
    }
    return NO;
}


@end
