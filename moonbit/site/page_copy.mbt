///|
pub(all) struct PageCopy {
  description : String
  loadError : String
  retryHint : String
  retry : String
  projectError : String
} derive(ToJson)

///|
pub fn page_copy(locale : Locale) -> PageCopy {
  match locale {
    English =>
      {
        description: "Create motion together with friends and AI. Animate shapes, equations, and media in your browser. Join through a shared link, with no login required.",
        loadError: "Could not open this page",
        retryHint: "Check your connection and try again.",
        retry: "Reload",
        projectError: "Could not open the project. Check your connection and try again.",
      }
    Japanese =>
      {
        description: "友人と、AIと。図形・数式・素材に動きをつけて、ブラウザで一緒に動画をつくる。共有リンクからログインなしで参加できます。",
        loadError: "ページを読み込めませんでした",
        retryHint: "接続を確認して、もう一度お試しください。",
        retry: "再読み込み",
        projectError: "プロジェクトを開けませんでした。通信を確認して、もう一度お試しください。",
      }
  }
}
