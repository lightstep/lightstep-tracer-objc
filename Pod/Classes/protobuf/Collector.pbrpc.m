#import "Collector.pbrpc.h"

#import <ProtoRPC/ProtoRPC.h>
#import <RxLibrary/GRXWriter+Immediate.h>

@implementation LTSCollectorService

// Designated initializer
- (instancetype)initWithHost:(NSString *)host {
  return (self = [super initWithHost:host packageName:@"lightstep.collector" serviceName:@"CollectorService"]);
}

// Override superclass initializer to disallow different package and service names.
- (instancetype)initWithHost:(NSString *)host
                 packageName:(NSString *)packageName
                 serviceName:(NSString *)serviceName {
  return [self initWithHost:host];
}

+ (instancetype)serviceWithHost:(NSString *)host {
  return [[self alloc] initWithHost:host];
}


#pragma mark Report(ReportRequest) returns (ReportResponse)

- (void)reportWithRequest:(LTSReportRequest *)request handler:(void(^)(LTSReportResponse *_Nullable response, NSError *_Nullable error))handler{
  [[self RPCToReportWithRequest:request handler:handler] start];
}
// Returns a not-yet-started RPC object.
- (GRPCProtoCall *)RPCToReportWithRequest:(LTSReportRequest *)request handler:(void(^)(LTSReportResponse *_Nullable response, NSError *_Nullable error))handler{
  return [self RPCToMethod:@"Report"
            requestsWriter:[GRXWriter writerWithValue:request]
             responseClass:[LTSReportResponse class]
        responsesWriteable:[GRXWriteable writeableWithSingleHandler:handler]];
}
@end
