/*
 Copyright (c) 2009, 2011 Lee Barney
 Permission is hereby granted, free of charge, to any person obtaining a 
 copy of this software and associated documentation files (the "Software"), 
 to deal in the Software without restriction, including without limitation the 
 rights to use, copy, modify, merge, publish, distribute, sublicense, 
 and/or sell copies of the Software, and to permit persons to whom the Software 
 is furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be 
 included in all copies or substantial portions of the Software.
 
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, 
 INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A 
 PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT 
 HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF 
 CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE 
 OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 
 */

#include <CoreData/CoreData.h>
#include "NSManagedObject+Dictionary.h"

#import "Trackable.h"
#import "SynchronizedDB.h"

@implementation NSManagedObject (toDictionary)

-(NSDictionary *) toDictionary
{
	/*if (![self isKindOfClass:[Trackable class]]) {
		return [NSDictionary dictionary];
	}*/

    NSArray* attributes = [[[self entity] attributesByName] allKeys];
    NSArray* relationships = [[[self entity] relationshipsByName] allKeys];
    NSMutableDictionary* dict = [NSMutableDictionary dictionaryWithCapacity:
                                 [attributes count] + [relationships count] + 1];
    
    for (NSString* attributeName in attributes) {
        [dict setObject:[self valueForKey:attributeName] forKey:attributeName];
    }
    for (NSString* relationship in relationships) {
        NSObject* value = [self valueForKey:relationship];
		NSLog(@"doing relationship %@",relationship);
        if ([value isKindOfClass:[NSSet class]]) {
            // To-many relationship
			NSLog(@"is a to many relationship");
            // The core data set holds a collection of managed objects
            NSSet* relatedObjects = (NSSet*) value;
			
            // Our set holds a collection of dictionaries
            NSMutableSet* dictSet = [NSMutableSet setWithCapacity:[relatedObjects count]];
			
            for (NSManagedObject* relatedObject in relatedObjects) {
                NSDictionary *relatedDictionary = [NSDictionary dictionaryWithObject:[relatedObject valueForKey:@"UUID"] forKey:@"UUID"];
                [dictSet addObject:relatedDictionary];
            }
			
            [dict setObject:dictSet forKey:relationship];
        }
        else if ([value isKindOfClass:[Trackable class]]) {
			NSLog(@"%@ is a to one relationship", [value class]);
            // To-one relationship
            Trackable* relatedObject = (Trackable*) value;
            /*
             * all tracked objects are required to have a uuid
             */
            NSLog(@"relationship setting %@ to uuid %@",relationship,[relatedObject valueForKey:@"UUID"]);
            //need to set the 
            [dict setObject:[relatedObject valueForKey:@"UUID"] forKey:relationship];
        }

    }
    return dict;
}


+(void) updateStoreWithDictionaries:(NSArray*)dictionaries inContext:(NSManagedObjectContext*)aContext{
    NSMutableDictionary *unfoundRelationships = [NSMutableDictionary dictionaryWithCapacity:0];
    NSDateFormatter *theDateFormatter = [[NSDateFormatter alloc] init];
    [theDateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    for (NSDictionary *anObjectDescription in dictionaries) {
        NSString *key = [[anObjectDescription allKeys] objectAtIndex:0];
        NSArray *keyParts = [key componentsSeparatedByString:@"_"];
        NSString *objectType = [keyParts objectAtIndex:2];
        NSLog(@"objectType: %@",objectType);
        
        NSDictionary *keysAndValues = [anObjectDescription objectForKey:key]; 
        /*
         *  All Trackables must have a UUID
         */
        NSString *currentUUID = [keysAndValues objectForKey:@"UUID"];
        //valid change types are delete, update, create
        /*
         *  Check to see if the object already exists in the data store
         */
		NSFetchRequest *request = [[NSFetchRequest alloc] init];
		NSEntityDescription *entity = [NSEntityDescription entityForName:objectType inManagedObjectContext:aContext];
		[request setEntity:entity];
		NSPredicate *predicate = [NSPredicate predicateWithFormat:@"UUID == [c]%@", currentUUID];
		[request setPredicate:predicate];
		NSError *error = nil;
		NSMutableArray *foundTrackables = [[aContext executeFetchRequest:request error:&error] mutableCopy];
        NSLog(@"description: %@",anObjectDescription);
        NSString *eventType = [keysAndValues objectForKey:@"eventType"];
        NSLog(@"event %@ found trackables for %@: %@",eventType, currentUUID,foundTrackables);
        if ([eventType hasPrefix:@"delete"]) {
            if ([foundTrackables count] > 0) {
                //there should only be one but use a loop just in case.
                for (Trackable *foundTrackable in foundTrackables) {
                    [aContext deleteObject:foundTrackable];
                }
                continue;
            }
        }
        else if([eventType hasPrefix:@"create"] || [eventType hasPrefix:@"create"]){
            Trackable *theTrackable = nil;
            
            if ([eventType hasPrefix:@"create"]) {
                theTrackable = [NSEntityDescription
                                insertNewObjectForEntityForName:objectType
                                inManagedObjectContext:aContext];
            }
            else{
                theTrackable = [foundTrackables objectAtIndex:0];
            }
            /*
             *  Find any relationships requiring this new Trackable.  
             *  Set them and then remove them from the tracker.
             */
            NSLog(@"objects needing a relationship: %@",unfoundRelationships);
            NSDictionary *neededRelationshipsForUUID = [unfoundRelationships objectForKey:currentUUID];
            NSLog(@"relationships needed for UUID: %@, %@",currentUUID,neededRelationshipsForUUID);
            
            NSEnumerator *neededRelationshipEnumerator = [neededRelationshipsForUUID keyEnumerator];
            NSString *relationshipName = nil;
            while((relationshipName = [neededRelationshipEnumerator nextObject])){
                 NSArray *neededRelationshipsOfCorrectType = [neededRelationshipsForUUID objectForKey:relationshipName];
                 //for each Trackable waiting for this UUID
                 NSLog(@"objects needing this relationship: %@",neededRelationshipsOfCorrectType);
                 
                 for(Trackable *needyTrackable in neededRelationshipsOfCorrectType){
                     NSLog(@"needy Trackable: %@",needyTrackable);
                     [needyTrackable setValue:theTrackable forKey:relationshipName];
                 }
            }
            [unfoundRelationships removeObjectForKey:currentUUID];

            NSEnumerator *enumerator = [keysAndValues keyEnumerator];
            NSString *key;
            while ((key = [enumerator nextObject])) {
                NSLog(@"setting value for key: %@",key);
                // find all of the to-many relationships
                if([[keysAndValues objectForKey:key] isKindOfClass:[NSArray class] ]){
                    NSMutableSet *relatedTrackablesToAdd = nil;
                    for(id relatedReference in [keysAndValues objectForKey:key]){
                        if ([relatedReference isKindOfClass:[NSDictionary class]]) {
                            NSLog(@"%@ is not a dictionary so can not be a Trackable", key);
                            break;
                        }
                        NSString *relatedUUID = [relatedReference objectForKey:@"UUID"];
                        // if the 
                        if (!relatedReference) {
                            NSLog(@"%@ does not have a UUID so can not be a Trackable",key);
                            break;
                        }
                        NSFetchRequest *request = [[NSFetchRequest alloc] init];
                        //NSLog(@"%@",[Synchronizer instance:nil].theContext);
                        NSEntityDescription *entity = [NSEntityDescription entityForName:objectType inManagedObjectContext:aContext];
                        [request setEntity:entity];
                        //NSLog(@"%@",[aName class]);
                        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"UUID == [c]%@", relatedUUID];
                        [request setPredicate:predicate];
                        NSError *error = nil;
                        NSMutableArray *foundRelatedTrackables = [[aContext executeFetchRequest:request error:&error] mutableCopy];
                        if ([foundTrackables count] > 0) {
                            if (relatedTrackablesToAdd == nil) {
                                relatedTrackablesToAdd = [NSMutableSet setWithCapacity:1];
                            }
                            Trackable *foundRelatedTrackable = [foundRelatedTrackables objectAtIndex:0];
                            //???? change this
                            [relatedTrackablesToAdd addObject:foundRelatedTrackable];
                        }
                        else{
                            NSArray *trackableNotFound = [NSArray arrayWithObjects:key, theTrackable, nil];
                            
                            [unfoundRelationships setValue:trackableNotFound forKey:relatedUUID];
                        }
                    }
                    if (relatedTrackablesToAdd) {
                        [theTrackable setValue:relatedTrackablesToAdd forKey:key];
                    }
                }
                //else if it is a to-one relationship (IGNORE THE BASE UUID key for the object being created)
                else if(![key isEqualToString:@"UUID"]
                          && [[keysAndValues objectForKey:key] isKindOfClass:[NSString class]]
                          && [NSManagedObject isUUID:[keysAndValues objectForKey:key]]){
                    NSString *relatedUUID = [keysAndValues objectForKey:key];
                    /*
                     *  See if the related Trackable already exists.  If not then store the 
                     *  need for later resolution.
                     */
                    NSFetchRequest *request = [[NSFetchRequest alloc] init];
                    //NSLog(@"%@",[Synchronizer instance:nil].theContext);
                    NSEntityDescription *entity = [NSEntityDescription entityForName:objectType inManagedObjectContext:aContext];
                    [request setEntity:entity];
                    //NSLog(@"%@",[aName class]);
                    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"UUID == [c]%@", relatedUUID];
                    [request setPredicate:predicate];
                    NSError *error = nil;
                    NSMutableArray *foundRelatedTrackables = [[aContext executeFetchRequest:request error:&error] mutableCopy];
                    if ([foundRelatedTrackables count] > 0) {
                        Trackable *foundTrackable = [foundRelatedTrackables objectAtIndex:0];
                        NSSet *changedObjects = [[NSSet alloc] initWithObjects:&foundTrackable count:1];
                        [theTrackable willChangeValueForKey:key withSetMutation:NSKeyValueUnionSetMutation usingObjects:changedObjects];
                        [[theTrackable primitiveValueForKey:key] addObject:foundTrackable];
                        [theTrackable didChangeValueForKey:key withSetMutation:NSKeyValueUnionSetMutation usingObjects:changedObjects];
                        [changedObjects release];
                    }
                    //not found so add it to the required list.
                    else{
                        
                        NSMutableDictionary *neededRelationshipsForThisUUID = [unfoundRelationships objectForKey:relatedUUID];
                        if (!neededRelationshipsForThisUUID) {
                            neededRelationshipsForThisUUID = [NSMutableDictionary dictionaryWithCapacity:1];
                            [unfoundRelationships setObject:neededRelationshipsForThisUUID forKey:relatedUUID];
                        }
                        //key is the name of the relationship
                        NSMutableArray *allUUIDsForRelationshipWithName = [neededRelationshipsForThisUUID objectForKey:key];
                        if (!allUUIDsForRelationshipWithName) {
                            allUUIDsForRelationshipWithName = [NSMutableArray arrayWithCapacity:1];
                            [neededRelationshipsForThisUUID setObject:allUUIDsForRelationshipWithName forKey:key];
                        }
                        NSLog(@"adding needed relationship %@ with trackable: %@",key,theTrackable);
                        [allUUIDsForRelationshipWithName addObject:theTrackable];
                        NSLog(@"unfound: %@",unfoundRelationships);
                    }
                }
                //else it must be a non-Trackable value
                else{
                    id value = [keysAndValues objectForKey:key];
                    if ([value isKindOfClass:[NSString class]]) {
                        //NSDate* theDate = [theDateFormatter dateFromString:value];
                        //[theDateFormatter getObjectValue:theDate forString:value range:theRange error:&dateError];
                        NSDate *theDate = [theDateFormatter dateFromString:value];
                        NSLog(@"theDate: %@ from string: %@",theDate,value);
                        if(theDate){
                            value = theDate;
                        }
                    }
                    //NSLog(@"key: '%@' comparedTo 'eventType'",key);
                    if ([key isEqualToString:@"eventType"]) {
                        value = @"update";
                    }
                    //NSLog(@"setting value: %@ for key: %@",value,key);
                    [theTrackable setValue:value forKey:key];
                }
            }
            NSError *saveError = nil;
            [aContext save:&saveError];
            NSLog(@"save error: %@",saveError);
            //NSLog(@"theTrackable: %@",theTrackable);
        }
        else{
            NSLog(@"Error: unrecognized event type: %@",eventType);
        }
        
    }
    [theDateFormatter release];
}

+(BOOL) isUUID:(NSString*)aPotentialUUIDString{

	if (([aPotentialUUIDString length] != 36) 
		|| [aPotentialUUIDString characterAtIndex:8] != '-' 
		|| [aPotentialUUIDString characterAtIndex:13] != '-'
		|| [aPotentialUUIDString characterAtIndex:18] != '-'
		|| [aPotentialUUIDString characterAtIndex:23] != '-'
		
		) {
		return NO;
	}
	NSLog(@"found uuid for relationship: %@",aPotentialUUIDString);
	return YES;
}

@end
