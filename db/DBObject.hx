package db;
import Reflect;
import db.DBManager;

// this corresponds to neko.db.Object
// all mapped ojbects should expand this interface

class DBObject {

  // if set to true this object was select by a FOR UPDATE query
  // this usually means that the value does no longer change within this
  // transaction
  // I don't know yet wether this really makes sense
  // This hould be reset to false if a transaction ends.
  // I put it in because SPODS have it. I'm not too sure how much sense it makes
  public var __update: Bool; 

  // new objcet? new objects have not been written to the database yet
  public var __new: Bool;

  public function new() {
    __new = true;
#if php
    // only required for PHP?
    local_manager = cast(DBManager.managers.get(Type.getClassName(Type.getClass(this))));
#end
  }

  var local_manager : {
    private function doStore( o : DBObject ) : DBObject;
    private function doSync( o : DBObject ) : DBObject;
    private function doDelete( o : DBObject ) : Void;
    private function objectToString( o : DBObject ) : String;
  };


  // dirty implementation. An object is called dirty if a field which is stored {{{
  // in db changed but the object has not been stored to database yet

  // if dirty a property was changed by the user. This means it should be
  // written back to the database because adding getters and setters marking
  // the object is dirty is tedious haxe-dbtool will create that code for you
  public var __dirty_data:Bool; // a field was changed

  // }}}

  public function delete() {
    local_manager.doDelete(this);
  }

  public function toString() {
    return local_manager.objectToString(this);
  }

}
