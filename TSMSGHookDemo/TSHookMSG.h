//
//  TSHookMSG.h
//  hookDemo
//
//  Created by YYInc on 2019/3/10.
//  Copyright © 2019年 caoxuerui. All rights reserved.
//

#ifndef TSHookMSG_h
#define TSHookMSG_h

#include <stdio.h>
#include <objc/objc.h>

typedef struct {
    __unsafe_unretained Class cls;
    SEL sel;
    uint64_t time; // us (1/1000 ms)
    int depth;
} smCallRecord;

extern void smCallTraceStart(void);
extern void smCallTraceStop(void);

extern void smCallConfigMinTime(uint64_t us); //default 1000
extern void smCallConfigMaxDepth(int depth);  //default 3

extern smCallRecord *smGetCallRecords(int *num);

extern void smClearCallRecords(void);

#endif /* TSHookMSG_h */
