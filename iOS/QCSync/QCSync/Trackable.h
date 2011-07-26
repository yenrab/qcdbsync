//
//  Trackable.h
//  QC DBSync Example
//
//  Created by lee barney on 7/25/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>


@interface Trackable : NSManagedObject {
@private
}
@property (nonatomic, retain) NSDate * updateTime;
@property (nonatomic, retain) NSString * eventType;
@property (nonatomic, retain) NSString * UUID;
@property (nonatomic, retain) NSNumber * isRemoteData;

@end
