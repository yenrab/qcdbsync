//
//  SyncTracker.h
//  QC DBSync Example
//
//  Created by Lee Barney on 4/4/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>


@interface SyncTracker : NSManagedObject {
@private
}
@property (nonatomic, retain) NSDate * lastSync;

@end
