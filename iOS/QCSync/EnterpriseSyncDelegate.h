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

#import <UIKit/UIKit.h>

/**
 EnterpriseSyncListener is a Delegate for the synchronization process.  Add these delegate protocol methods to some object of your choice to receive notifications regarding the synchronization process.  
 */
@protocol EnterpriseSyncDelegate

@required
/**
 Called when synchronization completes successfully
 @returns void
 */
-(void) onSuccess;
/**
 Called when synchronization failes prior to completion
  @param error An NSError describing the synchronization error
 @returns void
 */
-(void) onFailure:(NSError*)error;

/*
 *  If you use Xcode to include CoreData these methods are implemented in your AppDelegate already.
 *  If you don't use Xcode to do this you will need to implement the methods yourself.
 */

- (void)saveContext;

- (NSPersistentStoreCoordinator*)persistentStoreCoordinator;

- (NSManagedObjectContext*)managedObjectContext;


@end