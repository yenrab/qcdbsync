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
#import "Trackable.h"

@implementation NSManagedObject (toDictionary)

-(NSDictionary *) toDictionary:(NSMutableSet*)traversedObjects inContext:(NSManagedObjectContext*)aContext{
	static int recursion_level = 0;
	recursion_level++;
	//NSLog(@"recursion level: %d class: %@",recursion_level, [self class]);
    if ([[self entity] isKindOfEntity:[NSEntityDescription entityForName:@"SyncTracker" inManagedObjectContext:aContext]]) {
        [NSException raise:@"Invalid Trackable Entity" format:@"The SyncTracker in your data model may not inherit from Trackable.  Please fix this and try again.", nil];
    }
    NSEntityDescription *trackableDescription = [NSEntityDescription entityForName:@"Trackable" inManagedObjectContext:aContext];
    BOOL selfIsTrackable = [[self entity] isKindOfEntity:trackableDescription];

	if (!selfIsTrackable) {
		recursion_level --;
		return [NSDictionary dictionary];
	}
	BOOL traversed = [traversedObjects containsObject:self];
	//NSLog(@" %@is traversed: %@",[self class], traversed == YES ? @"YES" : @"NO");
	if (!traversed) {
		//NSLog(@"Adding %@ object to traversed list",[self class]);
		[traversedObjects addObject:self];
	}
    NSLog(@"description: %@",[self entity]);
    NSArray* attributes = [[[self entity] attributesByName] allKeys];
    NSArray* relationships = [[[self entity] relationshipsByName] allKeys];
    NSMutableDictionary* entityRepresentationDictionary = [NSMutableDictionary dictionaryWithCapacity:
                                 [attributes count] + [relationships count] + 1];
	if (selfIsTrackable) {
		//NSLog(@"type of object is %@",[self entity]);
        //NSLog(@"rep dict: %@",entityRepresentationDictionary);
        for (NSString* attr in attributes) {
            if ([attr isEqualToString:@"isRemoteData"]) {
                continue;
            }
            //NSLog(@"attribute name: %@",attr);
            NSObject* value = [self valueForKey:attr];
            NSLog(@"setting key: %@     value: %@",attr,value);
            if (value != nil) {
                [entityRepresentationDictionary setObject:value forKey:attr];
            }
        }	
        //NSLog(@"rep dict: %@",entityRepresentationDictionary);	
        
        for (NSString* relationship in relationships) {
            NSObject* value = [self valueForKey:relationship];
            //NSLog(@"doing relationship %@",relationship);
            if ([value isKindOfClass:[NSSet class]]) {
                // To-many relationship
                //NSLog(@"is a to many relationship");
                // The core data set holds a collection of managed objects
                NSSet* relatedObjects = (NSSet*) value;
                
                // The set needs to hold a collection of related objects as dictionaries
                NSMutableSet* dictSet = [NSMutableSet setWithCapacity:[relatedObjects count]];
                
                for (NSManagedObject* relatedObject in relatedObjects) {
                    
                    /*
                     *  If the object in the relationship has not been traversed call toDictionary.
                     */
                    if (![traversedObjects containsObject:relatedObject]) {
                        NSDictionary *subDictionary = [relatedObject toDictionary:traversedObjects inContext:aContext];
                        if(subDictionary != nil){
                            [dictSet addObject:subDictionary];
                        }
                    }
                    //the related object is trackable and has already been traversed
                    else if([[relatedObject entity] isKindOfEntity:trackableDescription]) {
                        NSDictionary *traversedDictionary = [NSDictionary dictionaryWithObject:[relatedObject valueForKey:@"UUID"] forKey:@"UUID"];
                        [dictSet addObject:traversedDictionary];
                    }
                }
                
                [entityRepresentationDictionary setObject:dictSet forKey:relationship];
            }
            else if ([value isKindOfClass:[NSManagedObject class]] 
                     && [[((NSManagedObject*)value) entity] isKindOfEntity:trackableDescription]) {
                //NSLog(@"%@ is a to one relationship", [value class]);
                // To-one relationship
                Trackable* relatedObject = (Trackable*) value;
                
                if (![traversedObjects containsObject:relatedObject]) {
                    // Call toDictionary on the referenced object and put the result back into our dictionary.
                    //NSLog(@"calling to dictionary on %@",[relatedObject class]);
                    NSDictionary *subDictionary = [relatedObject toDictionary:traversedObjects inContext:aContext];
                    if(subDictionary != nil){
                        [entityRepresentationDictionary setObject:subDictionary forKey:relationship];
                    }
                }
                else{
                    /*
                     * all tracked objects are required to have a uuid
                     */
                    //NSLog(@"relationship setting %@ to uuid %@",relationship,[relatedObject valueForKey:@"UUID"]);
                    //need to set the 
                    [entityRepresentationDictionary setObject:[relatedObject valueForKey:@"UUID"] forKey:relationship];
                }
            }
                          }
    }
	recursion_level --;
	if ([entityRepresentationDictionary count] == 0) {
		return nil;
	}
    NSString *syncType = [NSString stringWithFormat:@"sync_type_%@",[[self entity] name]];
    NSDictionary *returnValue = [NSDictionary dictionaryWithObject:entityRepresentationDictionary forKey:syncType];
    ////NSLog(@"returning: %@",returnValue);
    return returnValue;
}




+(NSArray*) fromDictionary:(NSArray*)dictionaries inContext:(NSManagedObjectContext*)aContext{
	NSMutableArray *createdObjects = [NSMutableArray arrayWithCapacity:0];
	
	int numDictionaries = [dictionaries count];
	for (int i = 0; i < numDictionaries; i++) {
		NSDictionary *anObjectDescription = [dictionaries objectAtIndex:i];
		
		//NSLog(@"creating from representation: %@",anObjectDescription);
		/*
		 *  find or create a managed object of the correct type.
		 */
		NSString *objectType = [anObjectDescription objectForKey:@"eventType"];
		NSString *uuid = [anObjectDescription objectForKey:@"UUID"];
		/*
		 *  Check to see if this object has already been created.
		 *  If not then create it.
		 */
		Trackable *aTrackableEntity = nil;
		NSFetchRequest *request = [[NSFetchRequest alloc] init];
		////NSLog(@"%@",[Synchronizer instance:nil].theContext);
		NSEntityDescription *entity = [NSEntityDescription entityForName:objectType inManagedObjectContext:aContext];
		[request setEntity:entity];
		////NSLog(@"%@",[aName class]);
		NSPredicate *predicate = [NSPredicate predicateWithFormat:@"uuid == [c]%@", uuid];
		[request setPredicate:predicate];
		NSError *error = nil;
		NSMutableArray *foundEntities = [[aContext executeFetchRequest:request error:&error] mutableCopy];
		if (error != nil) {
			//NSLog(@"%@",error);
			return createdObjects;
		}
		if ([foundEntities count] == 1) {
			aTrackableEntity = [foundEntities objectAtIndex:0];
		}
		else {
			aTrackableEntity = [NSEntityDescription insertNewObjectForEntityForName:objectType
																		inManagedObjectContext:aContext];
			[aTrackableEntity setValue:uuid forKey:@"UUID"];
			if (![aContext save:&error]) {
				// Handle the error.
				//NSLog(@"ERROR: %@",error);
			}
		}
		[createdObjects addObject:aTrackableEntity];
		NSArray *attributeNames = [anObjectDescription allKeys];
		int numAtts = [attributeNames count];
		for (int attNum = 0; attNum < numAtts; attNum++) {
			NSString *attributeName = [attributeNames objectAtIndex:attNum];
			if ([attributeName isEqual:@"eventType"] || [attributeName isEqual:@"UUID"]) {
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
					//NSLog(@"%@",error);
					continue;
				}
				if ([foundAttributeEntities count] == 1) {
					attributeValue = [foundAttributeEntities objectAtIndex:0];
				}
				else {
					attributeValue = [NSEntityDescription insertNewObjectForEntityForName:attributeName
																	 inManagedObjectContext:aContext];
					[(Trackable*)attributeValue setValue:uuid forKey:@"UUID"];
					if (![aContext save:&error]) {
						// Handle the error.
						//NSLog(@"ERROR: %@",error);
					}
				}
			}
			else if([attributeValue isKindOfClass:[NSArray class]]){
				attributeValue = [NSManagedObject fromDictionary:attributeValue inContext:aContext];
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
	//NSLog(@"found uuid for to one relationship: %@",aPotentialUUIDString);
	return YES;
}

@end
