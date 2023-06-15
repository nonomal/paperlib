import fs from "fs";
import path from "path";
import { Store } from "pinia";

import { APIClient } from "./api/api";
import { AppInteractor } from "./interactors/app-interactor";
import { EntityInteractor } from "./interactors/entity-interactor";
import { FeedInteractor } from "./interactors/feed-interactor";
import { PluginSideInteractor } from "./interactors/plugin-side-interactor";
import { PreviewInteractor } from "./interactors/preview-interactor";
import { RenderInteractor } from "./interactors/render-interactor";
import { WordAddinInteractor } from "./interactors/word-addin-interactor";
import { Preference } from "./preference/preference";
import { APPService } from "./services/app-service";
import { DatabaseService } from "./services/database-service";
import { LogService } from "./services/log-service";
import { PaperService } from "./services/paper-service";
import { PreferenceService } from "./services/preference-service";
import { StateService } from "./services/state-service/state-service";
import { IProcessingState } from "./services/state-service/state/processing";
import { MainRendererStateStore } from "./state/renderer/appstate";
import { NetworkTool } from "./utils/got";
import { Logger } from "./utils/logger";

declare global {
  interface Window {
    appInteractor: AppInteractor;
    entityInteractor: EntityInteractor;
    renderInteractor: RenderInteractor;
    feedInteractor: FeedInteractor;
    previewInteractor: PreviewInteractor;
    pluginSideInteractor: PluginSideInteractor;
    wordAddinInteractor: WordAddinInteractor;

    logger: Logger;
    networkTool: NetworkTool;
    preference: Preference;
    stateStore: MainRendererStateStore;
  }

  interface Realm {
    safeWrite: <T>(callback: () => T) => T;
  }

  var paperlibAPI: APIClient;

  var appService: APPService;
  var preferenceService: PreferenceService;
  var stateService: StateService;
  var logService: LogService;
  var databaseService: DatabaseService;
  var paperService: PaperService;

  var processingState: Store<"processingState", IProcessingState>;
}
