///|
/// npm Promise rejection values are native errors. Preserve their identity and
/// expose domain failures through the same Error.message contract at the boundary.
fn[T] host_errors(promise : @core.Promise[T]) -> @core.Promise[T] {
  promise.catch_(fn(error) {
    let value = match error {
      FontError(message) =>
        @core.new(@core.global_this()._get("Error"), [@core.any(message)])
      @core.ThrowError(value) => value
      _ => @core.any(error)
    }
    @core.Promise::reject(value).to_any().cast()
  })
}
