/*
 Copyright (c) 2011 Lee Barney
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

package org.quickconnectfamily.sync;

import java.io.IOException;
import java.io.UnsupportedEncodingException;
import java.lang.ref.WeakReference;
import java.net.URI;
import java.net.URISyntaxException;
import java.net.URL;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.concurrent.Semaphore;

import javax.crypto.Cipher;

import org.apache.http.HttpEntity;
import org.apache.http.HttpResponse;
import org.apache.http.HttpVersion;
import org.apache.http.NameValuePair;
import org.apache.http.client.ClientProtocolException;
import org.apache.http.client.CookieStore;
import org.apache.http.client.HttpClient;
import org.apache.http.client.entity.UrlEncodedFormEntity;
import org.apache.http.client.methods.HttpPost;
import org.apache.http.client.protocol.ClientContext;
import org.apache.http.conn.scheme.PlainSocketFactory;
import org.apache.http.conn.scheme.Scheme;
import org.apache.http.conn.scheme.SchemeRegistry;
import org.apache.http.conn.ssl.SSLSocketFactory;
import org.apache.http.impl.client.BasicCookieStore;
import org.apache.http.impl.client.DefaultHttpClient;
import org.apache.http.impl.conn.tsccm.ThreadSafeClientConnManager;
import org.apache.http.message.BasicNameValuePair;
import org.apache.http.params.BasicHttpParams;
import org.apache.http.params.HttpParams;
import org.apache.http.params.HttpProtocolParams;
import org.apache.http.protocol.BasicHttpContext;
import org.apache.http.protocol.HTTP;
import org.apache.http.protocol.HttpContext;
import org.apache.http.util.EntityUtils;
import org.quickconnectfamily.dbaccess.DataAccessException;
import org.quickconnectfamily.dbaccess.DataAccessObject;
import org.quickconnectfamily.dbaccess.DataAccessResult;
import org.quickconnectfamily.json.JSONException;
import org.quickconnectfamily.json.JSONUtilities;

import android.app.Activity;
import android.content.Context;
/**
 * The SynchronizedDB class provides a safe way of keeping a SQLite file on an Android device in sync with 
 * a remote server.  The API for this class is the only API needed.<br/>
 * 
 * This class depends upon the QCDBAccess library.  It must also be included in your project.
 * <br/>
 * Transactions are started and stopped using the SynchronizedDB startTransaction and endTransaction methods.  If any error 
 * occurs while executing the SQL found within these two transaction method calls then 
 * a roll back of the changes made will be executed.  
 * <br/>
 * If your database is not going to be used any longer you can use the SynchronizedDB cleanUp method to free the resources.
 * 
 * 
 * 
 * @author Lee S. Barney
 *
 */
public class SynchronizedDB{

	private WeakReference<Context> theActivityRef;
	private HttpClient httpClient;
	private HashMap<String,String> registeredSQLStatements = new HashMap<String,String>();
	private String dbName;
	private URI remoteURL;
	private String remoteUname;
	private String remotePword;
	private boolean allTransactionStatementsExecuted;
	private boolean executingTransaction;
	private Semaphore semaphore = new Semaphore(1);
	private HttpContext localContext;
	private boolean loggedIn;

	/**
	 * Creates a SynchronizedDB object used to interact with a local database and a remote HTTP service.  It 
	 * sends a login request to the 
	 * @param theActivityRef - the activity that the database is associated with.  This is usually your initial Acivity class.
	 * @param aDbName - the name of the SQLite file to be kept in sync.
	 * @param aRemoteURL - the URL of the service that will respond to synchronization requests including the port number if not port 80.  
	 * For security reasons it is suggested that your URL be an HTTPS URL but this is not required.
	 * @param port - the port number of the remote HTTP service.
	 * @param aRemoteUname - a security credential used in the remote service
	 * @param aRemotePword - a security credential used in the remote service
	 * @param syncTimeout - the amount of time in seconds to attempt all sync requests before timing out.
	 * @throws DataAccessException
	 * @throws URISyntaxException
	 * @throws InterruptedException
	 */
	public SynchronizedDB(WeakReference<Context> theActivityRef, String aDbName, URL aRemoteURL, int port, String aRemoteUname, String aRemotePword, long syncTimeout) throws DataAccessException, URISyntaxException, InterruptedException {
		dbName = aDbName;
		remoteURL = aRemoteURL.toURI();
		remoteUname = aRemoteUname;
		remotePword = aRemotePword;
		this.theActivityRef = theActivityRef;
		
		SchemeRegistry schemeRegistry = new SchemeRegistry();
		if(aRemoteURL.toExternalForm().indexOf("http") == 0){
			schemeRegistry.register(new Scheme("http", PlainSocketFactory.getSocketFactory(), port));
		}
		else if(aRemoteURL.toExternalForm().indexOf("https") == 0){
			schemeRegistry.register(new Scheme("https", SSLSocketFactory.getSocketFactory(), port));
		}
		HttpParams params = new BasicHttpParams();
		HttpProtocolParams.setVersion(params, HttpVersion.HTTP_1_1);
		HttpProtocolParams.setContentCharset(params, "utf-8");

		ThreadSafeClientConnManager cm = new ThreadSafeClientConnManager(params, schemeRegistry);
		 
		httpClient = new DefaultHttpClient(cm, params);

		startTransaction();
		String errorMessage = null;
		//insert the required tables if they don't exist
		try {
			DataAccessResult aResult = DataAccessObject.setData(theActivityRef, aDbName, "CREATE TABLE IF NOT EXISTS sync_info(int id PRIMARY KEY  NOT NULL, last_sync TIMESTAMP);", null);
			if(aResult.getErrorDescription().equals("not an error")){
				aResult = DataAccessObject.setData(theActivityRef, aDbName, "CREATE TABLE IF NOT EXISTS sync_values(timeStamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, sql_key TEXT, sql_params TEXT)", null);
				if(!aResult.getErrorDescription().equals("not an error")){
					allTransactionStatementsExecuted = false;
					errorMessage = aResult.getErrorDescription();
				}
			}
			else{
				allTransactionStatementsExecuted = false;
				errorMessage = aResult.getErrorDescription();
			}
		} catch (DataAccessException e) {
			e.printStackTrace();
			errorMessage = e.getLocalizedMessage();
			allTransactionStatementsExecuted = false;
			errorMessage = e.getLocalizedMessage();
		}
		endTransaction();
		if(allTransactionStatementsExecuted == false){
			throw new DataAccessException("Error: Transaction failure. "+errorMessage);
		}
		
		/*
		 * Do login and store context
		 */
		// Create a local instance of cookie store
	    CookieStore cookieStore = new BasicCookieStore();

	    // Create local HTTP context
	    localContext = new BasicHttpContext();
	    // Bind custom cookie store to the local context
	    localContext.setAttribute(ClientContext.COOKIE_STORE, cookieStore);
	    
	}

	
	/**
	 * This method is used to associate a representative key String with a String containing SQL.  All SQL that is 
	 * used to interact with the database must be registered if it is to be used with the setData and getData 
	 * SynchronizedDB methods.
	 * @param sqlKey - a representative String describing the SQL.  Usually one word or camel case phrase.
	 * @param SQL - the SQL to be executed later using the getData or setData methods.
	 * @throws InterruptedException
	 */
	public void registerSynchedStatement(String sqlKey, String SQL) throws InterruptedException{
		
		if(!executingTransaction){
			semaphore.acquire(1);
		}
		registeredSQLStatements.put(sqlKey, SQL);
		if(!executingTransaction){
			semaphore.release(1);
		}
	}
	
	/**
	 * This method is used to associate a series of key - SQL pairs as if they had been registered 
	 * individually using the registerSynchedStatement method.
	 * @param keySQLMap - a HashMap containing multiple key/SQL pairs to be registered for later use.
	 * @throws InterruptedException
	 */
	public void registerSyncStatements(HashMap<String,String> keySQLMap) throws InterruptedException{
		if(!executingTransaction){
			semaphore .acquire(1);
		}
		registeredSQLStatements.putAll(keySQLMap);
		if(!executingTransaction){
			semaphore.release(1);
		}
	}

	/**
	 * This method is used to retrieve data from the SQLite database on the device.
	 * @param sqlKey - the key representing the SQL to be executed.  This may be a standard or prepared SQL statement but 
	 * must have previously been registered using one of the registerSync* methods.
	 * @param parameters - an array of objects to be bound to the ? place holders if the registered SQL is to be used as 
	 * a prepared statement.
	 * @return a DataAccessResult containing the data retrieved by the query, the names of the resultant fields, and 
	 * any SQL error that may have been generated by faulty SQL.  See the QCDBAccess library documentation.
	 * @throws DataAccessException
	 * @throws InterruptedException
	 */
	public DataAccessResult getData(String sqlKey, Object[] parameters) throws DataAccessException, InterruptedException{
		if(!executingTransaction){
			semaphore.acquire(1);
		}
		DataAccessResult retVal = null;
		String sql = registeredSQLStatements.get(sqlKey);
		if(sql == null){
			throw new DataAccessException("No such key: "+sqlKey);
		}
		semaphore.acquire(1);
		retVal = DataAccessObject.getData(theActivityRef, dbName, sql, parameters);
		semaphore.release(1);
		if(!executingTransaction){
			semaphore.release(1);
		}
		return retVal;
	}
	/**
	 This method is used to insert data into the SQLite database on the device or do any other type of database modification.
	 * @param sqlKey - the key representing the SQL to be executed.  This may be a standard or prepared SQL statement but 
	 * must have previously been registered using one of the registerSync* methods.
	 * @param parameters - an array of objects to be bound to the ? place holders if the registered SQL is to be used as 
	 * a prepared statement.  This array of values is stored for sending to the remote HTTP service as data to be synchronized 
	 * and stored in the remote database behind the service.
	 * @return a DataAccessResult containing a SQL error if any was generated by faulty SQL.  See the QCDBAccess library documentation.
	 * @throws DataAccessException
	 * @throws InterruptedException
	 * @throws JSONException
	 */
	public DataAccessResult setData(String sqlKey, Object[] parameters) throws DataAccessException, InterruptedException, JSONException{
		DataAccessResult retVal = null;
		String sql = registeredSQLStatements.get(sqlKey);

		if(sql == null){
			throw new DataAccessException("No such key: "+sqlKey);
		}
			
		startTransaction();
		if(!executingTransaction){
			semaphore.acquire(1);
		}
		//insert into sync table
		Object[] preparedStatementParameters = new Object[2];
		preparedStatementParameters[0] = sqlKey;
		preparedStatementParameters[1] = JSONUtilities.stringify(parameters);
		DataAccessResult syncInsertResult = DataAccessObject.setData(theActivityRef, dbName, 
													"INSERT INTO sync_values (sql_key, sql_params) VALUES(?,?)", preparedStatementParameters);
		if(!syncInsertResult.getErrorDescription().equals("not an error")){
			throw new DataAccessException("Error: unable to insert sync values "+parameters+" for key "+sqlKey);
		}
		
		//execute the sql statement
		retVal = DataAccessObject.setData(theActivityRef, dbName, sql, parameters);
		endTransaction();

		//registeredSQLStatements.put(sqlKey, SQL);
		if(!executingTransaction){
			semaphore.release(1);
		}
		return retVal;
	}
	/**
	 * This method is called prior to making multiple setData calls.  It starts an SQLite transaction.
	 * @throws InterruptedException
	 * @throws DataAccessException
	 */
	public void startTransaction() throws InterruptedException, DataAccessException{
		semaphore.acquire(1);
		executingTransaction = true;
		DataAccessObject.startTransaction(theActivityRef, dbName);
		semaphore.release(1);
		allTransactionStatementsExecuted = true;
	}
	/**
	 * This method is called after the startTransaction method and any number of setData calls.  It terminates 
	 * an SQLite transaction and does a rollback if any of the setData calls generated an SQL error.
	 * @throws InterruptedException
	 * @throws DataAccessException
	 */
	public void endTransaction() throws InterruptedException, DataAccessException{
		semaphore.acquire(1);
		DataAccessObject.endTransaction(theActivityRef, dbName, allTransactionStatementsExecuted);
		executingTransaction = true;
		semaphore.release(1);
	}
	/**
	 * This method pushes any stored setData parameters to the HTTP service, waits for any data from the service, 
	 * and then inserts any data received from the service into the appropriate tables in the local SQLite database.
	 * @throws ClientProtocolException
	 * @throws DataAccessException
	 * @throws JSONException
	 * @throws IOException
	 * @throws InterruptedException
	 * @throws QCSynchronizationException
	 */
	public void sync() throws ClientProtocolException, DataAccessException, JSONException, IOException, InterruptedException, QCSynchronizationException{
		sync(null,HTTP.UTF_8);
	}
	/**
	 * This method pushes any stored setData parameters to the HTTP service, waits for any data from the service, 
	 * and then inserts any data received from the service into the appropriate tables in the local SQLite database.
	 * @param anEncryptionCipher - a Cipher used to encrypt the data sent to the HTTP service and decrypt the response.
	 * @throws DataAccessException
	 * @throws JSONException
	 * @throws ClientProtocolException
	 * @throws IOException
	 * @throws InterruptedException
	 * @throws QCSynchronizationException
	 */
	public void sync(Cipher anEncryptionCipher) throws DataAccessException, JSONException, ClientProtocolException, IOException, InterruptedException, QCSynchronizationException{
		try{
			sync(anEncryptionCipher, HTTP.UTF_8);
		}
		catch (UnsupportedEncodingException e) {
			//UTF-8 is supported so do nothing
		}
	}
	/**
	 * This method pushes any stored setData parameters to the HTTP service, waits for any data from the service, 
	 * and then inserts any data received from the service into the appropriate tables in the local SQLite database.
	 * @param anEncryptionCipher - a Cipher used to encrypt the data sent to the HTTP service and decrypt the response.
	 * @param encoding - the encoding type of the data sent to and received from the HTTP service.  Example: UTF-8.    
	 * This parameter must be one of the public static values found in the org.apache.http.protocol.HTTP class.
	 * @throws DataAccessException
	 * @throws JSONException
	 * @throws ClientProtocolException
	 * @throws IOException
	 * @throws InterruptedException
	 * @throws QCSynchronizationException
	 */
	@SuppressWarnings("unchecked")
	public void sync(Cipher anEncryptionCipher, String encoding) throws DataAccessException, JSONException, ClientProtocolException, IOException, InterruptedException, QCSynchronizationException{
		//if not logged in login
		if(!loggedIn){
			try {
				HttpPost httppost = new HttpPost(remoteURL);

				List <NameValuePair> nameValuePairList = new ArrayList <NameValuePair>();
				nameValuePairList.add(new BasicNameValuePair("cmd", "login"));
				nameValuePairList.add(new BasicNameValuePair("uname", this.remoteUname));
				nameValuePairList.add(new BasicNameValuePair("pword", this.remotePword));

				httppost.setEntity(new UrlEncodedFormEntity(nameValuePairList, HTTP.UTF_8));



				System.out.println("executing login request " + httppost.getRequestLine());
				HttpResponse response = httpClient.execute(httppost, localContext);
				if(response.getStatusLine().getStatusCode() / 200 == 1){
					HttpEntity responseEntity = response.getEntity();
					String JSONString = EntityUtils.toString(responseEntity, HTTP.UTF_8);
					ArrayList<Object> resultList = (ArrayList<Object>) JSONUtilities.parse(JSONString);
					HashMap<String,String> resultMap = (HashMap<String,String>)resultList.get(0);
					String error = resultMap.get("sync_error");
					if(error != null){
						throw new IOException(error);
					}
					else{
						loggedIn = true;
						System.out.println("successful login");
					}
				}
				else{
					throw new IOException("Invalid user name or password");
				}
			}
			catch(Exception e){
				throw new IOException(e);
			}
		}
		System.out.println("login success.  about to query.");
		//get the data from the sync_values table
		startTransaction();
		System.out.println("after transaction start");
		DataAccessResult syncValuesResult = DataAccessObject.getData(theActivityRef, dbName, "SELECT * FROM sync_values", null);
		ArrayList<ArrayList<String>> syncValues = syncValuesResult.getResults();
		//get the data from the sync_info table
		DataAccessResult lastSyncResult = DataAccessObject.getData(theActivityRef, dbName, "SELECT last_sync FROM sync_info", null);
		
		//release the semaphore here since the rest is just data prep and send
		
		
		String lastSync = "1970-01-01 00:00:00";
		if(lastSyncResult.getResults().size() > 0){
			lastSync = lastSyncResult.getResults().get(0).get(0);
		}
		//create a sync object from the data
		SyncData theDataToSync = new SyncData(lastSync, syncValues);
		//JSON the sync object using encryption if ciper is not null

		String JSONString = null;
		if(anEncryptionCipher == null){
			JSONString = JSONUtilities.stringify(theDataToSync);
		}
		else{
			//Not supported in QCJSON at this time.
			//JSONString = JSONUtilities.stringify(theDataToSync, anEncryptionCipher);
			JSONString = JSONUtilities.stringify(theDataToSync);
		}
		//escape the resultant string

		//post the JSON
		try {
			HttpPost httppost = new HttpPost(remoteURL);

			List <NameValuePair> nameValuePairList = new ArrayList <NameValuePair>();
			nameValuePairList.add(new BasicNameValuePair("cmd", "sync"));
			nameValuePairList.add(new BasicNameValuePair("data", JSONString));

			httppost.setEntity(new UrlEncodedFormEntity(nameValuePairList, HTTP.UTF_8));



			System.out.println("executing request " + httppost.getRequestLine());
			HttpResponse response = httpClient.execute(httppost, localContext);
			if(response.getStatusLine().getStatusCode() / 200 == 1){
				HttpEntity responseEntity = response.getEntity();
	 
				String result = EntityUtils.toString(responseEntity, HTTP.UTF_8);
				System.out.println("JSON: "+result);
				ArrayList<Object> resultList = (ArrayList<Object>)JSONUtilities.parse(result);
				HashMap<String,String>syncResultMap = (HashMap<String,String>)resultList.get(0);
				if(syncResultMap.get("sync_error") != null && !((Object)syncResultMap.get("sync_response")).equals("data_success")){
					throw new QCSynchronizationException((String)syncResultMap.get("sync_error"));
				}
				HashMap<String,Object>dataMap = (HashMap<String,Object>)resultList.get(1);
				//HashMap<String,String> timeStampMap = (HashMap<String,String>)resultList.get(1);
				String lastSyncTime = (String)dataMap.get("sync_time");
				ArrayList<HashMap<String,Object>> dataList = (ArrayList<HashMap<String,Object>>)dataMap.get("sync_data");
				//update the time stamp for lastSyncTime
				Object[] preparedStatementParameters = new Object[1];
				preparedStatementParameters[0] = lastSyncTime;
				try{
				DataAccessResult updateResult = DataAccessObject.setData(theActivityRef, dbName, "INSERT OR REPLACE INTO sync_info VALUES(0,?)", preparedStatementParameters);
				
				//execute each of the inserts for the sync data received.
				for(HashMap<String,Object>syncDatum : dataList){
					String sqlKey = (String)syncDatum.get("key");
					ArrayList<String> sqlParameterList = (ArrayList<String>)syncDatum.get("syncInfo");
					String sql = registeredSQLStatements.get(sqlKey);
					updateResult = DataAccessObject.setData(theActivityRef, dbName, sql, sqlParameterList.toArray());
				}
				}
				catch(Exception e){
					throw new QCSynchronizationException(e.getLocalizedMessage()+" "+e.getCause());
				}
				
				this.clearSync();
			}
			else{
				throw new IOException(response.getStatusLine().toString());
			}
		}
		finally {
			endTransaction();
		}
	}
	/**
	 * This is a method that should rarely, if ever, be used.  It deletes all data previously stored for later synchronization.
	 * @throws InterruptedException
	 * @throws DataAccessException
	 * @throws JSONException
	 */
	public void clearSync() throws InterruptedException, DataAccessException, JSONException{
    	this.startTransaction();
		this.setData("DELETE FROM sync_values", null);
		this.endTransaction();
	}
	/**
	 * This method sends a logout command to the remote HTTP service and closes down the HTTP client on the Android device.
	 * @throws IOException
	 */
	public void cleanUp() throws IOException{
		try {
			HttpPost httppost = new HttpPost(remoteURL);

			List <NameValuePair> nameValuePairList = new ArrayList <NameValuePair>();
			nameValuePairList.add(new BasicNameValuePair("cmd", "logout"));

			httppost.setEntity(new UrlEncodedFormEntity(nameValuePairList, HTTP.UTF_8));

			System.out.println("executing logout request " + httppost.getRequestLine());
			HttpResponse response = httpClient.execute(httppost, localContext);
			if(response.getStatusLine().getStatusCode() / 200 != 1){
				throw new IOException("Unable to logout");
			}
		}
		catch(Exception e){
			throw new IOException(e);
		}
		// When HttpClient instance is no longer needed,
		// shut down the connection manager to ensure
		// immediate deallocation of all system resources
		httpClient.getConnectionManager().shutdown();
	}


}
