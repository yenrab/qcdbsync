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


/**
 @mainpage A small easy to use library used to keep your local CoreData data store in sync with a remote database.
 
 QC Sync allows your CoreData database to be synced with a database of your choice.  It is database and database structure agnostic.  In other words it works regardless of which database you choose to use as well as the structure of the database.  In fact it will also work with remote flat files if you choose.  These could be XML, CSV, or some other structure.
 
 
 
 @section Features
 
 @li Easy-to-use API
 @li DBMS agnostic, database design agnostic
 @li Thread-safe
 @li Backend app or service language agnostic
 @li User device agnostic.  iOS and OS X are supported
 @li One user can have multiple devices and the data is kept in sync on all of them
 
 
 @section Links
 
 @li <a href="http://www.quickconnectfamily.org/qcdbsync">QC Sync web site</a>.
 @li Browse <a href="http://sourceforge.net/projects/qcdbsync/">the project at sourceForge</a>.
 
 */


#import <CoreData/CoreData.h>
#import "EnterpriseSyncDelegate.h"

@class SyncData;


/**
 SynchronizedDB is used to keep your CoreData datastore in sync with a remote database of your choice.  
 */
@interface SynchronizedDB :  NSManagedObject
{
	NSMutableDictionary *changes;
	NSMutableData *resultData;
	NSURL *url;
	NSCondition *theCondition;
	NSPersistentStoreCoordinator* theCoordinator;
    //NSManagedObjectContext *baseContext;
    /**
     The delegate notified on sync completion or failure
     */
	id <EnterpriseSyncDelegate> delegate;
    BOOL loggedIn;
    NSString *uName;
    NSString *pWord;
}
@property (nonatomic, retain) NSDictionary *changes;
@property (nonatomic, retain) NSMutableData *resultData;
@property (nonatomic, retain) NSURL *url;
@property (nonatomic, retain) id<EnterpriseSyncDelegate> delegate;
@property (nonatomic, retain) NSCondition *theCondition;
@property (nonatomic, retain) NSPersistentStoreCoordinator* theCoordinator;
@property (readonly) BOOL loggedIn;

/**
 Returns an initialized SynchronizedDB object that is ready to sync any changes made to the data store.  
 This method also attempts to login the service using the user name and password.
 @param aCoreDataContainer The instance that has the managedObjectContext as an attribute.  If Xcode generated your CoreData code for you this is your app delegate
 @param aURLString the url to the web app or service that is the front end for the remote database
 @param aUserName the user name on the remote app or service that has rights to access the app or service
 @param aPassword the password for the user on the remote app or service that has rights to access the app or service
 @returns an initialized SynchronizedDB object that is waiting to sync with a remote app or service if login succeeds
 */
- (SynchronizedDB*)init:(id<EnterpriseSyncDelegate>)aCoreDataContainer withService:(NSString*)aURLString userName:(NSString*)aUserName password:(NSString*)aPassword;
/**
 Attempt to login.  This is used if at any time the connection is lost to the remote service.
 @param userName The user name for the remote service
 @param password The password for the remote service
 @returns a BOOL value indicating if login request is sent successfully.  Does not indicate successful login.
 */
- (BOOL) attemptRemoteLogin:(NSString*)userName withPassword:(NSString*)password;
/**
 Triggers synchronization of the local CoreData datastore with the remote web app or service.
 @returns YES on success or NO on failure.
 */
- (BOOL)sync;
/**
 A class method that returns unique UUID identifiers
 @returns NSString* to a UUID string
 */
+ (NSString*)UUIDString;

@end



