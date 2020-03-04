//
//  ViewController.m
//  TSMSGHookDemo
//
//  Created by YYInc on 2020/3/4.
//  Copyright © 2020 caoxuerui. All rights reserved.
//

#import "ViewController.h"
#import "TSHookMSG.h"
#include <objc/runtime.h>

@interface ViewController ()

@end

@implementation ViewController

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        SEL fromSelectorAppear = @selector(viewWillAppear:);
        SEL toSelectorAppear = @selector(clsCallHookViewWillAppear:);
        [ViewController hookClass:self fromSelector:fromSelectorAppear toSelector:toSelectorAppear];

        SEL fromSelectorDisappear = @selector(viewWillDisappear:);
        SEL toSelectorDisappear = @selector(clsCallHookViewWillDisappear:);

        [ViewController hookClass:self fromSelector:fromSelectorDisappear toSelector:toSelectorDisappear];
    });
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    [ViewController startWithMaxDepth:0];
    
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = CGRectMake(100, 100, 100, 100);
    button.backgroundColor = [UIColor blueColor];
    [button addTarget:self action:@selector(buttonCilck) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:button];
    
    [ViewController save];
}

- (void)buttonCilck {
    [self.navigationController pushViewController:[UIViewController new] animated:YES];
}

+ (void)startWithMaxDepth:(int)depth {
    smCallConfigMaxDepth(depth);
    [ViewController startFunction];
}

+ (void)startFunction {
    smCallTraceStart();
}

+ (void)save {
//    NSMutableString *mStr = [NSMutableString new];
//    NSArray<SMCallTraceTimeCostModel *> *arr = [self loadRecords];
//    for (SMCallTraceTimeCostModel *model in arr) {
//        //记录方法路径
//        model.path = [NSString stringWithFormat:@"[%@ %@]",model.className,model.methodName];
//        [self appendRecord:model to:mStr];
//    }
    
//    NSLog(@"time：%@",mStr);
    [self loadRecords];
}

+ (void)loadRecords {
//    NSMutableArray<SMCallTraceTimeCostModel *> *arr = [NSMutableArray new];
    NSString *className;
    NSString *methodName;
    BOOL isClassMethod;
    NSTimeInterval timeCost;
    NSUInteger callDepth;
    NSString *path;
    BOOL lastCall;
    NSUInteger frequency;
    int num = 0;
    smCallRecord *records = smGetCallRecords(&num);
    for (int i = 0; i < num; i++) {
        smCallRecord *rd = &records[i];
//        SMCallTraceTimeCostModel *model = [SMCallTraceTimeCostModel new];
        className = NSStringFromClass(rd->cls);
        methodName = NSStringFromSelector(rd->sel);
        isClassMethod = class_isMetaClass(rd->cls);
        timeCost = (double)rd->time / 1000000.0;
        callDepth = rd->depth;
//        [arr addObject:model];
        NSLog(@"className:%@,methodName:%@,timeCost:%f",className,methodName,timeCost);
    }
//    NSUInteger count = arr.count;
//    for (NSUInteger i = 0; i < count; i++) {
//        SMCallTraceTimeCostModel *model = arr[i];
//        if (model.callDepth > 0) {
//            [arr removeObjectAtIndex:i];
//            //Todo:不需要循环，直接设置下一个，然后判断好边界就行
//            for (NSUInteger j = i; j < count - 1; j++) {
//                //下一个深度小的话就开始将后面的递归的往 sub array 里添加
//                if (arr[j].callDepth + 1 == model.callDepth) {
//                    NSMutableArray *sub = (NSMutableArray *)arr[j].subCosts;
//                    if (!sub) {
//                        sub = [NSMutableArray new];
//                        arr[j].subCosts = sub;
//                    }
//                    [sub insertObject:model atIndex:0];
//                }
//            }
//            i--;
//            count--;
//        }
//    }
//    return arr;
}

#pragma mark - Method Hook
- (void)clsCallHookViewWillAppear:(BOOL)animated {
    //执行插入代码
    [self clsCallInsertToViewWillAppear];
    [self clsCallHookViewWillAppear:animated];
}
- (void)clsCallHookViewWillDisappear:(BOOL)animated {
    //执行插入代码
    [self clsCallInsertToViewWillDisappear];
    [self clsCallHookViewWillDisappear:animated];
}

- (void)clsCallInsertToViewWillAppear {
    //显示
    [ViewController startWithMaxDepth:0];
}
- (void)clsCallInsertToViewWillDisappear {
    //消失
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        [ViewController save];
    });
}

+ (void)hookClass:(Class)classObject fromSelector:(SEL)fromSelector toSelector:(SEL)toSelector {
    Class class = classObject;
    
    Method fromMethod = class_getInstanceMethod(class, fromSelector);
    Method toMethod = class_getInstanceMethod(class, toSelector);
    
    if(class_addMethod(class, fromSelector, method_getImplementation(toMethod), method_getTypeEncoding(toMethod))) {
        class_replaceMethod(class, toSelector, method_getImplementation(fromMethod), method_getTypeEncoding(fromMethod));
    } else {
        method_exchangeImplementations(fromMethod, toMethod);
    }
    
}

@end
