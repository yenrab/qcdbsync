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

@interface NSManagedObject (toDictionary)
-(NSDictionary *) toDictionary:(NSMutableSet*)traversedObjects;
+(NSArray*) fromDictionary:(NSArray*)dictionaries inContext:(NSManagedObjectContext*)aContext;
+(BOOL) isUUID:(NSString*)aPotentialUUIDString;
@end

