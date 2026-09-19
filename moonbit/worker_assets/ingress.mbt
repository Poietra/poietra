///|
priv struct Ingress {
  reader : @streams.ReadableStreamDefaultReader
  mut pending : @core.Promise[@core.Any]?
  mut stopped : Bool
  mut ended : Bool
  mut size : Double
  limit : Int
}

///|
fn Ingress::read(self : Ingress) -> @core.Promise[@core.Any] {
  match self.pending {
    Some(promise) => promise
    None => {
      let promise = @core.from_async(async fn() {
        defer {
          self.pending = None
        }
        let result = self.reader.read()
        self.ended = result._get("done").cast()
        if !self.ended {
          self.size += (result._get("value")._get("byteLength").cast() : Double)
        }
        result
      })
      self.pending = Some(promise)
      promise
    }
  }
}

///|
async fn Ingress::close(self : Ingress) -> Unit {
  self.stopped = true
  let timeout : @core.PromiseResolvers[@core.Any] = @core.Promise::withResolvers()
  let timer = @core.global_this()._call("setTimeout", [
    @core.any(fn() {
      timeout.reject(
        @core.new(@core.global_this()._get("Error"), [
          @core.any("Upload drain deadline"),
        ]).cast(),
      )
    }),
    @core.any(2000),
  ])
  defer @core.global_this()._call("clearTimeout", [timer]) |> ignore
  defer self.reader.release_lock()
  try {
    while !self.ended && self.size <= (self.limit + 131072).to_double() {
      let race : @core.Promise[@core.Any] = @core.global_this()
        ._get("Promise")
        ._call("race", [
          @core.any(
            (
              [self.read(), timeout.promise] :
              FixedArray[@core.Promise[@core.Any]]),
          ),
        ])
        .cast()
      race.wait() |> ignore
    }
  } catch {
    _ => ()
  }
  if !self.ended {
    self.reader.cancel() catch {
      _ => ()
    }
  }
}

///|
fn ingress(
  request : @web.Request,
  limit : Int,
) -> (@web.Request, Ingress?) raise {
  let body = request.as_any()._get("body")
  if @core.is_nullish(body) {
    return (request, None)
  }
  let stream : @streams.ReadableStream = body.cast()
  let input : Ingress = {
    reader: @core.throwable(fn() { stream.get_reader() }),
    pending: None,
    stopped: false,
    ended: false,
    size: 0.0,
    limit,
  }
  let source = @core.from_entries([
    (
      "pull",
      @core.any(fn(controller : @core.Any) {
        @core.from_async(async fn() {
          try {
            let result = input.read().wait()
            if !input.stopped {
              @core.throwable(fn() {
                if input.ended {
                  controller._call("close", []) |> ignore
                } else {
                  controller._call("enqueue", [result._get("value")]) |> ignore
                }
              })
            }
          } catch {
            error =>
              if !input.stopped {
                controller._call("error", [@http.native_error(error)]) |> ignore
              }
          }
        })
        |> @http.native_errors
      }),
    ),
    ("cancel", @core.any(fn() { input.stopped = true })),
  ])
  let wrapped = @core.new(@core.global_this()._get("ReadableStream"), [source])
  let request : @web.Request = @core.throwable(fn() {
    @core.new(@core.global_this()._get("Request"), [
      request.as_any(),
      @core.from_entries([("body", wrapped), ("duplex", @core.any("half"))]),
    ]).cast()
  })
  (request, Some(input))
}
