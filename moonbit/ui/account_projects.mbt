///|
fn account_login_error() -> String {
  let url = @core.new(@core.global_this()._get("URL"), [
    @core.global_this()._get("location")._get("href"),
  ])
  match
    optional_string(
      url._get("searchParams")._call("get", [@core.any("auth_error")]),
    ) {
    Some("denied") =>
      "ログインをキャンセルしました。このまま編集を続けられます。"
    Some("expired") =>
      "ログインの確認が期限切れになりました。もう一度お試しください。"
    Some(code) =>
      if code.is_empty() {
        ""
      } else {
        "ログインできませんでした。もう一度お試しください。"
      }
    None => ""
  }
}

///|
pub fn account_projects(input : @core.Any) -> @react.Element {
  let open : Bool = input._get("open").cast()
  let room : String = input._get("roomId").cast()
  let name : String = input._get("name").cast()
  let synced : Bool = input._get("synced").cast()
  let (controller, view) = use_account(room, name, synced, open)
  let initial_error = @react.use_memo(account_login_error, [])
  let (login_error, set_login_error) = @react.use_state(initial_error)
  @react.use_effect(
    fn() {
      let window = @core.global_this()
      let url = @core.new(window._get("URL"), [
        window._get("location")._get("href"),
      ])
      let params = url._get("searchParams")
      if truthy(params._call("has", [@core.any("projects")])) ||
        truthy(params._call("has", [@core.any("auth_error")])) {
        params._call("delete", [@core.any("projects")]) |> ignore
        params._call("delete", [@core.any("auth_error")]) |> ignore
        let history = window._get("history")
        history._call("replaceState", [
          history._get("state"),
          @core.any(""),
          url,
        ])
        |> ignore
      }
      fn() { () }
    },
    [],
  )
  if !open {
    return input._get("children")._invoke([@core.null()]).cast()
  }
  let user = match view.session {
    Some(session) => session.user
    None => None
  }
  let disabled = truthy(input._get("busy")) || !view.pending.is_empty()
  let account : Array[&@react.ReactNode] = []
  if view.loading {
    account.push(
      h(
        "p",
        { "className": @core.any("account-hint"), "role": @core.any("status") },
        ["ログイン状態を確認しています…"],
      ),
    )
  } else if user is Some(user) {
    account.push(
      h("div", { "className": @core.any("account-heading") }, [
        h(
          "span",
          {
            "className": @core.any("account-initial"),
            "aria-hidden": @core.any(true),
          },
          [user.name[:user.name.length().min(1)].to_owned()],
        ),
        h("div", Map([]), [
          h("strong", Map([]), [user.name]),
          h("span", Map([]), [
            (if user.provider == @editor.Google { "Google" } else { "GitHub" }) +
            " でログイン中",
          ]),
        ]),
        h(
          "button",
          {
            "className": @core.any("subtle-button"),
            "disabled": @core.any(disabled),
            "onClick": @core.any(fn() {
              controller.mutate(@editor.SignOut, room)
            }),
          },
          [icon("LogOut", 14), "ログアウト"],
        ),
      ]),
    )
    account.push(
      h("p", { "className": @core.any("account-hint") }, [
        "このアカウントの一覧を、別の端末でも開けます。ログアウト後も共有リンクから編集できます。",
      ]),
    )
  } else if view.session is Some(_) {
    account.push(h("h3", Map([]), ["ゲストで編集中"]))
    account.push(
      h("p", { "className": @core.any("account-hint") }, [
        "ログインすると、自分のプロジェクト一覧を別の端末でも開けます。共有リンクからの参加・編集はログインなしで使えます。",
      ]),
    )
    if view.session is Some(session) {
      if session.google || session.github {
        let links : Array[&@react.ReactNode] = []
        if session.google {
          links.push(
            h(
              "a",
              {
                "href": @core.any(login_url("google", room)),
                "onClick": @core.any(fn() { set_login_error("") }),
              },
              [
                h(
                  "span",
                  {
                    "className": @core.any("provider-letter"),
                    "aria-hidden": @core.any(true),
                  },
                  ["G"],
                ),
                "Google でログイン",
              ],
            ),
          )
        }
        if session.github {
          links.push(
            h(
              "a",
              {
                "href": @core.any(login_url("github", room)),
                "onClick": @core.any(fn() { set_login_error("") }),
              },
              ["GitHub でログイン"],
            ),
          )
        }
        account.push(
          h("div", { "className": @core.any("account-login-actions") }, links),
        )
        if session.google && session.github {
          account.push(
            h("p", { "className": @core.any("account-hint") }, [
              "Google と GitHub は別のアカウントです。以前と同じ方法でログインすると、自分の一覧に戻れます。",
            ]),
          )
        }
      } else {
        account.push(
          h("p", { "className": @core.any("account-hint") }, [
            "ログインは準備中です。共有リンクで編集を続けられます。",
          ]),
        )
      }
    }
  } else {
    account.push(
      h("h3", Map([]), ["ログイン状態を確認できませんでした"]),
    )
  }
  if !login_error.is_empty() {
    account.push(
      h(
        "p",
        { "className": @core.any("project-error"), "role": @core.any("alert") },
        [login_error],
      ),
    )
  }
  if !view.error.is_empty() {
    account.push(
      h("div", { "className": @core.any("account-error") }, [
        h(
          "p",
          {
            "className": @core.any("project-error"),
            "role": @core.any("alert"),
          },
          [view.error],
        ),
        h(
          "button",
          {
            "className": @core.any("subtle-button"),
            "disabled": @core.any(disabled),
            "onClick": @core.any(fn() {
              controller.refresh()
              if user is Some(_) {
                controller.list()
              }
            }),
          },
          [icon("RefreshCw", 13), "再試行"],
        ),
      ]),
    )
  }
  let content : Array[&@react.ReactNode] = [
    h(
      "section",
      {
        "className": @core.any("project-account"),
        "aria-label": @core.any("アカウント"),
      },
      account,
    ),
  ]
  if user is Some(_) {
    content.push(account_project_list(controller, view, input, disabled))
  }
  input._get("children")._invoke([@core.any(@react.fragment(content))]).cast()
}

///|
fn account_project_list(
  controller : AccountController,
  view : AccountView,
  input : @core.Any,
  disabled : Bool,
) -> @react.Element {
  let room : String = input._get("roomId").cast()
  let name : String = input._get("name").cast()
  let synced : Bool = input._get("synced").cast()
  let listed = view.projects.any(fn(project) { project.room_id == room })
  let content : Array[&@react.ReactNode] = [
    h("div", { "className": @core.any("saved-projects-heading") }, [
      h("h3", Map([]), ["自分のプロジェクト一覧"]),
      h(
        "button",
        {
          "className": @core.any("subtle-button"),
          "disabled": @core.any(disabled || !synced || listed),
          "onClick": @core.any(fn() {
            if synced {
              controller.mutate(@editor.RememberProject(room, name), room)
            }
          }),
        },
        [
          icon(if listed { "Check" } else { "Plus" }, 14),
          if listed {
            "一覧に追加済み"
          } else {
            "このプロジェクトを一覧に追加"
          },
        ],
      ),
    ]),
    h("p", { "className": @core.any("account-hint") }, [
      "ログイン中に開いたプロジェクトへのショートカットです。この一覧は自分だけに表示され、共有リンクを知っている人は一緒に編集できます。",
    ]),
  ]
  if !view.notice.is_empty() {
    content.push(
      h(
        "p",
        { "className": @core.any("account-hint"), "role": @core.any("status") },
        [view.notice],
      ),
    )
  }
  if view.projects.is_empty() {
    let props = { "className": @core.any("account-hint") }
    if view.list_loading {
      props["role"] = @core.any("status")
    }
    content.push(
      h("p", props, [
        if view.list_loading {
          "プロジェクト一覧を読み込んでいます…"
        } else {
          "一覧は空です。このプロジェクトを追加すると、別の端末からも開けます。"
        },
      ]),
    )
  } else {
    let rows : Array[&@react.ReactNode] = []
    let date_format = @core.new(
      @core.global_this()._get("Intl")._get("DateTimeFormat"),
      [
        @core.any("ja-JP"),
        host_record({ "month": @core.any("short"), "day": @core.any("numeric") }),
      ],
    )
    for item in view.projects {
      let current = item.room_id == room
      let props = {
        "href": @core.any(
          "/?" + account_query({ "room": @core.any(item.room_id) }),
        ),
        "onClick": @core.any(fn(event : @core.Any) {
          if current {
            prevent_default(event)
            input._get("onOpenChange")._invoke([@core.any(false)]) |> ignore
          }
        }),
      }
      if current {
        props["aria-current"] = @core.any("page")
      }
      rows.push(
        h("li", { "key": @core.any(item.room_id) }, [
          h("a", props, [
            h(
              "span",
              {
                "className": @core.any("saved-project-icon"),
                "aria-hidden": @core.any(true),
              },
              [icon(if current { "Check" } else { "FolderOpen" }, 16)],
            ),
            h("span", { "className": @core.any("saved-project-title") }, [
              h("strong", Map([]), [item.name]),
              h("small", Map([]), [
                if current {
                  "編集中"
                } else {
                  "一覧の更新: " +
                  string_value(
                    date_format._call("format", [@core.any(item.updated_at)]),
                  )
                },
              ]),
            ]),
          ]),
          h(
            "button",
            {
              "className": @core.any("icon-button"),
              "disabled": @core.any(disabled),
              "aria-label": @core.any(
                item.name + " を自分の一覧から外す",
              ),
              "title": @core.any(
                "自分の一覧から外す（共有リンクは残ります）",
              ),
              "onClick": @core.any(fn() {
                controller.mutate(@editor.RemoveProject(item.room_id), room)
              }),
            },
            [icon("X", 14)],
          ),
        ]),
      )
    }
    content.push(
      h("ul", { "className": @core.any("saved-project-list") }, rows),
    )
  }
  h(
    "section",
    {
      "className": @core.any("saved-projects"),
      "aria-label": @core.any("自分のプロジェクト"),
    },
    content,
  )
}
