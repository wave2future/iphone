#import <UIKit/UIKit.h>

@interface MainTabBar : UITabBarController <UITabBarControllerDelegate> {

}

- (void)setupView:(UIViewController *)view title:(NSString *)title image:(NSString *)image;
+ (UIColor *)yammerGray;
- (void)addCompose;
- (id)initWithNavigatorURL:(NSURL*)URL query:(NSDictionary*)query;

@end
