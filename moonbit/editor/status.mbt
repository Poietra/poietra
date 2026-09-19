///|
pub(all) enum Transport {
  Connected
  Disconnected
  Connecting
} derive(Eq)

///|
pub(all) enum Persistence {
  Ready
  Loading
  Unavailable
} derive(Eq)

///|
pub(all) struct Connection {
  transport : Transport
  synced : Bool
  has_project : Bool
  persistence : Persistence
  issue : String?
}

///|
pub(all) struct ConnectionView {
  live : Bool
  label : String
  description : String
  storage : String
  warning : Bool
}

///|
pub fn connection_view(state : Connection) -> ConnectionView {
  let live = state.transport == Connected && state.synced && state.has_project
  let has_issue = state.issue
    .map(fn(value) { !value.is_empty() })
    .unwrap_or(false)
  let label = if live {
    "Live"
  } else if has_issue || state.transport == Disconnected {
    "Offline"
  } else if !state.has_project && state.persistence == Loading {
    "Loading"
  } else {
    "Syncing"
  }
  let description = if live {
    "共同編集に接続しています。"
  } else {
    state.issue.unwrap_or(
      if label == "Loading" {
        "このブラウザに保存されたプロジェクトを読み込んでいます。"
      } else {
        "共同編集の変更を同期しています。"
      },
    )
  }
  let storage = match state.persistence {
    Ready =>
      "変更をこのブラウザに自動保存します。オフラインの変更は再接続後に共有されます。"
    Loading =>
      "ブラウザ内の保存を準備しています。準備が終わるまでこのタブを開いたままにしてください。"
    Unavailable =>
      "ブラウザ内の保存を確認できません。このタブを開いたまま再接続するか、Save project でファイルを保存してください。"
  }
  {
    live,
    label,
    description,
    storage,
    warning: has_issue || state.persistence == Unavailable,
  }
}

///|
pub(all) enum FeedbackKind {
  Active
  Complete
  Cancelled
  Locked
  Inactive
} derive(Eq)

///|
pub(all) struct OperationStatus {
  label : String
  detail : String?
  kind : FeedbackKind
}

///|
pub(all) struct FeedbackEntry {
  scope : String
  status : OperationStatus
}

///|
pub(all) struct FeedbackState {
  revision : Int
  entry : FeedbackEntry?
}

///|
pub(all) enum FeedbackAction {
  Report(String, OperationStatus?)
  Expire(Int)
}

///|
pub fn reduce_feedback(
  state : FeedbackState,
  action : FeedbackAction,
) -> FeedbackState {
  match action {
    Report(scope, status) =>
      {
        revision: state.revision + 1,
        entry: status.map(fn(status) { { scope, status, } }),
      }
    Expire(revision) =>
      if revision == state.revision {
        { ..state, entry: None, }
      } else {
        state
      }
  }
}

///|
pub fn is_completion(status : OperationStatus) -> Bool {
  status.kind == Complete || status.kind == Cancelled
}

///|
pub fn announcement(status : OperationStatus?) -> String {
  guard status is Some(status) && is_completion(status) else { return "" }
  let suffix = match status.detail {
    Some(detail) if !detail.is_empty() => " · " + detail
    _ => ""
  }
  status.label + suffix
}

///|
pub fn feedback_name(kind : FeedbackKind) -> String {
  match kind {
    Active => "active"
    Complete => "complete"
    Cancelled => "cancelled"
    Locked => "locked"
    Inactive => "idle"
  }
}
