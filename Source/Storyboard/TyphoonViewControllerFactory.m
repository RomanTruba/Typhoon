////////////////////////////////////////////////////////////////////////////////
//
//  TYPHOON FRAMEWORK
//  Copyright 2015, Typhoon Framework Contributors
//  All Rights Reserved.
//
//  NOTICE: The authors permit you to use, modify, and distribute this file
//  in accordance with the terms of the license agreement accompanying it.
//
////////////////////////////////////////////////////////////////////////////////

#import "TyphoonViewControllerFactory.h"

#import "TyphoonStoryboardDefinitionContext.h"
#import "TyphoonComponentFactory+Storyboard.h"
#import "TyphoonComponentFactory+TyphoonDefinitionRegisterer.h"
#import "ViewController+TyphoonStoryboardIntegration.h"
#import "View+TyphoonDefinitionKey.h"
#import "TyphoonDefinition+InstanceBuilder.h"
#import "TyphoonInjectionContext.h"
#import "TyphoonAbstractInjection.h"
#import "TyphoonViewControllerInjector.h"
#import "TyphoonAssemblyAccessor.h"

static NSDictionary *viewControllerClassMap;
static NSDictionary *viewControllerTyphoonKeyMap;

@implementation TyphoonViewControllerFactory

+ (NSDictionary *)viewControllerClassMap {
    if (!viewControllerClassMap) {
        viewControllerClassMap = @{};
    }
    return viewControllerClassMap;
}

+ (NSDictionary *)viewControllerTyphoonKeyMap {
    if (!viewControllerTyphoonKeyMap) {
        viewControllerTyphoonKeyMap = @{};
    }
    return viewControllerTyphoonKeyMap;
}

+ (void)cacheControllerClass:(Class)controllerClass forKey:(NSString *)key {
    NSMutableDictionary *map = [[self viewControllerClassMap] mutableCopy];
    map[key] = controllerClass;
    viewControllerClassMap = [map copy];
}

+ (void)cacheTyphoonKey:(NSString *)typhoonKey forKey:(NSString *)key {
    NSMutableDictionary *map = [[self viewControllerTyphoonKeyMap] mutableCopy];
    map[key] = typhoonKey;
    viewControllerTyphoonKeyMap = [map copy];
}

+ (TyphoonComponentFactory *)factoryFromFactoryCompatable:(id<TyphoonComponentFactory>)factoryCompatible
{
    if ([factoryCompatible isKindOfClass:[TyphoonComponentFactory class]]) {
        return (id)factoryCompatible;
    } else if ([factoryCompatible respondsToSelector:@selector(factory)]) {
        id factory = [(TyphoonAssemblyAccessor *)factoryCompatible factory];
        if ([factory isKindOfClass:[TyphoonComponentFactory class]]) {
            return factory;
        }
    }
    [NSException raise:NSInternalInconsistencyException format:@"Can't TyphoonComponentFactory from %@ instance", factoryCompatible];
    return nil;
}

+ (TyphoonViewControllerBaseClass *)viewControllerWithStoryboardContext:(TyphoonStoryboardDefinitionContext *)context
                                         injectionContext:(TyphoonInjectionContext *)injectionContext
                                                  factory:(id<TyphoonComponentFactory>)factoryCompatible
{
    TyphoonComponentFactory *factory = [self factoryFromFactoryCompatable:factoryCompatible];
    
    id<TyphoonComponentsPool> storyboardPool = [factory storyboardPool];
    __block NSString *storyboardName = nil;
    [context.storyboardName valueToInjectWithContext:injectionContext completion:^(id value) {
        storyboardName = value;
    }];

    TyphoonStoryboardClass *storyboard = storyboardPool[storyboardName];
    if (!storyboard) {
        storyboard = [TyphoonStoryboard storyboardWithName:storyboardName
                                                   factory:factory
                                                    bundle:[NSBundle bundleForClass:[self class]]];
        @synchronized(self) {
            storyboardPool[storyboardName] = storyboard;
        }
    }
    
    __block NSString *viewControllerId = nil;
    [context.viewControllerId valueToInjectWithContext:injectionContext completion:^(id value) {
        viewControllerId = value;
    }];
#if TARGET_OS_IPHONE || TARGET_OS_TV
    TyphoonViewControllerBaseClass *viewController = [storyboard instantiateViewControllerWithIdentifier:viewControllerId];
#elif TARGET_OS_MAC
    TyphoonViewControllerBaseClass *viewController = [storyboard instantiateControllerWithIdentifier:viewControllerId];
#endif
    
    NSString *key = [self viewControllerMapKeyWithIdentifier:viewControllerId storyboardName:storyboardName];
    [self cacheControllerClass:[viewController class] forKey:key];
    if (viewController.typhoonKey) {
        [self cacheTyphoonKey:viewController.typhoonKey forKey:key];
    }
    
    return viewController;
}

+ (TyphoonViewControllerBaseClass *)viewControllerWithIdentifier:(NSString *)identifier
                                                  storyboard:(TyphoonStoryboard *)storyboard
{
    TyphoonViewControllerBaseClass *prototype = [storyboard instantiatePrototypeViewControllerWithIdentifier:identifier];
    TyphoonViewControllerBaseClass *result = [self configureOrObtainFromPoolViewControllerForInstance:prototype
                                                                            withFactory:storyboard.factory
                                                                             storyboard:storyboard];
     NSString *key = [self viewControllerMapKeyWithIdentifier:identifier storyboardName:storyboard.storyboardName];
    [self cacheControllerClass:[result class] forKey:key];
    if (result.typhoonKey) {
        [self cacheTyphoonKey:result.typhoonKey forKey:key];
    }

    return result;
}

+ (TyphoonViewControllerBaseClass *)cachedViewControllerWithIdentifier:(NSString *)identifier
                                                    storyboardName:(NSString *)storyboardName
                                                           factory:(id<TyphoonComponentFactory>)factoryCompatible
{
    TyphoonComponentFactory *factory = [self factoryFromFactoryCompatable:factoryCompatible];
    
    NSDictionary *classMap = [self viewControllerClassMap];
    NSDictionary *typhoonKeyMap = [self viewControllerTyphoonKeyMap];
    NSString *key = [self viewControllerMapKeyWithIdentifier:identifier storyboardName:storyboardName];
    Class viewControllerClass = classMap[key];
    NSString *typhoonKey = typhoonKeyMap[key];
    return [factory scopeCachedViewControllerForClass:viewControllerClass typhoonKey:typhoonKey];
}

+ (id)configureOrObtainFromPoolViewControllerForInstance:(TyphoonViewControllerBaseClass *)instance
                                             withFactory:(id<TyphoonComponentFactory>)factoryCompatible
                                              storyboard:(TyphoonStoryboard *)storyboard
{
    TyphoonComponentFactory *factory = [self factoryFromFactoryCompatable:factoryCompatible];

    TyphoonViewControllerBaseClass *cachedInstance = [factory scopeCachedViewControllerForInstance:instance typhoonKey:instance.typhoonKey];
    
    if (cachedInstance) {
        return cachedInstance;
    }
    
    TyphoonViewControllerInjector *injector = [TyphoonViewControllerInjector new];
    [injector injectPropertiesForViewController:instance withFactory:factory storyboard:storyboard];
    
    return instance;
}


+ (NSString *)viewControllerMapKeyWithIdentifier:(NSString *)identifier storyboardName:(NSString *)storyboardName {
    return [NSString stringWithFormat:@"%@-%@", storyboardName, identifier];
}

@end