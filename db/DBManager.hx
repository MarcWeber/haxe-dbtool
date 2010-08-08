package db;

import Reflect;
using Lambda;

/**


        ALPHA state: expect code to be broken!

        You can still get the basic idea from the HaXe website reading about SPODs.

        However this implementation differs slightly:

        - there is one implementation for all targets (PHP, JS, ..)

        - I have plans to extend it so that you can fetch related objects
          using one query only using JOINS. Whether I will implement it depends
          on my needs


        So what did I change?
        - removed keywords, should be handled by DBConnection
        - removed no_update. Using __update field instead
        - using DBConnection instead of neko.db.Connection and its
        - removed doUpdate, doInsert. Added doStore instead which does the right
        thing in both cases
        implementations

	- merged some code from PHP implementation. See #ifdef sections
        - using static list in DBObject to determine table_fields.

**/
class DBManager<T : DBObject> {

	/* ----------------------------- STATICS ------------------------------ */
	public static var cnx(default,setConnection) : DBConnection;
	private static var object_cache : Hash<DBObject> = new Hash();
	private static var init_list : List<DBManager<DBObject>> = new List();
	private static var cache_field = "__cache__";
	private static var LOCKS = ["","",""];
	public static var managers = new Hash<DBManager<Dynamic>>();

	private static function setConnection( c : DBConnection ) {
		Reflect.setField(DBManager,"cnx",c);
		if( c != null ) {
			if( c.dbName() == "MySQL" ) {
				LOCKS[1] = " LOCK IN SHARE MODE";
				LOCKS[2] = " FOR UPDATE";
			} else {
				LOCKS[1] = "";
				LOCKS[2] = "";
			}
		}
		return c;
	}

	/* ---------------------------- BASIC API ----------------------------- */
	var table_name : String;
	var table_fields : Array<String>;
	var table_keys : Array<String>;
	var class_proto : { prototype : Dynamic };
	var lock_mode : Int;
        var cl: Dynamic; //Class<T:php.db.Object>;

	public function new( classval : Class<db.DBObject> ) {
		cl = classval;

		// get basic infos
		var cname : Array<String> = cl.__name__;
		table_name = cnx.quoteName(if( cl.TABLE_NAME != null ) cl.TABLE_NAME else cname[cname.length-1]);
		table_keys = if( cl.TABLE_IDS != null ) cl.TABLE_IDS else ["id"];
		class_proto = cl;
		lock_mode = 2;

		// get the list of private fields
		var apriv : Array<String> = cl.PRIVATE_FIELDS;
		apriv = if( apriv == null ) new Array() else apriv.copy();
                apriv.push("__dirty_data");
                apriv.push("__update");
                apriv.push("__new");


		// apriv.push("local_manager");
		apriv.push("__class__");

/*
                I don't want to maintain the reflection stuff at the moment -
                using static field


		// get the proto fields not marked private (excluding methods)
		var tf = new List();

// this code should be present in reflection API?
#if neko
		var proto : { local_manager : DBManager<T> } = class_proto.prototype;
		var instance_fields = Reflect.fields(proto)
#elseif php
		var proto = Type.createEmptyInstance(cl);
		var instance_fields = Type.getInstanceFields(cl);
		var scls = Type.getSuperClass(cl);
		while(scls != null) {
			for(remove in Type.getInstanceFields(scls))
				instance_fields.remove(remove);
			scls = Type.getSuperClass(scls);
		}
#else
		TODO
                PHP: see new() constructor and managers
#end

		for( f in instance_fields ) {
			var isfield = !Reflect.isFunction(Reflect.field(proto,f));
			if( isfield )
				for( f2 in apriv )
					if( f == f2 ) {
						isfield = false;
						break;
					}
			if( isfield )
				tf.add(f);
		}
                table_fields = tf.array();
*/
                table_fields = cl.TABLE_FIELDS;

		// set the manager and ready for further init
		// proto.local_manager = this;
		init_list.add(cast this);

		// set the manager and ready for further init

		var clname = Type.getClassName(classval); // is this same as cname ?
		managers.set(clname, this);
	}

	public function get( id : Int, ?lock : Bool ) : T {
		if( lock == null )
			lock = true;
		if( table_keys.length != 1 )
			throw "Invalid number of keys";
		if( id == null )
			return null;
		var x : Dynamic = getFromCacheKey(id + table_name);
		if( x != null && (!lock || !x.__update ) )
			return x;
		var s = new StringBuf();
		s.add("SELECT * FROM ");
		s.add(table_name);
		s.add(" WHERE ");
		s.add(cnx.quoteName(table_keys[0]));
		s.add(" = ");
		cnx.addValue(s,id);
		if( lock )
			s.add(getLockMode());
		return object(s.toString(),lock);
	}

	public function getWithKeys( keys : {}, ?lock : Bool ) : T {
		if( lock == null )
			lock = true;
		var x : Dynamic = getFromCacheKey(makeCacheKey(cast keys));
		if( x != null && (!lock || !x.__update ) )
			return x;
		var s = new StringBuf();
		s.add("SELECT * FROM ");
		s.add(table_name);
		s.add(" WHERE ");
		addKeys(s,keys);
		if( lock )
			s.add(getLockMode());
		return object(s.toString(),lock);
	}

	// implement this a second time for get ?
        public function getOrNewWithKeys( keys : {}, ?lock: Bool) : T {
		var o = getWithKeys(keys, lock);
                if (o == null){
                  var o : T = Type.createEmptyInstance(cl);
                  o.__new = true;
		  // assuming non autoincrement. So assign keys
		  // if it is autoincrement keys will be overridden when
		  // inserting
                  for (f in table_keys)
                    Reflect.setField(o,f,Reflect.field(keys,f));
		}
                return o;
        }

	public function delete( x : {} ) {
		var s = new StringBuf();
                cnx.delete(table_name, x, table_keys);
	}

	public function search( x : {}, ?lock : Bool ) : List<T> {
		if( lock == null )
			lock = true;
		var s = new StringBuf();
		s.add("SELECT * FROM ");
		s.add(table_name);
		s.add(" WHERE ");
		addCondition(s,x);
		if( lock )
			s.add(getLockMode());
		return objects(s.toString(),lock);
	}

	function addCondition(s : StringBuf,x) {
		var first = true;
		if( x != null )
			for( f in Reflect.fields(x) ) {
				if( first )
					first = false;
				else
					s.add(" AND ");
				s.add(cnx.quoteName(f));
				var d = Reflect.field(x,f);
				if( d == null )
					s.add(" IS NULL");
				else {
					s.add(" = ");
					cnx.addValue(s,d);
				}
			}
		if( first )
			s.add("1");
	}

	public function all( ?lock: Bool ) : List<T> {
		if( lock == null )
			lock = true;
		return objects("SELECT * FROM " + table_name + if( lock ) getLockMode() else "",lock);
	}

	public function count( ?x : {} ) : Int {
                return cnx.queryIntPH("SELECT COUNT(*) FROM t WHERE ?w", [x]);
	}

	public function quote( s : String ) : String {
		return cnx.quote( s );
	}

	public function result( sql : String ) : Dynamic {
		return cnx.query(sql, function(r){return r.next();});
	}

	public function results<T>( sql : String ) : List<T> {
		return cast(cnx.queryResults(sql));
	}

	/* -------------------------- SPODOBJECT API -------------------------- */

	function doStore( x : T ): DBObject {
		unmake(x);
                if (x.__new){
                	// insert
			cnx.insert(table_name, x, table_fields);

			if( table_keys.length == 1 && Reflect.field(x,table_keys[0]) == null ){
                          Reflect.setField(x,"_"+table_keys[0],cnx.lastInsertId());
                        }
			addToCache(x);
                } else {
                	// update
			if (x.__dirty_data){
				cnx.update(table_name, x, table_fields, x, table_keys);
				x.__dirty_data = false;
			}
                }
                return x;
	}


	function doSync( i : T ): DBObject {
		object_cache.remove(makeCacheKey(i));
		var i2 = getWithKeys(i,!(cast i).__update );
		// delete all fields
		for( f in Reflect.fields(i) )
			Reflect.deleteField(i,f);
		// copy fields from new object
		for( f in Reflect.fields(i2) )
			Reflect.setField(i,f,Reflect.field(i2,f));
		// set same field-cache
		Reflect.setField(i,cache_field,Reflect.field(i2,cache_field));
		// rebuild in case it's needed
		make(i);
		addToCache(i);
                return i;
	}


	function doDelete( x : T ) {
                cnx.delete(table_name, x, this.table_fields);
		removeFromCache(x);
	}

        /* where this used?
	function objectToString( it : T ) : String {
		var s = new StringBuf();
		s.add(table_name);
		if( table_keys.length == 1 ) {
			s.add("#");
			s.add(Reflect.field(it,table_keys[0]));
		} else {
			s.add("(");
			var first = true;
			for( f in table_keys ) {
				if( first )
					first = false;
				else
					s.add(",");
				s.add(quoteField(f));
				s.add(":");
				s.add(Reflect.field(it,f));
			}
			s.add(")");
		}
		return s.toString();
	}
        */

	/* ---------------------------- INTERNAL API -------------------------- */

	function cacheObject( x : T, lock : Bool ): T {
#if neko
		addToCache(x);
		// untyped __dollar__objsetproto(x,class_proto.prototype);
		Reflect.setField(x,cache_field,untyped __dollar__new(x));
                return x;
#elseif php

		var o : T = Type.createEmptyInstance(cl);

		for(field in table_fields) {
			Reflect.setField(o, field, Reflect.field(x, field));
		}
		addToCache(o);

                return o;
#end
	}

	function make( x : T ) {
	}

	function unmake( x : T ) {
	}

	function addKeys( s : StringBuf, x : {} ) {
		var first = true;
		for( k in table_keys ) {
			if( first )
				first = false;
			else
				s.add(" AND ");
			s.add(cnx.quoteName(k));
			s.add(" = ");
			var f = Reflect.field(x,k);
			if( f == null )
				throw ("Missing key "+k);
			cnx.addValue(s,f);
		}
	}

	function select( cond : String ) {
		var s = new StringBuf();
		s.add("SELECT * FROM ");
		s.add(table_name);
		s.add(" WHERE ");
		s.add(cond);
		s.add(getLockMode());
		return s.toString();
	}

	function selectReadOnly( cond : String ) {
		var s = new StringBuf();
		s.add("SELECT * FROM ");
		s.add(table_name);
		s.add(" WHERE ");
		s.add(cond);
		return s.toString();
	}

	public function object( sql : String, lock : Bool ) : T {
                var t = this;
		return cnx.query(sql, function(rs){
                        if( rs == null )
                                return null;
                        var r = rs.next();

                        var r = t.getFromCache(r,lock);
                        if( r != null )
                                return r;
                        var r = t.cacheObject(r,lock);
                        r.__new = false;
                        t.make(r);
                        return r;
                });
	}

	public function objects( sql : String, lock : Bool ) : List<T> {
		var me = this;
		var l = cnx.query(sql, function(rs){ return rs.results(); } );
		var l2 = new List<T>();
		for( x in l ) {
			var c = getFromCache(x,lock);
			if( c != null )
				l2.add(c);
			else {
				x = cacheObject(x,lock);
				make(x);
				l2.add(x);
			}
			x.__new = false;
		}
		return l2;
	}

	/* --------------------------- MISC API  ------------------------------ */

	inline function getLockMode() {
		return LOCKS[lock_mode];
	}

	public function setLockMode( exclusive, readShared ) {
		lock_mode = exclusive ? 2 : (readShared ? 1 : 0);
	}

	public function dbClass() : Class<Dynamic> {
		return cast class_proto;
	}

	/* --------------------------- INIT / CLEANUP ------------------------- */

	public static function initialize() {
		var l = init_list;
		init_list = new List();
		for( m in l ) {
			var rl : Void -> Array<Dynamic> = (cast m.class_proto).RELATIONS;
			if( rl != null )
				for( r in rl() )
					m.initRelation(r);
		}
	}

	public static function cleanup() {
		object_cache = new Hash();
	}

	function initRelation(r : { prop : String, key : String, manager : DBManager<DBObject>, lock : Bool } ) {
		// setup getter/setter
		var manager = r.manager;
		var hprop = "__"+r.prop;
		var hkey = r.key;
		var lock = r.lock;
		if( lock == null ) lock = true;
		if( manager == null || manager.table_keys == null ) throw ("Invalid manager for relation "+table_name+":"+r.prop);
		if( manager.table_keys.length != 1 ) throw ("Relation "+r.prop+"("+r.key+") on a multiple key table");
		Reflect.setField(class_proto.prototype,"get_"+r.prop,function() {
			var othis = untyped this;
			var f = Reflect.field(othis,hprop);
			if( f != null )
				return f;
			var id = Reflect.field(othis,hkey);
			f = manager.get(id,lock);
			// it's highly possible that in that case the object has been inserted
			// after we started our transaction : in that case, let's lock it, since
			// it's still better than returning 'null' while it exists
			if( f == null && id != null && !lock )
				f = manager.get(id,true);
			Reflect.setField(othis,hprop,f);
			return f;
		});
		Reflect.setField(class_proto.prototype,"set_"+r.prop,function(f) {
			var othis = untyped this;
			Reflect.setField(othis,hprop,f);
			Reflect.setField(othis,hkey,Reflect.field(f,manager.table_keys[0]));
			return f;
		});
		// remove prop from precomputed table_fields
		// always add key to table fields (even if not declared)
		table_fields.remove(r.prop);
		table_fields.remove(r.key);
		table_fields.push(r.key);
	}

	/* ---------------------------- OBJECT CACHE -------------------------- */

	function makeCacheKey( x : T ) : String {
		if( table_keys.length == 1 ) {
			var k = Reflect.field(x,table_keys[0]);
			if( k == null )
				throw("Missing key "+table_keys[0]);
			return Std.string(k)+table_name;
		}
		var s = new StringBuf();
		for( k in table_keys ) {
			var v = Reflect.field(x,k);
			if( k == null )
				throw("Missing key "+k);
			s.add(v);
			s.add("#");
		}
		s.add(table_name);
		return s.toString();
	}

	function addToCache( x : T ) {
		object_cache.set(makeCacheKey(x),x);
	}

	function removeFromCache( x : T ) {
		object_cache.remove(makeCacheKey(x));
	}

	function getFromCacheKey( key : String ) : T {
		return cast object_cache.get(key);
	}

	function getFromCache( x : T, lock : Bool ) : T {
		var c : Dynamic = object_cache.get(makeCacheKey(x));
		if( c != null && lock && c.__update ) {
			// restore update method since now the object is locked
			c.update = class_proto.prototype.update;
			// and synchronize the fields since our result is up-to-date !
			for( f in Reflect.fields(c) )
				Reflect.deleteField(c,f);
			for( f in Reflect.fields(x) )
				Reflect.setField(c,f,Reflect.field(x,f));
			// use the new object as our cache of fields
			Reflect.setField(c,cache_field,x);
			// remake object
			make(c);
		}
		return c;
	}

}

// vim: sw=8,noexpandtab
