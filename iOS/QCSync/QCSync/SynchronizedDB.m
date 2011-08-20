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
#import "SyncTracker.h"
#import "Trackable.h"
#import "EnterpriseSyncDelegate.h"
#import "JSON.h"
#import "NSManagedObject+Dictionary.h"
#import "NSManagedObjectContext_Sync.h"
#import <objc/runtime.h> 
#import <objc/message.h>







@interface SynchronizedDB()

- (NSManagedObject*)buildObjectFromDictionary:(NSDictionary*)anObjectDescriptionDictionary inContext:(NSManagedObjectContext*)theContext error:(NSError **)error;

@end
    

@implementation SynchronizedDB 

@synthesize changes;
@synthesize resultData;
@synthesize url;
@synthesize delegate;
@synthesize theCondition;
@synthesize theCoordinator;
@synthesize loggedIn;
@synthesize usesJSONService;



/*
 * An initialization method for SynchronizedDB objects.
 */
- (SynchronizedDB*)init:(id<EnterpriseSyncDelegate>)aCoreDataContainer withService:(NSString*)aURLString userName:(NSString*)aUserName password:(NSString*)aPassword isJSONService:(BOOL)isJSONServiceFlag{
    
    /*
     * Initialize the service.
     */
    [self initWithDelegate:aCoreDataContainer toService:aURLString isJSONService:isJSONServiceFlag];
	/*
	 *  By making a request now we can check for connectivity
	 */
    /*
	 * login if not logged in
	 */
    
    self->loggedIn = [self attemptRemoteLogin:aUserName withPassword:aPassword];
	return self;
}


- (SynchronizedDB*)initWithDelegate:(id<EnterpriseSyncDelegate>)aCoreDataContainer toService:(NSString*)aURLString isJSONService:(BOOL)isJSONServiceFlag{
    self.usesJSONService = isJSONServiceFlag;
    self.delegate = aCoreDataContainer;
    /*
     * Setup listening for changes in the Core Data managed context
     * use notifications and the notification center to do so.
     * This is similar to, but not the same as, triggers in a database.
     */
    [[NSNotificationCenter defaultCenter]
     addObserver:self
     selector:@selector(dataChanged:)
     name:NSManagedObjectContextDidSaveNotification
     object:aCoreDataContainer.managedObjectContext];
    /*
     *  set up the swizzling for sync
     */
    //delete
    SEL originalSelector = @selector(deleteObject:);
    SEL overrideSelector = @selector(actualDeleteObject:);
    Method originalMethod = class_getInstanceMethod([NSManagedObjectContext class], originalSelector);
    Method overrideMethod = class_getInstanceMethod([NSManagedObjectContext class], overrideSelector);
    if (class_addMethod([NSManagedObjectContext class], originalSelector, method_getImplementation(overrideMethod), method_getTypeEncoding(overrideMethod))) {
        class_replaceMethod([NSManagedObjectContext class], overrideSelector, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod));
    } else {
        method_exchangeImplementations(originalMethod, overrideMethod);
    }
    
    //executeRequest
    originalSelector = @selector(executeFetchRequest:error:);
    overrideSelector = @selector(actualExecuteFetchRequest:error:);
    originalMethod = class_getInstanceMethod([NSManagedObjectContext class], originalSelector);
    overrideMethod = class_getInstanceMethod([NSManagedObjectContext class], overrideSelector);
    if (class_addMethod([NSManagedObjectContext class], originalSelector, method_getImplementation(overrideMethod), method_getTypeEncoding(overrideMethod))) {
        class_replaceMethod([NSManagedObjectContext class], overrideSelector, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod));
    } else {
        method_exchangeImplementations(originalMethod, overrideMethod);
    }
    
    self.theCoordinator = [aCoreDataContainer persistentStoreCoordinator];
    self.theCondition = [[NSCondition alloc] init];
    
    
    
    /*
     * Setup listening for changes in the Core Data managed context
     * use notifications and the notification center to do so.
     * This is similar to triggers in a database making out-bound calls.
     */
    [[NSNotificationCenter defaultCenter]
     addObserver:self
     selector:@selector(dataChanged:)
     name:NSManagedObjectContextDidSaveNotification
     object:self.delegate.managedObjectContext];
    
    
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
    //no login done with this type of connection.
    self->loggedIn = YES;
    return self;
}

- (void)mergeChangesFromContextDidSaveNotification:(NSNotification *)notification{
    
}



- (BOOL) attemptRemoteLogin:(NSString*)userName withPassword:(NSString*)password{
    @try {
        NSMutableURLRequest* loginRequest = [[NSMutableURLRequest alloc] initWithURL:self.url];
        [loginRequest setHTTPMethod:@"POST"];
        NSString *content = nil;
        if (self.usesJSONService) {
            [loginRequest setValue:@"application/json; charset=utf-8" forHTTPHeaderField:@"content-type"];
            content = [NSString stringWithFormat:@"{\"cmd\":\"login\",\"uname\":\"%@\",\"pword\":\"%@\"}", userName, password];
        }
        else{
            content = [NSString stringWithFormat:@"cmd=login&uname=%@&pword=%@", userName, password];
        }
        NSLog(@"request content string: %@",content);
        [loginRequest setHTTPBody:[content dataUsingEncoding:NSUTF8StringEncoding]];
        NSError *error = nil;
        NSURLResponse  *response = nil;
        [NSURLConnection sendSynchronousRequest: loginRequest returningResponse: &response error: &error];
        return YES;
    }
    @catch (NSException *exception) {
        self->loggedIn = NO;
        return NO;
    }
}


/*
 * A SynchronizedDB method used to detect insertions and deletions of as well as changes to 
 * objects managed by Core Data.  This executes on the same thread that created the 
 * SynchronizedDB.  Should be the main thread.
 */
- (void)dataChanged:(NSNotification *)notification{

    
    //[self.theCondition lock];
    
	NSDate *updateTimeStamp = [NSDate date];

	NSDictionary *info = notification.userInfo;
	NSSet *insertedObjects = [info objectForKey:NSInsertedObjectsKey];
	NSSet *deletedObjects = [info objectForKey:NSDeletedObjectsKey];
	NSSet *updatedObjects = [info objectForKey:NSUpdatedObjectsKey];
    
	
    NSManagedObjectContext *aContext = [[NSManagedObjectContext alloc] init];
    [aContext setPersistentStoreCoordinator: self.theCoordinator];
    
    
    NSEntityDescription *aTrackableDescription = [NSEntityDescription entityForName:@"Trackable" inManagedObjectContext:aContext];
    //NSEntityDescription *aDeletedTrackableDescription = [NSEntityDescription entityForName:@"DeletedTrackable" inManagedObjectContext:aContext];
    NSLog(@"deleted: %@     inserted: %@    modified: %@",deletedObjects,insertedObjects,updatedObjects);
    BOOL shouldSave = NO;

	for (NSManagedObject *anInsertedObject in insertedObjects) {
		if([[anInsertedObject entity] isKindOfEntity:aTrackableDescription]){
            Trackable *asTrackable = (Trackable*)anInsertedObject;
            if (asTrackable.isRemoteData) {
                asTrackable.isRemoteData = [NSNumber numberWithBool: NO];
                continue;
            }
			asTrackable.updateTime = updateTimeStamp;
            asTrackable.eventType = @"create";
            shouldSave = YES;
		}
		
	}
	
	for (NSManagedObject *anUpdatedObject in updatedObjects) {
		if([[anUpdatedObject entity] isKindOfEntity:aTrackableDescription]){
            Trackable *asTrackable = (Trackable*)anUpdatedObject;
            NSLog(@"asTrackable %@",[asTrackable entity]);
            if (asTrackable.isRemoteData) {
                asTrackable.isRemoteData = [NSNumber numberWithBool: NO];
                continue;
            }
            asTrackable.updateTime = updateTimeStamp;
            asTrackable.eventType = @"update";
            shouldSave = YES;
		}
	}
    if(shouldSave){
        
        /*
         * Turn listening off to stop infinite loop
         */
        NSNotificationCenter *theCenter = [NSNotificationCenter defaultCenter];
        [theCenter removeObserver:self];
         
        [self.delegate saveContext];
        /*
         * Turn listening back on.
         */
        [[NSNotificationCenter defaultCenter]
         addObserver:self
         selector:@selector(dataChanged:)
         name:NSManagedObjectContextDidSaveNotification
         object:self.delegate.managedObjectContext];
        
        //[((NSObject*)self.delegate) performSelectorOnMainThread:@selector(saveContext) withObject:error waitUntilDone:YES];
    }
    //[self.theCondition unlock];
}

/*
 * A user methods that is called by the application to trigger syncing 
 * of the local and remote databases.
 */
-(BOOL)sync{
	/*
	 * this lock will be released in the callback methods
	 * for success or failure
	 */
	//[self.theCondition lock];
    //NSLog(@"syncing");

    
    
    NSManagedObjectContext *theContext = [[NSManagedObjectContext alloc] init];
    [theContext setPersistentStoreCoordinator: self.theCoordinator];
    //NSLog(@"context %@",theContext);

	NSFetchRequest *request = [[NSFetchRequest alloc] init];
	NSEntityDescription *theSyncTrackerDescription = [NSEntityDescription entityForName:@"SyncTracker" inManagedObjectContext:theContext];
	[request setEntity:theSyncTrackerDescription];
 
    
	NSError *error = nil;
	NSArray *syncTrackers = [theContext executeFetchRequest:request error:&error];
    SyncTracker *theTracker = nil;
    if ([syncTrackers count] < 1) {
        theTracker = (SyncTracker*)[NSEntityDescription insertNewObjectForEntityForName:@"SyncTracker" inManagedObjectContext:theContext];
        theTracker.lastSync = [NSDate distantPast];
        NSLog(@"%@",error);
    }
    
    else{
        theTracker = (SyncTracker*)[syncTrackers objectAtIndex:0];
    }
    //[self.theCondition lock];
   NSLog(@"last sync time: %@",[[[theContext executeFetchRequest:request error:&error] objectAtIndex:0] lastSync]);
    NSDate *lastSync = theTracker.lastSync;
    //in case of some sort of error set last sync so no exception is thrown.
    if (!lastSync) {
        lastSync = [NSDate distantPast];
    }
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
    //NSLog(@"predicate: %@",onlyNew);
    [request setPredicate:onlyNew];
    NSDate *executionTimeStamp = [NSDate date];//this is used later for doing the deletions.
    error = nil;
    NSArray *trackables = [theContext actualExecuteFetchRequest:request error:&error];
    /*for (int i = 0; i < [trackables count]; i++) {
        NSLog(@"%@  %@",lastSync, [[trackables objectAtIndex:i] updateTime]);
    }*/
    //NSLog(@"trackables: %@",trackables);
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
    NSLog(@"dataToSend: %@",dataToSend);
    
	NSMutableSet *traversedTrackables = [NSMutableSet setWithCapacity:1];
    
    int numTrackables = [trackables count];
    for(int i = 0; i < numTrackables; i++){
        Trackable *aTrackable = [trackables objectAtIndex:i];
        NSLog(@"last sync: %@  update time: %@",lastSync,aTrackable.updateTime);
        if (![traversedTrackables containsObject:aTrackable]) {
            //NSLog(@"converting: %@",aTrackable);
            NSDictionary *convertedTrackable = nil;
            if (aTrackable.flaggedAsDeleted) {
                 NSString *syncType = [NSString stringWithFormat:@"sync_type_%@",[[aTrackable entity] name]];
                NSDictionary *dataDict = [NSDictionary dictionaryWithObjectsAndKeys:@"delete",@"eventType",aTrackable.updateTime,@"updateTime",aTrackable.UUID,@"UUID", nil];
                convertedTrackable = [NSDictionary dictionaryWithObjectsAndKeys:dataDict,syncType, nil];
            }
            else{
                convertedTrackable = [aTrackable toDictionary:traversedTrackables inContext:theContext];
            }
            NSLog(@"converted: %@",convertedTrackable);
            [syncData addObject:convertedTrackable];
        }
    }
    //NSLog(@"data to send: %@",dataToSend);
	/*
	 * JSON up the data to send
	 */
		
	QC_SBJsonWriter *aWriter = [[QC_SBJsonWriter alloc] init];
	NSString *jsonString = [aWriter stringWithObject:dataToSend];
	[aWriter release];
	NSLog(@"sendString: %@",jsonString);
	BOOL success = YES;
    
    NSUndoManager *undoManager = [[NSUndoManager alloc] init];
    [theContext setUndoManager:undoManager];
    [undoManager beginUndoGrouping];
    @try {
        
   
        NSMutableURLRequest* postDataRequest = [[NSMutableURLRequest alloc] initWithURL:self.url];
        [postDataRequest setHTTPMethod:@"POST"];
        NSString* content = nil;
        if (self.usesJSONService) {
            [postDataRequest setValue:@"application/json; charset=utf-8" forHTTPHeaderField:@"content-type"];
            content = [NSString stringWithFormat:@"{\"cmd\":\"sync\",\"data\":%@}", jsonString];
        }
        else{
            content = [NSString stringWithFormat:@"cmd=sync&data=%@", jsonString];
        }
        NSLog(@"request content string: %@",content);
        [postDataRequest setHTTPBody:[content dataUsingEncoding:NSUTF8StringEncoding]];
        
        /*
         * send the request
         */
        error = nil;
        NSURLResponse  *response = nil;
        NSData *jsonData = [NSURLConnection sendSynchronousRequest: postDataRequest returningResponse: &response error: &error];
        
        if(error){
            
            [((NSObject*)self.delegate) performSelectorOnMainThread:@selector(onFailure:) withObject:error waitUntilDone:NO];
            
            success = NO;
        }
        if(success){
            NSString *responseJsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
            
            NSMutableString *modifiedJsonString = [NSMutableString stringWithString:responseJsonString];
            [modifiedJsonString replaceOccurrencesOfString:@"\\" withString:@"" 
                                             options:NSCaseInsensitiveSearch 
                                               range:NSMakeRange(0, [modifiedJsonString length])];
            
                                  
            //NSLog(@"response:'%@'   error: %@",responseJsonString,error);

            
            
            
            /*
             *  parse the JSON for insertion
             */
            NSLog(@"response string:'%@'",responseJsonString);
            QC_SBJsonParser* aParser = [[QC_SBJsonParser alloc] init];
            NSDictionary* syncInformation = [aParser objectWithString:responseJsonString];
            NSLog(@"response object:'%@'",syncInformation);
            [aParser release];
            NSString* syncTimeString = [syncInformation objectForKey:@"sync_time"];
            NSDateFormatter* aFormatter = [[NSDateFormatter alloc] init];
            [aFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
            
            NSTimeZone* utcTimeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
            [aFormatter setTimeZone:utcTimeZone];
            NSDate* syncTimeFromServer = [aFormatter dateFromString:syncTimeString];
            [aFormatter release];
            
            /*
             *  set the last sync time of the SyncData object to be the time sent from the server.
             */
            
            theTracker.lastSync = syncTimeFromServer;
            
            /*
             * retreive the array of objects to sync
             */
            NSArray *resultDataTable = [syncInformation objectForKey:@"sync_data"];
            NSLog(@"result data only: %@",resultDataTable);
            int numData = [resultDataTable count];
            NSEntityDescription *trackableDescription = [NSEntityDescription entityForName:@"Trackable" inManagedObjectContext:theContext];
            for(int i = 0; i < numData; i++){
                /*
                 *  Need to parse the data correctly and insert them into the store.
                 */
                //NSArray *aRow = [resultDataTable objectAtIndex:i];
                //if there is no data in the row move to the next row
                //if ([aRow count] == 0) {
                //    continue;
                //}
                //NSDictionary *aData = [aRow objectAtIndex:0];
                NSDictionary *aData = [resultDataTable objectAtIndex:i];
                NSLog(@"\n\n\n\nbeginning of loopData %i from server: %@",i,aData);
                //bad data sent from server
                if ([aData count] > 1) {
                    
                    // Make underlying error.
                    NSError *underlyingError = [[[NSError alloc] initWithDomain:NSPOSIXErrorDomain
                                                                           code:errno userInfo:nil] autorelease];
                    // Make and return custom domain error.
                    NSArray *objArray = [NSArray arrayWithObjects:@"To many keys in data returned.", underlyingError, @"sync:", nil];
                    NSArray *keyArray = [NSArray arrayWithObjects:NSLocalizedDescriptionKey,
                                         NSUnderlyingErrorKey, NSFilePathErrorKey, nil];
                    NSDictionary *eDict = [NSDictionary dictionaryWithObjects:objArray
                                                                      forKeys:keyArray];
                    
                    NSError *anError = [[[NSError alloc] initWithDomain:@"org.quickconnectfamily.qcsync"
                                                                   code:2 userInfo:eDict] autorelease];
                    
                    [self.delegate onFailure:anError];
                    success = NO;
                    break;
                }
                NSArray *values = [aData allValues];
                NSDictionary *dataValue = [values objectAtIndex:0];
                if([[dataValue objectForKey:@"eventType"] isEqualToString:@"delete"]){
                    NSString *aUUID = [dataValue objectForKey:@"UUID"];
                    if (!aUUID) {
                        // Make underlying error.
                        NSError *underlyingError = [[[NSError alloc] initWithDomain:NSPOSIXErrorDomain
                                                                               code:errno userInfo:nil] autorelease];
                        // Make and return custom domain error.
                        NSArray *objArray = [NSArray arrayWithObjects:@"Missing UUID in delete message.", underlyingError, @"sync:", nil];
                        NSArray *keyArray = [NSArray arrayWithObjects:NSLocalizedDescriptionKey,
                                             NSUnderlyingErrorKey, NSFilePathErrorKey, nil];
                        NSDictionary *eDict = [NSDictionary dictionaryWithObjects:objArray
                                                                          forKeys:keyArray];
                        
                        NSError *anError = [[[NSError alloc] initWithDomain:@"org.quickconnectfamily.qcsync"
                                                                       code:2 userInfo:eDict] autorelease];
                        
                        [self.delegate onFailure:anError];
                        success = NO;
                        break;
                    }
                    
                    NSFetchRequest *updateToDeleteRequest = [[NSFetchRequest alloc] init];
                    [updateToDeleteRequest setEntity:trackableDescription];
                    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"UUID == [c]%@", aUUID];
                    [updateToDeleteRequest setPredicate:predicate];
                    NSError *aFetchError = nil;
                    NSMutableArray *foundEntities = [[theContext actualExecuteFetchRequest:updateToDeleteRequest error:&aFetchError] mutableCopy];
                    //even though only one entity should be found modify them all
                    for (Trackable *foundEntity in foundEntities) {
                        NSLog(@"UUID: %@    deleting: %@",foundEntity.UUID,[foundEntity entity]);
                        //set the objects found to be deleted later in this method when all entities that are flagged are deleted.
                        foundEntity.flaggedAsDeleted = [NSNumber numberWithBool:YES];
                    }
                }
                //must be create or update
                else{
                    NSError *conversionError = nil;
                    [self buildObjectFromDictionary:aData inContext:theContext error:&conversionError];
                    if (conversionError) {
                        //build error;
                        NSLog(@"coversion from dictionary %@ to ManagedObject failed.  %@",aData, conversionError.localizedFailureReason);
                        success = NO;
                        break;
                    }
                }
            }
            if (success) {
                /*
                 *  delete the trackables representing deletions since sync was successful
                 */
                NSFetchRequest *deleteSyncEntriesRequest = [[NSFetchRequest alloc] init];
                [deleteSyncEntriesRequest setEntity:trackableDescription];
                NSPredicate *deletedPredicate = [NSPredicate predicateWithFormat:@"flaggedAsDeleted == %@ and updateTime < %@", [NSNumber numberWithBool:YES],executionTimeStamp];
                [deleteSyncEntriesRequest setPredicate:deletedPredicate];
                
                error = nil;
                NSArray *oldDeletedTrackables = [theContext actualExecuteFetchRequest:deleteSyncEntriesRequest error:&error];
                for(int i = 0; i < [oldDeletedTrackables count]; i++){
                    Trackable *aTrackable = (Trackable*)[oldDeletedTrackables objectAtIndex:i];
                    [theContext actualDeleteObject:aTrackable];
                }
                
                //NSLog(@"context %@",theContext);
                //self->theBaseContext works
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
                    [((NSObject*)self.delegate) performSelectorOnMainThread:@selector(onFailure:) withObject:error waitUntilDone:NO];
                }
                else{
                    [((NSObject*)self.delegate) performSelectorOnMainThread:@selector(saveContext) withObject:error waitUntilDone:YES];

                    [((NSObject*)self.delegate) performSelectorOnMainThread:@selector(onSuccess) withObject:error waitUntilDone:NO];
                }
            }
        }
    }
    @catch (NSException *exception) {
        NSString *description = [exception description];
        int errCode = 1;
        
        // Make underlying error.
        NSError *underlyingError = [[[NSError alloc] initWithDomain:NSPOSIXErrorDomain
                                                               code:errno userInfo:nil] autorelease];
        // Make and return custom domain error.
        NSArray *objArray = [NSArray arrayWithObjects:description, underlyingError, @"sync:", nil];
        NSArray *keyArray = [NSArray arrayWithObjects:NSLocalizedDescriptionKey,
                             NSUnderlyingErrorKey, NSFilePathErrorKey, nil];
        NSDictionary *eDict = [NSDictionary dictionaryWithObjects:objArray
                                                          forKeys:keyArray];
        
        NSError *anError = [[[NSError alloc] initWithDomain:@"org.quickconnectfamily.qcsync"
                                               code:errCode userInfo:eDict] autorelease];
        
        [self.delegate onFailure:anError];
        self->loggedIn = NO;
        success = NO;
    }
    [undoManager endUndoGrouping];
    if (!success) {
        [undoManager undo];
    }
    [undoManager release];
	//[self.theCondition unlock];
    return success;

}

- (NSManagedObject*)buildObjectFromDictionary:(NSDictionary*)anObjectDescriptionDictionary inContext:(NSManagedObjectContext*)theContext error:(NSError **)error{
    NSLog(@"\n\n\n\nStarting new object from dictionary.");
    NSManagedObject *returnEntity = nil;
    NSString *syncType = [[anObjectDescriptionDictionary allKeys] objectAtIndex:0];
    NSArray *syncTypeParts = [syncType componentsSeparatedByString:@"_"];
    //NSLog(@"sync parts: %@",syncTypeParts);
    NSString *className = [syncTypeParts objectAtIndex:2];
    NSDictionary *anObjectDescription = [[anObjectDescriptionDictionary allValues] objectAtIndex:0];
    
    NSLog(@"type: %@    description: %@",syncType, anObjectDescription);
    
    //NSDictionary *dataDescription = [aData objectForKey:@"sync_info"];
    NSString *operationType = [anObjectDescription objectForKey:@"eventType"];
    //NSLog(@"%@",operationType);
    //NSString *aUUID = [anObjectDescription objectForKey:@"UUID"];
    /*
     *  Create and update end up being the same behavior.
     */
    if ([operationType isEqualToString:@"create"] || [operationType isEqualToString:@"update"]) {
        NSLog(@"working with a %@",className);
        //find an instance
        NSString *aUUID = [anObjectDescription objectForKey:@"UUID"];
        NSEntityDescription *entity = [NSEntityDescription entityForName:className 
                                                  inManagedObjectContext:theContext];

        //see if the entity already exists
        NSFetchRequest *request = [[NSFetchRequest alloc] init];
        [request setEntity:entity];
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"UUID == [c]%@", aUUID];
		[request setPredicate:predicate];
        NSError *fetchError = nil;
        NSMutableArray *foundEntities = [[theContext executeFetchRequest:request error:&fetchError] mutableCopy];
        
        /*
         *
         *  For some reason the predicate is not filtering any of the entities when the request is executed.
         *  The code below should work if the predicate was working correctly. I'm going to replace it with 
         *  a manual search.
         *
         */
        /*
        [request release];
        //if the entity already exists then ignore the create message.
        if ([foundEntities count] == 0) {
            //create
            NSLog(@"!!!!!!!!!!!!!!!!!!!!!!creating!!!!!!!!!!!!!!!!");
            NSManagedObject *anObject = [NSEntityDescription insertNewObjectForEntityForName:className 
                                                                      inManagedObjectContext:theContext];
            Trackable *asTrackable = (Trackable*)anObject;
            asTrackable.isRemoteData = [NSNumber numberWithBool: YES];
            returnEntity = anObject;
        }
        else{
            NSLog(@"!!!!!!!!!!!!!!!!!!!!!!found!!!!!!!!!!!!!!!!");
            returnEntity = [foundEntities objectAtIndex:0];
        }
         */
        for (NSManagedObject *aPossibleEntity in foundEntities) {
            NSString *possibleUUID = [aPossibleEntity valueForKey:@"UUID"];
            if ([aUUID isEqualToString:possibleUUID]) {
                NSLog(@"!!!!!!!!!!!!!!!!!!!!!!found!!!!!!!!!!!!!!!!");
                returnEntity = aPossibleEntity;
                break;
            }
        }
        if (!returnEntity) {
            NSLog(@"!!!!!!!!!!!!!!!!!!!!!!creating!!!!!!!!!!!!!!!!");
            NSManagedObject *anObject = [NSEntityDescription insertNewObjectForEntityForName:className 
                                                                      inManagedObjectContext:theContext];
            Trackable *asTrackable = (Trackable*)anObject;
            asTrackable.isRemoteData = [NSNumber numberWithBool: YES];
            returnEntity = anObject;

        }
        
        /*
         *  use key/value coding to set the attributes.
         */
        NSArray * allDescriptionKeys = [anObjectDescription allKeys];
        for (NSString *aKey in allDescriptionKeys) {
            if ([aKey isEqualToString:@"eventType"] || [aKey isEqualToString:@"flaggedAsDeleted"]) {
                continue;
            }
            NSObject *aValue = [anObjectDescription objectForKey:aKey];
            //NSLog(@"setting key %@ to value %@",aKey,aValue);
            if([aValue isKindOfClass:[NSArray class]]){
                //handle to-many relationship creation and sub object creation if needed.
                for (NSDictionary* aRelatedObjectDescriptionDictionary in (NSArray*)aValue) {
                    
                    //NSString *adderMethodName = [NSString stringWithFormat:@"add%@Object",[aKey capitalizedString]];
                    //NSLog(@"using method %@",adderMethodName);
                    //SEL adderMethod = NSSelectorFromString(adderMethodName);
                    NSManagedObject *relatedObject = nil;
                    //get the class type of the object to be created.
                    NSString *subSyncType = [[aRelatedObjectDescriptionDictionary allKeys] objectAtIndex:0];
                    NSArray *subSyncTypeParts = [subSyncType componentsSeparatedByString:@"_"];
                    //NSLog(@"sync parts: %@",subSyncTypeParts);
                    NSString *subClassName = [subSyncTypeParts objectAtIndex:2];
                    
                    NSDictionary *subEntityDescription = [aRelatedObjectDescriptionDictionary objectForKey:subSyncType];
                    
                    //this may be a UUID only description.  Find the object
                    if ([subEntityDescription count] == 1) {
                        
                        NSString *aUUID = [subEntityDescription objectForKey:@"UUID"];
                        NSEntityDescription *entity = [NSEntityDescription entityForName:subClassName 
                                                                  inManagedObjectContext:theContext];
                        //fetch the existing entity
                        NSFetchRequest *request = [[NSFetchRequest alloc] init];
                        [request setEntity:entity];
                        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"UUID == [c]%@", aUUID];
                        [request setPredicate:predicate];
                        NSError *aFetchError = nil;
                        NSMutableArray *foundEntities = [[theContext executeFetchRequest:request error:&aFetchError] mutableCopy];
                        relatedObject = [foundEntities objectAtIndex:0];
                        
                    }
                    //need to create the object
                    else{
                        NSError *anError;
                        relatedObject = [self buildObjectFromDictionary:subEntityDescription inContext:theContext error:&anError];
                        if (anError) {
                            //set error pointer
                            *error = anError;
                            return nil;
                        }
                    }
                    //NSLog(@"adding entity: %@",[relatedObject entity]);
                    //NSLog(@"adding to entity: %@",[anObject entity]);
                    
                    
                    NSSet *changedObjects = [[NSSet alloc] initWithObjects:&relatedObject count:1];
                    [returnEntity willChangeValueForKey:aKey withSetMutation:NSKeyValueUnionSetMutation usingObjects:changedObjects];
                    [[returnEntity primitiveValueForKey:aKey] addObject:relatedObject];
                    [returnEntity didChangeValueForKey:aKey withSetMutation:NSKeyValueUnionSetMutation usingObjects:changedObjects];
                    [changedObjects release];
                    
                    //[anObject performSelector:adderMethod withObject:relatedObject];
                }
            }
            else if([aValue isKindOfClass:[NSDictionary class]]){
                NSDictionary *valueAsDictionary = (NSDictionary*)aValue;
                
                //this may be a UUID only description.  Find the object
                NSManagedObject *relatedObject = nil;
                NSString *subSyncType = [[valueAsDictionary allKeys] objectAtIndex:0];
                NSArray *subSyncTypeParts = [subSyncType componentsSeparatedByString:@"_"];
                //NSLog(@"sync parts: %@",subSyncTypeParts);
                NSString *subClassName = [subSyncTypeParts objectAtIndex:2];
                
                NSDictionary *subEntityDescriptionDictionary = [valueAsDictionary objectForKey:subSyncType];
                NSString *aUUID = [subEntityDescriptionDictionary objectForKey:@"UUID"];
                
                NSEntityDescription *entity = [NSEntityDescription entityForName:subClassName 
                                                          inManagedObjectContext:theContext];
                //fetch the existing entity
                NSFetchRequest *request = [[NSFetchRequest alloc] init];
                [request setEntity:entity];
                NSPredicate *predicate = [NSPredicate predicateWithFormat:@"UUID == [c]%@", aUUID];
                [request setPredicate:predicate];
                NSError *aFetchError = nil;
                NSMutableArray *foundEntities = [[theContext executeFetchRequest:request error:&aFetchError] mutableCopy];
                
                if ([foundEntities count] == 1) {
                    relatedObject = [foundEntities objectAtIndex:0];
                    
                }
                //need to create the object
                else{
                    NSError *anError = nil;
                    relatedObject = [self buildObjectFromDictionary:valueAsDictionary inContext:theContext error:&anError];
                    if (anError) {
                        //set error pointer
                        *error = anError;
                        return nil;
                    }
                }
                [returnEntity setValue:relatedObject forKey:aKey];
                
            }
            else{
                //NSLog(@"setting %@",aKey);
                if ([aKey isEqualToString:@"updateTime"]) {
                    
                    NSDateFormatter* dateFormatter = [[NSDateFormatter alloc] init];
                    [dateFormatter setTimeStyle:NSDateFormatterFullStyle];
                    [dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
                    
                    NSString* asString = (NSString*)aValue;
                    //NSString *dateString = [dateFormatter stringFromDate:[NSDate date]];
                    
                    NSDate *aDate = [dateFormatter dateFromString:asString];
                    [dateFormatter release];
                    
                    [returnEntity setValue:aDate forKey:aKey];
                    NSLog(@"setting attribute: %@ with value: %@",aKey, aValue);
                }
                else{
                    NSLog(@"setting attribute: %@ with value: %@",aKey, aValue);
                    [returnEntity setValue:aValue forKey:aKey];
                }
            }
        }

    }
    else if([operationType isEqualToString:@"delete"]){
        NSString *aUUID = [anObjectDescription objectForKey:@"UUID"];
        NSEntityDescription *entity = [NSEntityDescription entityForName:className 
                                                  inManagedObjectContext:theContext];
        //see if the entity already exists
        NSFetchRequest *request = [[NSFetchRequest alloc] init];
        [request setEntity:entity];
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"UUID == [c]%@", aUUID];
        [request setPredicate:predicate];
        NSError *aFetchError = nil;
        NSMutableArray *foundEntities = [[theContext executeFetchRequest:request error:&aFetchError] mutableCopy];
        //there should only be one but remove any that are found.
        if ([foundEntities count] > 0) {
            for (NSManagedObject* anEntityToDelete in foundEntities) {
                [theContext deleteObject:anEntityToDelete];
            }
        }

        returnEntity = nil;
    
    }
    return returnEntity;
}

+(NSString*)UUIDString {
    CFUUIDRef theUUID = CFUUIDCreate(NULL);
    CFStringRef string = CFUUIDCreateString(NULL, theUUID);
    CFRelease(theUUID);
    return [NSMakeCollectable(string) autorelease];
}


@end
