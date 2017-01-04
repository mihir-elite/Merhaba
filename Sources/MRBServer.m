//
//  MRBServer.m
//  Merhaba
//
//  Created by Abdullah Selek on 02/01/2017.
//
//  MIT License
//
//  Copyright (c) 2017 Abdullah Selek
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.

#import "MRBServer.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>

NSString * const MRBDefaultProtocol = @"_Server._tcp.";
NSString * const MRBServerErrorDomain = @"ServerErrorDomain";

/**
  * the call back function called when the server accepts a connection
 */
static void SocketAcceptedConnectionCallBack(CFSocketRef socket,
                                             CFSocketCallBackType type,
                                             CFDataRef address,
                                             const void *data, void *info);

@implementation MRBServer

- (id)init {
    return [self initWithDomainName:@""
                           protocol:MRBDefaultProtocol
                               name:@""];
}

- (id)initWithProtocol:(NSString *)protocol {
    return [self initWithDomainName:@""
                           protocol:[NSString stringWithFormat:@"_%@._tcp.", protocol]
                               name:@""];
}

- (id)initWithDomainName:(NSString *)domain
                protocol:(NSString *)protocol
                    name:(NSString *)name {
    self = [super init];
    if (self) {
        self.domain = domain;
        self.protocol = protocol;
        self.name = name;
        self.outputStreamHasSpace = NO;
        self.payloadSize = 128;
    }
    return self;
}

- (CFSocketRef)createSocket {
    CFSocketContext socketCtxt = {0, (__bridge void *)(self), NULL, NULL, NULL};
    return CFSocketCreate(kCFAllocatorDefault,
                          PF_INET,
                          SOCK_STREAM,
                          IPPROTO_TCP,
                          kCFSocketAcceptCallBack,
                          (CFSocketCallBack)&SocketAcceptedConnectionCallBack,
                          &socketCtxt);
}

- (BOOL)publishNetService {
    BOOL successful = NO;
    self.netService = [[NSNetService alloc] initWithDomain:self.domain
                                                      type:self.protocol
                                                      name:self.name
                                                      port:self.port];
    if (self.netService) {
        [self.netService scheduleInRunLoop:[NSRunLoop currentRunLoop]
                                   forMode:NSRunLoopCommonModes];
        [self.netService publish];
        self.netService.delegate = self;
        successful = YES;
    }
    return successful;
}

- (BOOL)start {
    BOOL successful = YES;
    NSError *error;
    self.socket = [self createSocket];
    if (!self.socket) {
        error = [[NSError alloc] initWithDomain:MRBServerErrorDomain
                                           code:MRBServerNoSocketsAvailable
                                       userInfo:nil];
        successful = NO;
    }
    
    if (successful) {
        // enable address reuse
        int yes = 1;
        setsockopt(CFSocketGetNative(self.socket),
                   SOL_SOCKET, SO_REUSEADDR,
                   (void *)&yes, sizeof(yes));
        /** set the packet size for send and receive
          * cuts down on latency and such when sending
          * small packets
         */
        uint8_t packetSize = self.payloadSize;
        setsockopt(CFSocketGetNative(self.socket),
                   SOL_SOCKET, SO_SNDBUF,
                   (void *)&packetSize, sizeof(packetSize));
        setsockopt(CFSocketGetNative(self.socket),
                   SOL_SOCKET, SO_RCVBUF,
                   (void *)&packetSize, sizeof(packetSize));

        /** set up the IPv4 endpoint; use port 0, so the kernel
          * will choose an arbitrary port for us, which will be
          * advertised through Bonjour
         */
        struct sockaddr_in addr4;
        memset(&addr4, 0, sizeof(addr4));
        addr4.sin_len = sizeof(addr4);
        addr4.sin_family = AF_INET;
        addr4.sin_port = 0; // since we set it to zero the kernel will assign one for us
        addr4.sin_addr.s_addr = htonl(INADDR_ANY);
        NSData *address4 = [NSData dataWithBytes:&addr4 length:sizeof(addr4)];

        if (kCFSocketSuccess != CFSocketSetAddress(self.socket, (CFDataRef)address4)) {
            error = [[NSError alloc] initWithDomain:MRBServerErrorDomain
                                               code:MRBServerCouldNotBindToIPv4Address
                                           userInfo:nil];
            if (self.socket) {
                CFRelease(self.socket);
            }
            self.socket = NULL;
            successful = NO;
        } else {
            // now that the binding was successful, we get the port number
            NSData *addr = (NSData *)CFBridgingRelease(CFSocketCopyAddress(self.socket));
            memcpy(&addr4, [addr bytes], [addr length]);
            self.port = ntohs(addr4.sin_port);

            // set up the run loop sources for the sockets
            CFRunLoopRef cfrl = CFRunLoopGetCurrent();
            CFRunLoopSourceRef source4 = CFSocketCreateRunLoopSource(kCFAllocatorDefault, self.socket, 0);
            CFRunLoopAddSource(cfrl, source4, kCFRunLoopCommonModes);
            CFRelease(source4);

            if(![self publishNetService]) {
                successful = NO;
            }
        }
    }

    return successful;
}

@end

static void SocketAcceptedConnectionCallBack(CFSocketRef socket,
                                             CFSocketCallBackType type,
                                             CFDataRef address,
                                             const void *data, void *info) {

}
