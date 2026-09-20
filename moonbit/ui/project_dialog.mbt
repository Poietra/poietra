///|
fn project_action_button(
  name : String,
  title : String,
  detail : String,
  busy : Bool,
  action : () -> Unit,
) -> @react.Element {
  h(
    "button",
    {
      "key": @core.any(title),
      "disabled": @core.any(busy),
      "onClick": @core.any(action),
    },
    [
      icon(name, 20),
      h("span", Map([]), [
        h("strong", Map([]), [title]),
        h("small", Map([]), [detail]),
      ]),
    ],
  )
}

///|
pub fn project_dialog(input : @core.Any) -> @react.Element {
  let open : Bool = input._get("open").cast()
  let project = input._get("project")
  let services = input._get("services")
  let room = input._get("roomId")
  let name : String = project._get("name").cast()
  let file = @react.use_ref((None : @core.Any?))
  let (view, set_view) = @react.use_state(ProjectDialogView::Idle(""))
  let owner = @react.use_ref((None : ProjectSession?))
  let session = match owner.get_current() {
    Some(session) => session
    None => {
      let session : ProjectSession = {
        mounted: false,
        job: None,
        publish: set_view,
      }
      owner.set_current(Some(session))
      session
    }
  }
  @react.use_effect(
    fn() {
      session.mounted = open
      session.cancel()
      fn() {
        session.mounted = false
        session.cancel()
      }
    },
    [@core.any(open), room],
  )
  let busy = view is Running(_)
  let on_open_change = @core.any(fn(value : Bool) {
    if !value {
      session.cancel()
    }
    input._get("onOpenChange")._invoke([@core.any(value)]) |> ignore
  })
  @react.jsx(@core.any(account_projects), [], props={
    "open": @core.any(open),
    "roomId": room,
    "name": @core.any(name),
    "synced": input._get("synced"),
    "busy": @core.any(busy),
    "onOpenChange": on_open_change,
    "children": @core.any(fn(account : @core.Any) {
      let content : Array[&@react.ReactNode] = [HostNode::{ value: account, }]
      content.push(
        h("div", { "className": @core.any("project-actions") }, [
          project_action_button(
            "FilePlus2",
            "New project",
            "空のキャンバスから始める",
            busy,
            fn() { session.start(BlankProject, services) },
          ),
          project_action_button(
            "Play",
            "Try the example",
            "ベジェ曲線と数式のアニメーション",
            busy,
            fn() { session.start(DemoProject, services) },
          ),
          project_action_button(
            "Sigma",
            "Follow the gradient",
            "微分が伝わる仕組みを、3 つの場面で",
            busy,
            fn() { session.start(CalculusProject, services) },
          ),
          project_action_button(
            "FolderOpen",
            "Open project",
            "保存した .poietra.json を新しいリンクで開く",
            busy,
            fn() {
              if file.get_current() is Some(element) {
                element._call("click", []) |> ignore
              }
            },
          ),
          h(
            "input",
            {
              "key": @core.any("project-file"),
              "ref": file.as_any(),
              "type": @core.any("file"),
              "aria-label": @core.any("プロジェクトファイル"),
              "accept": @core.any(".json,.poietra.json,application/json"),
              "hidden": @core.any(true),
              "onChange": @core.any(fn(event : @core.Any) {
                let target = event._get("currentTarget")
                let files = target._get("files")
                let selected = if @core.is_nullish(files) {
                  @core.undefined()
                } else {
                  files._get("0")
                }
                target._set("value", @core.any(""))
                if !@core.is_nullish(selected) {
                  session.start(OpenProject(selected), services)
                }
              }),
            },
            [],
          ),
        ]),
      )
      match view {
        Running(operation) =>
          content.push(
            h(
              "p",
              {
                "key": @core.any("progress"),
                "className": @core.any("project-progress"),
                "role": @core.any("status"),
              },
              [
                icon("LoaderCircle", 15, props={
                  "className": @core.any("loading-spinner"),
                }),
                match operation {
                  Saving =>
                    "画像を含む保存ファイルを準備しています…"
                  Opening => "プロジェクトを開いています…"
                },
              ],
            ),
          )
        Idle(error) =>
          if !error.is_empty() {
            content.push(
              h(
                "p",
                {
                  "key": @core.any("error"),
                  "className": @core.any("project-error"),
                  "role": @core.any("alert"),
                },
                [error],
              ),
            )
          }
      }
      content.push(
        h(
          "div",
          { "key": @core.any("save"), "className": @core.any("project-save") },
          [
            h("span", Map([]), [name]),
            h(
              "button",
              {
                "className": @core.any("subtle-button"),
                "disabled": @core.any(busy),
                "onClick": @core.any(fn() {
                  session.start(SaveProject(project), services)
                }),
              },
              [icon("Download", 14), "Save project"],
            ),
          ],
        ),
      )
      @react.jsx(@core.any(modal), content, props={
        "open": @core.any(open),
        "onOpenChange": on_open_change,
        "title": @core.any("Projects"),
        "description": @core.any(
          "新しいプロジェクトには、新しい共有リンクが作られます。",
        ),
        "className": @core.any("projects-dialog"),
      })
    }),
  })
}
