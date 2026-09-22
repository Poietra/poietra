///|
fn flush_documents(store : @core.Any) -> Unit {
  let provider = store._get("provider")
  if !@core.is_nullish(provider) {
    let socket = provider._get("ws")
    if !@core.is_nullish(socket) &&
      @core.typeof_(socket._get("flushDocuments")) == "function" {
      socket._call("flushDocuments", []) |> ignore
    }
  }
}

///|
fn StoreSession::watch_page(self : StoreSession) -> Unit {
  let global = @core.global_this()
  let document = global._get("document")
  let hidden = fn() {
    !@core.is_nullish(document) &&
    @core.equal(document._get("visibilityState"), @core.any("hidden"))
  }
  self.page_suspended = hidden()
  for
    (target, event) in [
      (global, "pagehide"),
      (global, "pageshow"),
      (document, "visibilitychange"),
    ] {
    if @core.is_nullish(target) ||
      @core.typeof_(target._get("addEventListener")) != "function" {
      continue
    }
    let callback = @core.any(fn() {
      if !self.destroyed {
        // Later pagehide handlers (for example chat cancellation) can still
        // write to Yjs. Send those immediately: their timers may never run.
        self.page_suspended = match event {
          "pagehide" => true
          _ => hidden()
        }
        self.flush_presence()
        flush_documents(self.store)
      }
    })
    target._call("addEventListener", [@core.any(event), callback]) |> ignore
    self.cleanup.push(fn() {
      target._call("removeEventListener", [@core.any(event), callback])
      |> ignore
    })
  }
}
