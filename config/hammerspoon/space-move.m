// A narrow adapter for the macOS 26.4+ bridged window management API.
// No Dock injection or changes to system protection.
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <dlfcn.h>
#include <errno.h>
#include <mach-o/dyld.h>
#include <mach-o/nlist.h>

// Resolve a private local symbol from the loaded Mach-O symbol table.
static void *bridgeFunction(void) {
    const char *name="__ZL54SLSPerformAsynchronousBridgedWindowManagementOperationP47SLSAsynchronousBridgedWindowManagementOperation";
    for (uint32_t i=0;i<_dyld_image_count();i++) {
        if (!strstr(_dyld_get_image_name(i),"/SkyLight.framework/")) continue;
        const struct mach_header_64 *h=(const void *)_dyld_get_image_header(i);
        const struct symtab_command *symbols=NULL;
        const struct segment_command_64 *link=NULL;
        const struct load_command *c=(const void *)(h+1);
        for (uint32_t j=0;j<h->ncmds;j++,c=(const void *)((const char *)c+c->cmdsize)) {
            if (c->cmd==LC_SYMTAB) symbols=(const void *)c;
            if (c->cmd==LC_SEGMENT_64 && !strcmp(((const struct segment_command_64 *)c)->segname,SEG_LINKEDIT)) link=(const void *)c;
        }
        if (!symbols || !link) continue;
        intptr_t slide=_dyld_get_image_vmaddr_slide(i);
        uintptr_t base=slide+link->vmaddr-link->fileoff;
        const struct nlist_64 *entries=(const void *)(base+symbols->symoff);
        const char *strings=(const void *)(base+symbols->stroff);
        for (uint32_t j=0;j<symbols->nsyms;j++) {
            if (entries[j].n_un.n_strx<symbols->strsize && !strcmp(strings+entries[j].n_un.n_strx,name)) return (void *)(slide+entries[j].n_value);
        }
    }
    return NULL;
}

static BOOL moveWindow(uint64_t window, uint64_t space) {
    // Resolve the framework, class and private entry point once; scanning
    // every loaded image's symbol table costs milliseconds per move.
    static void *framework=NULL;
    static Class type=nil;
    static int64_t (*perform)(id)=NULL;
    static BOOL resolved=NO;
    if (!resolved) {
        resolved=YES;
        framework=dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",RTLD_NOW);
        type=NSClassFromString(@"SLSBridgedMoveWindowsToManagedSpaceOperation");
        perform=bridgeFunction();
    }
    if (!framework || !type || !perform) return NO;
    id operation=((id(*)(id,SEL,id,uint64_t))objc_msgSend)([type alloc],sel_registerName("initWithWindows:spaceID:"),@[@(window)],space);
    if (!operation) return NO;
    // The bridged operation runs asynchronously; keep the latest one alive
    // instead of letting ARC release it when this function returns.
    static id retainedOperation=nil;
    retainedOperation=operation;
    (void)retainedOperation;
    perform(operation);
    return YES;
}

// Loaded inside Hammerspoon to use its existing Accessibility authorization.
#include <lua.h>
#include <lauxlib.h>
static int move(lua_State *L) {
    uint64_t window=luaL_checkinteger(L,1),space=luaL_checkinteger(L,2);
    lua_pushboolean(L,window>0 && window<=UINT32_MAX && space>0 && moveWindow(window,space));
    return 1;
}
int luaopen_space_move(lua_State *L) {
    lua_pushcfunction(L,move);return 1;
}
