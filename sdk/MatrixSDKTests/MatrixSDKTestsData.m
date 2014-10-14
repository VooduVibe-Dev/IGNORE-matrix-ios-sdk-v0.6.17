/*
 Copyright 2014 OpenMarket Ltd
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

#import "MatrixSDKTestsData.h"

#import "MXHomeServer.h"
#import "MXError.h"

/*
 Out of the box, the tests are supposed to be run with the iOS simulator attacking
 a test home server running on the same Mac machine.
 The reason is that the simulator can access to the home server running on the Mac 
 via localhost. So everyone can use a localhost HS url that works everywhere.
 
 You are free to change this URL and you have to if you want to run tests on a true
 device.
 
 Here, we use one of the home servers launched by the ./demo/start.sh script
 */


#define MXTESTS_BOB @"mxBob"
#define MXTESTS_BOB_PWD @"bobbob"


NSString *const kMXTestsHomeServerURL = @"http://localhost:8080";

@interface MatrixSDKTestsData ()
{
    MXHomeServer *homeServer;
}
@end

@implementation MatrixSDKTestsData

- (id)init
{
    self = [super init];
    if (self)
    {
        homeServer = [[MXHomeServer alloc] initWithHomeServer:kMXTestsHomeServerURL];
    }
    return self;
}

+ (id)sharedData
{
    static MatrixSDKTestsData *sharedData = nil;
    @synchronized(self) {
        if (sharedData == nil)
            sharedData = [[self alloc] init];
    }
    return sharedData;
}


- (void)getBobCredentials:(void (^)())success
{
    if (self.bobCredentials)
    {
        // Credentials are already here, they are ready
        success();
    }
    else
    {
        // First, try register the user
        [homeServer registerWithUser:MXTESTS_BOB andPassword:MXTESTS_BOB_PWD success:^(MXLoginResponse *credentials) {
            
            _bobCredentials = credentials;
            success();
            
        } failure:^(NSError *error) {
            MXError *mxError = [[MXError alloc] initWithNSError:error];
            if (mxError && [mxError.errcode isEqualToString:@"M_USER_IN_USE"])
            {
                // The user already exists. This error is normal.
                // Log Bob in to get his keys
                [homeServer loginWithUser:MXTESTS_BOB andPassword:MXTESTS_BOB_PWD success:^(MXLoginResponse *credentials) {
                    
                    _bobCredentials = credentials;
                    success();
                    
                } failure:^(NSError *error) {
                    NSAssert(NO, @"Cannot log mxBOB in");
                }];
            }
            else
            {
                NSAssert(NO, @"Cannot create mxBOB account");
            }
        }];
    }
}

- (void)getBobMXSession:(void (^)(MXSession *))success
{
    [self getBobCredentials:^{
        
        MXSession *session = [[MXSession alloc] initWithHomeServer:kMXTestsHomeServerURL userId:self.bobCredentials.user_id accessToken:self.bobCredentials.access_token];
        
        success(session);
    }];
}


- (void)doMXSessionTestWithBob:(XCTestCase*)testCase
                   readyToTest:(void (^)(MXSession *bobSession, XCTestExpectation *expectation))readyToTest
{
    XCTestExpectation *expectation = [testCase expectationWithDescription:@"asyncTest"];
    
    MatrixSDKTestsData *sharedData = [MatrixSDKTestsData sharedData];
    
    [sharedData getBobCredentials:^{
        
        MXSession *session = [[MXSession alloc] initWithHomeServer:kMXTestsHomeServerURL userId:sharedData.bobCredentials.user_id accessToken:sharedData.bobCredentials.access_token];
        
        readyToTest(session, expectation);
        
    }];
    
    [testCase waitForExpectationsWithTimeout:10000 handler:nil];
}

- (void)doMXSessionTestWithBobAndARoom:(XCTestCase*)testCase
                           readyToTest:(void (^)(MXSession *bobSession, NSString* room_id, XCTestExpectation *expectation))readyToTest
{
    [self doMXSessionTestWithBob:testCase
                     readyToTest:^(MXSession *bobSession, XCTestExpectation *expectation) {
        // Create a random room to use
        [bobSession createRoom:nil visibility:nil room_alias_name:nil topic:nil invite:nil success:^(MXCreateRoomResponse *response) {
            
            readyToTest(bobSession, response.room_id, expectation);
            
        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot create a room - error: %@", error);
        }];
    }];
}

- (void)doMXSessionTestInABobRoomAndANewTextMessage:(XCTestCase*)testCase
                                  newTextMessage:(NSString*)newTextMessage
                                   onReadyToTest:(void (^)(MXSession *bobSession, NSString* room_id, NSString* new_text_message_event_id, XCTestExpectation *expectation))readyToTest
{
    XCTestExpectation *expectation = [testCase expectationWithDescription:@"asyncTest"];
    
    MatrixSDKTestsData *sharedData = [MatrixSDKTestsData sharedData];
    
    [sharedData getBobMXSession:^(MXSession *bobSession) {
        // Create a random room to use
        [bobSession createRoom:nil visibility:nil room_alias_name:nil topic:nil invite:nil success:^(MXCreateRoomResponse *response) {
            
            // Post the the message text in it
            [bobSession postTextMessage:response.room_id text:newTextMessage success:^(NSString *event_id) {
                
                readyToTest(bobSession, response.room_id, event_id, expectation);
                
            } failure:^(NSError *error) {
                NSAssert(NO, @"Cannot set up intial test conditions");
            }];
            
        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot create a room - error: %@", error);
        }];
    }];
    
    [testCase waitForExpectationsWithTimeout:10000 handler:nil];
}

- (void)doMXSessionTestWithBobAndARoomWithMessages:(XCTestCase*)testCase
                                       readyToTest:(void (^)(MXSession *bobSession, NSString* room_id, XCTestExpectation *expectation))readyToTest
{
    [self doMXSessionTestWithBobAndARoom:testCase
                             readyToTest:^(MXSession *bobSession, NSString *room_id, XCTestExpectation *expectation) {
        
        MatrixSDKTestsData *sharedData = [MatrixSDKTestsData sharedData];
        
        // Add 5 messages to the room
        [sharedData for:bobSession andRoom:room_id postMessages:5 success:^{
            
            readyToTest(bobSession, room_id, expectation);
        }];
        
    }];
}

- (void)doMXSessionTestWihBobAndSeveralRoomsAndMessages:(XCTestCase*)testCase
                                         readyToTest:(void (^)(MXSession *bobSession, XCTestExpectation *expectation))readyToTest
{
    XCTestExpectation *expectation = [testCase expectationWithDescription:@"asyncTest"];
    
    MatrixSDKTestsData *sharedData = [MatrixSDKTestsData sharedData];
    
    [sharedData getBobMXSession:^(MXSession *bobSession) {
        
        // Fill Bob's account with 5 rooms of 3 messages
        [sharedData for:bobSession createRooms:5 withMessages:3 success:^{
            readyToTest(bobSession, expectation);
        }];
    }];
    
    [testCase waitForExpectationsWithTimeout:10000 handler:nil];
}


- (void)for:(MXSession *)mxSession andRoom:(NSString*)room_id postMessages:(NSUInteger)messagesCount success:(void (^)())success
{
    NSLog(@"postMessages :%ld", messagesCount);
    if (0 == messagesCount)
    {
        success();
    }
    else
    {
        [mxSession postTextMessage:room_id text:[NSString stringWithFormat:@"Fake message #-%ld", messagesCount]
                           success:^(NSString *event_id) {

            // Post the next message
            [self for:mxSession andRoom:room_id postMessages:messagesCount - 1 success:success];

        } failure:^(NSError *error) {
            // If the error is M_LIMIT_EXCEEDED, make sure your home server rate limit is high
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];
    }
}

- (void)for:(MXSession *)mxSession createRooms:(NSUInteger)roomsCount withMessages:(NSUInteger)messagesCount success:(void (^)())success
{
    if (0 == roomsCount)
    {
        // The recursivity is done
        success();
    }
    else
    {
        // Create the room
        [mxSession createRoom:nil visibility:nil room_alias_name:nil topic:nil invite:nil success:^(MXCreateRoomResponse *response) {

            // Fill it with messages
            [self for:mxSession andRoom:response.room_id postMessages:messagesCount success:^{

                // Go to the next room
                [self for:mxSession createRooms:roomsCount - 1 withMessages:messagesCount success:success];
            }];
        } failure:^(NSError *error) {
            // If the error is M_LIMIT_EXCEEDED, make sure your home server rate limit is high
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];
    }
}

@end
