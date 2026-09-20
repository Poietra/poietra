///|
fn use_account(
  room : String,
  name : String,
  ready : Bool,
  open : Bool,
) -> (AccountController, AccountView) {
  let (view, publish) = @react.use_state(AccountView::{
    session: None,
    projects: [],
    loading: true,
    list_loading: false,
    pending: "",
    error: "",
    notice: "",
    excluded: None,
  })
  let owner = @react.use_ref((None : AccountController?))
  let controller = match owner.get_current() {
    Some(controller) => controller
    None => {
      let controller : AccountController = {
        view,
        identity: None,
        mounted: true,
        session_request: @core.null(),
        list_request: @core.null(),
        write: None,
        saved: None,
        attempted: None,
        publish,
      }
      owner.set_current(Some(controller))
      controller
    }
  }
  @react.use_effect(
    fn() {
      controller.mounted = true
      controller.refresh()
      let window = @core.global_this()
      let refresh = fn() {
        if @core.equal(
            window._get("document")._get("visibilityState"),
            @core.any("visible"),
          ) {
          controller.refresh()
        }
      }
      window._call("addEventListener", [@core.any("focus"), @core.any(refresh)])
      |> ignore
      fn() {
        controller.mounted = false
        account_cancel(controller.session_request)
        account_cancel(controller.list_request)
        if controller.write is Some(write) {
          account_cancel(write.controller)
          controller.write = None
        }
        window._call("removeEventListener", [
          @core.any("focus"),
          @core.any(refresh),
        ])
        |> ignore
      }
    },
    [],
  )
  let identity = controller.identity.unwrap_or("")
  @react.use_effect(
    fn() {
      if open {
        controller.list()
      }
      fn() { () }
    },
    [@core.any(open), @core.any(identity), @core.any(view.session)],
  )
  @react.use_effect(
    fn() {
      let key : @editor.AccountSave = { account: identity, room, name, }
      if !ready ||
        identity.is_empty() ||
        !view.pending.is_empty() ||
        view.excluded == Some({ account: identity, room, }) ||
        controller.saved == Some(key) ||
        controller.attempted == Some(key) {
        return fn() { () }
      }
      let window = @core.global_this()
      let timer = window._call("setTimeout", [
        @core.any(fn() {
          controller.attempted = Some(key)
          controller.mutate(@editor.VisitProject(room, name), room)
        }),
        @core.any(600),
      ])
      fn() { window._call("clearTimeout", [timer]) |> ignore }
    },
    [
      @core.any(ready),
      @core.any(identity),
      @core.any(room),
      @core.any(name),
      @core.any(view.excluded),
      @core.any(view.pending),
    ],
  )
  (controller, view)
}

///|
pub fn use_account_projects(
  room : String,
  name : String,
  ready : Bool,
  open : Bool,
) -> @core.Any {
  let (controller, view) = use_account(room, name, ready, open)
  let session = view.session
    .map(fn(session) {
      host_record({
        "providers": host_record({
          "google": @core.any(session.google),
          "github": @core.any(session.github),
        }),
        "user": session.user
        .map(fn(user) {
          host_record({
            "id": @core.any(user.id),
            "name": @core.any(user.name),
            "provider": @core.any(@editor.auth_provider_name(user.provider)),
          })
        })
        .unwrap_or(@core.null()),
      })
    })
    .unwrap_or(@core.null())
  host_record({
    "session": session,
    "projects": @core.any(
      host_array(
        view.projects.map(fn(project) {
          host_record({
            "roomId": @core.any(project.room_id),
            "name": @core.any(project.name),
            "updatedAt": @core.any(project.updated_at),
          })
        }),
      ),
    ),
    "loading": @core.any(view.loading),
    "listLoading": @core.any(view.list_loading),
    "pending": @core.any(view.pending),
    "error": @core.any(view.error),
    "refreshSession": @core.any(fn() {
      ui_native_errors(
        @core.from_async(async fn() { controller.refresh_session() }),
      )
    }),
    "refreshProjects": @core.any(fn() {
      ui_native_errors(
        @core.from_async(async fn() { controller.refresh_projects() }),
      )
    }),
    "remember": @core.any(fn() {
      ui_native_errors(
        @core.from_async(async fn() {
          if ready {
            controller.mutate_async(@editor.RememberProject(room, name), room)
          }
        }),
      )
    }),
    "remove": @core.any(fn(target : String) {
      ui_native_errors(
        @core.from_async(async fn() {
          controller.mutate_async(@editor.RemoveProject(target), room)
        }),
      )
    }),
    "logout": @core.any(fn() {
      ui_native_errors(
        @core.from_async(async fn() {
          controller.mutate_async(@editor.SignOut, room)
        }),
      )
    }),
  })
}
