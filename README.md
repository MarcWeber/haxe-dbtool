== haxe-dbtool - a small library writing both: the SPOD objects and SQL queries

Example:

    var dbTool =
        new DBTool(
          cnx,                           // the connection to the database
          {pathPrefix:"haxe/", fqn: ""}, // where to store the object containing the scheme updates
          "dbobjects"                    // package name of SPODs
      );


    dbTool.addTable("customers", [
        new DBField("id", db_int).uniq(),
        new DBField("firstname", db_varchar(50)),
        new DBField("lastname", db_varchar(50)),
        new DBField("last_login", db_date),
        new DBField("registered", db_date_auto(true, false)),
        new DBField("record_changed", db_date_auto(true, true)),
    ]);

    dbTool.addTable("customer_logins", [
        new DBField("customer_id", db_int).references("customers","id"),
    ]);

If you run

    dbTool.prepareUpdate();

haxe-dbtool will create a haxe/DBUpdatePostgreSQL.hx file for you:


    class DBUpdatePostgreSQL {
      static function request(db, sql){ /* run the query - log on failure */ }
    // scheme0:n
      static public function scheme1(db: neko.db.Connection){
        request(db, 
          "CREATE TABLE db_version(
          version int UNIQUE  NOT NULL 
          ,hash_of_serialized_scheme varchar(32) NOT NULL 
          ) WITH OIDS;
        ");
        request(db, 
          "CREATE TABLE customers(
          id int UNIQUE  NOT NULL 
          ,firstname varchar(50) NOT NULL 
          ,lastname varchar(50) NOT NULL 
          ,last_login timestamp  NOT NULL 
          ,registered timestamp  NOT NULL  default CURRENT_TIMESTAMP 
          ,record_changed timestamp  NOT NULL  default CURRENT_TIMESTAMP 
          ) WITH OIDS;
        ");
        // trigger code for Postgresql db updating the date fields

        request(db, 
            "CREATE TABLE customer_logins(
            customer_id int NOT NULL  REFERENCES customers(id)
            ) WITH OIDS;
        ");
        db.request("INSERT INTO db_version (version, hash_of_serialized_scheme) VALUES (1, "+db.quote("521c5360601ac67da43484ef06be3fdf")+")");
      }
    // scheme1:oy6:tablesacy10:db.DBTabley11:primaryKeysny4:namey10:db_versiony6:fie [ .. serialized scheme representation ]


    }

Note that dbtool also added db_version table which keeps track of
scheme applied to the database. The hash_of_serialized_scheme contains a hash
of the current database schema. You'll learn soon about its purpose. Just note
that at the end of scheme1 the db_version table is updated to reflect the
change.

// TODO SPOD objects will be created as well in the near future

Let's play around and add another field called landing_page:
 

        dbTool.addTable("customer_logins", [
            new DBField("customer_id", db_int).references("customers","id"),
    +       new DBField("landing_page", db_varchar(200)),
        ]);

Rerunning dbTool.prepareUpdate(); will now read the old known scheme which is
represented in the update method scheme1 above from the comment. Then it'll create
a diff to reach the target scheme. This diff is written into the scheme2 method:

The DBUpdatePostgreSQL class got a new method:

      static public function scheme2(db: neko.db.Connection){
        var expectedHash = "521c5360601ac67da43484ef06be3fdf";
        if ( expectedHash != db.request("SELECT hash_of_serialized_scheme FROM db_version WHERE version = 1").getResult(0)){
          throw "wrong branch ? refusing to update. Expected scheme hash :"+expectedHash + ", version 1. Set this hash in the version table to continue";
        request(db, 
          "ALTER TABLE customer_logins ADD COLUMN landing_page varchar(200) NOT NULL ");
        db.request("INSERT INTO db_version (version, hash_of_serialized_scheme) VALUES (2, "+db.quote("ec8b2fbea8ec1e67aefbfedfb6e201af")+")");
      }
    // scheme2:oy6:tablesacy10:db.DBTabley11:primaryKeysny4:namey10:db_versiony6:fieldsacy10:db.DBFieldR3y7:versiony4:typewy18:db.DBToolFieldTypey6:db_int:0y12:__referencesny11:__autovalueny8:nullablefy6:__uniqty9:__indexedny9:__defaultny9:__commentngcR6R3y25:hash_of_serialized_schemeR8wR9y10:db_varchar:1i32R11nR12nR13fR14nR15nR16nR17nghgcR1R2nR3y9:customersR5acR6R3y2:idR8wR9R10:0R11nR12nR13fR14tR15nR16nR17ngcR6R3y9:firstnameR8wR9R19:1i50R11nR12nR13fR14nR15nR16nR17ngcR6R3y8:lastnameR8wR9R19:1i50R11nR12nR13fR14nR15nR16nR17ngcR6R3y10:last_loginR8wR9y7:db_date:0R11nR12nR13fR14nR15nR16nR17ngcR6R3y10:registeredR8wR9y12:db_date_auto:2tfR11nR12nR13fR14nR15nR16nR17ngcR6R3y14:record_changedR8wR9R27:2ttR11nR12nR13fR14nR15nR16nR17nghgcR1R2nR3y15:customer_loginsR5acR6R3y11:customer_idR8wR9R10:0R11oy5:tableR20y5:fieldR21gR12nR13fR14nR15nR16nR17ngcR6R3y12:landing_pageR8wR9R19:1i200R11nR12nR13fR14nR15nR16nR17nghghg

Now you can see that dbtool created the ALTER TABLE .. ADD COLUMN sql line for you.
You can also see that it first checks that the actual database scheme hash
is equal to the expected hash. The hash is simply the md5sum of the serialized
scheme description. If you have two independent branches, one adding scheme2(a)
and another adding a different scheme2(b) and scheme3 this prevents applying
scheme3 on scheme2(a).

You learned how dbtool creates scheme update methods automatically. How to
apply them now? doUpdate will run them all. The class is loaded (by Reflection
API) and all scheme methods newer than the last one found in db are applied.
Example:

    dbTool.doUpdate()

Usually you want to tweak the update step before running it. Eg you can add
additionaly HaXe code for whatever reason.


ATTENTION: The syntax changed slightly. See comments top of DBTool.hx - and read source :)


== RUN TEST SUITE ==

a) real-world-test:

      cd real-world-test/
      cp mysql-connection.txt.example mysql-connection.txt
      cp postgresql-connection.txt.example postgresql-connection.txt
      $EDITOR mysql-connection.txt postgresql-connection.txt
      bash test.sh

b) simple test suite for DBConnection

Create a file with these contents:

      localhost
      3306
      MYSQL_USER
      MYSQL_PASSWORD

      MYSQL_DATABASE

Then run

      haxe tests_php.hxml
      php dist-php/Test.php


== THIS IS WORK IN PROGRESS ==
So expect
  * API changes
  * incomplete implementation

TODO:
  throw Exceptions if Strings are used which are too long
