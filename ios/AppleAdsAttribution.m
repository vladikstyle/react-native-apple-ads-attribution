#import "AppleAdsAttribution.h"
#import <React/RCTLog.h>
#import <AdServices/AdServices.h>

@implementation AppleAdsAttribution
static NSString *const RNAAAErrorDomain = @"RNAAAErrorDomain";
static int NUM_RETRIES = 3;

RCT_EXPORT_MODULE();

- (dispatch_queue_t)methodQueue {
    return dispatch_get_main_queue();
}

+ (void)rejectPromiseWithNSError:(RCTPromiseRejectBlock)reject error:(NSError * _Nullable)error {
    if (error == NULL) {
        reject(@"unknown", @"Failed with unknown error", nil);
    } else {
        NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
        [userInfo setValue:error forKey:@"message"];
        [userInfo setValue:@(error.code) forKey:@"nativeErrorCode"];
        NSError *newErrorWithUserInfo = [NSError errorWithDomain:RNAAAErrorDomain
                                                            code:100
                                                        userInfo:userInfo];
        reject(@"unknown", error.localizedDescription, newErrorWithUserInfo);
    }
}

+ (void)rejectPromiseWithUserInfo:(RCTPromiseRejectBlock)reject userInfo:(NSMutableDictionary *)userInfo {
    NSError *error = [NSError errorWithDomain:RNAAAErrorDomain code:100 userInfo:userInfo];
    reject(userInfo[@"code"], userInfo[@"message"], error);
}

+ (BOOL)isSimulator {
#if (TARGET_OS_SIMULATOR)
    return YES;
#else
    return NO;
#endif
}

/**
 * Uses the provided token to request attribution data from Apple's AdServices API.
 */
+ (void)requestAdServicesAttributionDataUsingToken:(NSString *)token
                                       retriesLeft:(int)retriesLeft
                                 completionHandler:(void (^)(NSDictionary * _Nullable data, NSError * _Nullable error))completionHandler
API_AVAILABLE(ios(14.3)) {
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"text/plain" forHTTPHeaderField:@"Content-Type"];
    [request setURL:[NSURL URLWithString:@"https://api-adservices.apple.com/api/v1/"]];
    [request setHTTPBody:[token dataUsingEncoding:NSUTF8StringEncoding]];

    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable reqError) {
        if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
            NSInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
            if (statusCode != 200) {
                if ((statusCode == 404 || statusCode == 500) && retriesLeft > 0) {
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        [AppleAdsAttribution requestAdServicesAttributionDataUsingToken:token retriesLeft:retriesLeft-1 completionHandler:completionHandler];
                    });
                } else {
                    NSMutableDictionary *details = [NSMutableDictionary dictionary];
                    [details setValue:[NSString stringWithFormat:@"Request to get data from AdServices API failed with status code %ld. Re-tried %i times", (long)statusCode, NUM_RETRIES - retriesLeft] forKey:NSLocalizedDescriptionKey];
                    NSError *error = [NSError errorWithDomain:RNAAAErrorDomain code:100 userInfo:details];
                    completionHandler(nil, error);
                }
                return;
            }
        }

        if (reqError != nil) {
            completionHandler(nil, reqError);
        } else if (data) {
            NSError *serializationError = nil;
            NSDictionary *attributionDataDictionary = [NSJSONSerialization JSONObjectWithData:data options:0 error:&serializationError];
            if (!serializationError && attributionDataDictionary) {
                completionHandler(attributionDataDictionary, nil);
            } else {
                completionHandler(nil, serializationError);
            }
        } else {
            NSMutableDictionary *details = [NSMutableDictionary dictionary];
            [details setValue:@"Request to AdServices API failed with unknown error" forKey:NSLocalizedDescriptionKey];
            NSError *error = [NSError errorWithDomain:RNAAAErrorDomain code:100 userInfo:details];
            completionHandler(nil, error);
        }
    }] resume];
}

/**
 * Tries to generate an attribution token that then can be used for calls to Apple's AdServices API.
 * Returns nil if token couldn't be generated.
 */
+ (NSString *)getAdServicesAttributionToken:(NSError * _Nullable *)error {
    if ([AppleAdsAttribution isSimulator]) {
        if (error != NULL) {
            NSMutableDictionary *details = [NSMutableDictionary dictionary];
            [details setValue:@"Error getting token, not available in Simulator" forKey:NSLocalizedDescriptionKey];
            *error = [NSError errorWithDomain:RNAAAErrorDomain code:100 userInfo:details];
        }
        return nil;
    }

    if (@available(iOS 14.3, *)) {
        Class AAAttributionClass = NSClassFromString(@"AAAttribution");
        if (AAAttributionClass) {
            NSString *attributionToken = [AAAttributionClass attributionTokenWithError:error];
            if (*error == nil && attributionToken) {
                return attributionToken;
            }
        } else {
            NSMutableDictionary *details = [NSMutableDictionary dictionary];
            [details setValue:@"Error getting token, AAAttributionClass not found" forKey:NSLocalizedDescriptionKey];
            *error = [NSError errorWithDomain:RNAAAErrorDomain code:100 userInfo:details];
        }
    } else if (error != NULL) {
        NSMutableDictionary *details = [NSMutableDictionary dictionary];
        [details setValue:@"Error getting token, AdServices not available pre iOS 14.3" forKey:NSLocalizedDescriptionKey];
        *error = [NSError errorWithDomain:RNAAAErrorDomain code:100 userInfo:details];
    }
    return nil;
}

/**
 * Generates an attribution token that it then uses to request attribution data from Apple's AdServices API.
 * Returns an error if attribution data couldn't be fetched.
 */
+ (void)getAdServicesAttributionDataWithCompletionHandler:(void (^)(NSDictionary * _Nullable data, NSError * _Nullable error))completionHandler {
    if (@available(iOS 14.3, *)) {
        NSError *tokenError = nil;
        NSString *attributionToken = [AppleAdsAttribution getAdServicesAttributionToken:&tokenError];

        if (attributionToken) {
            [AppleAdsAttribution requestAdServicesAttributionDataUsingToken:attributionToken retriesLeft:NUM_RETRIES completionHandler:completionHandler];
        } else {
            completionHandler(nil, tokenError);
        }
    } else {
        NSMutableDictionary *details = [NSMutableDictionary dictionary];
        [details setValue:@"AdServices not available pre iOS 14.3" forKey:NSLocalizedDescriptionKey];
        NSError *error = [NSError errorWithDomain:RNAAAErrorDomain code:100 userInfo:details];
        completionHandler(nil, error);
    }
}

RCT_EXPORT_METHOD(getAdServicesAttributionToken:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    NSError *error = nil;
    NSString *attributionToken = [AppleAdsAttribution getAdServicesAttributionToken:&error];

    if (attributionToken != nil) {
        resolve(attributionToken);
    } else {
        [AppleAdsAttribution rejectPromiseWithNSError:reject error:error];
    }
}

RCT_EXPORT_METHOD(getAdServicesAttributionData:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    [AppleAdsAttribution getAdServicesAttributionDataWithCompletionHandler:^(NSDictionary * _Nullable attributionData, NSError * _Nullable error) {
        if (attributionData != nil) {
            resolve(attributionData);
        } else {
            [AppleAdsAttribution rejectPromiseWithNSError:reject error:error];
        }
    }];
}

@end
