///|
pub(all) enum ChatRole {
  Person
  Assistant
} derive(Eq)

///|
pub(all) enum ChatStatus {
  Pending
  Complete
  Failed
  Cancelled
} derive(Eq)

///|
pub(all) enum ProposalStatus {
  Proposed
  Applied
  Discarded
} derive(Eq)

///|
pub(all) enum ChatSelection {
  Composition(String)
  Transition(String)
} derive(Eq)

///|
pub(all) struct ChatScope {
  scene_id : String
  selection : ChatSelection
  selected_ids : Array[String]
  label : String
}

///|
pub(all) struct ChatMessage[P] {
  id : String
  role : ChatRole
  content : String
  scope : ChatScope
  author_id : String
  author_name : String
  color : String
  created_at : Double
  mentions_codex : Bool?
  reply_to : String?
  request_client_id : Double?
  status : ChatStatus?
  proposal : P?
  applied : Bool?
  dismissed : Bool?
}

///|
pub(all) struct ConversationTurn {
  role : ChatRole
  content : String
  proposal_status : ProposalStatus?
}

///|
pub fn trim_history(
  history : Array[ConversationTurn],
) -> Array[ConversationTurn] {
  let kept = []
  let mut characters = 0
  for index = history.length() - 1
      index >= 0 && kept.length() < 24
      index = index - 1 {
    let entry = history[index]
    let text = entry.content[:entry.content.length().min(3000)].to_owned()
    if characters + text.length() > 24000 {
      break
    }
    kept.push({
      ..entry,
      content: text,
      proposal_status: if entry.role == Assistant {
        entry.proposal_status
      } else {
        None
      },
    })
    characters += text.length()
  }
  kept.rev_in_place()
  kept
}

///|
pub fn[P] chat_history(
  messages : Array[ChatMessage[P]],
  scene_id : String,
  author_id : String,
  mention : (String) -> String?,
  has_changes : (P) -> Bool,
) -> Array[ConversationTurn] {
  let turns = []
  for message in messages {
    if message.scope.scene_id != scene_id {
      continue
    }
    match message.role {
      Person => {
        if message.status != Some(Complete) {
          continue
        }
        let content = if message.mentions_codex.unwrap_or(false) {
          mention(message.content).unwrap_or(message.content)
        } else {
          message.content
        }
        turns.push({
          role: Person,
          content: if message.author_id == author_id {
            content
          } else {
            message.author_name + ": " + content
          },
          proposal_status: None,
        })
      }
      Assistant =>
        turns.push({
          role: Assistant,
          content: message.content,
          proposal_status: if message.proposal.map(has_changes).unwrap_or(false) {
            Some(
              if message.applied.unwrap_or(false) {
                Applied
              } else if message.dismissed.unwrap_or(false) {
                Discarded
              } else {
                Proposed
              },
            )
          } else {
            None
          },
        })
    }
  }
  trim_history(turns)
}

///|
pub fn chat_status_name(status : ChatStatus) -> String {
  match status {
    Pending => "pending"
    Complete => "complete"
    Failed => "failed"
    Cancelled => "cancelled"
  }
}

///|
pub fn chat_status(value : String) -> ChatStatus? {
  match value {
    "pending" => Some(Pending)
    "complete" => Some(Complete)
    "failed" => Some(Failed)
    "cancelled" => Some(Cancelled)
    _ => None
  }
}

///|
pub fn proposal_status_name(status : ProposalStatus) -> String {
  match status {
    Proposed => "proposed"
    Applied => "applied"
    Discarded => "discarded"
  }
}
