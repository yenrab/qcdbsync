//
//  NSManagedObjectContext_SyncDelete.m
//  QCSync
//
//  Created by lee barney on 7/30/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "NSManagedObjectContext_Sync.h"
#import "Trackable.h"

@implementation NSManagedObjectContext (NSManagedObjectContext_SyncDelete)

-(void)actualDeleteObject:(NSManagedObject*) objectToDelete{
    NSLog(@"deleting %@",objectToDelete);
    NSEntityDescription *trackableDescription = [NSEntityDescription entityForName:@"Trackable" inManagedObjectContext:self];
    if ([[objectToDelete entity] isKindOfEntity:trackableDescription]) {
        Trackable *asTrackable = (Trackable*)objectToDelete;
        asTrackable.flaggedAsDeleted = [NSNumber numberWithBool:YES];
        asTrackable.updateTime = [NSDate date];
        
        /*
         *  clean up relationships
         */
        
        NSArray* relationships = [[[objectToDelete entity] relationshipsByName] allKeys];
        for (NSString* relationship in relationships) {
            NSObject* value = [objectToDelete valueForKey:relationship];
            //NSLog(@"doing relationship %@",relationship);
            if ([value isKindOfClass:[NSSet class]]) {//to-many relationship
                NSSet *changedObjects = [[NSSet alloc] initWithObjects:&objectToDelete count:1];
                [objectToDelete willChangeValueForKey:relationship withSetMutation:NSKeyValueMinusSetMutation usingObjects:changedObjects];
                [[objectToDelete primitiveValueForKey:relationship] removeObject:value];
                [objectToDelete didChangeValueForKey:relationship withSetMutation:NSKeyValueMinusSetMutation usingObjects:changedObjects];
                [changedObjects release];
                
            }
            else{//to-one relationship
                [objectToDelete setValue:nil forKey:relationship];
            }
        }
        
    }
    else{
        //this is not recursive since at run time newDeleteObject references the functionality of the original delete method.
        //see the swizzle in the init method of SynchronizedDB.
        [self actualDeleteObject:objectToDelete];
    }
    
}
- (NSArray *)actualExecuteFetchRequest:(NSFetchRequest *)request error:(NSError **)error{
    NSEntityDescription *trackableDescription = [NSEntityDescription entityForName:@"Trackable" inManagedObjectContext:self];
    if ([[request entity] isKindOfEntity:trackableDescription]) {
    //add this predicate in to filter out all those entities that have been deleted somewhere else in your code.
        NSPredicate *deletedPredicate = [NSPredicate predicateWithFormat:@"flaggedAsDeleted == %@ || flaggedAsDeleted != %@", [NSNull null],[NSNumber numberWithBool:YES]];
        [request setPredicate:deletedPredicate];
    }
    return [self actualExecuteFetchRequest:request error:error];

}
@end

