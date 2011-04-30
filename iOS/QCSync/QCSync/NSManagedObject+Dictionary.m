/*
 *  NSManagedObject+Dictionary.m
 *  CoreDataSyncExample
 *
 *  Created by Vladimir Zardina
 *  Modified by Lee Barney
 *
 *  Modification includes the requirement that all
 *  NSManagedObjects have a UUID field called uuid.  It is used
 *  when an object has already been converted so as not to 
 *  duplicate data.
 *
 *
 *  Logic has been added specifically for the EnterpriseSync library
 *
 *
 */

#include <CoreData/CoreData.h>
#include "NSManagedObject+Dictionary.h"

#import "SyncTracker.h"
#import "SyncEntry.h"
#import "Trackable.h"
#import "SynchronizedDB.h"

@implementation NSManagedObject (toDictionary)

-(NSDictionary *) toDictionary:(NSMutableSet*)traversedObjects
{
	static int recursion_level = 0;
	recursion_level++;
	NSLog(@"recursion level: %d",recursion_level);
	if (![self isKindOfClass:[Trackable class]] 
		  && ![self isKindOfClass:[SyncTracker class]]
		  && ![self isKindOfClass:[SyncEntry class]]) {
		recursion_level --;
		return [NSDictionary dictionary];
	}
	BOOL traversed = [traversedObjects containsObject:self];
	NSLog(@" %@is traversed: %@",[self class], traversed == YES ? @"YES" : @"NO");
	if (!traversed) {
		NSLog(@"Adding %@ object to traversed list",[self class]);
		[traversedObjects addObject:self];
		/*
		 *  Each time an object is set to be traversed also set it's SyncEntry to be traversed.
		 */
		if ([self isKindOfClass:[Trackable class]]) {
			NSObject* aSyncEntry = [self valueForKey:@"syncEntry"];
			//if (aSyncEntry != nil) {
				[traversedObjects addObject:aSyncEntry];
			//}
		}
	}

    NSArray* attributes = [[[self entity] attributesByName] allKeys];
    NSArray* relationships = [[[self entity] relationshipsByName] allKeys];
    NSMutableDictionary* dict = [NSMutableDictionary dictionaryWithCapacity:
                                 [attributes count] + [relationships count] + 1];
	if (![self isKindOfClass:[SyncTracker class]] && ![self isKindOfClass:[SyncEntry class]]) {
		NSLog(@"type of object is %@",[self class]);
		[dict setObject:[[self class] description] forKey:@"syncType"];
	}
	
	if ([self isKindOfClass:[SyncEntry class]] && ((SyncEntry*)self).UUID != nil) {
		[dict setObject:((SyncEntry*)self).UUID forKey:@"UUID"];
		//[dict setObject:((SyncEntry*)self).deleteType  forKey:@"deleteType"];
	}
	else {
		for (NSString* attr in attributes) {
			if ([attr isEqual:@"isDirty"]) {
				continue;
			}
			NSObject* value = [self valueForKey:attr];
			if (value != nil) {
				NSLog(@"setting value: %@",value);
				[dict setObject:value forKey:attr];
			}
		}		
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
				/*
				 * Don't follow the reverse relationship from a tracked object
				 * to the SyncEntry but do go from the SyncData to the SyncEntry
				 * and from the SyncEntry to the tracked object and across relationships
				 * between tracked objects.
				 */
				if (![self isKindOfClass:[SyncTracker class]] && [relatedObject isKindOfClass:[SyncEntry class]]) {
					break;
				}
				
				/*
				 *  If the object in the relationship has not been traversed call to dictionary.
				 */
                if (![traversedObjects containsObject:relatedObject]) {
					NSDictionary *subDictionary = [relatedObject toDictionary:traversedObjects];
					if(subDictionary != nil){
						[dictSet addObject:subDictionary];
					}
                }
				else if(![relatedObject isKindOfClass:[SyncEntry class]]) {
					NSDictionary *traversedDictionary = [NSDictionary dictionaryWithObject:[relatedObject valueForKey:@"uuid"] forKey:@"uuid"];
					[dictSet addObject:traversedDictionary];
				}
            }
			
            [dict setObject:dictSet forKey:relationship];
        }
        else if ([value isKindOfClass:[Trackable class]]) {
			NSLog(@"%@ is a to one relationship", [value class]);
            // To-one relationship
            Trackable* relatedObject = (Trackable*) value;
			
			if ([relatedObject isKindOfClass:[SyncTracker class]] || ([self isKindOfClass:[Trackable class]] && [relatedObject isKindOfClass:[SyncEntry class]])) {
				NSLog(@"returning since self is trackable and value is sync entry");
				recursion_level --;
				return nil;
			}
            if (![traversedObjects containsObject:relatedObject]) {
                // Call toDictionary on the referenced object and put the result back into our dictionary.
				NSLog(@"calling to dictionary on %@",[relatedObject class]);
				NSDictionary *subDictionary = [relatedObject toDictionary:traversedObjects];
				if(subDictionary != nil){
					[dict setObject:subDictionary forKey:relationship];
				}
				if ([self isKindOfClass:[SyncEntry class]]) {
					return subDictionary;
				}
            }
			else if(![relatedObject isKindOfClass:[SyncEntry class]] && ![relatedObject isKindOfClass:[SyncTracker class]]){
				/*
				 * all tracked objects are required to have a uuid
				 */
				NSLog(@"relationship setting %@ to uuid %@",relationship,[relatedObject valueForKey:@"uuid"]);
				//need to set the 
				[dict setObject:[relatedObject valueForKey:@"uuid"] forKey:relationship];
			}
        }

    }
	recursion_level --;
	if ([dict count] == 0) {
		return nil;
	}
    return dict;
}


+(NSArray*) fromDictionary:(NSArray*)dictionaries inContext:(NSManagedObjectContext*)aContext{
	NSMutableArray *createdObjects = [NSMutableArray arrayWithCapacity:0];
	
	int numDictionaries = [dictionaries count];
	for (int i = 0; i < numDictionaries; i++) {
		NSDictionary *anObjectDescription = [dictionaries objectAtIndex:i];
		
		NSLog(@"creating from representation: %@",anObjectDescription);
		/*
		 *  find or create a managed object of the correct type.
		 */
		NSString *objectType = [anObjectDescription objectForKey:@"eventType"];
		NSString *uuid = [anObjectDescription objectForKey:@"uuid"];
		/*
		 *  Check to see if this object has already been created.
		 *  If not then create it.
		 */
		Trackable *aTrackableEntity = nil;
		NSFetchRequest *request = [[NSFetchRequest alloc] init];
		//NSLog(@"%@",[Synchronizer instance:nil].theContext);
		NSEntityDescription *entity = [NSEntityDescription entityForName:objectType inManagedObjectContext:aContext];
		[request setEntity:entity];
		//NSLog(@"%@",[aName class]);
		NSPredicate *predicate = [NSPredicate predicateWithFormat:@"uuid == [c]%@", uuid];
		[request setPredicate:predicate];
		NSError *error = nil;
		NSMutableArray *foundEntities = [[aContext executeFetchRequest:request error:&error] mutableCopy];
		if (error != nil) {
			NSLog(@"%@",error);
			return createdObjects;
		}
		if ([foundEntities count] == 1) {
			aTrackableEntity = [foundEntities objectAtIndex:0];
		}
		else {
			aTrackableEntity = [NSEntityDescription insertNewObjectForEntityForName:objectType
																		inManagedObjectContext:aContext];
			[aTrackableEntity setValue:uuid forKey:@"uuid"];
			if (![aContext save:&error]) {
				// Handle the error.
				NSLog(@"ERROR: %@",error);
			}
		}
		[createdObjects addObject:aTrackableEntity];
		NSArray *attributeNames = [anObjectDescription allKeys];
		int numAtts = [attributeNames count];
		for (int attNum = 0; attNum < numAtts; attNum++) {
			NSString *attributeName = [attributeNames objectAtIndex:attNum];
			if ([attributeName isEqual:@"syncType"] || [attributeName isEqual:@"uuid"]) {
				continue;
			}
			/*
			 * if the name of the attribute is the name of a relationship to a single object
			 * and the object doesn't exist then I need to create it and set the attribute 
			 * to the single object.
			 */
			id attributeValue = [anObjectDescription objectForKey:attributeName];
			//NSString *upperAttributeName = [attributeName stringByReplacingCharactersInRange:NSMakeRange(0,1) withString:[[attributeName substringToIndex:1] uppercaseString]];
			
			/*
			 *  If an attribute has the UUID structure and is not the uuid attribute then there must
			 *  be a one-to-one relationship.
			 */
			if ([attributeValue isKindOfClass:[NSString class]] && [NSManagedObject isUUID:attributeValue]) {
				/*
				 *  find or create an object with the given UUID.
				 */
				NSFetchRequest *request = [[NSFetchRequest alloc] init];
				NSEntityDescription *entity = [NSEntityDescription entityForName:attributeName inManagedObjectContext:aContext];
				[request setEntity:entity];
				NSPredicate *predicate = [NSPredicate predicateWithFormat:@"uuid == [c]%@", attributeValue];
				[request setPredicate:predicate];
				NSMutableArray *foundAttributeEntities = [[aContext executeFetchRequest:request error:&error] mutableCopy];
				if (error != nil) {
					NSLog(@"%@",error);
					continue;
				}
				if ([foundAttributeEntities count] == 1) {
					attributeValue = [foundAttributeEntities objectAtIndex:0];
				}
				else {
					attributeValue = [NSEntityDescription insertNewObjectForEntityForName:attributeName
																	 inManagedObjectContext:aContext];
					[(Trackable*)attributeValue setValue:uuid forKey:@"uuid"];
					if (![aContext save:&error]) {
						// Handle the error.
						NSLog(@"ERROR: %@",error);
					}
				}
			}
			else if([attributeValue isKindOfClass:[NSArray class]]){
				attributeValue = [NSManagedObject fromRepresentation:attributeValue];
			}
			[aTrackableEntity setValue:attributeValue forKey:attributeName];
		}
	}
	return createdObjects;
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
	NSLog(@"found uuid for to one relationship: %@",aPotentialUUIDString);
	return YES;
}

@end
