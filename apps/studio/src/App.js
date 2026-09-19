import { createElement } from "react";
import { App as MoonApp } from "../../../_build/js/release/build/ui/ui.js";
import "./ui/AssistantPanel.css";
import "./ui/ConnectionStatus.css";
import "./ui/EasingEditor.css";
import "./ui/export-dialog.css";
import "./ui/groups.css";
import "./ui/MediaTimeline.css";
import "./ui/OperationFeedback.css";
import "./ui/ProjectDialog.css";
import "./ui/ProjectPreview.css";
import "./ui/PropertyAnimation.css";
import "./ui/SceneTabs.css";
import "./ui/Stage.css";
import "./ui/TexInput.css";
import "./ui/TimelineFeedback.css";
import "./ui/TimelineSeek.css";
// Project snapshots belong to MoonBit; load file/media I/O only when requested.
const services = {
    portableProject: (...args) => import("./editor/images.js").then(module => module.portableProject(...args)),
    rehostImageAssets: (...args) => import("./editor/images.js").then(module => module.rehostImageAssets(...args)),
    createProjectRoom: (...args) => import("./editor/projects.js").then(module => module.createProjectRoom(...args)),
};
export const App = props => createElement(MoonApp, { ...props, services });
