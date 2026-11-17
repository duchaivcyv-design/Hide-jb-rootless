#import "RootViewController.h"

@interface RootViewController ()
@end

@implementation RootViewController

- (void)loadView {
  [super loadView];
  self.view.backgroundColor = UIColor.blackColor;
}

- (void)viewDidLoad {
  [super viewDidLoad];

  _titleLabel =
      [[UILabel alloc] initWithFrame:CGRectMake(0, 50, UIScreen.mainScreen.bounds.size.width, 100)];
  _titleLabel.text = @"vnodebypass";
  _titleLabel.textAlignment = NSTextAlignmentCenter;
  _titleLabel.textColor = UIColor.whiteColor;
  _titleLabel.font = [UIFont systemFontOfSize:40];
  [self.view addSubview:_titleLabel];

  _subtitleLabel = [[UILabel alloc]
      initWithFrame:CGRectMake(0, 100, UIScreen.mainScreen.bounds.size.width, 100)];
  _subtitleLabel.text = @"USE IT AT YOUR OWN RISK! (Rootless iOS 15-18 Ready)"; // Cập nhật thông báo
  _subtitleLabel.textAlignment = NSTextAlignmentCenter;
  _subtitleLabel.textColor = UIColor.whiteColor;
  _subtitleLabel.font = [UIFont systemFontOfSize:20];
  [self.view addSubview:_subtitleLabel];

  _button = [UIButton buttonWithType:UIButtonTypeSystem];
  _button.frame = CGRectMake(UIScreen.mainScreen.bounds.size.width / 2 - 60, // Tăng kích thước button
                             UIScreen.mainScreen.bounds.size.height / 2 - 25, 120, 50);
  [_button setTitle:[self getBypassStatus] ? @"Disable Bypass" : @"Enable Bypass" // Thay đổi text
           forState:UIControlStateNormal];
  [_button addTarget:self
                action:@selector(buttonPressed:)
      forControlEvents:UIControlEventTouchUpInside];
  [self.view addSubview:_button];
}

// Hàm mới để kiểm tra trạng thái bypass phức tạp hơn
- (BOOL)getBypassStatus {
    // Thay vì chỉ kiểm tra /bin/bash, cần kiểm tra sự tồn tại của /tmp/vnodeMem.txt
    // hoặc một cờ trạng thái khác mà tool của mày tạo ra khi kích hoạt bypass.
    // Ví dụ: kiểm tra file lock, hoặc trạng thái của một daemon.
    return [[NSFileManager defaultManager] fileExistsAtPath:[NSString stringWithUTF8String:vnodeMemPath]];
}

- (void)buttonPressed:(UIButton *)sender {
  BOOL currentStatus = [self getBypassStatus]; // Lấy trạng thái hiện tại
  NSArray *opts;
  if (currentStatus) { // Đang enable, muốn disable
    opts = @[ @"-r", @"-R" ]; // Revert và Recovery
  } else { // Đang disable, muốn enable
    opts = @[ @"-s", @"-h" ]; // Save và Hide
  }

  NSString *launchPath =
      [NSString stringWithFormat:@"/usr/bin/%@", NSProcessInfo.processInfo.processName];
  // Đối với rootless, launchPath có thể là /var/jb/usr/bin/vnodebypass
  // Cần xác định đúng launchPath
  if (![[NSFileManager defaultManager] fileExistsAtPath:launchPath]) {
      launchPath = [NSString stringWithFormat:@"/var/jb/usr/bin/%@", NSProcessInfo.processInfo.processName];
      if (![[NSFileManager defaultManager] fileExistsAtPath:launchPath]) {
          NSLog(@"Error: vnodebypass binary not found at /usr/bin or /var/jb/usr/bin!");
          [_button setTitle:@"Error!" forState:UIControlStateNormal];
          return;
      }
  }


  NSTask *task1 = [NSTask launchedTaskWithLaunchPath:launchPath arguments:@[ opts[0] ]];
  [task1 waitUntilExit];
  NSTask *task2 = [NSTask launchedTaskWithLaunchPath:launchPath arguments:@[ opts[1] ]];
  [task2 waitUntilExit];

  // Kiểm tra lại trạng thái sau khi thực hiện lệnh
  BOOL newStatus = [self getBypassStatus];
  NSString *statusText;
  if (currentStatus && !newStatus) { // Đã disable thành công
      statusText = @"Bypass Disabled";
  } else if (!currentStatus && newStatus) { // Đã enable thành công
      statusText = @"Bypass Enabled";
  } else {
      statusText = @"Failed";
  }

  [_button setTitle:statusText forState:UIControlStateNormal];
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    sleep(1);
    dispatch_async(dispatch_get_main_queue(), ^{
      [_button setTitle:[self getBypassStatus] ? @"Disable Bypass" : @"Enable Bypass" forState:UIControlStateNormal];
    });
  });
}
@end
