//
//  NSManagedObjectContext_SyncDelete.h
//  QCSync
//
//  Created by lee barney on 7/30/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <CoreData/CoreData.h>

@interface NSManagedObjectContext (NSManagedObjectContext_SyncDelete)

-(void)actualDeleteObject:(NSManagedObject*) objectToDelete;
- (NSArray *)actualExecuteFetchRequest:(NSFetchRequest *)request error:(NSError **)error;
@end

