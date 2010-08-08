class HE {

  // this should be included in the compiler !
  static public function tryFinally<R>(body: Void -> R, finally_: Void -> Void):R{
    try {
      var r = body();
      finally_();
      return r;
    } catch(e:Dynamic){
      finally_();
      neko.Lib.rethrow(e);
    }
    return null;
  }

}
