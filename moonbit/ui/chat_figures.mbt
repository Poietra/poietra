///|
/// A figure waiting in the composer. The normalized bytes are uploaded to room
/// storage when sent; the data URL is what Codex sees.
priv struct ChatFigure {
  blob : @core.Any
  data : String
  width : Double
  height : Double
}

///|
fn ChatController::update_figures(
  self : ChatController,
  figures : Array[ChatFigure],
) -> Unit {
  self.figure_drafts[self.current_scene.get_current().unwrap()] = figures
  (self.set_figures)(figures)
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
  @core.from_async(async fn() {
    let added = []
    let existing = self.figure_drafts.get(scene).unwrap_or([]).length()
    try {
      for file in files {
        if existing + added.length() >= @assets.figure_limit {
          (self.set_error)(
            "画像は \{@assets.figure_limit} 枚まで添付できます。",
          )
          break
        }
        let image = @browser_media.normalize_image(file).wait()
        let data = @browser_media.blob_data_url(image._get("blob")).wait()
        added.push({
          blob: image._get("blob"),
          data,
          width: image._get("width").cast(),
          height: image._get("height").cast(),
        })
      }
    } catch {
      error =>
        (self.set_error)(
          error_message(
            ui_native_error(error),
            "画像を添付できませんでした。",
          ),
        )
    }
    if added.is_empty() {
      return
    }
    // Normalization awaited; continue from the latest render's drafts.
    let latest = self.latest.get_current().unwrap()
    let figures = latest.figure_drafts.get(scene).unwrap_or([]) + added
    latest.figure_drafts[scene] = figures[:figures
    .length()
    .min(@assets.figure_limit)].to_owned()
    let prompt = latest.drafts.get(scene).unwrap_or("")
    if @boundary.codex_mention(prompt) is None {
      latest.drafts[scene] = "@codex " + prompt
    }
    if latest.current_scene.get_current() == Some(scene) {
      (latest.set_figures)(latest.figure_drafts.get(scene).unwrap_or([]))
      (latest.set_prompt)(latest.drafts.get(scene).unwrap_or(""))
      latest.focus()
    }
  })
  |> ignore
}

///|
/// Returning a stopped or failed request to the composer also returns its
/// stored figures, read back from room storage.
fn ChatController::restore_figures(
  self : ChatController,
  scene : String,
  attachments : Array[@editor.ChatAttachment],
) -> Unit {
  self.figure_drafts[scene] = []
  if self.current_scene.get_current() == Some(scene) {
    (self.set_figures)([])
  }
  if attachments.is_empty() {
    return
  }
  @core.from_async(async fn() {
    let figures = []
    try {
      for attachment in attachments {
        let blob = @browser_media.image_blob(attachment.src, @core.undefined()).wait()
        figures.push({
          blob,
          data: @browser_media.blob_data_url(blob).wait(),
          width: attachment.width,
          height: attachment.height,
        })
      }
    } catch {
      error => {
        (self.set_error)(
          error_message(
            ui_native_error(error),
            "添付画像を読み込めませんでした。",
          ),
        )
        return
      }
    }
    let latest = self.latest.get_current().unwrap()
    latest.figure_drafts[scene] = figures
    if latest.current_scene.get_current() == Some(scene) {
      (latest.set_figures)(figures)
    }
  })
  |> ignore
}

///|
fn figure_list(
  class_name : String,
  items : Array[&@react.ReactNode],
) -> @react.Element {
  h("div", { "className": @core.any(class_name) }, items)
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
  figure_list("chat-figures composer-figures", items)
}

///|
fn message_figures(
  attachments : Array[@editor.ChatAttachment],
) -> @react.Element {
  let items : Array[&@react.ReactNode] = []
  for index, attachment in attachments {
    items.push(
      h(
        "a",
        {
          "key": @core.any(attachment.src),
          "href": @core.any(attachment.src),
          "target": @core.any("_blank"),
          "rel": @core.any("noopener"),
        },
        [
          h(
            "img",
            {
              "src": @core.any(attachment.src),
              "alt": @core.any("添付画像 \{index + 1}"),
              "width": @core.any(attachment.width),
              "height": @core.any(attachment.height),
              "loading": @core.any("lazy"),
            },
            [],
          ),
        ],
      ),
    )
  }
  figure_list("chat-figures", items)
}
