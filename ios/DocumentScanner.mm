#import <VisionKit/VisionKit.h>
#import "DocumentScanner.h"

#if __has_include(<DocumentScanner/DocumentScanner-Swift.h>)
#import <DocumentScanner/DocumentScanner-Swift.h>
#elif __has_include("DocumentScanner-Swift.h")
#import "DocumentScanner-Swift.h"
#else
#warning "DocumentScanner-Swift.h not found at build time"
#endif

@interface DocumentScanner ()
@property (nonatomic, strong) RNDocumentScanner *activeDocumentScanner;
@end

@implementation DocumentScanner
RCT_EXPORT_MODULE()

- (void)scanDocument:(JS::NativeDocumentScanner::ScanDocumentOptions &)options
            resolve:(RCTPromiseResolveBlock)resolve
            reject:(RCTPromiseRejectBlock)reject
{
  NSMutableDictionary *scanDocumentOptions = [NSMutableDictionary new];

  scanDocumentOptions[@"responseType"] = options.responseType();
  
  if (options.croppedImageQuality().has_value()) {
    scanDocumentOptions[@"croppedImageQuality"] = @(options.croppedImageQuality().value());
  }

  if (options.maxNumDocuments().has_value()) {
    scanDocumentOptions[@"maxNumDocuments"] = @(options.maxNumDocuments().value());
  }

  if (options.autoConfirm().has_value()) {
    scanDocumentOptions[@"autoConfirm"] = @(options.autoConfirm().value());
  }

  self.activeDocumentScanner = [RNDocumentScanner new];

  __weak typeof(self) weakSelf = self;
  RCTPromiseResolveBlock retainedResolve = ^(id result) {
    resolve(result);
    weakSelf.activeDocumentScanner = nil;
  };
  RCTPromiseRejectBlock retainedReject = ^(NSString *code, NSString *message, NSError *error) {
    reject(code, message, error);
    weakSelf.activeDocumentScanner = nil;
  };

  [self.activeDocumentScanner scanDocument:scanDocumentOptions resolve:retainedResolve reject:retainedReject];
}

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
    return std::make_shared<facebook::react::NativeDocumentScannerSpecJSI>(params);
}

@end
