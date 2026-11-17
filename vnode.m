#include "vnode.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include "SVC_Caller.h"
#include "kernel.h"
#include "libdimentio.h"

const char *vnodeMemPath;
NSArray *hidePathList = nil;

__attribute__((constructor)) void initVnodeMemPath() {
  vnodeMemPath =
      [NSString stringWithFormat:@"/tmp/%@.txt", NSProcessInfo.processInfo.processName].UTF8String;
}

void initPath() {
  NSString *basePath = @"/usr/share";
  if ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb/usr/share"]) {
      basePath = @"/var/jb/usr/share";
      printf("Detected Rootless environment, using %s as base path.\n", basePath.UTF8String);
  } else {
      printf("Detected Rootful environment, using %s as base path.\n", basePath.UTF8String);
  }

  hidePathList = [NSArray
      arrayWithContentsOfFile:[NSString stringWithFormat:@"%@/%@/hidePathList.plist",
                                                         basePath, NSProcessInfo.processInfo.processName]];
  if (hidePathList == nil) {
      NSString *fallbackPath = [NSString stringWithFormat:@"/usr/share/%@/hidePathList.plist", NSProcessInfo.processInfo.processName];
      hidePathList = [NSArray arrayWithContentsOfFile:fallbackPath];
  }
  
  if (hidePathList == nil) goto exit;
  for (id path in hidePathList) {
    if (![path isKindOfClass:[NSString class]]) goto exit;
  }
  return;
exit:
  printf("hidePathList.plist is broken or not found, please reinstall vnodebypass!\n");
  exit(1);
}

void saveVnode() {
  if (access(vnodeMemPath, F_OK) == 0) {
    printf("Already exist /tmp/vnodeMem.txt, Please vnode recovery first!\n");
    return;
  }

  initPath();
  if (init_kernel() == 1) {
    printf("Failed init_kernel\n");
    return;
  }
  find_task(getpid(), &our_task);
  if (!this_proc) return;
  printf("this_proc: " KADDR_FMT "\n", this_proc);

  FILE *fp = fopen(vnodeMemPath, "w");
  if (!fp) {
    printf("Failed to open vnodeMemPath for writing!\n");
    if (tfp0) mach_port_deallocate(mach_task_self(), tfp0);
    return;
  }

  int hideCount = (int)[hidePathList count];
  
  for (int i = 0; i < hideCount; i++) {
    NSString *pathStr = [hidePathList objectAtIndex:i];
    const char *hidePath = [pathStr UTF8String];
    
    int file_index = open(hidePath, O_RDONLY);
    if (file_index == -1 && [pathStr hasPrefix:@"/var/jb"]) {
      NSString *fallbackPath = [pathStr stringByReplacingOccurrencesOfString:@"/var/jb" withString:@""];
      file_index = open(fallbackPath.UTF8String, O_RDONLY);
    } else if (file_index == -1 && ![pathStr hasPrefix:@"/var/jb"]) {
      NSString *rootlessPath = [NSString stringWithFormat:@"/var/jb%@", pathStr];
      file_index = open(rootlessPath.UTF8String, O_RDONLY);
    }

    if (file_index == -1) continue;

    uint64_t vnodeVal = get_vnode_with_file_index(file_index, this_proc);
    if (vnodeVal != 0) {
      printf("hidePath: %s, vnode[%d]: 0x%" PRIX64 "\n", hidePath, i, vnodeVal);
      printf("vnode_usecount: 0x%" PRIX32 ", vnode_iocount: 0x%" PRIX32 "\n",
             kernel_read32(vnodeVal + off_vnode_usecount),
             kernel_read32(vnodeVal + off_vnode_iocount));
      fprintf(fp, "0x%" PRIX64 "\n", vnodeVal);
    }
    close(file_index);
  }
  fclose(fp);
  if (tfp0) mach_port_deallocate(mach_task_self(), tfp0);
  printf("Saved vnode to /tmp/vnodeMem.txt\nMake sure vnode recovery to prevent kernel panic!\n");
}

void hideVnode() {
  if (init_kernel() == 1) {
    printf("Failed init_kernel\n");
    return;
  }
  if (access(vnodeMemPath, F_OK) == 0) {
    FILE *fp = fopen(vnodeMemPath, "r");
    if (fp) {
      uint64_t savedVnode;
      int i = 0;
      while (fscanf(fp, "0x%" PRIX64 "\n", &savedVnode) == 1) {
        printf("Saved vnode[%d] = 0x%" PRIX64 "\n", i, savedVnode);
        hide_path(savedVnode);
        i++;
      }
      fclose(fp);
    }
  }
  if (tfp0) mach_port_deallocate(mach_task_self(), tfp0);
  printf("Hide file!\n");
}

void revertVnode() {
  if (init_kernel() == 1) {
    printf("Failed init_kernel\n");
    return;
  }
  if (access(vnodeMemPath, F_OK) == 0) {
    FILE *fp = fopen(vnodeMemPath, "r");
    if (fp) {
      uint64_t savedVnode;
      int i = 0;
      while (fscanf(fp, "0x%" PRIX64 "\n", &savedVnode) == 1) {
        printf("Saved vnode[%d] = 0x%" PRIX64 "\n", i, savedVnode);
        show_path(savedVnode);
        i++;
      }
      fclose(fp);
    }
  }
  if (tfp0) mach_port_deallocate(mach_task_self(), tfp0);
  printf("Show file!\n");
}

void recoveryVnode() {
  if (init_kernel() == 1) {
    printf("Failed init_kernel\n");
    return;
  }
  if (access(vnodeMemPath, F_OK) == 0) {
    FILE *fp = fopen(vnodeMemPath, "r");
    if (fp) {
      uint64_t savedVnode;
      int i = 0;
      while (fscanf(fp, "0x%" PRIX64 "\n", &savedVnode) == 1) {
        kernel_write32(savedVnode + off_vnode_iocount,
                       kernel_read32(savedVnode + off_vnode_iocount) - 1);
        kernel_write32(savedVnode + off_vnode_usecount,
                       kernel_read32(savedVnode + off_vnode_usecount) - 1);
        printf("Saved vnode[%d] = 0x%" PRIX64 "\n", i, savedVnode);
        printf("vnode_usecount: 0x%" PRIX32 ", vnode_iocount: 0x%" PRIX32 "\n",
               kernel_read32(savedVnode + off_vnode_usecount),
               kernel_read32(savedVnode + off_vnode_iocount));
        i++;
      }
      fclose(fp);
    }
    remove(vnodeMemPath);
  }
  if (tfp0) mach_port_deallocate(mach_task_self(), tfp0);
  printf("Recovered vnode! No more kernel panic when you shutdown.\n");
}

void checkFile() {
  initPath();
  int hideCount = (int)[hidePathList count];
  for (int i = 0; i < hideCount; i++) {
    NSString *pathStr = [hidePathList objectAtIndex:i];
    const char *hidePath = [pathStr UTF8String];
    int ret = SVC_Access(hidePath);
    printf("hidePath: %s, errno: %d\n", hidePath, ret);
  }
  printf("Done check file!\n");
}
