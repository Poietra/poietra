///|
fn save_blob(blob : @core.Any, filename : String) -> Unit raise {
  let global = @core.global_this()
  let urls = global._get("URL")
  let url = @core.throwable(fn() { urls._call("createObjectURL", [blob]) })
  errdefer urls._call("revokeObjectURL", [url]) |> ignore
  @core.throwable(fn() {
    let anchor = global
      ._get("document")
      ._call("createElement", [@core.any("a")])
    anchor._set("href", url)
    anchor._set("download", @core.any(filename))
    anchor._call("click", []) |> ignore
    global._call("setTimeout", [
      @core.any(fn() { urls._call("revokeObjectURL", [url]) |> ignore }),
      @core.any(60000),
    ])
    |> ignore
  })
}

///|
extern "js" fn ui_throw(value : @core.Any) -> Unit =
  #|value => { throw value; }

///|
pub fn download_blob(blob : @core.Any, filename : String) -> Unit {
  save_blob(blob, filename) catch {
    error => ui_throw(ui_native_error(error))
  }
}

///|
extern "js" fn fixed_number(value : Double, digits : Int) -> String =
  #|(value, digits) => value.toFixed(digits)
