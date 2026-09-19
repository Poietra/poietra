///|
priv suberror BrowserFailure {
  BrowserFailure(@core.Any)
}

///|
/// npm Promise rejection values are native errors. Preserve their identity and
/// expose domain failures through the same Error.message contract at the boundary.
fn host_error(error : Error) -> @core.Any {
  match error {
    FontError(message) =>
      @core.new(@core.global_this()._get("Error"), [@core.any(message)])
    @core.ThrowError(value) => value
    BrowserFailure(value) => value
    _ => @core.any(error)
  }
}

///|
fn[T] host_errors(promise : @core.Promise[T]) -> @core.Promise[T] {
  promise.catch_(fn(error) {
    @core.Promise::reject(host_error(error)).to_any().cast()
  })
}
