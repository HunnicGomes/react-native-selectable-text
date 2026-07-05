#import <Foundation/Foundation.h>

int main() {
    @autoreleasepool {
        NSArray *options = @[@"Copy", @"Paste", @"Select All", @"Look Up", @"Translate...", @"Share...", @"Some Special-Char Option!"];

        NSDate *start = [NSDate date];

        for (int i = 0; i < 10000; i++) {
            for (NSString *option in options) {
                NSString *selectorName = [[option stringByReplacingOccurrencesOfString:@" " withString:@"_"]
                                                    stringByReplacingOccurrencesOfString:@"[^a-zA-Z0-9_]"
                                                    withString:@"_"
                                                    options:NSRegularExpressionSearch
                                                    range:NSMakeRange(0, option.length)];
            }
        }

        NSTimeInterval baselineTime = [[NSDate date] timeIntervalSinceDate:start];
        NSLog(@"Baseline time (regex in loop): %f seconds", baselineTime);

        NSMutableDictionary *origToCleaned = [NSMutableDictionary dictionary];
        for (NSString *option in options) {
            NSString *selectorName = [[option stringByReplacingOccurrencesOfString:@" " withString:@"_"]
                                                stringByReplacingOccurrencesOfString:@"[^a-zA-Z0-9_]"
                                                withString:@"_"
                                                options:NSRegularExpressionSearch
                                                range:NSMakeRange(0, option.length)];
            origToCleaned[option] = selectorName;
        }

        start = [NSDate date];
        for (int i = 0; i < 10000; i++) {
            for (NSString *option in options) {
                NSString *selectorName = origToCleaned[option];
            }
        }
        NSTimeInterval cachedTime = [[NSDate date] timeIntervalSinceDate:start];
        NSLog(@"Cached time (dictionary lookup): %f seconds", cachedTime);

        NSLog(@"Speedup: %.2fx", baselineTime / cachedTime);
    }
    return 0;
}
