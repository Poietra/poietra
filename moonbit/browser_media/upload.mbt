///|
fn error_value(message : String) -> @core.Any {
  @core.new(@core.global_this()._get("Error"), [@core.any(message)])
}

///|
pub fn upload_media(
  room : String,
  blob : @core.Any,
  signal : @core.Any,
  progress : @core.Any,
) -> @core.Promise[String] {
  @core.from_async(async fn() {
    check_abort(signal)
    report_import(progress, Uploading, 0.0)
    check_abort(signal)
    let xhr = @core.throwable(fn() {
      @core.new(@core.global_this()._get("XMLHttpRequest"), [])
    })
    let result : @core.PromiseResolvers[String] = @core.Promise::withResolvers()
    let settled = Ref(false)
    let reject = fn(value : @core.Any) {
      if !settled.val {
        settled.val = true
        result.reject(value.cast())
      }
    }
    let cancel = fn() { xhr._call("abort", []) |> ignore }
    defer {
      settled.val = true
      if !@core.is_nullish(signal) {
        signal._call("removeEventListener", [
          @core.any("abort"),
          @core.any(cancel),
        ])
        |> ignore
      }
      for event in ["onload", "onerror", "ontimeout", "onabort"] {
        xhr._set(event, @core.null())
      }
      xhr._get("upload")._set("onprogress", @core.null())
    }
    @core.throwable(fn() {
      xhr._call("open", [
        @core.any("POST"),
        @core.any("/api/rooms/" + room + "/media"),
      ])
      |> ignore
      xhr._set("timeout", @core.any(120000))
      xhr._call("setRequestHeader", [
        @core.any("Content-Type"),
        blob._get("type"),
      ])
      |> ignore
      xhr._set(
        "onload",
        @core.any(fn() {
          if settled.val {
            return
          }
          @core.throwable(fn() {
            let data = @core.throwable(fn() {
              @core.global_this()
              ._get("JSON")
              ._call("parse", [xhr._get("responseText")])
            }) catch {
              _ => @core.undefined()
            }
            let valid_object = !@core.is_nullish(data) &&
              @core.typeof_(data) == "object"
            let source = if valid_object {
              data._get("src")
            } else {
              @core.undefined()
            }
            let status : Int = xhr._get("status").cast()
            if status >= 200 &&
              status < 300 &&
              @core.typeof_(source) == "string" &&
              @assets.room_source(source.cast(), @assets.Media) {
              settled.val = true
              result.resolve(source.cast())
            } else {
              let error = if valid_object {
                data._get("error")
              } else {
                @core.undefined()
              }
              let message = if @core.typeof_(error) == "string" &&
                !@core.equal(error, @core.any("")) {
                error.cast()
              } else {
                "素材を保存できませんでした。接続を確認して再試行してください。"
              }
              reject(error_value(message))
            }
          }) catch {
            error => reject(native_error(error))
          }
        }),
      )
      let failed = fn() {
        reject(
          error_value(
            "素材のアップロードに失敗しました。接続を確認して再試行してください。",
          ),
        )
      }
      xhr._set("onerror", @core.any(failed))
      xhr._set("ontimeout", @core.any(failed))
      xhr._set(
        "onabort",
        @core.any(fn() {
          reject(
            @core.new(@core.global_this()._get("DOMException"), [
              @core.any("素材の追加を中止しました。"),
              @core.any("AbortError"),
            ]),
          )
        }),
      )
      xhr
      ._get("upload")
      ._set(
        "onprogress",
        @core.any(fn(event : @core.Any) {
          if settled.val {
            return
          }
          try {
            let computable : Bool = event._get("lengthComputable").cast()
            let loaded : Double = event._get("loaded").cast()
            let total : Double = event._get("total").cast()
            report_import(
              progress,
              if computable && loaded >= total {
                Saving
              } else {
                Uploading
              },
              if computable {
                loaded / total
              } else {
                0.0
              },
            )
          } catch {
            error => {
              reject(native_error(error))
              cancel()
            }
          }
        }),
      )
      if !@core.is_nullish(signal) {
        signal._call("addEventListener", [
          @core.any("abort"),
          @core.any(cancel),
          @core.from_entries([("once", @core.any(true))]),
        ])
        |> ignore
      }
    })
    check_abort(signal)
    @core.throwable(fn() { xhr._call("send", [blob]) }) |> ignore
    let source = result.promise.wait()
    check_abort(signal)
    source
  })
  |> native_errors
}
