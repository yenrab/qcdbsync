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

#import "SynchronizedDB.h"
#import "DeletedTrackable.h"
#import "SyncTracker.h"
#import "Trackable.h"
#import "EnterpriseSyncDelegate.h"
#import "JSON.h"
#import "NSManagedObject+Dictionary.h"


@implementation SynchronizedDB 

@synthesize changes;
@synthesize resultData;
@synthesize url;
@synthesize delegate;
@synthesize theCondition;
@synthesize theCoordinator;

/*
 * An initialization method for SynchronizedDB objects.
 */
- (SynchronizedDB*)init:(NSPersistentStoreCoordinator*)aCoordinator withService:(NSString*)aURLString userName:(NSString*)aUserName password:(NSString*)aPassword{

    self.theCoordinator = aCoordinator;
    self.theCondition = [[NSCondition alloc] init];
	/*
	 *  turn on automated cookie handling
	 */
	NSHTTPCookieStorage *cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    [cookieStorage setCookieAcceptPolicy:NSHTTPCookieAcceptPolicyAlways];
	
	/*
	 *  create the lock used to control syncing and updating
	 */
	//self.synchronizationLock = [NSLock new];
	
	self.changes = [NSMutableDictionary dictionaryWithCapacity:0];
	self.url = [NSURL URLWithString:aURLString];
	self.resultData = [NSMutableData dataWithLength:0];
	/*
	 *  By making a request now we can check for connectivity
	 */
    /*
	 * login if not logged in
	 */
    NSMutableURLRequest* loginRequest = [[NSMutableURLRequest alloc] initWithURL:self.url];
    [loginRequest setHTTPMethod:@"POST"];
    
    NSString* content = [NSString stringWithFormat:@"cmd=login&uname=%@&pword=%@", aUserName, aPassword];
    
    [loginRequest setHTTPBody:[content dataUsingEncoding:NSUTF8StringEncoding]];
    NSError *error = nil;
    NSURLResponse  *response = nil;
    [NSURLConnection sendSynchronousRequest: loginRequest returningResponse: &response error: &error];
    
    if (response == nil && error != nil) {
        NSLog(@"Login Failure: %@",error);
        return nil;
    }
	return self;
}


/*
 * A SynchronizedDB method used to detect insertions and deletions of as well as changes to 
 * objects managed by Core Data.
 */
- (void)dataChanged:(NSNotification *)notification{
	
    /*
	 *  if currently doing a sync return early and don't create sync entries.
	 */
    
    [self.theCondition lock];
    
	NSDate *updateDate = [NSDate date];
	NSDictionary *info = notification.userInfo;
	NSSet *insertedObjects = [info objectForKey:NSInsertedObjectsKey];
	NSSet *deletedObjects = [info objectForKey:NSDeletedObjectsKey];
	NSSet *updatedObjects = [info objectForKey:NSUpdatedObjectsKey];
    
    
    NSManagedObjectContext *theContext = [[NSManagedObjectContext alloc] init];
    [theContext setPersistentStoreCoordinator: self.theCoordinator];
    
    /*
     * Setup listening for changes in the Core Data managed context
     * use notifications and the notification center to do so.
     * This is similar to triggers in a database making out-bound calls.
     */
    [[NSNotificationCenter defaultCenter]
     addObserver:self
     selector:@selector(dataChanged:)
     name:NSManagedObjectContextDidSaveNotification
     object:theContext];
	
	for (NSManagedObject *aDeletedObject in deletedObjects) {
        /*
         *  Create a deleted trackable object for anything deleted
         *  that isn't a deleted trackable object
         */
		if([aDeletedObject isKindOfClass:[Trackable class]]
            && ![aDeletedObject isKindOfClass:[DeletedTrackable class]]){
			Trackable *deletedTrackable = (Trackable*)aDeletedObject;
			//NSLog(@"deleted object: %@",deletedTrackable);/* 
            /*
             * create a DeletedTrackable
             */
			DeletedTrackable *aDeletedTrackable = (DeletedTrackable*)[NSEntityDescription insertNewObjectForEntityForName:@"DeletedTrackable" inManagedObjectContext:theContext];
            aDeletedTrackable.UUID = deletedTrackable.UUID;
            aDeletedTrackable.updateTime = updateDate;
		}
	}

	for (NSManagedObject *anInsertedObject in insertedObjects) {
		if([anInsertedObject isKindOfClass:[Trackable class]]
           && ![anInsertedObject isKindOfClass:[DeletedTrackable class]]){
			Trackable *aTrackable = (Trackable*)anInsertedObject;
			aTrackable.updateTime = updateDate;
            aTrackable.eventType = @"create";
		}
		
	}
	
	for (NSManagedObject *anUpdatedObject in updatedObjects) {
		if([anUpdatedObject isKindOfClass:[Trackable class]]
           && ![anUpdatedObject isKindOfClass:[DeletedTrackable class]]){
			Trackable *aTrackable = (Trackable*)anUpdatedObject;
			aTrackable.updateTime = [NSDate date];
            if(![aTrackable.eventType isEqual:@"create"]){
                aTrackable.updateTime = updateDate;
                aTrackable.eventType = @"update";
            }
		}
	}
    [self.theCondition unlock];
}

/*
 * A user methods that is called by the application to trigger syncing 
 * of the local and remote databases.
 */
-(void)sync{
	/*
	 * this lock will be released in the callback methods
	 * for success or failure
	 */
	[self.theCondition lock];

    
    
    NSManagedObjectContext *theContext = [[NSManagedObjectContext alloc] init];
    [theContext setPersistentStoreCoordinator: self.theCoordinator];
    
    /*
     * Setup listening for changes in the Core Data managed context
     * use notifications and the notification center to do so.
     * This is similar to triggers in a database making out-bound calls.
     */
    [[NSNotificationCenter defaultCenter]
     addObserver:self
     selector:@selector(dataChanged:)
     name:NSManagedObjectContextDidSaveNotification
     object:theContext];
    

	NSFetchRequest *request = [[NSFetchRequest alloc] init];
	NSEntityDescription *theSyncTrackerDescription = [NSEntityDescription entityForName:@"SyncTracker" inManagedObjectContext:theContext];
	[request setEntity:theSyncTrackerDescription];
 
    
	NSError *error = nil;
	NSArray *syncTrackers = [theContext executeFetchRequest:request error:&error];
    SyncTracker *theTracker = (SyncTracker*)[syncTrackers objectAtIndex:0];
    NSDate *lastSync = [theTracker lastSync];
    /*
     *  Add in a predicate to filter so that only Trackables with and update time after the last sync time are
     *  returned.
     */
    NSEntityDescription *theTrackableDescription = [NSEntityDescription entityForName:@"Trackable" inManagedObjectContext:theContext];
	[request setEntity:theTrackableDescription];
    /*
     *  Get the list of all of the trackables to pass them to into the coverter.
     */
    NSPredicate *onlyNew = [NSPredicate predicateWithFormat:@"updateTime > %@",lastSync];
    [request setPredicate:onlyNew];
    error = nil;
    NSArray *trackables = [theContext executeFetchRequest:request error:&error];
    
    [request release];
    /*
	 * Since the JSON tool isn't built to work with Managed Objects they need to be converted to standard objects
	 *
     * setup the dictionary to send to JSON later
     */
    NSMutableDictionary *dataToSend = [NSMutableDictionary dictionaryWithCapacity:2];
    [dataToSend setObject:lastSync forKey:@"sync_time"];
    NSMutableArray *syncData = [NSMutableArray arrayWithCapacity:0];
    [dataToSend setObject:lastSync forKey:@"sync_data"];
    
	NSMutableSet *traversedTrackables = [NSMutableSet setWithCapacity:1];
    
    int numTrackables = [trackables count];
    for(int i = 0; i < numTrackables; i++){
        Trackable *aTrackable = [trackables objectAtIndex:i];
        if (![traversedTrackables containsObject:aTrackable]) {
            NSDictionary *convertedTrackable = [aTrackable toDictionary:traversedTrackables];
            NSString *trackableClassName = NSStringFromClass([aTrackable class]);
            NSDictionary *description = [NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"%@_%@",aTrackable.eventType,trackableClassName] forKey:convertedTrackable];
            [syncData addObject:description];
        }
    }

	/*
	 * JSON up the data to send
	 */
		
	SBJsonWriter *aWriter = [[SBJsonWriter alloc] init];
	NSString *jsonString = [aWriter stringWithObject:dataToSend];
	[aWriter release];
	NSLog(@"sendString: %@",jsonString);
	
	NSMutableURLRequest* postDataRequest = [[NSMutableURLRequest alloc] initWithURL:self.url];
    
    NSString* content = [NSString stringWithFormat:@"cmd=sync&data=%@", jsonString];
    
    [postDataRequest setHTTPBody:[content dataUsingEncoding:NSUTF8StringEncoding]];
    
	NSArray * availableCookies = [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookiesForURL:self.url];
    NSDictionary * headers = [NSHTTPCookie requestHeaderFieldsWithCookies:availableCookies];
	//NSLog(@"headers: %@",headers);
    [postDataRequest setAllHTTPHeaderFields:headers];
    //[NSURLConnection connectionWithRequest:postRequest delegate:self];
	/*
	 * send the request
	 */
    error = nil;
    NSURLResponse  *response = nil;
    NSData *jsonData = [NSURLConnection sendSynchronousRequest: postDataRequest returningResponse: &response error: &error];
    
    if (response == nil && error != nil) {
        NSLog(@"Login Failure: %@",error);
        return;
    }
    
    NSString *responseJsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    
    /*
     *  handle the JSON received
     */
    
    /*
     *  delete the trackables representing deletions since sync was successful
     */
    NSFetchRequest *existingSyncEntriesRequest = [[NSFetchRequest alloc] init];
	NSEntityDescription *theDescription = [NSEntityDescription entityForName:@"DeletedTrackable" inManagedObjectContext:theContext];
	[request setEntity:theDescription];
	error = nil;
	NSArray *oldDeletedTrackables = [theContext executeFetchRequest:existingSyncEntriesRequest error:&error];
	for(int i = 0; i < [oldDeletedTrackables count]; i++){
		DeletedTrackable *aTrackable = (DeletedTrackable*)[oldDeletedTrackables objectAtIndex:i];
		[theContext deleteObject:aTrackable];
	}
	if (![theContext save:&error]) {
		// Handle the error.
		//NSLog(@"error: %@",error);
		NSArray* detailedErrors = [[error userInfo] objectForKey:NSDetailedErrorsKey];
		if(detailedErrors != nil && [detailedErrors count] > 0) {
			for(NSError* detailedError in detailedErrors) {
				NSLog(@"  DetailedError: %@", [detailedError userInfo]);
			}
		}
		else {
			NSLog(@"  %@", [error userInfo]);
		}
	}
	
	
	/*
     *  parse the JSON for insertion
     */
	SBJsonParser* aParser = [[SBJsonParser alloc] init];
	NSDictionary* syncInformation = [aParser objectWithString:responseJsonString];
	[aParser release];
    NSString* syncTimeString = [syncInformation objectForKey:@"sync_time"];
    NSDateFormatter* aFormatter = [[NSDateFormatter alloc] init];
    [aFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    NSDate* syncTime = [aFormatter dateFromString:syncTimeString];
    [aFormatter release];
    
    /*
     *  set the last sync time of the SyncData object to be the time sent from the server.
     */
    theTracker.lastSync = syncTime;
    /*
     * retreive the array of objects to sync
     */
	NSArray *resultDataArray = [syncInformation objectForKey:@"sync_data"];
    int numData = [resultDataArray count];
    for(int i = 0; i < numData; i++){
        NSDictionary *aData = [resultDataArray objectAtIndex:i];
        NSDictionary *dataDescription = [aData objectForKey:@"sync_info"];
        NSString *key = [aData objectForKey:@"key"];
        NSArray *keyValues = [key componentsSeparatedByString:@"_"];
        NSString *operationType = [keyValues objectAtIndex:0];
        NSString *objectType = [keyValues objectAtIndex:1];
        
        NSString *uuid = [dataDescription objectForKey:@"UUID"];
        if (uuid == nil) {  
            NSLog(@"Warning: unable to process entry %@ since it has no UUID value. Ignoring this entry.",dataDescription);
            continue;
        }
        
        if ([operationType isEqualToString:@"create"]) {
            Trackable *theNewTrackable = [NSEntityDescription insertNewObjectForEntityForName:objectType inManagedObjectContext:theContext];
            [theNewTrackable setValuesForKeysWithDictionary:dataDescription];
        }
        else{
            //must be an update or delete.
            NSEntityDescription *entityDesc = [NSEntityDescription entityForName:objectType inManagedObjectContext:theContext];
            
            NSFetchRequest *updateRequest = [[NSFetchRequest alloc] init];
            
            [updateRequest setEntity:entityDesc];
            
            NSPredicate *predicate = [NSPredicate predicateWithFormat:@"(UUID = %@)", uuid];
            
            [updateRequest setPredicate:predicate];
            
            NSError *error = nil;
            
            NSArray *objects = [theContext executeFetchRequest:updateRequest error:&error];
            if ([objects count] != 1) {
                NSLog(@"Warning: Unable to locate a trackable element with the id: %@.  Ignoring this update.",uuid);
                continue;
            }
            Trackable *theFoundTrackable = [objects objectAtIndex:0];

            if ([operationType isEqualToString:@"update"]) {
                
                [theFoundTrackable setValuesForKeysWithDictionary:dataDescription];
            }
            else if ([operationType isEqualToString:@"delete"]) {
                
                [theContext deleteObject:theFoundTrackable];
                
            }
            else{
                NSLog(@"Warning: bad sync command %@ received.  Ignoring the entry: %@",operationType,aData);
            }
            [updateRequest release];
        }     
    }
	[self.delegate onSuccess];
	[self.theCondition unlock];

}
+(NSString*)UUIDString {
    CFUUIDRef theUUID = CFUUIDCreate(NULL);
    CFStringRef string = CFUUIDCreateString(NULL, theUUID);
    CFRelease(theUUID);
    return [NSMakeCollectable(string) autorelease];
}


@end
