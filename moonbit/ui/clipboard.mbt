///|
priv struct PasteJob {
  input : ClipboardInput
  request : @core.Any
}

///|
priv struct ClipboardController {
  mut input : ClipboardInput
  mut mounted : Bool
  mut history : @editor.PasteHistory?
  mut job : PasteJob?
}

///|
let object_clipboard_mime : String = "application/x-poietra-objects+json"

///|
fn clipboard_allowed(input : ClipboardInput, event : @core.Any) -> Bool {
  !@core.is_nullish(input.controls.scene) &&
  !(input.controls.composing.get_current() == Some(true)) &&
  !shortcut_text_target(event._get("target")) &&
  !selected_page_text() &&
  !@core.is_nullish(event._get("clipboardData"))
}

///|
fn ClipboardController::same_target(
  self : ClipboardController,
  input : ClipboardInput,
) -> Bool {
  let current = self.input
  self.mounted &&
  @core.equal(current.controls.store, input.controls.store) &&
  !@core.is_nullish(current.controls.scene) &&
  @core.equal(
    current.controls.scene._get("id"),
    input.controls.scene._get("id"),
  ) &&
  @core.equal(
    @core.any(current.controls.composition_id),
    @core.any(input.controls.composition_id),
  ) &&
  !current.controls.viewing_playback
}

///|
fn ClipboardController::release(
  self : ClipboardController,
  job : PasteJob,
) -> Unit {
  if job.input.image_request
    .get_current()
    .map(fn(request) { @core.equal(request, job.request) })
    .unwrap_or(false) {
    job.input.image_request.set_current(None)
    if self.mounted {
      (job.input.set_importing_image)(false)
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
  let active : FixedArray[String] = input.controls.active_ids
  if active.is_empty() {
    return
  }
  if input.controls.viewing_playback {
    prevent_default(event)
    (input.controls.actions.notify)(
      "編集する場面を開いてからコピーしてください。",
    )
    return
  }
  let store = input.controls.store
  let scene_id = input.controls.scene._get("id")
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
  let data = @boundary.copy_objects(current, input.controls.composition_id, ids)
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
        @core.any(input.controls.composition_id),
        @core.any(ids),
      ])
      |> ignore
      (input.controls.actions.set_selected_ids)(([] : FixedArray[String]))
    }
    (input.controls.actions.notify)(
      "\{objects.length()} 個のオブジェクトを" +
      (if cut { "切り取りました" } else { "コピーしました" }),
    )
  }) catch {
    error => {
      prevent_default(event)
      (input.controls.actions.notify)(
        error_message(
          ui_native_error(error),
          "コピーできませんでした",
        ),
      )
    }
  }
}

///|
async fn ClipboardController::prepare_paste(
  self : ClipboardController,
  input : ClipboardInput,
  objects : FixedArray[@core.Any],
) -> Bool {
  if input.image_request.get_current() is Some(_) ||
    input.media_request.get_current() is Some(_) {
    (input.controls.actions.notify)(
      "素材の保存が終わってから貼り付けてください。",
    )
    return false
  }
  let controller = new_controller()
  let signal = controller._get("signal")
  let request = host_record({
    "sceneId": input.controls.scene._get("id"),
    "compositionId": @core.any(input.controls.composition_id),
    "controller": controller,
  })
  let job : PasteJob = { input, request, }
  self.job = Some(job)
  input.image_request.set_current(Some(request))
  (input.set_importing_image)(true)
  defer self.release(job)
  let completed = try {
    (input.rehost_images)(
      objects,
      input.controls.store._get("roomId").cast(),
      signal,
    )
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
  input.image_request
  .get_current()
  .map(fn(current) { @core.equal(current, request) })
  .unwrap_or(false)
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
    (input.import_files)(files, None)
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
  let in_place = input.controls.paste_in_place.get_current() == Some(true)
  input.controls.paste_in_place.set_current(Some(false))
  @core.from_async(async fn() {
    try {
      let data = @core.throwable(fn() { @boundary.parse_objects(text) })
      if @core.is_nullish(data) {
        return
      }
      prevent_default(event)
      if input.controls.viewing_playback {
        (input.controls.actions.notify)(
          "編集する場面を開いてから貼り付けてください。",
        )
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
      let scene : String = input.controls.scene._get("id").cast()
      let composition : String = input.controls.composition_id
      let (history, offset) = @editor.next_paste(
        self.history,
        text,
        scene,
        composition,
        in_place,
      )
      let ids : FixedArray[String] = @core.throwable(fn() {
        input.controls.store
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
      (current.controls.actions.set_selected_ids)(ids)
      (current.controls.actions.set_tool)(@editor.SelectTool)
      key_select_composition(current.controls, composition)
      (current.controls.actions.notify)(
        "\{ids.length()} 個のオブジェクトを貼り付けました",
      )
    } catch {
      error => {
        prevent_default(event)
        if self.same_target(input) {
          (self.input.controls.actions.notify)(
            error_message(
              ui_native_error(error),
              "貼り付けできませんでした",
            ),
          )
        }
      }
    }
  })
  |> ignore
}

///|
fn use_clipboard_controls(input : ClipboardInput) -> Unit {
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
    [input.controls.store],
  )
}

///|
pub fn use_editor_clipboard(input : @core.Any) -> Unit {
  use_clipboard_controls(read_native_clipboard(input))
}
