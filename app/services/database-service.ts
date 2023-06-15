import { DatabaseCore, IDatabaseCore } from "@/base/database/core";
import { Eventable } from "@/base/event";
import { createDecorator } from "@/base/injection/injection";
import { ILogService, LogService } from "@/services/log-service";

export interface IDatabaseServiceState {
  dbInitializing: number;
  dbInitialized: number;
}

export const IDatabaseService = createDecorator("databaseService");

export class DatabaseService extends Eventable<IDatabaseServiceState> {
  constructor(
    @IDatabaseCore private readonly _databaseCore: DatabaseCore,
    @ILogService private readonly _logService: LogService
  ) {
    super("databaseService", {
      dbInitializing: 0,
      dbInitialized: 0,
    });

    this._databaseCore.on(["dbInitializing", "dbInitialized"], (payload) => {
      this.fire({ [payload.key]: payload.value });
    });
  }

  /**
   * Initialize the database.
   * @param reinit - Whether to reinitialize the database. */
  async initialize(reinit: boolean = true) {
    await this._databaseCore.initRealm(reinit);
  }

  /**
   * Pause the synchronization of the database. */
  pauseSync() {
    this._databaseCore.pauseSync();
  }

  /**
   * Resume the synchronization of the database. */
  resumeSync() {
    this._databaseCore.resumeSync();
  }

  /**
   * Migrate the local database to the cloud database. */
  migrateLocaltoCloud() {
    // TODO: implement
  }
}
