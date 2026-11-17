#import <Foundation/Foundation.h>
#import <NSTask.h>
#include <stdio.h>

int main(int argc, char *argv[], char *envp[]) {
  @autoreleasepool {
    NSTask *task = [NSTask new];
    task.launchPath = @"/usr/bin/uicache"; // Cần kiểm tra xem uicache có ở /var/jb/usr/bin không
    NSString *uicachePath = @"/usr/bin/uicache";
    if (![[NSFileManager defaultManager] fileExistsAtPath:uicachePath]) {
        uicachePath = @"/var/jb/usr/bin/uicache"; // Đối với rootless
        if (![[NSFileManager defaultManager] fileExistsAtPath:uicachePath]) {
            printf("Error: uicache not found at /usr/bin or /var/jb/usr/bin!\n");
            return 1;
        }
    }
    task.launchPath = uicachePath;

    BOOL isRemoving = [NSProcessInfo.processInfo.processName containsString:@"prerm"];
    BOOL isUpgrading = (argc > 1 && strstr(argv[1], "upgrade")); // Đảm bảo argv[1] tồn tại

    NSString *dpkgInfoPath = @"/var/lib/dpkg/info/kr.xsf1re.vnodebypass.list";
    NSString *rootlessPrefix = @"";
    // Kiểm tra môi trường rootless
    if ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb/var/lib/dpkg/info"]) {
        dpkgInfoPath = @"/var/jb/var/lib/dpkg/info/kr.xsf1re.vnodebypass.list";
        rootlessPrefix = @"/var/jb";
        printf("Detected Rootless environment in debian-script, using /var/jb prefix.\n");
    } else {
        printf("Detected Rootful environment in debian-script.\n");
    }


    if (isRemoving || isUpgrading) {
      // Đối với rootless, file list cũng nằm trong /var/jb
      NSArray *fileList =
          [[NSString stringWithContentsOfFile:dpkgInfoPath
                                     encoding:NSUTF8StringEncoding
                                        error:nil] componentsSeparatedByString:@"\n"];
      NSInteger appPathIndex =
          [fileList indexOfObjectPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
            return [obj hasSuffix:@".app"];
          }];
      if (appPathIndex != NSNotFound) {
        NSString *fullAppPath = fileList[appPathIndex];
        // Nếu là rootless và đường dẫn không có /var/jb, thêm vào
        if ([rootlessPrefix length] > 0 && ![fullAppPath hasPrefix:rootlessPrefix]) {
            fullAppPath = [rootlessPrefix stringByAppendingString:fullAppPath];
        }
        task.arguments = @[ @"-u", fullAppPath ];
        [task launch];
        [task waitUntilExit];
        printf("Uicache -u %s done.\n", fullAppPath.UTF8String);
      } else {
        printf("Could not find vnodebypass.app in dpkg list, skipping uicache -u.\n");
      }
      if (isRemoving) {
          // Sau khi gỡ, cần đảm bảo các file tạm /tmp/vnodeMem.txt cũng được dọn dẹp
          NSString *vnodeMemTmpPath = [NSString stringWithFormat:@"/tmp/%@.txt", @"vnodebypass"]; // Tên gốc của binary
          if ([[NSFileManager defaultManager] fileExistsAtPath:vnodeMemTmpPath]) {
              NSError *error;
              [[NSFileManager defaultManager] removeItemAtPath:vnodeMemTmpPath error:&error];
              if (error) {
                  printf("Failed to remove temporary vnodeMem file: %s\n", error.localizedDescription.UTF8String);
              } else {
                  printf("Removed temporary vnodeMem file: %s\n", vnodeMemTmpPath.UTF8String);
              }
          }
          return 0;
      }
    }

    // Đoạn mã đổi tên (obfuscation)
    NSString *originalBundleIdentifier = @"kr.xsf1re.vnodebypass"; // Định danh bundle gốc

    // Lấy tên random
    NSString *randomName = [[NSUUID UUID].UUIDString componentsSeparatedByString:@"-"].firstObject;
    printf("Generated random name for obfuscation: %s\n", randomName.UTF8String);

    // Cập nhật Info.plist
    NSString *appPlistPath = [NSString stringWithFormat:@"%@/Applications/%@.app/Info.plist", rootlessPrefix, originalBundleIdentifier];
    if (![[NSFileManager defaultManager] fileExistsAtPath:appPlistPath]) {
        appPlistPath = [NSString stringWithFormat:@"/Applications/%@.app/Info.plist", originalBundleIdentifier]; // Fallback cho rootful
    }
    NSMutableDictionary *appInfo = [NSMutableDictionary dictionaryWithContentsOfFile:appPlistPath];
    if (appInfo) {
        appInfo[@"CFBundleExecutable"] = randomName;
        if (![appInfo writeToFile:appPlistPath atomically:YES]) {
            printf("Failed to write updated Info.plist to %s\n", appPlistPath.UTF8String);
            // Không return, cố gắng tiếp tục để hoàn thành các bước khác
        } else {
            printf("Updated CFBundleExecutable to %s in %s\n", randomName.UTF8String, appPlistPath.UTF8String);
        }
    } else {
        printf("Failed to load Info.plist from %s\n", appPlistPath.UTF8String);
    }

    // Các đường dẫn cần đổi tên
    NSArray *renames = @[
      // Binary chính
      @[ [NSString stringWithFormat:@"%@/usr/bin/%@", rootlessPrefix, @"vnodebypass"], [NSString stringWithFormat:@"%@/usr/bin/%@", rootlessPrefix, randomName] ],
      // Binary trong ứng dụng
      @[ [NSString stringWithFormat:@"%@/Applications/%@.app/%@", rootlessPrefix, originalBundleIdentifier, @"vnodebypass"], [NSString stringWithFormat:@"%@/Applications/%@.app/%@", rootlessPrefix, originalBundleIdentifier, randomName] ],
      // Thư mục ứng dụng
      @[ [NSString stringWithFormat:@"%@/Applications/%@.app", rootlessPrefix, originalBundleIdentifier], [NSString stringWithFormat:@"%@/Applications/%@.app", rootlessPrefix, randomName] ],
      // Thư mục share
      @[ [NSString stringWithFormat:@"%@/usr/share/%@", rootlessPrefix, @"vnodebypass"], [NSString stringWithFormat:@"%@/usr/share/%@", rootlessPrefix, randomName] ]
    ];

    for (NSArray *rename in renames) {
      NSString *oldPath = rename[0];
      NSString *newPath = rename[1];
      NSError *error;
      
      // Đảm bảo đường dẫn gốc (không có /var/jb) cũng được kiểm tra
      NSString *originalOldPath = [oldPath stringByReplacingOccurrencesOfString:rootlessPrefix withString:@""];
      NSString *currentOldPath = [[NSFileManager defaultManager] fileExistsAtPath:oldPath] ? oldPath : originalOldPath;
      
      // Chỉ đổi tên nếu file/folder tồn tại
      if ([[NSFileManager defaultManager] fileExistsAtPath:currentOldPath]) {
          [[NSFileManager defaultManager] moveItemAtPath:currentOldPath toPath:newPath error:&error];
          if (error) {
            printf("Failed to rename %s to %s: %s\n", currentOldPath.UTF8String, newPath.UTF8String,
                   error.localizedDescription.UTF8String);
            // Cố gắng không trả về lỗi để tiếp tục các bước khác nếu có thể
          } else {
            printf("Renamed %s to %s\n", currentOldPath.UTF8String, newPath.UTF8String);
          }
      } else {
          printf("Path not found, skipping rename: %s\n", currentOldPath.UTF8String);
      }
    }

    // Cập nhật file dpkg info
    NSString *dpkgInfoContent =
        [NSString stringWithContentsOfFile:dpkgInfoPath
                                  encoding:NSUTF8StringEncoding
                                     error:nil];
    if (dpkgInfoContent) {
        dpkgInfoContent = [dpkgInfoContent stringByReplacingOccurrencesOfString:@"vnodebypass" withString:randomName];
        if (![dpkgInfoContent writeToFile:dpkgInfoPath
                               atomically:YES
                                 encoding:NSUTF8StringEncoding
                                    error:nil]) {
            printf("Failed to write updated dpkg info to %s\n", dpkgInfoPath.UTF8String);
        } else {
            printf("Updated dpkg info file: %s\n", dpkgInfoPath.UTF8String);
        }
    } else {
        printf("Failed to read dpkg info from %s\n", dpkgInfoPath.UTF8String);
    }

    // Uicache lại ứng dụng với tên mới
    NSString *newAppPath = [NSString stringWithFormat:@"%@/Applications/%@.app", rootlessPrefix, randomName];
    task.arguments = @[ @"-p", newAppPath ];
    [task launch];
    [task waitUntilExit];
    printf("Uicache -p %s done.\n", newAppPath.UTF8String);
    return 0;
  }
}
