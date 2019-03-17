# hook objc_msgSend从而获得OC方法执行时间

## 1.如何获取oc方法的执行时间？

​	oc中大部分方法都会转化为调用objc_msgSend这句方法的执行，所以提供了一个思路既是，在objc_msgSend方法执行前输出当前时间，在objc_msgSend方法执行后输出当前时间，两者相减就可以获得当前的方法执行时间。那么问题就转变为了如何在objc_msgSend执行前后插入打印时间的方法呢？因为要实现自定义的objc_msgSend方法，所以即需要替换之前系统的objc_msgSend方法，即要hook objc_msgSend方法。

### 1.1 如何hook objc_msgSend方法

​	说到hook，可能第一时间想到方法交换，但是由于objc_msgSend是一个c方法导致无法使用方法交换实现获取hook方法。

​	查找资料后发现，Facebook有提供fishhook框架供开发者动态修改c函数。

## 2.fishhook

### 2.1 介绍

​	[fishhook](https://github.com/facebook/fishhook)是Facebook在github上开源的一套动态修改c函数的框架，其原理简单可以描述为重新绑定mach-o文件中的符号，从而实现调用新绑定的符号地址的功能。

### 2.2 使用

​	首先在项目中导入fishhook.h和fishhook.c，然后定义一个rebinding结构体，传入需要替换的需要hook地址，hook之后新的函数执行地址，用于保存hook之前原函数的执行地址。然后调用rebind_symbols传入结构体数组，和数组的长度即可实现hook。使用实例如下（hook strlen函数，返回666）：

```objective-c
#include "fishhook.h"
struct rebinding {
    const char *name;// 需要hook的函数名称
    void *replacement;// hook后新函数的执行地址
    void **replaced;// 用于保存hook之前，原函数的函数地址
};
static int (*original_strlen)(const char *_s);

int new_strlen(const char *_s) {
    return 666;
}

int main(int argc, const char * argv[]) {
    char *str = "Hello_World";
    printf("%d\n", strlen(str));
    
    struct rebinding strlen_rebinding = { "strlen", new_strlen,
        (void *)&original_strlen };
    rebind_symbols((struct rebinding[1]){ strlen_rebinding }, 1);
    
    printf("%d\n", strlen(str));
    
    return 0;
}
```

### 2.3 原理

​	fishhook是如何做到可以hook c函数的呢？首先我们要了解程序在启动之前会执行一些什么操作：
#### 2.3.1 程序在启动之前会执行操作

​	程序启动之前会执行一下几步操作：

​	1.操作系统找到对应程序的mach-o，开辟进程资源，交由dyld(动态加载器)去加载到内存当中。

​	2.dyld加载对应的动态库

​	3.进行rebase(地址空间布局随机化)

​	4.进行符号bind(绑定函数符号地址，这一步为fishhook最重要的一步)

​	5.初始化oc

​	6.初始化其他等

​	简要分析其中与fishhook相关的步骤：

##### 2.3.1.1 mach-o组成分析

​	oc在编译后会生成mach-o可执行文件，mach-o的具体有一下几个部分组成：

​	1.head：mach-o的表头部分，主要包含CPU_TYPE等信息

![](https://s2.ax1x.com/2019/03/17/Ae60aR.png)

2.Load Commands：加载命令，有各个segment（段）组成。

![](https://s2.ax1x.com/2019/03/17/Ae66xO.png)

3.Data：数据，由一个一个section组成，section又来组成之前Load Commands的segment。section又主要由 \_\_TEXT（代码段），\_\_Data（数据段，包含懒加载表，非懒加载表等），__LINKEDIT（链接信息等，包含符号表）组成。

![](https://s2.ax1x.com/2019/03/17/Ae62se.png)

​	程序启动之前都会由系统找到对应的mach-o文件，由系统开辟进程，之后由dyld加载到内存中。

##### 2.3.1.2 bind(绑定)

​	首先我们通过nm -n指令查看mach-o中的符号地址。

![](https://s2.ax1x.com/2019/03/17/Ae6fZd.png)

​	我们发现_strlen并没有被初始化赋予地址，其实这些系统的函数，并不会被打包到我们的APP当中的(不可能每个APP都打包包含了系统api……)，那我们又是怎么使用这些系统api的呢？其实我们在代码中调用的系统api都是有一个函数调用的声明而已，刚开始并不会去真正分配改函数的执行地址，因为我们的代码是没有这些系统函数的具体实现的，程序在运行的时候dyld遇到这种没有分配的系统的函数，就会去从苹果提供的所有程序共享的动态库中(只有苹果自己才能用的所有程序共享的动态库)去动态链接寻找这些函数的具体实现，然后把具体的函数实现地址绑定到我们之前声明的地方，从而实现系统函数api的调用，这一过程就被称为懒加载，具体的地址信息也被保存在懒加载表中，所以我们在刚才的例子的mach-o文件中的懒加载表也是可以看到 _strlen符号的。

![](https://s2.ax1x.com/2019/03/17/Ae6hdA.png)

#### 2.3.2 fishhook原理

​	在使用fishhook的时候，我们有定义replacement这个hook之后新函数的执行地址，这个地址就是用来替换之前hook的系统函数的地址的。fishhook通过把懒加载表中系统函数的地址替换为我们自己定义的函数地址，从而实现hook。下面我们通过之前的demo来具体验证一下：

​	首先在rebind_symbols方法之前（真正hook之前）打上断点，在lldb中，通过：

```
image list
```

来获取当前程序的mach-o的地址：

![](https://s2.ax1x.com/2019/03/17/Ae6Iit.png)

再通过MachOView查看当前懒加载表中strlen的偏移地址：

![](https://s2.ax1x.com/2019/03/17/Ae67z8.png)

通过lldb调试地址，查看当前地址中存的数据：

```shell
x 0x0000000100000000+0x2070
```

![](https://s2.ax1x.com/2019/03/17/Ae6qsg.png)

在通过dis指令，反汇编得到具体的函数指令：

```shell
dis -s 0x7fff778e4220
```

![](https://s2.ax1x.com/2019/03/17/Ae6LLQ.png)

可以看到当前的0x100002070中确实存放的是strlen的函数执行地址(通过懒加载表也可以看出)。

当代码执行过rebind_symbols方法之后，在查看0x100002070中存放的数据：

![](https://s2.ax1x.com/2019/03/17/Ae6ziq.png)

我们发现0x100002070中存放的数据已经改变了，反汇编之后：

![](https://s2.ax1x.com/2019/03/17/AecSJ0.png)

发现0x100002070中存放的是我们自己实现的strlen的函数段段地址，从而证明hook strlen方法成功。

​	所有fishhook的原理就是，fishhook通过替换mach-o中懒加载表，非懒加载表中存储的函数段段地址，从而实现hook。

### 2.4 UML类图和调用关系流程图

​	fishhook只有两个文件，一个.h一个.c，主要实现都在.c中，并且代码量也只有300行不到，特别适合我们查看其中的具体原理实现。fishhook的UML类图如下：

![](https://s2.ax1x.com/2019/03/17/AecGTA.png)
其内部调用流程图如下：

![](https://s2.ax1x.com/2019/03/17/Aecrwj.png)

其中_dyld_register_func_for_add_image为系统api，手动注册自定义的image回调方法，当它每次被动态链接的时候都会触发其回调。

### 2.5 源码

rebind_symbols_for_image具体源码实现如下：

```c
/**
 @param header mach-o头地址
 @param slide ASLR(Address space layout randomization)
 */
static void rebind_symbols_for_image(struct rebindings_entry *rebindings, const struct mach_header *header, intptr_t slide) {
  Dl_info info;
  if (dladdr(header, &info) == 0) {
    return;
  }

  segment_command_t *cur_seg_cmd;// 当前的Load Commands
  segment_command_t *linkedit_segment = NULL;// 保存当前__LINKEDIT
  struct symtab_command* symtab_cmd = NULL;// 保存当前LC_SYMTAB
  struct dysymtab_command* dysymtab_cmd = NULL;// 保存当前
  
  // 首先跳过mach-o的header
  uintptr_t cur = (uintptr_t)header + sizeof(mach_header_t);
  // 遍历mach-o的Load Commands，cur游标每次加一个Load Commands的size
  for (uint i = 0; i < header->ncmds; i++, cur += cur_seg_cmd->cmdsize) {
    // 当前的Load Commands
    cur_seg_cmd = (segment_command_t *)cur;
    // 如果是LC_SEGMENT_64
    if (cur_seg_cmd->cmd == LC_SEGMENT_ARCH_DEPENDENT) {
      // 如果是__LINKEDIT(存储一些编译链接信息)
      if (strcmp(cur_seg_cmd->segname, SEG_LINKEDIT) == 0) {
        // 保存当前的Load Commands到linkedit_segment
        linkedit_segment = cur_seg_cmd;
      }
    // 当前Load Command是否是LC_SYMTAB(当前区域链接器信息)
    } else if (cur_seg_cmd->cmd == LC_SYMTAB) {
      symtab_cmd = (struct symtab_command*)cur_seg_cmd;
    }
    // 当前Load Command是否是LC_DYSYMTAB(动态链接器信息区域)
    else if (cur_seg_cmd->cmd == LC_DYSYMTAB) {
      dysymtab_cmd = (struct dysymtab_command*)cur_seg_cmd;
    }
  }

  if (!symtab_cmd || !dysymtab_cmd || !linkedit_segment ||
      !dysymtab_cmd->nindirectsyms) {
    return;
  }
    
  // linkedit_base:linkedit_segment的基础地址，slide:ALSR(Address space layout randomization)随机地址，vmaddr:该segment的地址，fileoff:该segment的偏移
  uintptr_t linkedit_base = (uintptr_t)slide + linkedit_segment->vmaddr - linkedit_segment->fileoff;
  // symtab:符号表的首地址，symoff:符号表偏移
  nlist_t *symtab = (nlist_t *)(linkedit_base + symtab_cmd->symoff);
  // strtab:获取字符串表，stroff:字符串表的首地址
  char *strtab = (char *)(linkedit_base + symtab_cmd->stroff);

  // indirectsymoff:dysymtab_command的首地址
  uint32_t *indirect_symtab = (uint32_t *)(linkedit_base + dysymtab_cmd->indirectsymoff);

  cur = (uintptr_t)header + sizeof(mach_header_t);
  // 再次遍历 Load Commands
  for (uint i = 0; i < header->ncmds; i++, cur += cur_seg_cmd->cmdsize) {
    cur_seg_cmd = (segment_command_t *)cur;
    // 如果是LC_SEGMENT_64
    if (cur_seg_cmd->cmd == LC_SEGMENT_ARCH_DEPENDENT) {
      if (strcmp(cur_seg_cmd->segname, SEG_DATA) != 0 &&
          strcmp(cur_seg_cmd->segname, SEG_DATA_CONST) != 0) {
        continue;
      }
      // 遍历LC_SEGMENT_64中的Section
      for (uint j = 0; j < cur_seg_cmd->nsects; j++) {
        // 获得当前Section
        section_t *sect = (section_t *)(cur + sizeof(segment_command_t)) + j;
        if ((sect->flags & SECTION_TYPE) == S_LAZY_SYMBOL_POINTERS) {
          // 如果是懒加载表
          perform_rebinding_with_section(rebindings, sect, slide, symtab, strtab, indirect_symtab);
        }
        if ((sect->flags & SECTION_TYPE) == S_NON_LAZY_SYMBOL_POINTERS) {
          // 如果是非懒加载表中
          perform_rebinding_with_section(rebindings, sect, slide, symtab, strtab, indirect_symtab);
        }
      }
    }
  }
}

```

perform_rebinding_with_section的主要代码实现如下：

```c
// 首次匹配到，则替换
if (cur->rebindings[j].replaced != NULL && indirect_symbol_bindings[i] != cur->rebindings[j].replacement) {
// 记录之前的地址，indirect_symbol_bindings[i]为之前的旧地址
*(cur->rebindings[j].replaced) = indirect_symbol_bindings[i];
}
// 替换indirect_symbol_bindings[i]为新地址
indirect_symbol_bindings[i] = cur->rebindings[j].replacement;
```

既然我们已经知道如何hook系统的c函数的了，是不是就可以直接hook objc_msgSend了呢？下面来看一下objc_msgSend的具体实现。

## 3.objc_msgSend

### 1.查看objc_msgSend定义

我们在messsge.h查看objc_msgSend定义发现

```objective-c
objc_msgSend(id _Nullable self, SEL _Nonnull op, ...)
```

​	objc_msgSend是不定参数的，既然是不定参数，可能想到使用va_list去解析不定参数的数组，但是由于objc_msgSend的特殊性，他的第二个参数SEL也是一个不定的参数，[再加之 arm64 下 va_list 的结构改变了，导致无法上述这样取参数。(bang神在JSPatch实现原理详解上提出，具体可以查看：https://blog.nelhage.com/2010/10/amd64-and-va_arg/)](https://github.com/bang590/JSPatch/wiki/JSPatch-%E5%AE%9E%E7%8E%B0%E5%8E%9F%E7%90%86%E8%AF%A6%E8%A7%A3)，无法获取具体参数也就是不是意味着不能hook objc_msgSend了呢？我们可以去查看objc_msgSend源码，参考苹果是怎么获取objc_msgSend的参数的。在查看了[objc_msgSend的源代码](https://opensource.apple.com/source/objc4/objc4-723/runtime/Messengers.subproj/)后，发现其是用汇编实现的，其参数是通过x0…等寄存器获取的，如下：

```asm
ENTRY _objc_msgSend
UNWIND _objc_msgSend, NoFrame
MESSENGER_START

cmp	x0, #0			// 检查第一个参数是否为空
b.le	LNilOrTagged		//  如果为空则跳转到LNilOrTagged段
ldr	x13, [x0]		// x13 = isa
and	x16, x13, #ISA_MASK	// x16 = class	
```

既然评估苹果是通过汇编实现的，我们也可以修改一下使用汇编实现其逻辑。

### 2.汇编实现

​	在arm64下有34个寄存器，其中x0~x30为通用寄存器，oc在传参数的时候会把相应的参数放入通用寄存器中（其实只有x0~x7是用来存放参数的，参数过多会存放在栈中），首先我们使用fishhook，hook objc_msgSend，我们自己的my_objc_msgSend中使用汇编实现，分别实现在真正的objc_msgSend之前调用方法，执行真正的objc_msgSend，在真正的objc_msgSend之后调用方法。具体实现如下：(并不是我自己实现的，是copy戴铭大神的代码，不过并不是他在课中讲到的，他在课中讲到的代码是github一个名为[InspectiveC](https://github.com/DavidGoldman/InspectiveC/blob/master/InspectiveCarm64.mm)的逆向相关的代码，[我是找到他的github中的汇编实现](https://github.com/ming1016/GCDFetchFeed/blob/master/GCDFetchFeed/GCDFetchFeed/Lib/SMLagMonitor/SMCallTraceCore.c))，具体实现如下：

```asm
__attribute__((__naked__))
static void hook_Objc_msgSend() {
    // 把寄存器存入栈中，保护现场
    __asm volatile ("stp x8, x9, [sp, #-16]!\n");
    __asm volatile ("stp x6, x7, [sp, #-16]!\n");
    __asm volatile ("stp x4, x5, [sp, #-16]!\n");
    __asm volatile ("stp x2, x3, [sp, #-16]!\n");
    __asm volatile ("stp x0, x1, [sp, #-16]!\n");
    
    // 把lr寄存器（下一条执行的代码段段地址）存入x2
    __asm volatile ("mov x2, lr\n");
    __asm volatile ("mov x3, x4\n");
    
    // 调用before_objc_msgSend. 把before_objc_msgSend函数的，代码段段地址存入x12寄存器中
    __asm volatile ("stp x8, x9, [sp, #-16]!\n");
    __asm volatile ("mov x12, %0\n" :: "r"(&before_objc_msgSend));
    __asm volatile ("ldp x8, x9, [sp], #16\n");
    // 调用x12中的值，即会调用before_objc_msgSend
    __asm volatile ("blr" " x12\n");
    
    
    // 恢复现场，从栈中取值，放入寄存器中
    __asm volatile ("ldp x0, x1, [sp], #16\n");
    __asm volatile ("ldp x2, x3, [sp], #16\n");
    __asm volatile ("ldp x4, x5, [sp], #16\n");
    __asm volatile ("ldp x6, x7, [sp], #16\n");
    __asm volatile ("ldp x8, x9, [sp], #16\n");
    
    // 调用orig_objc_msgSend. 把orig_objc_msgSend函数的，代码段段地址存入x12寄存器中
    __asm volatile ("stp x8, x9, [sp, #-16]!\n");
    __asm volatile ("mov x12, %0\n" :: "r"(orig_objc_msgSend));
    __asm volatile ("ldp x8, x9, [sp], #16\n");
    // 调用x12中的值，即会调用orig_objc_msgSend
    __asm volatile ("blr" " x12\n");
    
    // 把寄存器存入栈中，保护现场
    __asm volatile ("stp x8, x9, [sp, #-16]!\n");
    __asm volatile ("stp x6, x7, [sp, #-16]!\n");
    __asm volatile ("stp x4, x5, [sp, #-16]!\n");
    __asm volatile ("stp x2, x3, [sp, #-16]!\n");
    __asm volatile ("stp x0, x1, [sp, #-16]!\n");
    
    // 调用after_objc_msgSend. 把after_objc_msgSend函数的，代码段段地址存入x12寄存器中
    __asm volatile ("stp x8, x9, [sp, #-16]!\n");
    __asm volatile ("mov x12, %0\n" :: "r"(&after_objc_msgSend));
    __asm volatile ("ldp x8, x9, [sp], #16\n");
    // 调用x12中的值，即会调用after_objc_msgSend
    __asm volatile ("blr" " x12\n");
    
    // 把x0寄存器中的值放入lr寄存器，此时x0寄存器中的值为原函数中objc_msgSend执行后下一条执行的代码段段地址
    __asm volatile ("mov lr, x0\n");
    
    // 恢复现场，从栈中取值，放入寄存器中
    __asm volatile ("ldp x0, x1, [sp], #16\n");
    __asm volatile ("ldp x2, x3, [sp], #16\n");
    __asm volatile ("ldp x4, x5, [sp], #16\n");
    __asm volatile ("ldp x6, x7, [sp], #16\n");
    __asm volatile ("ldp x8, x9, [sp], #16\n");
    
    // return
    __asm volatile ("ret\n");
}

```

​	首先把寄存器存入栈中，保护现场。保存lr（下一条执行的代码段段地址）寄存器的值。通过blr（跳转到对应的地址执行）跳转指令执行 before_objc_msgSend（打印开始时间）函数。因为执行了before_objc_msgSend函数，所以现在寄存器中存的值肯定是before_objc_msgSend之后的数据，但是我们接下来需要执行真正的objc_msgSend，所以我们需要恢复之前保存到栈中的寄存器的值，恢复现场。之后也是通过blr指令执行真正的objc_msgSend。因为接下来要执行after_objc_msgSend（打印结束时间）函数，所以要保护执行真正的objc_msgSend之后的现场，所以我们需要把当前寄存器存入栈中。之后通过blr指令执行after_objc_msgSend函数，之后我们把之前存入栈中的寄存去取出，恢复现场，结束调用，从未实现在objc_msgSend前后打印时间，从而得到真正的objc_msgSend的执行时间。

### 3.实现效果

![](https://s2.ax1x.com/2019/03/17/AeccYq.png)

