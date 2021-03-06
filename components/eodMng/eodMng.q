/L/ Copyright (c) 2011-2014 Exxeleron GmbH
/L/
/L/ Licensed under the Apache License, Version 2.0 (the "License");
/L/ you may not use this file except in compliance with the License.
/L/ You may obtain a copy of the License at
/L/
/L/   http://www.apache.org/licenses/LICENSE-2.0
/L/
/L/ Unless required by applicable law or agreed to in writing, software
/L/ distributed under the License is distributed on an "AS IS" BASIS,
/L/ WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
/L/ See the License for the specific language governing permissions and
/L/ limitations under the License.

/A/ DEVnet:  Bartosz Dolecki
/V/ 3.0

/S/ End of day management component:
/S/ Responsible for:
/S/ - detecting rdb end of day process
/S/ - housekeeping - compressing / conflating / deleting old partitions
/S/ - synchronizing data with mirror hosts
/S/
/S/ Components:
/S/ End of day management module consists of following components
/S/ * End of day manager (<eodMng.q>) - core of the whole module, it monitors rdb state (regarding eod) and triggers housekeeping and synchronization when needed (by detecting which hosts should be synchronized and passing necessary parameters to <hdbSync.q>); it also reports warnings and errors
/S/ * Housekeeping script (<hdbHk.q>) - is a plug-in based process that handles hdb housekeeping (deletion of old partitions, data compression, snapshots etc.); <hdbHk.q> has its own configuration specifying tasks that need to be performed (see <hdbHk.q> for details)
/S/ * Synchronization script (<hdbSync.q>) - uses rsync to synchronize hdb in two cases:
/S/     1. - slave host pulls data from primary host 
/S/     2. - primary host pushes data to slave hosts in cold standby for synchronization 
/S/ 
/S/ Status files:
/S/ 
/S/ Each part of the module (each component) has its own status file
/S/ 
/S/ 1. - File generated by end of day manager (<eodMng.q>) - used only internally to restore eodMng status in case of process restart
/S/ *Status format*
/S/ (start code)
/S/ status next_eod_date last_update_time last_sync_host
/S/ (end)
/S/ where
/S/ (start code)
/S/ next_eod_date - date of next end of day expected by eodMng
/S/ last_update_time - time of the last update of the status (file is updated at regular time intervals)
/S/ last_sync_host - host with which data was synchronized during last end of day, �none� if no synchronization occurred � for example in case of a primary host)
/S/ (end)
/S/ 
/S/ Example
/S/ (start code)
/S/ idle 2014.04.25 2014.04.25D10:40:00.000000000 none
/S/ (end)
/S/ *File details*
/S/ Name - odMngStatus
/S/ Location - file located in data folder of the eodMng process
/S/ *Available statuses*
/S/ unknown - initial state (right after process start) changes after first rdb status reading
/S/ idle - end of day processing for the last day finished successfully and database is not performing any activities regarding end of day processing
/S/ eod_during - end of day processing in progress
/S/ housekeeping - performing housekeeping on rdb
/S/ sync_with_cold - housekeeping finished - sending data to cold hosts (if any)
/S/ sync_before - waiting for the primary host to be in the idle mode for the synchronization to start
/S/ sync_during - synchronization with primary host in progress
/S/ recovery - recoverable error during end of day processing occurred, however, the synchronization can still be performed (for now this situation occurs only when �wsfull signal is intercepted); if eodMng is in recovery state and none of the hosts with higher priority succeeded with end of day processing, hosts with lower priority are checked
/S/ error - last end of day processing failed (eg. out of memory, out of disk space etc.), as a result data in hdb might be corrupted; if next end of day is successful, eodMng will be back into idle state; 
/S/ *Notes*
/S/ * Underlying cause of the error state is logged, please check the monitor or logfile for the eodMng
/S/ * When housekeeping processes are completed on the primary host, the status is switched to idle (with date increased by 1 day) - this state indicates that all secondary hosts can synchronize data with it; please remember that active hosts pull data from primary host, while for cold hosts data is pushed by the primary host
/S/ 
/S/ 2. - File generated by housekeeping (<hdbHk.q>) - used to inform eodMng of housekeeping status
/S/ *Status format*
/S/ (start code)
/S/ status timestamp
/S/ (end)
/S/ where
/S/ (start code)
/S/ timestamp � timestamp of the status
/S/ (end)
/S/ Example
/S/ (start code)
/S/ begin 2013.02.17T16:38:44.812
/S/ (end)
/S/ *File details*
/S/ Location - file located in data folder of eodMng process
/S/ *Available statuses*
/S/ begin - housekeeping in progress
/S/ success - housekeeping process finished successfully
/S/ 
/S/ 4. - File generated by synchronization (<hdbSync.q>) - used to inform eodMng of synchronization status
/S/ *Status format*
/S/ (start code)
/S/ status timestamp
/S/ (end)
/S/ where
/S/ (start code)
/S/ timestamp � timestamp of the status
/S/ (end)
/S/ Example
/S/ (start code)
/S/ sync_partition 2013.02.17T16:38:44.812
/S/ (end)
/S/ *File details*
/S/ Location - file located in data folder of eodMng process
/S/ *Available statuses*
/S/ begin - synchronization started - sym file backup
/S/ sync_partition - sym backup completed, synchronizing current partition
/S/ sync_all - sym backup completed, synchronizing current partition   
/S/ success - synchronization successful
/S/ *Notes*
/S/ 
/S/ * File sync.cfg in the in the configuration directory (etc/) needs to be used to specify the order of the hosts, more specifically the cfg.eodOrder variable has to be defined, for example:
/S/ (start code)
/S/ [group:core]
/S/    [[core.eodMng]]
/S/       cfg.eodOrder = core.eodMng, prod2.eodMng, prod3.eodMng
/S/ (end)
/S/ *	In the above example, the core.eodMng process is considered to be master (as is listed first), and prod2.eodMng, prod3.eodMng processes will synchronize data with it
/S/ *	File sync.cfg is read by eodMng process before synchronisation and can be used to select master host for synchronisation. For example, consider a case when host of core.eodMng malfunctions and can no longer be used as a source of synchronisations, but prod2.eodMng works well. Then change in the order will result in prod2.eodMng becoming source of data for synchronisation for next end of day process. If host of core.eodMng becomes available again, the previous order can be restored
/S/ *	The only case when sync.cfg is not required, is a setup, where there is only one host (ie. no synchronisation will ever be performed)
/S/ 
/S/ Status table:
/S/ Overall status can be seen in the <.eodmng.status> table
/S/ (start code)
/S/ | host         | state | syncDate   | timeStamp               |    db    | current | cold | lastSyncHost |
/S/ |--------------|-------|------------|-------------------------|----------|---------|------|--------------|
/S/ | core.eodMng  | idle  | 2013.02.16 | 2013.02.15T15:48:50.498 | :kdb/db0 | 0       | 0    |none          |
/S/ | prod2.eodMng | idle  | 2013.02.16 | 2013.02.15T15:48:36.102 | :kdb/db1 | 1       | 0    |core.eodMng   |
/S/ | prod3.eodMng | error | 2013.02.15 | 2013.02.15T15:48:47.112 | :kdb/db2 | 0       | 1    |core.eodMng   |
/S/ (end)
/S/ where
/S/ host - process name (defined in system configuration file) of the eodMng process 
/S/ state - state of eodMan process
/S/ syncDate - date of next synchronization / end of day processing
/S/ timeStamp - timestamp of the last status update from given host
/S/ db - path to hdb
/S/ current [boolean] - true indicates that this host is a current process
/S/ cold [boolean] - true indicates that host is in cold standby (no eodMng process running)
/S/ lastSyncHost [symbol] - process name (as in host column) pointing to source of last synchronisation (or none if no sync performed)
/S/ 
/S/ Sample statuses of primary and secondary hosts:
/S/ *Primary host*
/S/ (start code)
/S/ | Action                                      | eodMng status   |
/S/ |---------------------------------------------|-----------------|
/S/ | eodMng is waiting for EOD event             | idle            |
/S/ | rdb starts EOD process                      | idle            |
/S/ | eodMng reads EOD status file                | eod_during      |
/S/ | rdb completes EOD process                   | eod_during      |
/S/ | eodMng reads EOD status file                | housekeeping    |
/S/ | eodMng starts housekeeping                  | housekeeping    |
/S/ | housekeeping completed                      | sync_before     |
/S/ | eodMng pushes data to cold hosts            | sync_with_cold  |
/S/ | secondary hosts sync data with primary host | idle            |
/S/ (end)
/S/ *Secondary host*
/S/ (start code)
/S/ | Action                                          | eodMng status |
/S/ |-------------------------------------------------|---------------|
/S/ | eodMng is waiting for EOD event                 | idle          |
/S/ | rdb starts EOD process                          | idle          |
/S/ | eodMng reads EOD status file                    | eod_during    |
/S/ | rdb completes EOD process                       | eod_during    |
/S/ | eodMng reads EOD status file                    | housekeeping  |
/S/ | eodMng starts housekeeping                      | housekeeping  |
/S/ | housekeeping completed                          | sync_before   |
/S/ | eodMng waits for primary host to finish its EOD | sync_before   | 
/S/ | secondary hosts pulls data from primary host    | sync_during   |
/S/ | synchronisation completed successfully          | idle          |
/S/ (end)

/------------------------------------------------------------------------------/
system"l ",getenv[`EC_QSL_PATH],"/sl.q";
.sl.init[`eodMng];

/------------------------------------------------------------------------------/
.sl.lib["cfgRdr/cfgRdr"];
.sl.lib["qsl/timer"];
.sl.lib["qsl/handle"];


/------------------------------------------------------------------------------/
/G/ Table with status information
/P/ host:SYMBOL         - eodMng process, defined by an address and port
/P/ state:SYMBOL        - state of eodMng process
/P/ syncDate:DATE       - process pid
/P/ timeStamp:TIMESTAMP - timestamp of the last status update from given host
/P/ db:SYMBOL           - path to hdb
/P/ current:BOOLEAN     - true means that this host is current process
/P/ cold:BOOLEAN        - true means that host is in cold standby (no eodMng process running)
/P/ lastSyncHost:SYMBOL - process name (as in host column) pointing to source of last synchronization (or none if no sync performed)

.eodmng.status:([host:`$()] state:`$(); syncDate:`date$(); timeStamp:`timestamp$(); db:`$(); current:`boolean$(); cold:`boolean$(); lastSyncHost:`$());
// .eodmng.p.restart[]

/F/ initializes failover environment by loading config file and starting timer
/P/ configFile:String - name of file with config
// 
// .eodmng.p.init[]
.eodmng.p.init:{[]
  .eodmng.p.configure[.eodmng.cfg];
  isConsistent:.eodmng.setAndVerifyEodOrder[];
  
  if[not .eodmng.setAndVerifyEodOrder[];
    .log.error[`eodMng] "Eod order is not consistent across remote eod managers - further activities won't be performed";
    .eodmng.p.changeState[`error];
    :();
    ];
  .log.info[`eodMng] "eodMng up and running for ", .eodmng.cfg`rdbName;
  .eodmng.stChangeTime:.eodmng.p.getCurrentTS[];
  .tmr.start[`.eodmng.p.timeouts;`int$(100*rand count .eodmng.cfg[`timer] % 100) + (.eodmng.cfg[`timer] * 1 + count .eodmng.p.dbList[]);`.eodmng.p.timeouts];
  };

.eodmng.p.configure:{[cfg]
  list:update hdbPath:string .cr.getCfgField'[hdb;`group;`dataPath] from .eodmng.cfg.eodMngList;
  .eodmng.cfg.eodMmg2hdbPath:exec eodMng!(hsym each `$.cr.getCfgField'[hdb;`group;`host],'hdbPath) from list;

  .eodmng.state:`unknown ;
  .eodmng.date:.eodmng.p.getCurrentDate[];

  .eodmng.comDir:hsym cfg`comDir;
  .eodmng.statusFile:` sv .eodmng.comDir,`eodMngStatus;
  .eodmng.histFile:` sv .eodmng.comDir,`eodResult;
  .eodmng.syncStatusFile:` sv .eodmng.comDir,`syncStatus;
  .eodmng.hkStatusFile:` sv .eodmng.comDir,`hkStatus;
  .eodmng.rdbName:cfg`rdbName;
  .eodmng.rdbFile:`$string[.eodmng.cfg.rdbDataDir], "/eodStatus";
  .eodmng.rdbDataDir:.eodmng.cfg.rdbDataDir;
  .eodmng.eodSuccFile:`$string[.eodmng.cfg.dataPath], "/eodSuccess";
  .eodmng.eodSuccHnd:hopen .eodmng.eodSuccFile;

  .eodmng.coldSyncing:-1;
  .eodmng.p.timeoutTryRestoreStatus[];
  .eodmng.hosts:exec eodMng from cfg`eodMngList;
  colds:cfg`eodMngListCold;
  active:.eodmng.hosts except colds;

  system "S ",string `int$.sl.zt[];
  .hnd.hopen[active;cfg`timeout;`eager];
  idx:first where 0i~/:.hnd.h each active;
  // send idx to other eodMng in status file
  .eodmng.myIdx:idx;

  .eodmng.p.hArgs:idx#.eodmng.hosts;
  .eodmng.p.lArgs:(idx+1)_.eodmng.hosts;

  `.eodmng.status insert flip flip (.eodmng.hosts;`unknown;0Nd;0Np;.eodmng.cfg.eodMmg2hdbPath[.eodmng.hosts];.eodmng.hosts in .eodmng.hosts[idx];.eodmng.hosts in colds;`none);
   .eodmng.cfg.eodOrder:.eodmng.hosts;
  };

/F/ returns currently active eodSync servers that have higher priority than this host
.eodmng.p.getHArgs:{
  :exec server from .hnd.status where server in .eodmng.p.hArgs, state=`open
  };
    
/F/ returns currently active eodSync servers that have lower priority than this host
.eodmng.p.LArgs:{
  :exec server from .hnd.status where server in .eodmng.p.lArgs, state=`open
  };

/F/ returns all active eodSync servers
.eodmng.p.dbList:{
  :.eodmng.p.getHArgs[],.eodmng.p.LArgs[]
  }; 
 
/F/ reports errors if one (or more) host connections are not available   
.eodmng.reportConnections:{[]
  servers:exec server from .hnd.status where (not state=`open),(not server=`);
  if[0<count servers; .log[`error][`eodMng] "Unable to connect to : ",1_"" {[x;y] x,",",y}/ string[servers]];
  };
    
/F/ changes state, notifies other processes and logs apropriate message
.eodmng.p.changeState:{[newState]
  if[not .eodmng.state~newState;
    if[.eodmng.state~`idle;.eodmng.reportConnections[]];
    level:$[`error~newState;`error;`info];
    .log[level][`eodMng] "status changed : ", (string .eodmng.state) , " -> " , (string newState);
    .eodmng.stChangeTime:.eodmng.p.getCurrentTS[];
    .eodmng.state:newState;
    .eodmng.p.notifyAll[];
    ];
  };
    
/F/ timer - main function for monitoring db status
.eodmng.p.timeouts:{[]
  ost:.eodmng.state;

  .eodmng.p.saveStatus[];
  .eodmng.p.showStatus[];
  .eodmng.p.notifyAll[];

  diff:.eodmng.p.getTimeDiff[];
  if[diff<(.eodmng.cfg[`timer] * 2 + count .eodmng.p.dbList[]); :()]; / delay further processing  so it can get async updates from others
  .eodmng.p.processStatus[.eodmng.state][ost];
  if[.eodmng.coldSyncing>=0;.eodmng.p.checkColdSyncs[]];
  };

/F/ calculates difference (in miliseconds) between current time and last time the state changed
.eodmng.p.getTimeDiff:{[]
  :(`long$.eodmng.p.getCurrentTS[]-.eodmng.stChangeTime)%1000*1000;
  }
    
/F/ starts housekeeping process
.eodmng.p.startHousekeeping:{
  if[not ""~.eodmng.cfg.hkProcessName;
    .log.info[`eodMng] "Housekeeping started at ", string ts:.eodmng.p.getCurrentTS[];
    result:.event.dot[`eodMng;`.eodmng.p.runHkScript;(.eodmng.cfg.hkProcessName;`date$ts);`error;`info`info`error;"Starting housekeeping script"];
    if[result~`error;
      .eodmng.p.changeState[`recovery];
      //.eodmng.date:.eodmng.date+1;
      ];
    :()
    ];
  .eodmng.p.changeState[`sync_before];
  };

/F/ actions to undertake when in `idle state
/P/ ost:Symbol - previous state 
.eodmng.p.processIdle:{[ost]
  .eodmng.p.checkStatus[];
  diff:diff:.eodmng.p.getTimeDiff[];
  if[(ost~.eodmng.state) & (.eodmng.state~`idle) & .eodmng.cfg.idleHangTime<diff;
    .eodmng.p.changeState[`error];
    .log.error[`eodMng] "idleHangTime exceeded, prevoius state change :", string[.eodmng.stChangeTime];
    ];
  };

/F/ actions to undertake when in `eod_during state
/P/ ost:Symbol - previous state 
.eodmng.p.processEodDuring:{[ost]
  .eodmng.p.checkStatus[];

  if[.eodmng.state~`error; // if eod failed on rdb (eg. wsful) switch to recovery state
    .eodmng.p.changeState[`recovery];
    //.eodmng.date:.eodmng.date+1;
    ];

  diff:diff:.eodmng.p.getTimeDiff[];
  if[(ost~.eodmng.state) & (.eodmng.state~`eod_during) & .eodmng.cfg.eodHangTime<diff;
    .eodmng.p.changeState[`error];
    .log.error[`eodMng] "eodHangTime exceeded, previous state change :", string[.eodmng.stChangeTime];
    ];
  };

/F/ actions to undertake when in `housekeeping state
/P/ ost:Symbol - previous state 
.eodmng.p.processHousekeeping:{[ost]
  hkSt:.eodmng.p.checkProcessStatus[.eodmng.cfg.hkProcessName;.eodmng.hkStatusFile];
  if[hkSt in `success`failure;
    $[hkSt~`success;
      .log.info[`eodMng] "Housekeeping success at ", string .eodmng.p.getCurrentTS[];
      [
        .log.error[`eodMng] "Housekeeping failed, see '" , .eodmng.cfg.hkProcessName ,"' error log ";
        .eodmng.date:.eodmng.date+1;
        ]
      ];
    .eodmng.p.changeState[$[hkSt~`success;`sync_before;`recovery]];
    ];
  };

.eodmng.p.loadSyncHierarchy:{[]
  if[2>count .eodmng.status;
    :.eodmng.cfg.eodOrder;
    ];
  .log.info[`eodMng] "Loading sync config";
  res:.pe.atLog[`eodMng;`.cr.loadSyncCfg;();`error;`error];
 
  if[res~`error;.log.warn[`eodMng] "No sync.cfg file present - order taken from system.cfg";];
  order:$[res~`error;order:exec host from .eodmng.status;.cr.getSyncCfgField[`THIS;`group;`cfg.eodOrder]];
  if[not (count order) = count .eodmng.status;
      .log.warn[`eodMng] "number of hosts in sync.cfg and system.cfg differ - sync order not changed";
      :()];
  if[not all order in exec host from .eodmng.status;
    .log.warn[`eodMng] "not all hosts from system.cfg present in sync.cfg - sync order not changed";
    :()];
  myProcess:first exec host from .eodmng.status where current;
  idx:first where myProcess = order;
  .eodmng.p.hArgs:idx#order;
  .eodmng.p.lArgs:(1+idx)_order;
  .log.info[`eodMng] "Sync hierarchy: ", .Q.s1[order];
  .eodmng.cfg.eodOrder:order;
  :order;
  };

.eodmng.setAndVerifyEodOrder:{[]
  //check consistency
  myOrder:.cr.p.getEodOrder[];
  activeHosts:exec host from .eodmng.status where (not current),(not cold);
  toRefresh:exec server from .hnd.status where server in activeHosts, state<>`open;
  if[0<>count toRefresh;.hnd.refresh[toRefresh]];
  opened:exec server from .hnd.status where server in activeHosts, state=`open;
  closed:activeHosts except opened;
  if[0<>count closed;
    .log.warn[`eodMng] "Cannot communicate with ", .Q.s1[closed];
    ];
  orders:{.hnd.h[x] (`.cr.p.getEodOrder;())} each opened;
  consistency:$[0<>count orders;min 1b,min myOrder ~/: orders;1b];
  :consistency;
  };

/F/ actions to undertake when in `sync_before state
/P/ ost:Symbol - previous state 
.eodmng.p.processSyncBefore:{[ost]
  isConsistent: .eodmng.setAndVerifyEodOrder[];
  if[not isConsistent;
    .log.error[`eodMng] "Eod order is not consistent across remote eod managers - further activities won't be performed";
    .eodmng.p.changeState[`error];
    :();
    ];
  if[min (enlist 1b),.eodmng.p.finishFailedState each select state,syncDate from .eodmng.p.getReorderedStatus[]  where host in .eodmng.p.getHArgs[];
    .eodmng.p.changeState[`sync_with_cold];
    .eodmng.p.syncWithCold[];
    :();
    ];
  .eodmng.p.determineSync[];
  };

.cr.p.getEodOrder:{[]
  order:.eodmng.p.loadSyncHierarchy[];
  :(exec host from .eodmng.status)?order;
  };

/F/ actions to undertake when in `sync_before state
/P/ ost:Symbol - previous state 
.eodmng.p.processSyncWithCold:{[ost]
  if[.eodmng.coldSyncing<0;
    (neg .eodmng.eodSuccHnd) string[.eodmng.date];
    .eodmng.date:.eodmng.date+1;
    .eodmng.p.changeState[`idle];
    ];
  };

/F/ actions to undertake when in `sync_during state
/P/ ost:Symbol - previous state 
.eodmng.p.processSyncDuring:{[ost]
  syncSt:.eodmng.p.checkProcessStatus[.eodmng.cfg.syncProcessName;.eodmng.syncStatusFile];
  if[syncSt in `success`failure;
    $[syncSt~`success;
      .log.info[`eodMng] "Synchronization successful";
      .log.error[`eodMng] "Synchronization failed, see '" , .eodmng.cfg.syncProcessName ,"' error log for details"
      ];
    if[syncSt~`success;
      (neg .eodmng.eodSuccHnd) string[.eodmng.date];
      ];
    .eodmng.date:.eodmng.date+1;      
    .eodmng.p.changeState[$[syncSt~`success;`idle;`error]];
    ];
  };

/F/ actions to undertake when in `recovery state
/P/ ost:Symbol - previous state 
.eodmng.p.processRecovery:{[ost]
  .eodmng.p.checkForDeadEnd[];
  .eodmng.p.determineSync[];
  };

/F/ actions to undertake when in `error state
/P/ ost:Symbol - previous state 
.eodmng.p.processError:{[ost]
  result:.pe.at[.eodmng.checkServer;.eodmng.rdbName;{`error}];
  if[result~`running;
    sd:.eodmng.p.checkFileStatus[`$(string[.eodmng.rdbFile],string[.eodmng.date])];
    .eodmng.p.processFileStatus[first sd][last sd];
    if[.eodmng.state~`error;
      lastDate:last asc "D"${(neg count string[.sl.eodSyncedDate[]])#x}each string each key .eodmng.rdbDataDir;
      lastSuccessDate:"D"$last read0 .eodmng.eodSuccFile;
      if[lastDate>.eodmng.date;.eodmng.date:lastDate];
      if[lastSuccessDate~.eodmng.date-1;
        .eodmng.p.changeState[`idle];
        .log.info[`eodMng] "last eod was successfull -> restoring status to idle";
        ];  
      sd:.eodmng.p.checkFileStatus[`$(string[.eodmng.rdbFile],string[.eodmng.date])];
      .eodmng.p.processFileStatus[first sd][last sd];
      ];
    ];
  };

.eodmng.p.getReorderedStatus:{[]
  :update host:.eodmng.cfg.eodOrder from .eodmng.status each .eodmng.cfg.eodOrder
  };

/F/ determines if can sync with other host
.eodmng.p.determineSync:{[]
  // reorder status properly
  status:.eodmng.p.getReorderedStatus[];
  elist:$[.eodmng.state~`sync_before; 
    select state,syncDate from status where host in .eodmng.p.getHArgs[]; 
    select state,syncDate from status
    ];
      
  idx:elist?(`idle;.eodmng.date+1);
  if[idx<count elist;
    .eodmng.p.changeState[`sync_during];
    .eodmng.p.sync[(exec host from status)[idx]];
    ];
  };

/F/ maps state to function for handling that status
.eodmng.p.processStatus : ()!();
.eodmng.p.processStatus[`unknown]     : {[ost] .eodmng.p.checkStatus[];};
.eodmng.p.processStatus[`idle]        : .eodmng.p.processIdle;
.eodmng.p.processStatus[`eod_during]  : .eodmng.p.processEodDuring;
.eodmng.p.processStatus[`housekeeping]: .eodmng.p.processHousekeeping;
.eodmng.p.processStatus[`sync_before] : .eodmng.p.processSyncBefore;
.eodmng.p.processStatus[`sync_with_cold] : .eodmng.p.processSyncWithCold;
.eodmng.p.processStatus[`sync_during] : .eodmng.p.processSyncDuring;
.eodmng.p.processStatus[`recovery]    : .eodmng.p.processRecovery;
.eodmng.p.processStatus[`error]       : .eodmng.p.processError;

/F/ restarts status info (useful when `error was fixed)
// .eodmng.p.restart[]
.eodmng.p.restart:{[]
  .eodmng.p.changeState[`unknown];
  .log.info[`eodMng] "status restarted to : ", string[.eodmng.state], " with date ",string[.eodmng.date];
  .eodmng.date:.eodmng.p.getCurrentDate[];
  .eodmng.lastSyncHost:`none;
  };

/F/ logs db status on DEBUG level
.eodmng.p.showStatus:{[]
  .log.debug[`eodMng] "status : ", (string .eodmng.state), " ; date : ", string .eodmng.date;
  };

/F/ saves status to a file
.eodmng.p.saveStatus:{[]
  .pe.at[{.eodmng.statusFile 0: enlist (string .eodmng.state)," ",(string .eodmng.date)," ",(string .eodmng.p.getCurrentTS[])," ",string .eodmng.lastSyncHost};();{}];
  };

/F/ restores status from status file IF that file exists
.eodmng.p.timeoutTryRestoreStatus:{[]
  if[not ()~key .eodmng.statusFile;
    lines:" " vs first read0 .eodmng.statusFile;
    .eodmng.p.changeState[`$lines[0]];
    .eodmng.date:.eodmng.p.getCurrentDate[];
    .eodmng.lastSyncHost:`$lines[3];
    .eodmng.stChangeTime:.eodmng.p.getCurrentTS[];
    .log.info[`eodMng] "status restored to ", (string .eodmng.state);
    ];
  }

/F/ checks rdb status by monitoring its runtime status through yak
/F/ and checks db file for eod status
.eodmng.p.checkStatus:{[]
  result:.pe.at[.eodmng.checkServer;.eodmng.rdbName;{`error}];
  if[result in `error`stopped;
    .eodmng.p.changeState[`error];
    .log.error[`eodMng] "rdb process stoppped";
    ];
  if[result~`recovery;
    .eodmng.p.changeState[`recovery]
    ];
  if[(result~`running) & .eodmng.state in `unknown`idle`eod_during`error;
    sd:.eodmng.p.checkFileStatus[`$(string[.eodmng.rdbFile],string[.eodmng.date])];
    .eodmng.p.processFileStatus[first sd;last sd];
    ];
  };

/F/ checks syncScript status by monitoring its runtime status through yak
/F/ and checks db file for eod status
.eodmng.p.checkProcessStatus:{[pName;statusFileHnd]
  st:.eodmng.getProcessStatus[pName];
  if[st~"UNDEFINED";:`undefined];
  if[not st~"RUNNING";
    lines:.pe.at[read0;statusFileHnd;{enlist "fail"}];
    result:first " " vs first lines;
    if[result~"success";
      :`success;
      ];
    :`failure;
    ];
  :`running;
  };

/F/ checks if states of other hosts are either `error or `recovery.
/F/ sets status to error if so.
.eodmng.p.checkForDeadEnd:{[]
  status:.eodmng.p.getReorderedStatus[];

  if[ min {[x] (x[`state] in `error`recovery`unknown) | ((x[`state] ~ `idle) & x[`syncDate]~.eodmng.date)} each select state,syncDate from status ;
    .log.error[`eodMng] "No one to sync with!";
    .eodmng.date:.eodmng.date+1;
    .eodmng.p.changeState[`error];
    ];
  };
  
/F/ notifies all hosts from config about current status
.eodmng.p.notifyAll:{[]
  {.pe.at[.eodmng.p.notify;x;{}]} each exec host from .eodmng.status where (not current),(not cold);
  update syncDate:.eodmng.date, state:.eodmng.state, timeStamp:.eodmng.p.getCurrentTS[] from `.eodmng.status where current;
  };

/F/ converts file status to process state
.eodmng.p.processFileStatus : ()!();
.eodmng.p.processFileStatus[enlist "eodBefore"]   : {[date] .eodmng.date:date; if[not .eodmng.state~`error;.eodmng.p.changeState[`idle]];};
.eodmng.p.processFileStatus[enlist "eodDuring"]   : {[date] .eodmng.date:date; .eodmng.p.changeState[`eod_during];};
.eodmng.p.processFileStatus[enlist "eodSuccess"]  : {[date] .eodmng.date:date; .eodmng.p.changeState[$[not ""~.eodmng.cfg.hkProcessName;`housekeeping;`sync_before]];.eodmng.p.startHousekeeping[];};
.eodmng.p.processFileStatus[enlist "eodRecovery"] : {[date] .eodmng.date:date; .eodmng.p.changeState[`recovery]; .log.error[`eodMng] "rdb com file indicates recovery ";};
.eodmng.p.processFileStatus[enlist "eodFail"]     : {[date] .eodmng.date:date; if[not .eodmng.state~`error;.eodmng.p.changeState[`error]; .log.error[`eodMng] "rdb com file indicates error"; .eodmng.date:.eodmng.date+1;]; };
.eodmng.p.processFileStatus[enlist "noFile"]      : {[date] .eodmng.date:date; if[not .eodmng.state~`error;.eodmng.p.changeState[`error]; .log.error[`eodMng] "no rdb com file"; ]; };
/F/ relation telling if eod finished with failure (or did not perform eod)
/P/ pair:(Symbol;Date) - pair representing state to check
/R/ :Bool - 1b if eod for given state finished with failure, 0b otherwise
.eodmng.p.finishFailedState:{[st]
  a: (st[`state]) in `recovery`error;
  b: (.eodmng.date > (st[`syncDate])) & st[`state]~`idle;
  a | b
  };
/F/ sends data to all hosts with cold status
.eodmng.p.syncWithCold:{[]
  colds:exec db from .eodmng.status where cold;
  .eodmng.coldSyncing:count colds;
  };
  
/F/ check status of synchronization with colds hosts and triggers forementioned synchronization if needed
.eodmng.p.checkColdSyncs:{[]
  colds:exec host from .eodmng.status where cold;
  source:first exec db from .eodmng.status where current;
  result:$[.eodmng.coldSyncing<count colds;
           .eodmng.p.checkProcessStatus[.eodmng.cfg.syncProcessName;.eodmng.syncStatusFile];
           `empty];
  if[result in `failure`success`empty;
    .eodmng.p.coldReport[colds[.eodmng.coldSyncing];result];
    .eodmng.coldSyncing:.eodmng.coldSyncing-1;
    if[.eodmng.coldSyncing>=0;
      destHost:colds[.eodmng.coldSyncing];
      dest:first exec db from .eodmng.status where host=destHost;
      .log.info[`eodMng] "sending data to cold host ", string (destHost);
      .event.dot[`eodMng;`.eodmng.p.runSyncScript;(source;dest;.eodmng.date);();`info`info`error;"sending data to cold host ", (string destHost)];
      ];
    ];
  };

/F/ reports status of cold hosts synchronization
.eodmng.p.coldReport:{[x;y]
  if[y~`success;.log.info[`eodMng] "synchronizing cold host ",(string x)," finished at " , string .eodmng.p.getCurrentTS[]];
    if[y~`failure;.log.error[`eodMng] "synchronizing cold host ",(string x)," failed at " , string .eodmng.p.getCurrentTS[]];
  };

/F/ notifies single host on current state
/P/ host:Symbol - symbol representing host to notify
.eodmng.p.notify:{[host]
  if[(not .hnd.status[host][`state]~`open) and (not .hnd.status[host][`cold]) ;
    .hnd.refresh[enlist host];
    ];

  if[.hnd.status[host][`state]~`open;
    .hnd.ah[host] (`.eodmng.p.updateStatus;.eodmng.myIdx;.eodmng.state;.eodmng.date;.eodmng.p.getCurrentTS[]);
    ];
  };

/F/ function that handles status updates from other hosts.
/F/ it is called asynchronously by other hosts
/P/ idx:INTEGER - symbol representing remote host
/P/ status:SYMBOL - current status of remote host
/P/ d:DATE - date for status of the remote host
/P/ timestamp:DATETIME - timestamp of notification
/E/ .eodmng.p.updateStatus[1;`recovery,2011.11.12,.eodmng.p.getCurrentTS[]].eodmng.myAddr
.eodmng.p.updateStatus:{[idx;st;d;timestamp]
  update state:st, syncDate:d, timeStamp:timestamp from `.eodmng.status where i=idx;
  };

/F/ extract runtime status (from yak) for given process
/P/ pName:STRING - name of process
/R/ :STRING - status retrieved from yak
.eodmng.getProcessStatus:{[pName]
  cmd:"yak info ", pName ," -d\",\" -f \"uid:7#status:5\"";
  res:.pe.at[system; cmd;
  {[x;pName;cmd].log.warn[`eodMng]"Yak call invalid : ",cmd;"ERROR"}[;pName;cmd]];
  if[any "ERROR" in res;
    :"UNDEFINED";
    ];

  r:("," vs) each 1_res;
  :r[(r[;0])?pName;1];
  };

/F/ checks runtime status of db process
/P/ pName:STRING - name of db process
/R/ :SYMBOL - `running, `stopped or `error accordingly to information qiven by yak.
.eodmng.checkServer:{[pName]
  result:.eodmng.getProcessStatus[pName];
  if[result in ("TERMINATED";"STOPPED";"WSFULL");:`error];
  if[result~"UNDEFINED";:`undefined];
  $[result in ("RUNNING";"DISTURBED");`running;`stopped]
  };

/F/ chcecks db file and reads db status from it
/P/ files:SYMBOL - path to db status file  
.eodmng.p.checkFileStatus:{[file]
  lines:.pe.at[read0;file;{enlist ("noFile ",string .eodmng.date)}];
  list:" " vs first lines;
  (first list;"D"$ last list)
  };
  
/F/ performs synchronization with remote host
/P/ host:SYMBOL - symbol representing remote host  
.eodmng.p.sync:{[hst] 
  src:first exec db from .eodmng.status where host=hst;
  dst:first exec db from .eodmng.status where current;
  .event.dot[`eodMng;`.eodmng.p.runSyncScript;(src;dst;.eodmng.date);();`info`info`error;"starting syncScript to sync with ", (string hst)];
  .eodmng.lastSyncHost:hst;
  };  

/F/ runs syncScript.q with given settings
/P/ src:STRING - source dir for syncing
/P/ dst:STRING - destination dir for syncing
/P/ part:STRING - partition name (empty String for unpartitioned db)
.eodmng.p.runSyncScript:{[src;dst;date]
  cmd:"yak start ",.eodmng.cfg.syncProcessName," -a \"",
        "\\\"", (1_string src), "\\\" ",
        "\\\"", (1_string dst), "\\\" ",
        "\\\"", (string date), "\\\" ",
        "\\\"", (1_string .eodmng.cfg.symDir), "\\\" ",
        "\\\"", (1_string[.eodmng.syncStatusFile]), "\\\" ",
        "\"";
  .log.info[`eodMng] "Start synchronization with command ", cmd;
  system cmd;
  };

/F/ runs hkScript.q 
/P/ pName:STRING - name of hkScript process in Yak
.eodmng.p.runHkScript:{[pName;date]
  dst:first exec db from .eodmng.status where current;
  cmd:"yak start ",pName," -a \"", "-hdb \\\"", 1_string[dst], "\\\" ",
        "-hdbConn \\\"", string[.eodmng.cfg.hdbConn], "\\\" ",
        "-date \\\"", string[date], "\\\" ",
        "-status \\\"", 1_string[.eodmng.hkStatusFile], "\\\" ",
        "\"";
  .log.info[`eodMng] "Start housekeeping with command:", cmd;
  system cmd;
  :`completed;
  };

/F/ returns current timestamp 
.eodmng.p.getCurrentTS:.sl.zp;

/F/ returns current date 
.eodmng.p.getCurrentDate:.sl.eodSyncedDate;


/==============================================================================/
.sl.main:{[flags]
  .eodmng.cfg.idleHangTime:    .cr.getCfgField[`THIS;`group;`cfg.idleHangTime];
  .eodmng.cfg.eodHangTime:     .cr.getCfgField[`THIS;`group;`cfg.eodHangTime];
  .eodmng.cfg.timer:           .cr.getCfgField[`THIS;`group;`cfg.timer];
  .eodmng.cfg.timeout:         .cr.getCfgField[`THIS;`group;`cfg.timeout];
  .eodmng.cfg.comDir:          .cr.getCfgField[`THIS;`group;`cfg.comDir];
  .eodmng.cfg.dataPath:        .cr.getCfgField[`THIS;`group;`dataPath];
  
  .eodmng.cfg.rdbName:         .cr.getCfgField[`THIS;`group;`cfg.rdbName];
  .eodmng.cfg.rdbDataDir:      .cr.getCfgField[`$.eodmng.cfg.rdbName;`group;`dataPath];
  	
  .eodmng.cfg.eodMngList:      .cr.getCfgField[`THIS;`group;`cfg.eodMngList];
  .eodmng.cfg.eodMngListCold:  .cr.getCfgField[`THIS;`group;`cfg.eodMngListCold];
  .eodmng.cfg.hdbConn:         .cr.getCfgField[`THIS;`group;`cfg.hdbConn];
  .eodmng.cfg.syncProcessName: .cr.getCfgField[`THIS;`group;`cfg.syncProcessName];
  .eodmng.cfg.hkProcessName:   .cr.getCfgField[`THIS;`group;`cfg.hkProcessName];
  .eodmng.cfg.symDir:          .cr.getCfgField[`THIS;`group;`cfg.symDir];
  
  .sl.libCmd[];
  .eodmng.p.init[];
  };

/------------------------------------------------------------------------------/

.sl.run[`eodMng;`.sl.main;`];
