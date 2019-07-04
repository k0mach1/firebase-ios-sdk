/*
 * Copyright 2019 Google
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import <XCTest/XCTest.h>

#import <OCMock/OCMock.h>
#import "FBLPromise+Testing.h"

#import "FIRSecureStorage.h"

@interface FIRSecureStorage (Tests)
- (instancetype)initWithService:(NSString *)service cache:(NSCache *)cache;
- (void)resetInMemoryCache;
@end

@interface FIRSecureStorageTests : XCTestCase
@property(nonatomic, strong) FIRSecureStorage *storage;
@property(nonatomic, strong) NSCache *cache;
@property(nonatomic, strong) id mockCache;
@end

@implementation FIRSecureStorageTests

- (void)setUp {
  self.cache = [[NSCache alloc] init];
  self.mockCache = OCMPartialMock(self.cache);
  self.storage = [[FIRSecureStorage alloc] initWithService:@"com.tests.FIRSecureStorageTests"
                                                     cache:self.mockCache];
}

- (void)tearDown {
  self.storage = nil;
  self.mockCache = nil;
  self.cache = nil;
}

- (void)testSetGetObjectForKey {
  // 1. Write and read object initially.
  [self assertSuccessWriteObject:@[ @1, @2 ] forKey:@"test-key1"];
  [self assertSuccessReadObject:@[ @1, @2 ]
                         forKey:@"test-key1"
                          class:[NSArray class]
                  existsInCache:YES];

  // 2. Override existing object.
  [self assertSuccessWriteObject:@{@"key" : @"value"} forKey:@"test-key1"];
  [self assertSuccessReadObject:@{@"key" : @"value"}
                         forKey:@"test-key1"
                          class:[NSDictionary class]
                  existsInCache:YES];

  // 3. Read existing object which is not present in in-memory cache.
  [self.cache removeAllObjects];
  [self assertSuccessReadObject:@{@"key" : @"value"}
                         forKey:@"test-key1"
                          class:[NSDictionary class]
                  existsInCache:NO];

  // 4. Write and read an object for another key.
  [self assertSuccessWriteObject:@{@"key" : @"value"} forKey:@"test-key2"];
  [self assertSuccessReadObject:@{@"key" : @"value"}
                         forKey:@"test-key2"
                          class:[NSDictionary class]
                  existsInCache:YES];
}

- (void)testGetNonExistingObject {
  [self assertNonExistingObjectForKey:[NSUUID UUID].UUIDString class:[NSArray class]];
}

- (void)testGetExistingObjectClassMismatch {
  NSString *key = [NSUUID UUID].UUIDString;

  // Wtite.
  [self assertSuccessWriteObject:@[ @8 ] forKey:key];

  // Read.
  // Skip in-memory cache because the error is relevant only for Keychain.
  OCMExpect([self.mockCache objectForKey:key]).andReturn(nil);

  FBLPromise<id<NSSecureCoding>> *getPromise = [self.storage getObjectForKey:key
                                                                 objectClass:[NSString class]
                                                                 accessGroup:nil];

  XCTAssert(FBLWaitForPromisesWithTimeout(1));
  XCTAssertNil(getPromise.value);
  XCTAssertNotNil(getPromise.error);
  // TODO: Test for particular error.

  OCMVerifyAll(self.mockCache);
}

- (void)testRemoveExistingObject {
  NSString *key = @"testRemoveExistingObject";
  // Store the object.
  [self assertSuccessWriteObject:@[ @5 ] forKey:(NSString *)key];

  // Remove object.
  [self assertRemoveObjectForKey:key];

  // Check if object is still stored.
  [self assertNonExistingObjectForKey:key class:[NSArray class]];
}

- (void)testRemoveNonExistingObject {
  NSString *key = [NSUUID UUID].UUIDString;
  [self assertRemoveObjectForKey:key];
  [self assertNonExistingObjectForKey:key class:[NSArray class]];
}

#pragma mark - Common

- (void)assertSuccessWriteObject:(id<NSSecureCoding>)object forKey:(NSString *)key {
  OCMExpect([self.mockCache setObject:object forKey:key]).andForwardToRealObject();

  FBLPromise<NSNull *> *setPromise = [self.storage setObject:object forKey:key accessGroup:nil];

  XCTAssert(FBLWaitForPromisesWithTimeout(1));
  XCTAssertNil(setPromise.error);

  OCMVerify(self.mockCache);

  // Check in-memory cache.
  XCTAssertEqualObjects([self.cache objectForKey:key], object);
}

- (void)assertSuccessReadObject:(id<NSSecureCoding>)object
                         forKey:(NSString *)key
                          class:(Class)class
                  existsInCache:(BOOL)existisInCache {
  OCMExpect([self.mockCache objectForKey:key]).andForwardToRealObject();

  if (!existisInCache) {
    OCMExpect([self.mockCache setObject:object forKey:key]).andForwardToRealObject();
  }

  FBLPromise<id<NSSecureCoding>> *getPromise =
      [self.storage getObjectForKey:key objectClass:class accessGroup:nil];

  XCTAssert(FBLWaitForPromisesWithTimeout(1));
  XCTAssertEqualObjects(getPromise.value, object);
  XCTAssertNil(getPromise.error);

  OCMVerifyAll(self.mockCache);

  // Check in-memory cache.
  XCTAssertEqualObjects([self.cache objectForKey:key], object);
}

- (void)assertNonExistingObjectForKey:(NSString *)key class:(Class)class {
  OCMExpect([self.mockCache objectForKey:key]).andForwardToRealObject();

  FBLPromise<id<NSSecureCoding>> *promise =
      [self.storage getObjectForKey:key objectClass:class accessGroup:nil];

  XCTAssert(FBLWaitForPromisesWithTimeout(1));
  XCTAssertNil(promise.error);
  XCTAssertNil(promise.value);

  OCMVerifyAll(self.mockCache);
}

- (void)assertRemoveObjectForKey:(NSString *)key {
  OCMExpect([self.mockCache removeObjectForKey:key]).andForwardToRealObject();

  FBLPromise<NSNull *> *removePromise = [self.storage removeObjectForKey:key accessGroup:nil];
  XCTAssert(FBLWaitForPromisesWithTimeout(1));
  XCTAssertNil(removePromise.error);

  OCMVerifyAll(self.mockCache);
}

@end