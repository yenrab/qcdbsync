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
    
    NSManagedObjectContext *theContext = [[NSManagedObjectContext alloc] init];
    [theContext setPersistentStoreCoordinator: aCoordinator];
    
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
     * Setup listening for changes in the Core Data managed context
     * use notifications and the notification center to do so.
     * This is similar to triggers in a database making out-bound calls.
     */
    [[NSNotificationCenter defaultCenter]
     addObserver:self
     selector:@selector(dataChanged:)
     name:NSManagedObjectContextDidSaveNotification
     object:theContext];

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
        [NSException raise:@"HTTP Error" format:@"Error %d: %@", [error code], [error  localizedDescription]];
    }
    
    
    
    NSFetchRequest *request = [[NSFetchRequest alloc] init];
	NSEntityDescription *theSyncTrackerDescription = [NSEntityDescription entityForName:@"SyncTracker" inManagedObjectContext:theContext];
	[request setEntity:theSyncTrackerDescription];
    
    
	error = nil;
	NSArray *syncTrackers = [theContext executeFetchRequest:request error:&error];
    if(!syncTrackers || [syncTrackers count] == 0){ 
    
        
        
        NSManagedObjectContext *theContext = [[NSManagedObjectContext alloc] init];
        [theContext setPersistentStoreCoordinator: aCoordinator];
        
        SyncTracker *theTracker = (SyncTracker*)[NSEntityDescription insertNewObjectForEntityForName:@"SyncTracker" 
                                                            inManagedObjectContext:theContext];
        theTracker.lastSync = [NSDate distantPast];
    
    
        if (![theContext save:&error]) {
            // An example of how to handle errors
            NSMutableDictionary *errorDictionary = [NSMutableDictionary dictionaryWithObjectsAndKeys:error.localizedDescription, @"description", error.localizedFailureReason, @"reason", nil];
            NSLog(@"Error: %@",errorDictionary);
        }
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
    
	NSDate *updateDate = [NSDate date];
    //adjust for GMT
    NSTimeZone* currentTimeZone = [NSTimeZone localTimeZone];
    NSTimeZone* utcTimeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
    
    NSInteger currentGMTOffset = [currentTimeZone secondsFromGMTForDate:updateDate];
    NSInteger gmtOffset = [utcTimeZone secondsFromGMTForDate:updateDate];
    NSTimeInterval gmtInterval = gmtOffset - currentGMTOffset;
    
    updateDate = [[[NSDate alloc] initWithTimeInterval:gmtInterval sinceDate:updateDate] autorelease];     
    
    
    
	NSDictionary *info = notification.userInfo;
	NSSet *insertedObjects = [info objectForKey:NSInsertedObjectsKey];
	NSSet *deletedObjects = [info objectForKey:NSDeletedObjectsKey];
	NSSet *updatedObjects = [info objectForKey:NSUpdatedObjectsKey];
    
    
    NSManagedObjectContext *theContext = [[NSManagedObjectContext alloc] init];
    [theContext setPersistentStoreCoordinator:self.theCoordinator];
	
	for (NSManagedObject *aDeletedObject in deletedObjects) {
       
        /*
         *  Create a deleted trackable object for anything deleted
         *  that isn't a deleted trackable object
         */
		if([aDeletedObject isKindOfClass:[Trackable class]]
            && ![aDeletedObject isKindOfClass:[DeletedTrackable class]]){
            
            /*
             * create a DeletedTrackable representing the one deleted from the core data store
             */
            Trackable *aDeletedTrackable = (Trackable*)aDeletedObject;
			DeletedTrackable *trackableToDelete = (DeletedTrackable*)[NSEntityDescription insertNewObjectForEntityForName:@"DeletedTrackable" inManagedObjectContext:theContext];
            [trackableToDelete setValue:aDeletedTrackable.UUID forKey:@"UUID"];
            [trackableToDelete setValue:updateDate forKey:@"updateTime"];
            [trackableToDelete setValue:@"delete" forKey:@"eventType"];
		}
	}

	for (NSManagedObject *anInsertedObject in insertedObjects) {
        NSString *className = [[anInsertedObject entity] name];
        Class insertedType = NSClassFromString(className);
        
		if([insertedType isSubclassOfClass:[Trackable class]]
           && insertedType != [DeletedTrackable class]){
            NSError *grabError = nil;
            anInsertedObject = [theContext existingObjectWithID:[anInsertedObject objectID]error:&grabError];
            Trackable *aTrackable = (Trackable*)anInsertedObject;
            [aTrackable setValue:@"create" forKey:@"eventType"];
            [aTrackable setValue:updateDate forKey:@"updateTime"];
       }
	}
	
	for (NSManagedObject *anUpdatedObject in updatedObjects) {
        
		NSString *className = [[anUpdatedObject entity] name];
        Class updatedType = NSClassFromString(className);
        
		if([updatedType isSubclassOfClass:[Trackable class]]
           && updatedType != [DeletedTrackable class]){
            NSError *grabError = nil;
            anUpdatedObject = [theContext existingObjectWithID:[anUpdatedObject objectID]error:&grabError];
			Trackable *aTrackable = (Trackable*)anUpdatedObject;
			aTrackable.updateTime = [NSDate date];
            if(![aTrackable.eventType isEqual:@"create"]){
                [aTrackable setValue:@"update" forKey:@"eventType"];
                [aTrackable setValue:updateDate forKey:@"updateTime"];
            }
		}
	}

    [theContext mergeChangesFromContextDidSaveNotification:notification];
    //[theContext processPendingChanges];
    NSError *error = nil;
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

     
    [theContext release];
    
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

	NSFetchRequest *request = [[NSFetchRequest alloc] init];
	NSEntityDescription *theSyncTrackerDescription = [NSEntityDescription entityForName:@"SyncTracker" inManagedObjectContext:theContext];
	[request setEntity:theSyncTrackerDescription];
 
    
	NSError *error = nil;
	NSArray *syncTrackers = [theContext executeFetchRequest:request error:&error];
    SyncTracker *theTracker = (SyncTracker*)[syncTrackers objectAtIndex:0];
    NSDate *lastSync = [theTracker lastSync];
    NSLog(@"last sync: %@",[NSDate distantPast]);
    if(lastSync == nil){
        lastSync = [NSDate distantPast];
    }
    NSLog(@"tracker: %@",theTracker);
    /*
     *  Add in a predicate to filter so that only Trackables with and update time after the last sync time are
     *  returned.
     */
    NSEntityDescription *theTrackableDescription = [NSEntityDescription entityForName:@"Trackable" inManagedObjectContext:theContext];
	[request setEntity:theTrackableDescription];
    /*
     *  Get the list of all of the trackables to pass them to into the coverter.
     */
    //adjust for GMT
    NSLog(@"last sync before change: %@",lastSync);
    NSTimeZone* currentTimeZone = [NSTimeZone localTimeZone];
    NSTimeZone* utcTimeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
    
    NSInteger currentGMTOffset = [currentTimeZone secondsFromGMTForDate:lastSync];
    NSInteger gmtOffset = [utcTimeZone secondsFromGMTForDate:lastSync];
    NSTimeInterval gmtInterval = gmtOffset - currentGMTOffset;
    
    lastSync = [[[NSDate alloc] initWithTimeInterval:gmtInterval sinceDate:lastSync] autorelease];
    NSLog(@"last sync after change: %@",lastSync);

    NSLog(@"is greater than? %@ compared to now: %@",lastSync, [NSDate date]);
    NSPredicate *onlyNew = [NSPredicate predicateWithFormat:@"updateTime > %@",lastSync];
    NSLog(@"predicate: %@",onlyNew);
    [request setPredicate:onlyNew];
    error = nil;
    NSArray *trackables = [theContext executeFetchRequest:request error:&error];
    //tmp testing code
    for(int i = 0; i < [trackables count]; i++){
        Trackable *aTrackable = [trackables objectAtIndex:i];
        NSLog(@"trackable %@",aTrackable);
        NSDate *updated = aTrackable.updateTime;
        NSLog(@"%@",updated);
    }
    
    [request release];
    /*
	 * Since the JSON tool isn't built to work with Managed Objects they need to be converted to standard objects
	 *
     * setup the dictionary to send to JSON later
     */
    NSMutableDictionary *dataToSend = [NSMutableDictionary dictionaryWithCapacity:2];
    [dataToSend setObject:lastSync forKey:@"sync_time"];
    NSMutableArray *syncData = [NSMutableArray arrayWithCapacity:0];
    [dataToSend setObject:syncData forKey:@"sync_data"];
    
    int numTrackables = [trackables count];
    for(int i = 0; i < numTrackables; i++){
        Trackable *aTrackable = [trackables objectAtIndex:i];
        NSDictionary *convertedTrackable = [aTrackable toDictionary];
        NSDictionary *description = nil;
        
        NSString *className = [[aTrackable entity] name];
        Class insertedType = NSClassFromString(className);
        
		if([insertedType isSubclassOfClass:[Trackable class]]
           && insertedType != [DeletedTrackable class]){
            //NSString *trackableClassName = NSStringFromClass([aTrackable class]);
             NSString *trackableClassName = [[aTrackable entity] name];
            description = [NSDictionary dictionaryWithObject:convertedTrackable forKey:[NSString stringWithFormat:@"sync_type_%@",trackableClassName]];
        }
            
        else /*if (insertedType == [DeletedTrackable class]) */{
            description = [NSDictionary dictionaryWithObject:convertedTrackable forKey:@"delete"];
        }
        [syncData addObject:description];
    }

	/*
	 * JSON up the data to send
	 */
		
	SBJsonWriter *aWriter = [[SBJsonWriter alloc] init];
	NSString *jsonString = [aWriter stringWithObject:dataToSend];
	[aWriter release];
	NSLog(@"sendString: %@",jsonString);
    
	
	NSMutableURLRequest* postDataRequest = [[NSMutableURLRequest alloc] initWithURL:self.url];
    [postDataRequest setHTTPMethod:@"POST"];
	NSArray * availableCookies = [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookiesForURL:self.url];
    NSLog(@"cookies: %@",availableCookies);
    NSString* content = [NSString stringWithFormat:@"cmd=sync&data=%@", jsonString];
    
    [postDataRequest setHTTPBody:[content dataUsingEncoding:NSUTF8StringEncoding]];
    
	/*
	 * send the request
	 */
    error = nil;
    NSURLResponse  *response = nil;
    NSData *jsonData = [NSURLConnection sendSynchronousRequest: postDataRequest returningResponse: &response error: &error];
    
    if (response == nil && error != nil) {
        [NSException raise:@"HTTP Error" format:@"Error number: %d", [error code] ];
    }
    
    NSString *responseJsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    NSLog(@"response string: %@",responseJsonString);
    
    /*
     *  handle the JSON received
     */
    
    /*
     *  delete the trackables representing deletions since sync was successful
     */
    NSFetchRequest *existingSyncEntriesRequest = [[NSFetchRequest alloc] init];
	NSEntityDescription *theDescription = [NSEntityDescription entityForName:@"DeletedTrackable" inManagedObjectContext:theContext];
	[existingSyncEntriesRequest setEntity:theDescription];
	error = nil;
	NSArray *oldDeletedTrackables = [theContext executeFetchRequest:existingSyncEntriesRequest error:&error];
    if ([oldDeletedTrackables count] > 0) {
     
        for(int i = 0; i < [oldDeletedTrackables count]; i++){
            DeletedTrackable *aTrackable = (DeletedTrackable*)[oldDeletedTrackables objectAtIndex:i];
            [theContext deleteObject:aTrackable];
        }
	}
	
	/*
     *  parse the JSON for insertion
     */
	SBJsonParser* aParser = [[SBJsonParser alloc] init];
	NSDictionary* syncInformation = [aParser objectWithString:responseJsonString];
	[aParser release];
    NSLog(@"sync stuff: %@",syncInformation);
    NSString* syncTimeString = [syncInformation objectForKey:@"sync_time"];
    NSDateFormatter* aFormatter = [[NSDateFormatter alloc] init];
    [aFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    NSTimeZone *gmt = [NSTimeZone timeZoneWithAbbreviation:@"GMT"];
    [aFormatter setTimeZone:gmt];
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
    [NSManagedObject updateStoreWithDictionaries:resultDataArray inContext:theContext];
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
