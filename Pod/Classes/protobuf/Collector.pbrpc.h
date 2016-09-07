#import "Collector.pbobjc.h"

#import <ProtoRPC/ProtoService.h>
#import <RxLibrary/GRXWriteable.h>
#import <RxLibrary/GRXWriter.h>

#if GPB_USE_PROTOBUF_FRAMEWORK_IMPORTS
  #import <Protobuf/Timestamp.pbobjc.h>
#else
  #import "google/protobuf/Timestamp.pbobjc.h"
#endif


NS_ASSUME_NONNULL_BEGIN

@protocol LTSCollectorService <NSObject>

#pragma mark Report(ReportRequest) returns (ReportResponse)

- (void)reportWithRequest:(LTSReportRequest *)request handler:(void(^)(LTSReportResponse *_Nullable response, NSError *_Nullable error))handler;

- (GRPCProtoCall *)RPCToReportWithRequest:(LTSReportRequest *)request handler:(void(^)(LTSReportResponse *_Nullable response, NSError *_Nullable error))handler;


@end

/**
 * Basic service implementation, over gRPC, that only does
 * marshalling and parsing.
 */
@interface LTSCollectorService : GRPCProtoService<LTSCollectorService>
- (instancetype)initWithHost:(NSString *)host NS_DESIGNATED_INITIALIZER;
+ (instancetype)serviceWithHost:(NSString *)host;
@end

NS_ASSUME_NONNULL_END
