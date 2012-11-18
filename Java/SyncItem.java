package org.quickconnectfamily.sync;

import java.io.Serializable;
import java.util.ArrayList;

public class SyncItem implements Serializable{
	private String insertionTime;
	private String key;
	private ArrayList<Object> values;
	

	public SyncItem(String insertionTime, String key, ArrayList<Object> values) {
		this.insertionTime = insertionTime;
		this.key = key;
		this.values = values;
	}
}
