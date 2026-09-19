///|
priv struct PasteJob {
  input : @core.Any
  request : @core.Any
}

///|
priv struct ClipboardController {
  mut input : @core.Any
  mut mounted : Bool
  mut history : @editor.PasteHistory?
  mut job : PasteJob?
}

///|
let object_clipboard_mime : String = "application/x-poietra-objects+json"

///|
fn clipboard_allowed(input : @core.Any, event : @core.Any) -> Bool {
  !@core.is_nullish(input._get("scene")) &&
  !truthy(input._get("composing")._get("current")) &&
  !shortcut_text_target(event._get("target")) &&
  !selected_page_text() &&
  !@core.is_nullish(event._get("clipboardData"))
}

///|
fn ClipboardController::same_target(
  self : ClipboardController,
  input : @core.Any,
) -> Bool {
  let current = self.input
  self.mounted &&
  @core.equal(current._get("store"), input._get("store")) &&
  !@core.is_nullish(current._get("scene")) &&
  @core.equal(current._get("scene")._get("id"), input._get("scene")._get("id")) &&
  @core.equal(current._get("compositionId"), input._get("compositionId")) &&
  !truthy(current._get("transportView"))
}

///|
fn ClipboardController::release(
  self : ClipboardController,
  job : PasteJob,
) -> Unit {
  if @core.equal(job.input._get("imageRequest")._get("current"), job.request) {
    job.input._get("imageRequest")._set("current", @core.null())
    if self.mounted {
      key_callback(job.input, "setImportingImage", [@core.any(false)])
    }
  }
  if self.job is Some(current) && physical_equal(current, job) {
    self.job = None
  }
}

///|
fn ClipboardController::copy(
  self : ClipboardController,
  event : @core.Any,
) -> Unit {
  let input = self.input
  if !clipboard_allowed(input, event) {
    return
  }
  let active : FixedArray[String] = input._get("activeIds").cast()
  if active.is_empty() {
    return
  }
  if truthy(input._get("transportView")) {
    prevent_default(event)
    key_callback(input, "notify", [
      @core.any(
        "編集する場面を開いてからコピーしてください。",
      ),
    ])
    return
  }
  let store = input._get("store")
  let scene_id = input._get("scene")._get("id")
  let current = store._call("scene", [scene_id])
  let cut = @core.equal(event._get("type"), @core.any("cut"))
  let ids = active
    .iter()
    .filter(fn(id) {
      let object = current._get("objects")._get(id)
      !cut || @core.is_nullish(object) || !truthy(object._get("locked"))
    })
    .to_array()
  let ids = FixedArray::from_array(ids[:])
  let data = @boundary.copy_objects(
    current,
    input._get("compositionId").cast(),
    ids,
  )
  let objects : FixedArray[@core.Any] = data._get("objects").cast()
  if objects.is_empty() {
    return
  }
  @core.throwable(fn() {
    let text = @boundary.serialize_objects(data)
    let clipboard = event._get("clipboardData")
    clipboard._call("setData", [
      @core.any(object_clipboard_mime),
      @core.any(text),
    ])
    |> ignore
    clipboard._call("setData", [@core.any("text/plain"), @core.any(text)])
    |> ignore
    prevent_default(event)
    self.history = None
    if cut {
      store._call("hide", [
        scene_id,
        input._get("compositionId"),
        @core.any(ids),
      ])
      |> ignore
      key_callback(input, "setSelectedIds", [
        @core.any(([] : FixedArray[String])),
      ])
    }
    key_callback(input, "notify", [
      @core.any(
        "\{objects.length()} 個のオブジェクトを" +
        (if cut { "切り取りました" } else { "コピーしました" }),
      ),
    ])
  }) catch {
    error => {
      prevent_default(event)
      key_callback(input, "notify", [
        @core.any(
          error_message(
            ui_native_error(error),
            "コピーできませんでした",
          ),
        ),
      ])
    }
  }
}

///|
async fn ClipboardController::prepare_paste(
  self : ClipboardController,
  input : @core.Any,
  objects : FixedArray[@core.Any],
) -> Bool {
  if !@core.is_nullish(input._get("imageRequest")._get("current")) ||
    !@core.is_nullish(input._get("mediaRequest")._get("current")) {
    key_callback(input, "notify", [
      @core.any(
        "素材の保存が終わってから貼り付けてください。",
      ),
    ])
    return false
  }
  let controller = new_controller()
  let signal = controller._get("signal")
  let request = host_record({
    "sceneId": input._get("scene")._get("id"),
    "compositionId": input._get("compositionId"),
    "controller": controller,
  })
  let job : PasteJob = { input, request, }
  self.job = Some(job)
  input._get("imageRequest")._set("current", request)
  key_callback(input, "setImportingImage", [@core.any(true)])
  defer self.release(job)
  let completed = try {
    ui_call(input, "rehostImageAssets", [
      @core.any(objects),
      input._get("store")._get("roomId"),
      signal,
    ])
    |> ignore
    Ok(())
  } catch {
    error => Err(error)
  }
  if completed is Err(error) {
    if ui_aborted(signal) {
      return false
    }
    raise error
  }
  !ui_aborted(signal) &&
  self.same_target(input) &&
  @core.equal(input._get("imageRequest")._get("current"), request)
}

///|
fn ClipboardController::paste(
  self : ClipboardController,
  event : @core.Any,
) -> Unit {
  let input = self.input
  if !clipboard_allowed(input, event) {
    return
  }
  let clipboard = event._get("clipboardData")
  let files : FixedArray[@core.Any] = @core.global_this()
    ._get("Array")
    ._call("from", [clipboard._get("files")])
    .cast()
  if !files.is_empty() {
    prevent_default(event)
    key_callback(input, "importFiles", [@core.any(files)])
    return
  }
  let text : String = clipboard
    ._call("getData", [@core.any(object_clipboard_mime)])
    .cast()
  let text : String = if text.is_empty() {
    clipboard._call("getData", [@core.any("text/plain")]).cast()
  } else {
    text
  }
  let in_place = truthy(input._get("pasteInPlace")._get("current"))
  input._get("pasteInPlace")._set("current", @core.any(false))
  @core.from_async(async fn() {
    try {
      let data = @core.throwable(fn() { @boundary.parse_objects(text) })
      if @core.is_nullish(data) {
        return
      }
      prevent_default(event)
      if truthy(input._get("transportView")) {
        key_callback(input, "notify", [
          @core.any(
            "編集する場面を開いてから貼り付けてください。",
          ),
        ])
        return
      }
      let objects : FixedArray[@core.Any] = data._get("objects").cast()
      if objects
        .iter()
        .any(fn(object) {
          !@core.is_nullish(object._get("image")) ||
          !@core.is_nullish(object._get("media"))
        }) &&
        !self.prepare_paste(input, objects) {
        return
      }
      if !self.same_target(input) {
        return
      }
      let scene : String = input._get("scene")._get("id").cast()
      let composition : String = input._get("compositionId").cast()
      let (history, offset) = @editor.next_paste(
        self.history,
        text,
        scene,
        composition,
        in_place,
      )
      let ids : FixedArray[String] = @core.throwable(fn() {
        input
        ._get("store")
        ._call("paste", [
          @core.any(scene),
          @core.any(composition),
          data,
          @core.any(offset),
        ])
        .cast()
      })
      self.history = Some(history)
      let current = self.input
      key_callback(current, "setSelectedIds", [@core.any(ids)])
      key_callback(current, "setTool", [@core.any("select")])
      key_select_composition(current, composition)
      key_callback(current, "notify", [
        @core.any(
          "\{ids.length()} 個のオブジェクトを貼り付けました",
        ),
      ])
    } catch {
      error => {
        prevent_default(event)
        if self.same_target(input) {
          key_callback(self.input, "notify", [
            @core.any(
              error_message(
                ui_native_error(error),
                "貼り付けできませんでした",
              ),
            ),
          ])
        }
      }
    }
  })
  |> ignore
}

///|
pub fn use_editor_clipboard(input : @core.Any) -> Unit {
  let owner = @react.use_ref((None : ClipboardController?))
  let controller = match owner.get_current() {
    Some(controller) => controller
    None => {
      let controller : ClipboardController = {
        input,
        mounted: false,
        history: None,
        job: None,
      }
      owner.set_current(Some(controller))
      controller
    }
  }
  controller.input = input
  @react.use_effect(
    fn() {
      controller.mounted = true
      let window = @core.global_this()
      let copy = fn(event : @core.Any) { controller.copy(event) }
      let paste = fn(event : @core.Any) { controller.paste(event) }
      let handlers = [
        ("copy", @core.any(copy)),
        ("cut", @core.any(copy)),
        ("paste", @core.any(paste)),
      ]
      for handler in handlers {
        let (name, callback) = handler
        window._call("addEventListener", [@core.any(name), callback]) |> ignore
      }
      fn() {
        controller.mounted = false
        for handler in handlers {
          let (name, callback) = handler
          window._call("removeEventListener", [@core.any(name), callback])
          |> ignore
        }
        if controller.job is Some(job) {
          job.request._get("controller")._call("abort", []) |> ignore
          controller.release(job)
        }
      }
    },
    [input._get("store")],
  )
}
