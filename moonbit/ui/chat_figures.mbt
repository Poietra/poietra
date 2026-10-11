///|
/// A figure waiting in the composer. Only the request that carries it sends the
/// data URL to Codex; the chat message keeps the text alone.
priv struct ChatFigure {
  data : String
  width : Double
  height : Double
}

///|
/// A Scene's composer figures. `generation` changes whenever the figures are
/// replaced as a whole (sent or restored), so a preparation started earlier
/// discards its late result instead of joining a different request.
priv struct FigureDraft {
  mut figures : Array[ChatFigure]
  mut preparing : Int
  mut generation : Int
}

///|
fn ChatController::figure_draft(
  self : ChatController,
  scene : String,
) -> FigureDraft {
  match self.figure_drafts.get(scene) {
    Some(draft) => draft
    None => {
      let draft = { figures: [], preparing: 0, generation: 0, }
      self.figure_drafts[scene] = draft
      draft
    }
  }
}

///|
fn ChatController::show_figures(self : ChatController, scene : String) -> Unit {
  if self.current_scene.get_current() == Some(scene) {
    let draft = self.figure_draft(scene)
    (self.set_figures)(draft.figures)
    (self.set_preparing)(draft.preparing > 0)
  }
}

///|
/// Edits the current figures; a preparation in progress still adds its result.
fn ChatController::update_figures(
  self : ChatController,
  figures : Array[ChatFigure],
) -> Unit {
  let scene = self.current_scene.get_current().unwrap()
  self.figure_draft(scene).figures = figures
  self.show_figures(scene)
}

///|
/// Replaces a Scene's figures when they are sent or restored. Preparations
/// started before this no longer apply.
fn ChatController::replace_figures(
  self : ChatController,
  scene : String,
  figures : Array[ChatFigure],
) -> Unit {
  let draft = self.figure_draft(scene)
  draft.figures = figures
  draft.preparing = 0
  draft.generation += 1
  self.show_figures(scene)
}

///|
fn image_files(list : @core.Any) -> Array[@core.Any] {
  if @core.is_nullish(list) {
    return []
  }
  let files : FixedArray[@core.Any] = @core.global_this()
    ._get("Array")
    ._call("from", [list])
    .cast()
  files
  .iter()
  .filter(fn(file) { (file._get("type").cast() : String).has_prefix("image/") })
  .to_array()
}

///|
/// Figures are for Codex, so attaching one addresses the request to Codex.
fn ChatController::attach(
  self : ChatController,
  files : Array[@core.Any],
) -> Unit {
  if files.is_empty() {
    return
  }
  let scene = self.current_scene.get_current().unwrap()
  let draft = self.figure_draft(scene)
  let generation = draft.generation
  let existing = draft.figures.length()
  // Sending waits for preparation, so the figure cannot miss its request.
  draft.preparing += 1
  self.show_figures(scene)
  @core.from_async(async fn() {
    let added = []
    let mut failure = None
    try {
      for file in files {
        if existing + added.length() >= @assets.figure_limit {
          break
        }
        let image = @browser_media.normalize_image(file).wait()
        let data = @browser_media.blob_data_url(image._get("blob")).wait()
        added.push({
          data,
          width: image._get("width").cast(),
          height: image._get("height").cast(),
        })
      }
    } catch {
      error =>
        failure = Some(
          error_message(
            ui_native_error(error),
            "画像を添付できませんでした。",
          ),
        )
    }
    // Preparation awaited; continue from the latest render, and only if the
    // figures were not sent or replaced meanwhile.
    let latest = self.latest.get_current().unwrap()
    let draft = latest.figure_draft(scene)
    if draft.generation != generation {
      return
    }
    draft.preparing -= 1
    let figures = draft.figures + added
    if figures.length() > @assets.figure_limit ||
      existing + files.length() > @assets.figure_limit {
      failure = Some(
        "画像は \{@assets.figure_limit} 枚まで添付できます。",
      )
    }
    draft.figures = figures[:figures.length().min(@assets.figure_limit)].to_owned()
    if !added.is_empty() {
      let prompt = latest.drafts.get(scene).unwrap_or("")
      if @boundary.codex_mention(prompt) is None {
        latest.drafts[scene] = "@codex " + prompt
      }
    }
    if failure is Some(message) {
      (latest.set_error)(message)
    }
    latest.show_figures(scene)
    if !added.is_empty() && latest.current_scene.get_current() == Some(scene) {
      (latest.set_prompt)(latest.drafts.get(scene).unwrap_or(""))
      latest.focus()
    }
  })
  |> ignore
}

///|
fn composer_figures(controller : ChatController) -> @react.Element {
  let items : Array[&@react.ReactNode] = []
  for index, figure in controller.figures {
    let number = index + 1
    items.push(
      h("span", { "key": @core.any(number.to_string()) }, [
        h(
          "img",
          {
            "src": @core.any(figure.data),
            "alt": @core.any("添付画像 \{number}"),
            "width": @core.any(figure.width),
            "height": @core.any(figure.height),
          },
          [],
        ),
        h(
          "button",
          {
            "type": @core.any("button"),
            "aria-label": @core.any("添付画像 \{number} を削除"),
            "onClick": @core.any(fn() {
              let latest = controller.latest.get_current().unwrap()
              let rest = latest.figures.copy()
              rest.remove(index) |> ignore
              latest.update_figures(rest)
            }),
          },
          [icon("X", 11)],
        ),
      ]),
    )
  }
  if controller.preparing {
    items.push(
      h(
        "span",
        {
          "key": @core.any("preparing"),
          "className": @core.any("figure-preparing"),
          "role": @core.any("status"),
        },
        ["画像を準備中…"],
      ),
    )
  }
  h("div", { "className": @core.any("chat-figures composer-figures") }, items)
}

///|
fn figure_picker(controller : ChatController) -> Array[&@react.ReactNode] {
  [
    h(
      "button",
      {
        "key": @core.any("attach"),
        "className": @core.any("icon-button figure-button"),
        "type": @core.any("button"),
        "aria-label": @core.any("Codex に図を添付"),
        "title": @core.any(
          "図を添付(貼り付け・ドロップでも追加できます)",
        ),
        "disabled": @core.any(
          controller.figures.length() >= @assets.figure_limit,
        ),
        "onClick": @core.any(fn() {
          if controller.figure_input.get_current() is Some(input) {
            input._call("click", []) |> ignore
          }
        }),
      },
      [icon("ImagePlus", 14)],
    ),
    h(
      "input",
      {
        "key": @core.any("figure-input"),
        "ref": controller.figure_input.as_any(),
        "type": @core.any("file"),
        "accept": @core.any("image/png,image/jpeg,image/webp"),
        "multiple": @core.any(true),
        "hidden": @core.any(true),
        "aria-hidden": @core.any(true),
        "tabIndex": @core.any(-1),
        "onChange": @core.any(fn(event : @core.Any) {
          let input = event._get("currentTarget")
          let files = image_files(input._get("files"))
          input._set("value", @core.any(""))
          controller.latest.get_current().unwrap().attach(files)
        }),
      },
      [],
    ),
  ]
}
