///|
priv enum MotionAction {
  SaveMotion(@core.Any)
  ReadMotion(@core.Any)
  InsertMotion(@scene.Scene)
}

///|
priv struct MotionView {
  name : String
  source : @scene.Scene?
  parameters : Array[@editor.MotionParameter]
  page : Int
  texts : Map[String, String]
  colors : Map[String, String]
  message : String
  busy : String?
}

///|
priv struct MotionRequest {
  controller : @core.Any
  store : @core.Any
  scene : String
}

///|
priv struct MotionSession {
  mut input : @core.Any
  mut view : MotionView
  mut mounted : Bool
  mut job : MotionRequest?
  publish : (MotionView) -> Unit
}

///|
fn MotionSession::update(self : MotionSession, view : MotionView) -> Unit {
  self.view = view
  if self.mounted {
    (self.publish)(view)
  }
}

///|
fn MotionSession::owns(self : MotionSession, request : MotionRequest) -> Bool {
  self.mounted &&
  truthy(self.input._get("open")) &&
  self.job.map(fn(job) { physical_equal(job, request) }).unwrap_or(false) &&
  @core.equal(self.input._get("store"), request.store) &&
  @core.equal(self.input._get("scene")._get("id"), @core.any(request.scene)) &&
  !truthy(request.controller._get("signal")._get("aborted"))
}

///|
fn MotionSession::cancel(self : MotionSession) -> Unit {
  let previous = self.job
  self.job = None
  if previous is Some(request) {
    request.controller._call("abort", []) |> ignore
  }
  self.update({ ..self.view, busy: None, })
}

///|
fn MotionSession::start(self : MotionSession, action : MotionAction) -> Unit {
  if !self.mounted || self.job is Some(_) {
    return
  }
  let controller = @core.new(@core.global_this()._get("AbortController"), [])
  let signal = controller._get("signal")
  let input = self.input
  let store = input._get("store")
  let scene_id : String = input._get("scene")._get("id").cast()
  let request : MotionRequest = { controller, store, scene: scene_id, }
  self.job = Some(request)
  self.update({
    ..self.view,
    message: "",
    busy: Some(
      match action {
        SaveMotion(_) =>
          "素材を含む動きのファイルを保存しています…"
        ReadMotion(_) => "動きのファイルを読み込んでいます…"
        InsertMotion(_) =>
          "素材を準備して動きを挿入しています…"
      },
    ),
  })
  @core.from_async(async fn() {
    defer (if self.owns(request) {
      self.job = None
      self.update({ ..self.view, busy: None, })
    })
    try {
      match action {
        SaveMotion(project) => {
          let snapshot = ui_call(input._get("services"), "portableProject", [
            project, signal,
          ])
          if !self.owns(request) {
            return
          }
          let text : String = @core.throwable(fn() {
            @core.global_this()
            ._get("JSON")
            ._call("stringify", [snapshot, @core.null(), @core.any(2)])
            .cast()
          })
          let blob = @core.throwable(fn() {
            @core.new(@core.global_this()._get("Blob"), [
              @core.any(([text] : FixedArray[String])),
              host_record({ "type": @core.any("application/json") }),
            ])
          })
          save_blob(
            blob,
            project_filename(string_value(snapshot._get("name")) + ".motion"),
          )
          self.update({
            ..self.view,
            message: "動きのファイルを保存しました。別の Scene で読み込んで再利用できます。",
          })
        }
        ReadMotion(file) => {
          if (file._get("size").cast() : Double) > 134217728.0 {
            project_action_error(
              "動きのファイルは 128 MB 以下にしてください。",
            )
          }
          let text : String = ui_call(file, "text", []).cast()
          if !self.owns(request) {
            return
          }
          let source = @core.throwable(fn() { @boundary.read_motion_file(text) })
          self.update({
            ..self.view,
            source: Some(source),
            parameters: @editor.motion_parameters(source),
            page: 0,
            texts: Map([]),
            colors: Map([]),
            message: "",
          })
        }
        InsertMotion(source) => {
          let project = @boundary.motion_project(source)
          let objects = project._get("scenes")._get(source.id)._get("objects")
          ui_call(input._get("services"), "rehostImageAssets", [
            @core.any(
              FixedArray::from_array(
                @core.object_keys(objects).map(fn(id) { objects._get(id) })[:],
              ),
            ),
            store._get("roomId"),
            signal,
          ])
          |> ignore
          if !self.owns(request) {
            return
          }
          let result = @core.throwable(fn() {
            store._call("insertMotion", [@core.any(scene_id), project])
          })
          // Clear the active request before closing the dialog through its owner.
          self.job = None
          self.update({
            ..self.view,
            busy: None,
            message: "動きを挿入しました。",
          })
          @core.throwable(fn() { input._get("onInserted")._invoke([result]) })
          |> ignore
        }
      }
    } catch {
      error =>
        if self.owns(request) {
          self.update({
            ..self.view,
            message: error_message(
              ui_native_error(error),
              "動きを処理できませんでした。",
            ),
          })
        }
    }
  })
  |> ignore
}

///|
fn motion_library(input : @core.Any) -> @react.Element {
  let (view, publish) = @react.use_state(MotionView::{
    name: "Reusable motion",
    source: None,
    parameters: [],
    page: 0,
    texts: Map([]),
    colors: Map([]),
    message: "",
    busy: None,
  })
  let owner = @react.use_ref((None : MotionSession?))
  let self = match owner.get_current() {
    Some(self) => self
    None => {
      let self : MotionSession = {
        input,
        view,
        mounted: false,
        job: None,
        publish,
      }
      owner.set_current(Some(self))
      self
    }
  }
  self.input = input
  let file = @react.use_ref((None : @core.Any?))
  @react.use_effect(
    fn() {
      self.mounted = truthy(input._get("open"))
      self.cancel()
      fn() {
        self.mounted = false
        self.cancel()
      }
    },
    [input._get("open"), input._get("store"), input._get("scene")._get("id")],
  )
  let busy = view.busy is Some(_) || truthy(input._get("busy"))
  let ids : FixedArray[String] = input._get("selectedIds").cast()
  let content : Array[&@react.ReactNode] = [
    h("h3", Map([]), ["Reusable motion"]),
    h("p", { "className": @core.any("account-hint") }, [
      "選択したオブジェクトと動きを保存し、文字・色を差し替えて再利用します。音声トラックは含みません。",
    ]),
    h("label", { "className": @core.any("motion-field") }, [
      "保存する動きの名前",
      h(
        "input",
        {
          "aria-label": @core.any("Motion name"),
          "value": @core.any(view.name),
          "maxLength": @core.any(100),
          "disabled": @core.any(busy),
          "onChange": @core.any(fn(event : @core.Any) {
            self.update({
              ..self.view,
              name: string_value(event._get("target")._get("value")),
            })
          }),
        },
        [],
      ),
    ]),
    h("div", { "className": @core.any("account-login-actions") }, [
      h(
        "button",
        {
          "className": @core.any("subtle-button"),
          "disabled": @core.any(busy || ids.is_empty()),
          "onClick": @core.any(fn() {
            attempt(
              fn() {
                let scene = input
                  ._get("store")
                  ._call("scene", [input._get("scene")._get("id")])
                // Capture the selection and all poses synchronously before asset I/O.
                let project = @boundary.capture_motion(
                  scene,
                  ids,
                  self.view.name,
                )
                self.start(SaveMotion(project))
              },
              fn(message) { self.update({ ..self.view, message, }) },
              "動きを保存できませんでした。",
            )
          }),
        },
        [icon("Download", 14), "Save motion"],
      ),
      h(
        "button",
        {
          "className": @core.any("subtle-button"),
          "disabled": @core.any(busy),
          "onClick": @core.any(fn() {
            if file.get_current() is Some(file) {
              file._call("click", []) |> ignore
            }
          }),
        },
        [icon("FolderOpen", 14), "Load motion"],
      ),
    ]),
    h(
      "input",
      {
        "ref": file.as_any(),
        "type": @core.any("file"),
        "hidden": @core.any(true),
        "aria-label": @core.any("動きのファイル"),
        "accept": @core.any(".json,.poietra.json,application/json"),
        "onChange": @core.any(fn(event : @core.Any) {
          let target = event._get("currentTarget")
          let files = target._get("files")
          if !@core.is_nullish(files) && !@core.is_nullish(files._get("0")) {
            self.start(ReadMotion(files._get("0")))
          }
          target._set("value", @core.any(""))
        }),
      },
      [],
    ),
  ]
  if ids.is_empty() {
    content.push(
      h("p", { "className": @core.any("account-hint") }, [
        "保存するにはキャンバスかレイヤー一覧でオブジェクトを選択してください。親を選ぶと子孫も保存します。必要な親は非表示の補助として保持します。",
      ]),
    )
  }
  if view.source is Some(source) {
    let fields : Array[&@react.ReactNode] = []
    let page_size = 24
    let start = view.page * page_size
    let end = (start + page_size).min(view.parameters.length())
    for index = start; index < end; index = index + 1 {
      let parameter = view.parameters[index]
      let (original, replacement, label) = match parameter {
        MotionText(text) =>
          (text, view.texts.get(text).unwrap_or(text), "文字・数式")
        MotionColor(color) =>
          (color, view.colors.get(color).unwrap_or(color), "色")
      }
      fields.push(
        h(
          "label",
          { "className": @core.any("motion-field"), "key": @core.any(index) },
          [
            "\{label}: \{original}",
            h(
              "input",
              {
                "aria-label": @core.any("\{label}: \{original}"),
                "value": @core.any(replacement),
                "disabled": @core.any(busy),
                "maxLength": @core.any(
                  if parameter is MotionText(_) {
                    10000
                  } else {
                    100
                  },
                ),
                "onChange": @core.any(fn(event : @core.Any) {
                  let value = string_value(event._get("target")._get("value"))
                  match parameter {
                    MotionText(_) => {
                      let texts = self.view.texts.copy()
                      texts[original] = value
                      self.update({ ..self.view, texts, })
                    }
                    MotionColor(_) => {
                      let colors = self.view.colors.copy()
                      colors[original] = value
                      self.update({ ..self.view, colors, })
                    }
                  }
                }),
              },
              [],
            ),
          ],
        ),
      )
    }
    content.push(h("h4", Map([]), [source.name]))
    content.push(
      h("p", { "className": @core.any("account-hint") }, [
        "\{source.objects.length()} objects · \{source.compositionOrder.length()} Compositions。現在の Scene の末尾に追加し、既存のオブジェクトは最後の状態を維持します。",
      ]),
    )
    content.push(
      h("div", { "className": @core.any("motion-parameters") }, fields),
    )
    if view.parameters.length() > page_size {
      content.push(
        h("div", { "className": @core.any("account-login-actions") }, [
          h(
            "button",
            {
              "className": @core.any("subtle-button"),
              "disabled": @core.any(busy || start == 0),
              "onClick": @core.any(fn() {
                self.update({ ..self.view, page: self.view.page - 1, })
              }),
            },
            ["前の差し替え項目"],
          ),
          h("span", Map([]), [
            "\{start + 1}–\{end} / \{view.parameters.length()}",
          ]),
          h(
            "button",
            {
              "className": @core.any("subtle-button"),
              "disabled": @core.any(busy || end == view.parameters.length()),
              "onClick": @core.any(fn() {
                self.update({ ..self.view, page: self.view.page + 1, })
              }),
            },
            ["次の差し替え項目"],
          ),
        ]),
      )
    }
    content.push(
      h(
        "button",
        {
          "className": @core.any("primary-button"),
          "disabled": @core.any(busy),
          "onClick": @core.any(fn() {
            attempt(
              fn() {
                let replaced = @boundary.replace_motion(
                  source,
                  self.view.texts,
                  self.view.colors,
                )
                @boundary.validate_motion_insertion(
                  input
                  ._get("store")
                  ._call("scene", [input._get("scene")._get("id")]),
                  replaced,
                )
                self.start(InsertMotion(replaced))
              },
              fn(message) { self.update({ ..self.view, message, }) },
              "差し替える値を確認してください。",
            )
          }),
        },
        ["Insert motion"],
      ),
    )
  }
  if view.busy is Some(message) {
    content.push(
      h(
        "p",
        { "role": @core.any("status"), "className": @core.any("account-hint") },
        [message],
      ),
    )
    content.push(
      h(
        "button",
        {
          "className": @core.any("text-button"),
          "onClick": @core.any(fn() { self.cancel() }),
        },
        ["Cancel motion"],
      ),
    )
  }
  if !view.message.is_empty() {
    content.push(
      h(
        "p",
        { "role": @core.any("status"), "className": @core.any("account-hint") },
        [view.message],
      ),
    )
  }
  h(
    "section",
    {
      "className": @core.any("motion-library"),
      "aria-label": @core.any("Reusable motion"),
    },
    content,
  )
}
