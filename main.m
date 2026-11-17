#include <stdio.h>
#import <Foundation/Foundation.h>
#include <sys/syscall.h>
#include "vnode.h"
#include <dlfcn.h> // Để kiểm tra các dylib được tiêm

void showUsage() {
	printf("Usage: vnodebypass [OPTION]...\n");
	printf("Hide jailbreak files using VNODE that provides an internal representation of a file or directory or defines an interface to a file.\n\n");
	printf("Option:\n");
	printf("-s,  --save             Get vnode with file index and save path to /tmp/vnodeMem.txt\n");
	printf("-h,  --hide             Hide jailbreak files\n");
	printf("-r,  --revert           Revert jailbreak files\n");
	printf("-R,  --recovery         To prevent kernel panic, vnode_usecount and vnode_iocount will be substracted 1 and remove /tmp/vnodeMem.txt\n");
	printf("-c,  --check            Check if jailbreak file exists using SVC #0x80 SYS_access.\n");
}

int main(int argc, char *argv[], char *envp[]) {
    // Đảm bảo setuid/setgid hoạt động trong môi trường rootless.
    // Trong rootless, có thể không cần thiết nếu binary đã chạy với quyền root.
    // Hoặc cần sử dụng một cơ chế cấp quyền khác (vd: thông qua launchd hoặc một tweak root).
    setuid(0);
    setgid(0);

    if(getuid() != 0 && getgid() != 0) {
        printf("Require vnodebypass to be run as root! Current UID: %d, GID: %d\n", getuid(), getgid());
        // Đối với rootless, nếu không phải root, cần thông báo rõ ràng hơn
        // hoặc sử dụng một cách khác để có quyền cần thiết.
        return -1;
    }

    if (argc != 2) {
        showUsage();
        return -1;
    }

    if((strcmp(argv[1], "-s") == 0 || strcmp(argv[1], "--save") == 0))
        saveVnode();
    else if((strcmp(argv[1], "-h") == 0 || strcmp(argv[1], "--hide") == 0))
        hideVnode();
    else if((strcmp(argv[1], "-r") == 0 || strcmp(argv[1], "--revert") == 0))
        revertVnode();
    else if((strcmp(argv[1], "-R") == 0 || strcmp(argv[1], "--recovery") == 0))
        recoveryVnode();
    else if((strcmp(argv[1], "-c") == 0 || strcmp(argv[1], "--check") == 0))
        checkFile();
    else if((strcmp(argv[1], "-d") == 0 || strcmp(argv[1], "--detect")) == 0) // Thêm option mới
        detectJailbreakTweaks(); // Hàm mới để phát hiện tweak
    else
        showUsage();

    return 0;
}

// Hàm mới để phát hiện các dylib được tiêm vào (tweak)
void detectJailbreakTweaks() {
    printf("Checking for injected jailbreak tweaks...\n");
    // Đây chỉ là một ví dụ đơn giản, cần mở rộng để quét các đường dẫn dylib thực tế
    // và kiểm tra môi trường chạy của ứng dụng.
    const char *suspicious_libs[] = {
        "/Library/MobileSubstrate/DynamicLibraries/AnyTweak.dylib",
        "/var/jb/Library/MobileSubstrate/DynamicLibraries/AnotherTweak.dylib",
        "/usr/lib/TweakLoader.dylib", // Một số tweak loader phổ biến
        NULL
    };

    for (int i = 0; suspicious_libs[i] != NULL; ++i) {
        void *handle = dlopen(suspicious_libs[i], RTLD_LAZY);
        if (handle) {
            printf("  -> Suspicious library found and loaded: %s\n", suspicious_libs[i]);
            dlclose(handle);
        } else {
            // printf("  -> Library not found or failed to load: %s\n", suspicious_libs[i]);
        }
    }
    printf("Tweak detection completed. For stronger detection, deep process introspection is needed.\n");
}
