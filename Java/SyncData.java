package org.quickconnect.sync;

import java.io.Serializable;
import java.util.ArrayList;
import java.util.Iterator;

import org.quickconnect.json.JSONException;
import org.quickconnect.json.JSONUtilities;
 
public class SyncData implements Serializable{
	String lastSyncTime;
	ArrayList<SyncItem> syncInfo;
    
	@SuppressWarnings("unchecked")
	public SyncData(String lastSync, ArrayList<ArrayList<String>> syncValues) throws JSONException {
		this.lastSyncTime = lastSync;
		syncInfo = new ArrayList<SyncItem>();
		Iterator<ArrayList<String>> rowIt = syncValues.iterator();
		while(rowIt.hasNext()){
			ArrayList<String> aRow = rowIt.next();
			ArrayList<Object> values = (ArrayList<Object>)JSONUtilities.parse(aRow.get(2));
			SyncItem anItem = new SyncItem(aRow.get(0),aRow.get(1),values);
			syncInfo.add(anItem);
		}
	}
}
