(function () {
    "use strict";
    var dashboard = angular.module("dashboard", []);
    dashboard.run(initChartTemplate);
    dashboard.controller("dashboardController", ['$scope', function ($scope) {
        $scope.ChartState = ChartState; // for use in ng-expressions in html
        $scope.collectionsData = ChartState.Loading;
        $scope.O365ClientsData = ChartState.Loading;
        $scope.NonOfficeClientsData = ChartState.Loading;
        $scope.versionsData = ChartState.Loading;
        $scope.languagesData = ChartState.Loading;
        $scope.adrData = ChartState.Loading;
        $scope.deploymentChartData = ChartState.Loading;
        $scope.adrsExist = true;
        $scope.strings = getStrings(["_O365UpdatesDashboardTitle",
            "DeviceCollection",
            "O365Channels",
            "O365Clients",
            "O365Languages",
            "O365Versions",
            "O365ProText",
            "O365ProLink",
            "Clients",
            "O365Architecture",
            "O365ClientsManaged",
            "O365ClientsUnmanaged",
            "O365ClientsTotal",
            "NonOfficeClients",
            "O365ProPlus",
            "O365Adrs",
            "O365AdrsNotAvailable",
            "O365DepSuccess",
            "O365DepTarget",
            "O365DepError",
            "OfficeProplusReadiness",
            "CreateAdr",
            "CreateClientAgentSettings",
            "ADR",
            "O365NoDeployments",
            "Office365Installer",
            "InsidersChannelLong",
            "InsidersChannelShort",
            "TargetedChannelLong",
            "TargetedChannelShort",
            "MonthlyChannelLong",
            "MonthlyChannelShort",
            "BroadChannelLong",
            "BroadChannelShort",
            "PerpetualVL2019Long",
            "PerpetualVL2019Short",
            "MonthlyEnterpriseChannelLong",
            "MonthlyEnterpriseChannelShort",
            "BetaChannelLong",
            "BetaChannelShort",
            "Browse",
            "Other",
            "NumberOfDevices",
            "ShowTable",
            "ShowChart"
        ]);
        
        $scope.getString = function (stringName) {
            return $scope.strings[stringName];
        };

        var NonOfficeClientsTable = "NonOfficeClientsTable";
        var O365ClientsTable = "O365ClientsTable";
        var O365VersionsTable = "O365VersionsTable";
        var O365languagesTable = "O365languagesTable";
        var O365ChannelsTable = "O365ChannelsTable"; 

        var channelNames = {
            "http://officecdn.microsoft.com/pr/64256afe-f5d9-4f86-8936-8840a6a4f5be": {
                "long": $scope.strings.InsidersChannelLong,
                "short": $scope.strings.InsidersChannelShort
            },
            "https://officecdn.microsoft.com/pr/64256afe-f5d9-4f86-8936-8840a6a4f5be": {
                "long": $scope.strings.InsidersChannelLong,
                "short": $scope.strings.InsidersChannelShort
            },
            "http://officecdn.microsoft.com/pr/492350f6-3a01-4f97-b9c0-c7c6ddf67d60": {
                "long": $scope.strings.MonthlyChannelLong,
                "short": $scope.strings.MonthlyChannelShort
            },
            "https://officecdn.microsoft.com/pr/492350f6-3a01-4f97-b9c0-c7c6ddf67d60": {
                "long": $scope.strings.MonthlyChannelLong,
                "short": $scope.strings.MonthlyChannelShort
            },
            "http://officecdn.microsoft.com/pr/b8f9b850-328d-4355-9145-c59439a0c4cf": {
                "long": $scope.strings.TargetedChannelLong,
                "short": $scope.strings.TargetedChannelShort
            },
            "https://officecdn.microsoft.com/pr/b8f9b850-328d-4355-9145-c59439a0c4cf": {
                "long": $scope.strings.TargetedChannelLong,
                "short": $scope.strings.TargetedChannelShort
            },
            "http://officecdn.microsoft.com/pr/7ffbc6bf-bc32-4f92-8982-f9dd17fd3114": {
                "long": $scope.strings.BroadChannelLong,
                "short": $scope.strings.BroadChannelShort
            },
            "https://officecdn.microsoft.com/pr/7ffbc6bf-bc32-4f92-8982-f9dd17fd3114": {
                "long": $scope.strings.BroadChannelLong,
                "short": $scope.strings.BroadChannelShort
            },
            "http://officecdn.microsoft.com/pr/f2e724c1-748f-4b47-8fb8-8e0d210e9208": {
                "long": $scope.strings.PerpetualVL2019Long,
                "short": $scope.strings.PerpetualVL2019Short
            },
            "https://officecdn.microsoft.com/pr/f2e724c1-748f-4b47-8fb8-8e0d210e9208": {
                "long": $scope.strings.PerpetualVL2019Long,
                "short": $scope.strings.PerpetualVL2019Short
            },
            "http://officecdn.microsoft.com/pr/55336b82-a18d-4dd6-b5f6-9e5095c314a6": {
                "long": $scope.strings.MonthlyEnterpriseChannelLong,
                "short": $scope.strings.MonthlyEnterpriseChannelShort
            },
            "https://officecdn.microsoft.com/pr/55336b82-a18d-4dd6-b5f6-9e5095c314a6": {
                "long": $scope.strings.MonthlyEnterpriseChannelLong,
                "short": $scope.strings.MonthlyEnterpriseChannelShort
            },
            "http://officecdn.microsoft.com/pr/5440fd1f-7ecb-4221-8110-145efaa6372f": {
                "long": $scope.strings.BetaChannelLong,
                "short": $scope.strings.BetaChannelShort
            },
            "https://officecdn.microsoft.com/pr/5440fd1f-7ecb-4221-8110-145efaa6372f": {
                "long": $scope.strings.BetaChannelLong,
                "short": $scope.strings.BetaChannelShort
            }
        };

        $scope.isO365InstallerOn = bridge.IsO365InstallerOn();
        $scope.hasAdrPermission = bridge.HasADRPermissions();
        $scope.hasClientSettingsPermissions = bridge.HasClientSettingsPermissions();

        $scope.keyPressDrillThrough = function (event, id) {
            if (event.keyCode == 13) {
                switch (id) {                  
                    case 'O365Versions':
                        window.external.OnModelTypeClick($scope.SMS_DeviceCollections.Selected.CollectionID, $scope.SMS_DeviceCollections.Selected.Name, '');
                        break;
                }
            }
        };


        // *** VARIABLE DECLARATIONS
        var COLL_DISP_LIMIT = 5; // determines the amount of collections displayed in the dropdown filter
        $scope.SMS_DeviceCollections = {}; //temp storage for collections data
        $scope.ADRS = []; // list of ADRs for dropdown selector

        // *** DATA QUERIES AND PREPARATION ***
        //gets collections data to load the Collections dropdown filter
        wmiQuery("SELECT CollectionID, Name, MemberCount FROM SMS_Collection Where CollectionType=2 ORDER BY LocalMemberCount DESC",
        SMS_DeviceCollectionsReceived);

        //get ADRs to load the ADR dropdown filter
        wmiQuery("SELECT DISTINCT AutoDeploymentID, Name FROM SMS_O365ADRs", function(res) {
            if (res.length == 0) {
                $scope.adrData = ChartState.NoDataFound;
                $scope.adrsExist = false;
                bridge.Log("SMS_O365ADRs returned no results", loggingStates.Error);
                return;
            }

            $scope.adrData = ChartState.DataReady;
            $scope.ADRS = res;
            $scope.ADR_choice = $scope.ADRS[0]; // default ADR dropdown 
            $scope.select_ADRchoice();
            $scope.$apply();
        });

        function SMS_DeviceCollectionsReceived(res) {
            if (res.length == 0) {
              logger.err("SMS_Collection returned no results");
              $scope.collectionsData = ChartState.NoDataFound;
              $scope.$apply();
              return;
            }

            // store first n number of results n = COLL_DISP_LIMIT and set default selected to first(largest) collection
            $scope.SMS_DeviceCollections.All = res.slice(0, COLL_DISP_LIMIT);
            $scope.SMS_DeviceCollections.Selected = res[0];

            for (var i = 0; i < $scope.SMS_DeviceCollections.All.length; ++i) {
                $scope.SMS_DeviceCollections.All[i].Name = bridge.GetCollectionAliasName($scope.SMS_DeviceCollections.All[i].Name);
            }

            $scope.collectionsData = ChartState.DataReady;
            $scope.SMS_DeviceCollectionChanged();

            $scope.$apply();
        };

        function getO365Data(collection) {
            var clientCounts = JSON.parse(window.external.GetO365ClientCounts(collection.CollectionID));
            var versionCounts = JSON.parse(window.external.GetO365VersionCounts(collection.CollectionID));
            var languageCounts = JSON.parse(window.external.GetO365LanguageCounts(collection.CollectionID));
            var channelCounts = JSON.parse(window.external.GetO365ChannelCounts(collection.CollectionID));
            var officeReadinessCounts86 = JSON.parse(window.external.GetOfficeReadinessCounts(collection.CollectionID, 'x86'));
            var officeReadinessCounts64 = JSON.parse(window.external.GetOfficeReadinessCounts(collection.CollectionID, 'x64'));
            var officeReadinessTotal = parseInt(officeReadinessCounts64.ReadyCount) + parseInt(officeReadinessCounts64.NotAssessedCount) + parseInt(officeReadinessCounts64.NeedsReviewCount) +
                parseInt(officeReadinessCounts86.ReadyCount) + parseInt(officeReadinessCounts86.NotAssessedCount) + parseInt(officeReadinessCounts86.NeedsReviewCount);
            if (officeReadinessTotal != 0) {
                $scope.$apply;
            }
            var clients, officeClients, nonOfficeClients, versions, languages, channels;
            // lengths will be 0 if query returns nothing, and charts will not render
            if (clientCounts.length == 0 || versionCounts.length == 0 || languageCounts.length == 0 || channelCounts.length == 0) {
                logger.err("SMS_O365UpdatesDashboard returned no results");
                $scope.O365ClientsData = ChartState.NoDataFound;
                $scope.versionsData = ChartState.NoDataFound;
                $scope.NonOfficeClientsData = ChartState.NoDataFound;
               // $scope.O365ProPlusData = ChartState.NoDataFound;
                $scope.languagesData = ChartState.NoDataFound;
                $scope.$apply();
                return;
            }
            clients = {
                'O365ClientsManaged': clientCounts.ManagedOffice365Clients,
                'O365ClientsTotal': clientCounts.Office365Clients,
                'clientsTotal': clientCounts.MemberCount
            }

            officeClients = {};
            nonOfficeClients = {};
            officeClients[$scope.getString("O365ClientsManaged")] = clientCounts.ManagedOffice365Clients;
            officeClients[$scope.getString("O365ClientsUnmanaged")] = clientCounts.Office365Clients - clientCounts.ManagedOffice365Clients;
            nonOfficeClients[$scope.getString("NonOfficeClients")] = clientCounts.MemberCount - clientCounts.Office365Clients;

            versions = {};
            languages = {};
            channels = {};
            
            var countMachineInVersion = 0;
            versionCounts.forEach(function (el) {
                versions[el.VersionToReport00] = el.NumClients;
                countMachineInVersion += Number(el.NumClients);
            })
            if (clientCounts.Office365Clients - countMachineInVersion > 0)
            {
                versions[$scope.strings.Other] = clientCounts.Office365Clients - countMachineInVersion;
            }

          languageCounts.forEach(function (el) {
              languages[el.ClientCulture00] = el.NumLangss;
          })

          var countMachineNotInChannel = 0;
          channelCounts.forEach(function (el) {
              if (channelNames[el.cfgUpdateChannel00] != null) {
                  channels[channelNames[el.cfgUpdateChannel00].long] = el.NumOnChannel;
              }
              else {
                  countMachineNotInChannel += Number(el.NumOnChannel);
              }
          })
          if (countMachineNotInChannel > 0) {
              // Put machine with cfgUpdateChannel not in any of the 4 defined channels to "Other"
              channels[$scope.strings.Other] = countMachineNotInChannel;
          }

          createClientChart(clients, $scope, '#O365Clients', $scope.getString("O365Clients"));
          createNonOfficeBarChart(clients, $scope, '#NonOfficeClientsChart', $scope.getString("NonOfficeClients"));
          var collID = $scope.SMS_DeviceCollections.Selected.CollectionID;
          var colName = $scope.SMS_DeviceCollections.Selected.Name;
          createPieChart(collID, colName, versions, '#versionsChart', $scope.getString("O365Versions"));
          createLanguagesChart(languages, $scope, '#languagesChart', $scope.getString("O365Languages"));
          createPieChartChannels(channels, '#channelsChart', $scope.getString("O365Channels"));

          $scope.createTable(O365ClientsTable, officeClients);
          $scope.createTable(NonOfficeClientsTable, nonOfficeClients);
          $scope.createTable(O365VersionsTable, versions);
          $scope.createTable(O365languagesTable, languages);
          $scope.createTable(O365ChannelsTable, channels);
            
          $scope.O365ClientsData = ChartState.DataReady;
          $scope.versionsData = ChartState.DataReady;
          $scope.NonOfficeClientsData = ChartState.DataReady;
          $scope.languagesData = ChartState.DataReady;
          $scope.channelsData = ChartState.DataReady; 

          $scope.$apply();
      };
        
        // Function to be used by createDeploymentStackBarChart , changing the data to the right format needed for drawing
        function deploymentDataAction(data) {
            var Success = [$scope.strings["O365DepSuccess"]];
            var Error = [$scope.strings["O365DepError"]];
            var Target = [$scope.strings["O365DepTarget"]];
            var columns = [];
            if (data.length != 0) {
                for (var i = 0; i < data.length; i++) {
                if (data[i].length == 1) {
                    Success[Success.length] = parseInt(data[i][0].NumberSuccess, 10);
                    Error[Error.length] = parseInt(data[i][0].NumberErrors, 10);
                    Target[Target.length] = parseInt(data[i][0].NumberTargeted, 10) - (parseInt(data[i][0].NumberErrors, 10) + parseInt(data[i][0].NumberSuccess, 10));
                }
                }
                columns = [Success, Error, Target];
            } else {
                columns = [];
            }
            columns = [Success, Error, Target];
            return columns;
        };
        
        //*** DOM CHANGE HANDLERS
        // handle collection dropdown selection
        $scope.SMS_DeviceCollectionChanged = function () {
            $scope.O365ClientsData = ChartState.Loading;
            $scope.NonOfficeClientsData = ChartState.Loading;
            $scope.versionsData = ChartState.Loading;
            $scope.languagesData = ChartState.Loading;
            $scope.channelsData = ChartState.Loading;
            getO365Data($scope.SMS_DeviceCollections.Selected);
        };

        /*** Donut Chart and  Data Table switch ***/
        $scope.toggleO365ClientsBar = function () {
            $scope.toggleChart(O365ClientsTable);
        }

        $scope.toggleNonOfficeClientsChart = function () {
            $scope.toggleChart(NonOfficeClientsTable);
        }

        $scope.toggleO365VersionsChart = function () {
            $scope.toggleChart(O365VersionsTable);
        }

        $scope.toggleO365languagesChart = function () {
            $scope.toggleChart(O365languagesTable);
        }

        $scope.toggleO365ChannelsChart = function () {
            $scope.toggleChart(O365ChannelsTable);
        }
    

        $scope.toggleChart = function (ChartIdentifier) {
            var o365Table;
            var o365Chart;
            var showChartButton;

            if (ChartIdentifier == O365ClientsTable) {
                o365Table = document.getElementById('O365Clients-table');
                o365Chart = document.getElementById('O365Clients');
                showChartButton = document.getElementById('showO365ClientsBarButton');
            }
            else if (ChartIdentifier == NonOfficeClientsTable) {
                o365Table = document.getElementById('NonOfficeClients-table');
                o365Chart = document.getElementById('NonOfficeClientsChart');
                showChartButton = document.getElementById('showNonOfficeClientsChartButton');
            }
            else if (ChartIdentifier == O365VersionsTable) {
                o365Table = document.getElementById('O365Versions-table');
                o365Chart = document.getElementById('versionsChart');
                showChartButton = document.getElementById('showO365VersionsChartButton');
            }
            else if (ChartIdentifier == O365languagesTable) {
                o365Table = document.getElementById('O365languages-table');
                o365Chart = document.getElementById('languagesChart');
                showChartButton = document.getElementById('showO365languagesChartButton');
            }
            else if (ChartIdentifier == O365ChannelsTable) {
                o365Table = document.getElementById('O365Channels-table');
                o365Chart = document.getElementById('channelsChart');
                showChartButton = document.getElementById('showO365ChannelsChartButton');
            }

            if (o365Table.style.display == 'none' || o365Table.style.display == '') {
                o365Table.style.display = 'table';
                o365Chart.style.display = 'none';
                showChartButton.innerHTML = $scope.strings["ShowChart"];
            }
            else if (o365Table.style.display == 'table') {
                o365Table.style.display = 'none';
                o365Chart.style.display = 'block';
                showChartButton.innerHTML = $scope.strings["ShowTable"];
            }
        }

        $scope.createTable = function (ChartIdentifier, data) {
            var table;
            var tableName;

            if (ChartIdentifier == O365ClientsTable) {
                table = document.getElementById("O365Clients-table");
                tableName = $scope.strings.O365Clients;
            }
            else if (ChartIdentifier == NonOfficeClientsTable) {
                table = document.getElementById("NonOfficeClients-table");
                tableName = $scope.strings.NonOfficeClients;
            }
            else if (ChartIdentifier == O365VersionsTable) {
                table = document.getElementById("O365Versions-table");
                tableName = $scope.strings.O365Versions;
            }
            else if (ChartIdentifier == O365languagesTable) {
                table = document.getElementById("O365languages-table");
                tableName = $scope.strings.O365Languages;
            }
            else if (ChartIdentifier == O365ChannelsTable) {
                table = document.getElementById("O365Channels-table");
                tableName = $scope.strings.O365Channels;
            }

            table.innerHTML = ""; //Set data to null in case it exists

            if (tableName != $scope.strings.NonOfficeClients)   // Do not add title line to NonOffice client table since always only one row
                $scope.appendChildItem(table, tableName, $scope.strings.NumberOfDevices);  // Add the 1st title row for the table

            var dataKeys = Object.keys(data);
            var chartData = convertObjectToArrayOfArrays(data, dataKeys);

            chartData.forEach(function (k, v) {
                //Add data row
                $scope.appendChildItem(table, k[0], k[1]);
            });

            table.style.display = 'none';
        }

        // Append rows to corresponding table
        $scope.appendChildItem = function (table, item, count) {
            var div = 'div';
            var row = 'row';

            // create new div element
            var addDiv = document.createElement(div);
            addDiv.className = row;

            //Add item and Count
            addDiv.innerHTML = bridge.AddRows(item, count);

            table.appendChild(addDiv);
        };

        $scope.select_ADRchoice = function () {
            $scope.select_ADR = $scope.ADR_choice.AutoDeploymentID;
            $scope.deploymentChartData = ChartState.Loading;
            wmiQuery("SELECT * FROM SMS_O365ADRs WHERE AutoDeploymentID = '" + $scope.select_ADR + "'", function(res) {

              var totalRes = [];
              for (var i = 0; i < res.length; i++) {
                wmiQuery("SELECT NumberSuccess, NumberErrors, NumberTargeted  from SMS_DeploymentSummary WHERE DeploymentID = '" + res[0].AssociatedDeploymentID + "'", function(depResults) {
                  if (depResults.length == 0) {
                    bridge.Log("SMS_DeploymentSummary returned no results", loggingStates.Error);
                  }
                  totalRes[totalRes.length] = depResults;

                  $scope.deploymentChartData = ChartState.DataReady;
                  var chartData = deploymentDataAction(totalRes);
                  createDeploymentStackBarChart("#deploymentsChart", chartData, $scope, chartTitle);
                  $scope.$apply();
                });
              }
            });
        };

        //*** BUTTON CODE LAUNCH WIZARDS
        // launch wizard to create a new Office 365 Application
        $scope.launchO365Installer = function () {
            try {
                window.external.LaunchO365Installer();
            }
            catch (err) {
                console.log("launch Office 365 Install Wizard failed");
            }
        };

        // launch wizard to create a new ADR
        $scope.launchWizardADR = function() {
        try {
            window.external.LaunchWizardADR();
        } catch (err) {
            console.log("launch ADR wizard failed");
        }
        };

        // launch wizard to create a new Client Agent Settings
        $scope.launchWizardClientAgent = function() {
        try {
            window.external.LaunchWizardClientAgent();
        } catch (err) {
            console.log("launch Client Agent Settings wizard failed");
        }
        };

        //handle Enter key press event
        $scope.keyPressToggle = function (event, action) {
            if (event.keyCode == 13) {
                if (action == 1)
                { $scope.launchO365Installer(); }
                if (action == 2)
                { $scope.launchWizardADR(); }
                if (action == 3)
                { $scope.launchWizardClientAgent(); }
            }
        };

        // launch wizard to pick a collection
        $scope.LaunchWizardCollectionPicker = function () {
            try {
                // Collection is a string
                var collection = window.external.LaunchWizardCollectionPicker();

                //get get collection object
                wmiQuery("SELECT CollectionID, Name, MemberCount FROM SMS_Collection Where CollectionType=2 and CollectionID='"+ collection +"'", function (res) {

                    if (res.length === 0) {
                        logger.err("SMS_Collection returned no results");
                        return;
                    }
                 
                    //Check if the item already exist in the dropdown
                    var selectedIndex = 0;
                    var listContainsCollection = $scope.SMS_DeviceCollections.All.some(function (item, index) {
                        if (item.CollectionID === collection) {
                            selectedIndex = index;
                            return true;
                    }
                    return false;
                    });
                  
                    //If the item does not exists in the list, add it to the top and pop one from the buttom
                    if (!listContainsCollection) {
                        //Add the selected collection as the first item in the dropdown
                        $scope.SMS_DeviceCollections.All.unshift(res[0]);
                        //Localize the name
                        $scope.SMS_DeviceCollections.All[0].Name = bridge.GetCollectionAliasName($scope.SMS_DeviceCollections.All[0].Name);
                        // Only COLL_DISP_LIMIT items at a time should show in the drop down
                        if ($scope.SMS_DeviceCollections.All.length > COLL_DISP_LIMIT) {
                            $scope.SMS_DeviceCollections.All.pop();
                        }
                    }
                    // Update the selected item in the dropdown 
                    $scope.SMS_DeviceCollections.Selected = $scope.SMS_DeviceCollections.All[selectedIndex];
                    $scope.collectionsData = ChartState.DataReady;
                    $scope.SMS_DeviceCollectionChanged();
                    $scope.$apply();
                });

            } catch (err) {
                console.log("launch Collection Picker wizard failed.");
            }
        };

        // For accessibiltiy of body pane
        $scope.setupAria = function () {
            var O365ClientsDashboardBodyArea = document.getElementById("O365ClientsDashboardBody");
            O365ClientsDashboardBodyArea.setAttribute("aria-label", $scope.strings._O365UpdatesDashboardTitle);

            var O365ClientsDashboardBodyDivArea = document.getElementById("O365ClientsDashboardBodyDiv");
            O365ClientsDashboardBodyDivArea.setAttribute("aria-label", $scope.strings._O365UpdatesDashboardTitle);
        };
        $scope.setupAria();
    }])

        .directive('dashboardChart', defineChartDirective);

    //***** CHART GENERATORS ****
    function createClientChart(clientsData, $scope, domNode, chartTitle) {
      //get relevant string values and set as data keys
      var O365ClientsManaged = $scope.strings.O365ClientsManaged;
      var O365ClientsUnmanaged = $scope.strings.O365ClientsUnmanaged;
      var chartData = {};
      chartData[O365ClientsManaged] = clientsData.O365ClientsManaged;
      chartData[O365ClientsUnmanaged] = clientsData.O365ClientsUnmanaged;
      var columns = [[O365ClientsManaged, clientsData.O365ClientsManaged], [O365ClientsUnmanaged, clientsData.O365ClientsTotal - clientsData.O365ClientsManaged]];

        var summaryText = "";
        var chart = document.querySelectorAll(domNode);
		var chartEl = angular.element(chart);
		var tileEl = chartEl.parent();
        var str = [];

        columns.forEach(function (k, v) { str.push(k[0] + ": " + k[1] + ",  "); });
        summaryText = chartTitle + ". " + str.join("");

			chartEl.attr('aria-label', summaryText);
			tileEl.attr('aria-label', chartTitle);
		tileEl.attr('tabindex', '0');

          c3.generate({
          bindto: domNode,
        data: {
          columns: columns,
            type: 'bar',
            groups: [
                [$scope.strings.O365ClientsUnmanaged, $scope.strings.O365ClientsManaged]
            ],
            order : null
          },
          bar: {
              width: 50
          },
          legend: {
              reversed: true,
              position: 'right',
          },
          axis: {
              x: {
                  show: true,
                  type: 'category',
                  categories: ['']
              },
              y: {
                  label: $scope.strings['Clients'],
                  tick: {
                      format: function (y) {
                          if (y % 1 > 0) return '';
                          return y;
                      }
                  }
              }
          },
          size: {
              height: 250,
              width: 500
          }
            });
    };

    function createNonOfficeBarChart(clientsData, $scope, domNode, chartTitle) {
            var NonO365 = clientsData.clientsTotal - clientsData.O365ClientsTotal;
            var columns = [[$scope.strings.NonOfficeClients, NonO365]];

        var summaryText = "";
        var chart = document.querySelectorAll(domNode);
		var chartEl = angular.element(chart);
		var tileEl = chartEl.parent();
        var str = [];

        columns.forEach(function (k, v) { str.push(k[0] + ": " + k[1] + ",  "); });
        summaryText = chartTitle + ". " + str.join("");

			chartEl.attr('aria-label', summaryText);
			tileEl.attr('aria-label', chartTitle);
		tileEl.attr('tabindex', '0');

        c3.generate({
            bindto: domNode,
            data: {
                columns: columns,
                type: 'bar',
                order: null
            },
            bar: {
                width: 50
            },
            legend: {
                show: false
            },
            axis: {
                x: {
                    show: true,
                    type: 'category',
                    categories: ['']
                },
                y: {
                    label: $scope.strings['Clients'],
                    tick: {
                        format: function (y) {
                            if (y % 1 > 0) return '';
                            return y;
                        }
                    }
                }
            },
            size: {
                height: 250,
                width: 300
            }
        });
    };

    function createPieChart(coll, colName, data, domNode, chartTitle) {

      var dataKeys = Object.keys(data);
      var chartData = convertObjectToArrayOfArrays(data, dataKeys);

      //only show a maximum of 36 elements in the legend
      var above36 = [];
      if (dataKeys.length > 36) {
        above36 = removeLast(chartData, 36);
      }

      c3.generate({
        bindto: domNode,
        size: {
          height: 250
        },
        data: {
          columns: chartData,
          type: 'pie',
          onclick: function (d) {
              window.external.OnModelTypeClick(coll, colName, d.name);
          }
        },
        legend: {
          position: 'right',
          hide: above36
        },
        pie: {
          label: {
            format: function(value, ratio) {
              return value;
            }
          },
          expand: true
        },
        tooltip: {
          format: {
            value: function(value, ratio, id) {
              return value;
            }
          }
        }
        });

        GetSummaryText(domNode, chartTitle, chartData);
    };

    function createPieChartChannels(data, domNode, chartTitle) {

        var dataKeys = Object.keys(data);
        var chartData = convertObjectToArrayOfArrays(data, dataKeys);

        //only show a maximum of 36 elements in the legend
        var above36 = [];
        if (dataKeys.length > 36) {
            above36 = removeLast(chartData, 36);
        }

        c3.generate({
            bindto: domNode,
            size: {
                height: 250
            },
            data: {
                columns: chartData,
                type: 'pie'
            },
            legend: {
                position: 'right',
                hide: above36
            },
            pie: {
                label: {
                    format: function (value, ratio) {
                        return value;
                    }
                },
                expand: true
            },
            tooltip: {
                format: {
                    value: function (value, ratio, id) {
                        return value;
                    }
                }
            }
        });

        GetSummaryText(domNode, chartTitle, chartData);

    };

    function createLanguagesChart(languages, $scope, domNode, chartTitle) {
        var summaryText = "";
        var chart = document.querySelectorAll(domNode);
		var chartEl = angular.element(chart);
		var tileEl = chartEl.parent();
        var str = [];

        var languageNames = [];
        for (var key in languages) {
            languageNames[key] = bridge.GetLanguageString(key);
            str.push(languageNames[key] + ",  ");
        }
        summaryText = chartTitle + ". " + str.join("");

			chartEl.attr('aria-label', summaryText);
			tileEl.attr('aria-label', chartTitle);
		tileEl.attr('tabindex', '0');

        var barWidth = 0.95;
        // dynamically set bar width depending on the nr of languagues
        if (Object.keys(languages).length < 10) {
            barWidth = Object.keys(languages).length * 0.1;
        }
    
        c3.generate({
            bindto: domNode,
            size: {
                height: 250,
                width: 500
            },
            data: {
                json: languages,
                type: 'bar',
                labels: {
                format: function(v, id, i, j) {
                    return id;
                }
                }
            },
            bar: {
                width: {
                ratio: barWidth
                }
            },
            axis: {
                x: {
                show: true,
                type: 'category',
                categories: ['']
                },
                y: {
                label: $scope.strings['Clients'],
                tick: {
                    format: function(y) {
                    if (y % 1 > 0) return '';
                    return y;
                    }
                }
                }
            },
            legend: {
                show: false
            },
            tooltip: {
                grouped: false,
                format: {
                value: function(value, ratio, id) {
                    return value;
                },
                name: function(name, ratio, id, index) {
                    if (languageNames.hasOwnProperty(name)) {
                    return name + ' : ' + languageNames[name];
                    }
                    return name;
                },
                title: function() {
                    return '';
                }
                }
            }
        });
    };

    function createDeploymentStackBarChart(idToBindTo, chartData, $scope, chartTitle) {
      var columns = chartData;
      var pattern = ["#A9F5A9", "#F5A9A9", "#D8D8D8"];

        var summaryText = "";
        var chart = document.querySelectorAll(idToBindTo);
        var chartEl = angular.element(chart);
        var tileEl = chartEl.parent();
        var str = [];

        columns.forEach(function (k, v) { str.push(k[0] + ": " + k[1] + ",  "); });
        summaryText = chartTitle + ". " + str.join("");

			chartEl.attr('aria-label', summaryText);
			tileEl.attr('aria-label', chartTitle);
		tileEl.attr('tabindex', '0');

          var chart = c3.generate({
        bindto: idToBindTo,
        size: {
          height: 230,
          width: 450
        },
        data: {
          columns: columns,
          type: 'bar',
          empty: {
            label: {
              text: $scope.strings["O365NoDeployments"]
            }
          },
          bar: {
            width: 30
          },
          groups: [
          [$scope.strings["O365DepError"], $scope.strings["O365DepSuccess"], $scope.strings["O365DepTarget"]]
          ],
          order: null
        },
        grid: {
          y: {
            lines: [{
              value: 0
            }]
          }
        },
        color: {
          pattern: pattern
        },
        axis: {
          y: {
            tick: {
              format: function(d) {
                return (parseInt(d) == d) ? d : null;
              }
            }
          }
        }

        });
    };

    // Checks if value is null, 0, undefinded, "" or []
    function isEmpty(value) {
      return (value == 0 || value == null || value.length === 0 || isNaN(value));
    }

    // creates key with value of 1, or increments value in given object
    function incOrAdd(obj, key) {
      if (obj.hasOwnProperty(key)) {
        obj[key]++;
      } else {
        obj[key] = 1;
      }
    };

    // Sets aria-label for accessibility
    function GetSummaryText(bindID, chartTitle, chartData) {

        var chart = document.querySelectorAll(bindID);
        var chartEl = angular.element(chart);
        var tileEl = chartEl.parent();

        if (chartData == null) {
            var summaryText = chartTitle + "0.";
        }
        else {
            var str = [];
            chartData.forEach(function (k, v) { str.push(k[0] + ": " + k[1] + ",  "); });
            var summaryText = chartTitle + ". " + str.join("");
        }

			chartEl.attr('aria-label', summaryText);
			tileEl.attr('aria-label', chartTitle);
		tileEl.attr('tabindex', '0');
    }

    // removes the lowest n of a chart data array and returns an array of the removed strings
    function removeLast(chartData, n) {
      chartData.sort(function(a, b) {
        if (a[1] < b[1]) return -1;
        return 1;
      });
      var excess = chartData.slice(n, chartData.length);
      return excess.map(function(el) {
        return el[0];
      });

    };

}());
// SIG // Begin signature block
// SIG // MIInywYJKoZIhvcNAQcCoIInvDCCJ7gCAQExDzANBglg
// SIG // hkgBZQMEAgEFADB3BgorBgEEAYI3AgEEoGkwZzAyBgor
// SIG // BgEEAYI3AgEeMCQCAQEEEBDgyQbOONQRoqMAEEvTUJAC
// SIG // AQACAQACAQACAQACAQAwMTANBglghkgBZQMEAgEFAAQg
// SIG // 7XQmkTKfYe9Uj7JXQKqr7qpgePP57tLIHOBqAoIcjwyg
// SIG // gg2BMIIF/zCCA+egAwIBAgITMwAAAsyOtZamvdHJTgAA
// SIG // AAACzDANBgkqhkiG9w0BAQsFADB+MQswCQYDVQQGEwJV
// SIG // UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMH
// SIG // UmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
// SIG // cmF0aW9uMSgwJgYDVQQDEx9NaWNyb3NvZnQgQ29kZSBT
// SIG // aWduaW5nIFBDQSAyMDExMB4XDTIyMDUxMjIwNDYwMVoX
// SIG // DTIzMDUxMTIwNDYwMVowdDELMAkGA1UEBhMCVVMxEzAR
// SIG // BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
// SIG // bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
// SIG // bjEeMBwGA1UEAxMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
// SIG // MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA
// SIG // ok2x7OvGwA7zbnfezc3HT9M4dJka+FaQ7+vCqG40Bcm1
// SIG // QLlYIiDX/Whts0LVijaOvtl9iMeuShnAV7mchItKAVAA
// SIG // BpyHuTuav2NCI9FsA8jFmlWndk3uK9RInNx1h1H4ojYx
// SIG // dBExyoN6muwwslKsLEfauUml7h5WAsDPpufTZd4yp2Jy
// SIG // iy384Zdd8CJlfQxfDe+gDZEciugWKHPSOoRxdjAk0GFm
// SIG // 0OH14MyoYM4+M3mm1oH7vmSQohS5KIL3NEVW9Mdw7csT
// SIG // G5f93uORLvrJ/8ehFcGyWVb7UGHJnRhdcgGIbfiZzZls
// SIG // AMS/DIBzM8RHKGNUNSbbLYmN/rt7pRjL4QIDAQABo4IB
// SIG // fjCCAXowHwYDVR0lBBgwFgYKKwYBBAGCN0wIAQYIKwYB
// SIG // BQUHAwMwHQYDVR0OBBYEFIi4R40ylsyKlSKfrDNqzhx9
// SIG // da30MFAGA1UdEQRJMEekRTBDMSkwJwYDVQQLEyBNaWNy
// SIG // b3NvZnQgT3BlcmF0aW9ucyBQdWVydG8gUmljbzEWMBQG
// SIG // A1UEBRMNMjMwMDEyKzQ3MDUyOTAfBgNVHSMEGDAWgBRI
// SIG // bmTlUAXTgqoXNzcitW2oynUClTBUBgNVHR8ETTBLMEmg
// SIG // R6BFhkNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtp
// SIG // b3BzL2NybC9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDct
// SIG // MDguY3JsMGEGCCsGAQUFBwEBBFUwUzBRBggrBgEFBQcw
// SIG // AoZFaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9w
// SIG // cy9jZXJ0cy9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDct
// SIG // MDguY3J0MAwGA1UdEwEB/wQCMAAwDQYJKoZIhvcNAQEL
// SIG // BQADggIBAHgPA7DgB0udzEyB2LvG216zuskLUQ+iX8jF
// SIG // nl2i7tzXPDw5xXNXn2KvxdzBsf2osDW3LCdjFOwSjVkz
// SIG // +SUFQQNhjSHkd5knF6pzrL9V6lz72XiEg1Vi2gUM3HiL
// SIG // XSMIKOgdd78ZZJEmDLwdA692MO/1vVOFpOSv0QzpyBr5
// SIG // iqiotwMMsZVdZqXn8u9vRSmlk+3nQXdyOPoZXTGPLHXw
// SIG // z41kbSc4zI12bONTlDsLR3HD2s44wuyp3c72R8f9FVi/
// SIG // J9DU/+NOL37Z1yonzGZEuKdrAd6CvupAnLMlrIEv93mB
// SIG // sNRXuDDp4p9UYYK1taxzzgyUxgFDpluMHN0Oiiq9s73u
// SIG // 7DA2XvbX8paJz8IZPe9a1/KhsOi5Kxhb99SCXiUnv2lG
// SIG // xnVAz5G6wAW1bzxJYKI+Xj90RKseY3X5EMO7TnVpIZ9I
// SIG // w1IdrkHp/QLY90ZCch7kdBlLCVTFhSXZCDv4BcM6DhpR
// SIG // zbJsb6QDVfOv9aoG9aGV3a1EacyaedzLA2gWP6cTnCdA
// SIG // r4OrlrN5EFoCpOWgc77F/eQc3SLR06VTLVT1uKuNVxL2
// SIG // xZlD9Z+qC+a3TXa0zI/x1zEZNSgpLGsdVcaN6r/td3Ar
// SIG // GQGkDWiAL7eS75LIWZA2SD//9B56uzZ1nmEd8+KBYsPT
// SIG // dp922/W2kFrlj7MBtA6vWE/ZG/grOKiCMIIHejCCBWKg
// SIG // AwIBAgIKYQ6Q0gAAAAAAAzANBgkqhkiG9w0BAQsFADCB
// SIG // iDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
// SIG // b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
// SIG // Y3Jvc29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWlj
// SIG // cm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5
// SIG // IDIwMTEwHhcNMTEwNzA4MjA1OTA5WhcNMjYwNzA4MjEw
// SIG // OTA5WjB+MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
// SIG // aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
// SIG // ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSgwJgYDVQQD
// SIG // Ex9NaWNyb3NvZnQgQ29kZSBTaWduaW5nIFBDQSAyMDEx
// SIG // MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA
// SIG // q/D6chAcLq3YbqqCEE00uvK2WCGfQhsqa+laUKq4Bjga
// SIG // BEm6f8MMHt03a8YS2AvwOMKZBrDIOdUBFDFC04kNeWSH
// SIG // fpRgJGyvnkmc6Whe0t+bU7IKLMOv2akrrnoJr9eWWcpg
// SIG // GgXpZnboMlImEi/nqwhQz7NEt13YxC4Ddato88tt8zpc
// SIG // oRb0RrrgOGSsbmQ1eKagYw8t00CT+OPeBw3VXHmlSSnn
// SIG // Db6gE3e+lD3v++MrWhAfTVYoonpy4BI6t0le2O3tQ5GD
// SIG // 2Xuye4Yb2T6xjF3oiU+EGvKhL1nkkDstrjNYxbc+/jLT
// SIG // swM9sbKvkjh+0p2ALPVOVpEhNSXDOW5kf1O6nA+tGSOE
// SIG // y/S6A4aN91/w0FK/jJSHvMAhdCVfGCi2zCcoOCWYOUo2
// SIG // z3yxkq4cI6epZuxhH2rhKEmdX4jiJV3TIUs+UsS1Vz8k
// SIG // A/DRelsv1SPjcF0PUUZ3s/gA4bysAoJf28AVs70b1FVL
// SIG // 5zmhD+kjSbwYuER8ReTBw3J64HLnJN+/RpnF78IcV9uD
// SIG // jexNSTCnq47f7Fufr/zdsGbiwZeBe+3W7UvnSSmnEyim
// SIG // p31ngOaKYnhfsi+E11ecXL93KCjx7W3DKI8sj0A3T8Hh
// SIG // hUSJxAlMxdSlQy90lfdu+HggWCwTXWCVmj5PM4TasIgX
// SIG // 3p5O9JawvEagbJjS4NaIjAsCAwEAAaOCAe0wggHpMBAG
// SIG // CSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBRIbmTlUAXT
// SIG // gqoXNzcitW2oynUClTAZBgkrBgEEAYI3FAIEDB4KAFMA
// SIG // dQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYDVR0TAQH/BAUw
// SIG // AwEB/zAfBgNVHSMEGDAWgBRyLToCMZBDuRQFTuHqp8cx
// SIG // 0SOJNDBaBgNVHR8EUzBRME+gTaBLhklodHRwOi8vY3Js
// SIG // Lm1pY3Jvc29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9N
// SIG // aWNSb29DZXJBdXQyMDExXzIwMTFfMDNfMjIuY3JsMF4G
// SIG // CCsGAQUFBwEBBFIwUDBOBggrBgEFBQcwAoZCaHR0cDov
// SIG // L3d3dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNS
// SIG // b29DZXJBdXQyMDExXzIwMTFfMDNfMjIuY3J0MIGfBgNV
// SIG // HSAEgZcwgZQwgZEGCSsGAQQBgjcuAzCBgzA/BggrBgEF
// SIG // BQcCARYzaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3Br
// SIG // aW9wcy9kb2NzL3ByaW1hcnljcHMuaHRtMEAGCCsGAQUF
// SIG // BwICMDQeMiAdAEwAZQBnAGEAbABfAHAAbwBsAGkAYwB5
// SIG // AF8AcwB0AGEAdABlAG0AZQBuAHQALiAdMA0GCSqGSIb3
// SIG // DQEBCwUAA4ICAQBn8oalmOBUeRou09h0ZyKbC5YR4WOS
// SIG // mUKWfdJ5DJDBZV8uLD74w3LRbYP+vj/oCso7v0epo/Np
// SIG // 22O/IjWll11lhJB9i0ZQVdgMknzSGksc8zxCi1LQsP1r
// SIG // 4z4HLimb5j0bpdS1HXeUOeLpZMlEPXh6I/MTfaaQdION
// SIG // 9MsmAkYqwooQu6SpBQyb7Wj6aC6VoCo/KmtYSWMfCWlu
// SIG // WpiW5IP0wI/zRive/DvQvTXvbiWu5a8n7dDd8w6vmSiX
// SIG // mE0OPQvyCInWH8MyGOLwxS3OW560STkKxgrCxq2u5bLZ
// SIG // 2xWIUUVYODJxJxp/sfQn+N4sOiBpmLJZiWhub6e3dMNA
// SIG // BQamASooPoI/E01mC8CzTfXhj38cbxV9Rad25UAqZaPD
// SIG // XVJihsMdYzaXht/a8/jyFqGaJ+HNpZfQ7l1jQeNbB5yH
// SIG // PgZ3BtEGsXUfFL5hYbXw3MYbBL7fQccOKO7eZS/sl/ah
// SIG // XJbYANahRr1Z85elCUtIEJmAH9AAKcWxm6U/RXceNcbS
// SIG // oqKfenoi+kiVH6v7RyOA9Z74v2u3S5fi63V4GuzqN5l5
// SIG // GEv/1rMjaHXmr/r8i+sLgOppO6/8MO0ETI7f33VtY5E9
// SIG // 0Z1WTk+/gFcioXgRMiF670EKsT/7qMykXcGhiJtXcVZO
// SIG // SEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCGaIw
// SIG // ghmeAgEBMIGVMH4xCzAJBgNVBAYTAlVTMRMwEQYDVQQI
// SIG // EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
// SIG // HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAm
// SIG // BgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENB
// SIG // IDIwMTECEzMAAALMjrWWpr3RyU4AAAAAAswwDQYJYIZI
// SIG // AWUDBAIBBQCgga4wGQYJKoZIhvcNAQkDMQwGCisGAQQB
// SIG // gjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcC
// SIG // ARUwLwYJKoZIhvcNAQkEMSIEIDhfvixctAT3BRipxp01
// SIG // 2ZXyqirD+CBYOuFMFvuVahHDMEIGCisGAQQBgjcCAQwx
// SIG // NDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRw
// SIG // Oi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEB
// SIG // BQAEggEAATmyr5eJjQuNulEiaBZGt/ZMP1M7lLJzorTo
// SIG // 4q8AGhMFXepedA+kCLjA1R1eF9xHMAgLn0N9hJq2Vw/5
// SIG // leVF6VI0z3kDhYdkxaQy/7xIkM/88aev0Hn/ly9DkCxN
// SIG // QoMn0STodChWIW5wwJWtbYNg8gfPQKZPXx7ABWVvpD4e
// SIG // xIk86KkeLt/lPEnKMBCsYkYL4NrY+ZiHS88VsPjm0i5c
// SIG // Wl9b3fuu6FEYnpOUo4YdnyeezZ7arNY53pGy/qfXLdvg
// SIG // bC5Fn83jQhBWrEp8DRmAtd2naBmteDOGPXYiO2VS5FUD
// SIG // vlh7I7tyAvhjT6ZtnBufOWQzGuk2trKTYDKVQo8wuqGC
// SIG // FywwghcoBgorBgEEAYI3AwMBMYIXGDCCFxQGCSqGSIb3
// SIG // DQEHAqCCFwUwghcBAgEDMQ8wDQYJYIZIAWUDBAIBBQAw
// SIG // ggFZBgsqhkiG9w0BCRABBKCCAUgEggFEMIIBQAIBAQYK
// SIG // KwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCCBRE+F
// SIG // iqddWIHxdVrbEcUKp5hnkwRdqpkxsdjwhd+E0AIGY2Pf
// SIG // aYHQGBMyMDIyMTEwNDE3MjMzOS45NjhaMASAAgH0oIHY
// SIG // pIHVMIHSMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
// SIG // aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
// SIG // ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQL
// SIG // EyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExp
// SIG // bWl0ZWQxJjAkBgNVBAsTHVRoYWxlcyBUU1MgRVNOOkZD
// SIG // NDEtNEJENC1EMjIwMSUwIwYDVQQDExxNaWNyb3NvZnQg
// SIG // VGltZS1TdGFtcCBTZXJ2aWNloIIRezCCBycwggUPoAMC
// SIG // AQICEzMAAAG59gANZVRPvAMAAQAAAbkwDQYJKoZIhvcN
// SIG // AQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
// SIG // c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
// SIG // BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UE
// SIG // AxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAw
// SIG // HhcNMjIwOTIwMjAyMjE3WhcNMjMxMjE0MjAyMjE3WjCB
// SIG // 0jELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
// SIG // b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
// SIG // Y3Jvc29mdCBDb3Jwb3JhdGlvbjEtMCsGA1UECxMkTWlj
// SIG // cm9zb2Z0IElyZWxhbmQgT3BlcmF0aW9ucyBMaW1pdGVk
// SIG // MSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVTTjpGQzQxLTRC
// SIG // RDQtRDIyMDElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUt
// SIG // U3RhbXAgU2VydmljZTCCAiIwDQYJKoZIhvcNAQEBBQAD
// SIG // ggIPADCCAgoCggIBAONJPslh9RbHyQECbUIINxMF5uQk
// SIG // yN07VIShITXubLpWnANgBCLvCcJl7o/2HHORnsRcmSIN
// SIG // J/qclAmLIrOjnYnrbocAnixiMEXC+a1sZ84qxYWtEVY7
// SIG // VYw0LCczY+86U/8shgxqsaezKpWriPOcpV1Sh8SsOxf3
// SIG // 0yO7jvld/IBA3T6lHM2pT/HRjWk/r9uyx0Q4atx0mkLV
// SIG // YS9y55/oTlKLE00h792S+maadAdy3VgTweiwoEOXD785
// SIG // wv3h+fwH/wTQtC9lhAxhMO4p+OP9888Wxkbl6BqRWXud
// SIG // 54RTzqp2Vr+yen1Q1A6umyMB7Xq0snIYG5B1Acc4UgJl
// SIG // PQ/ZiMkqgxQNFCWQvz0G9oLgSPD8Ky0AkX22PcDOboPu
// SIG // NT4RceWPX0UVZUsX9IUgs7QF41HiQSwEeOOHGyrfQdmS
// SIG // slATrbmH/18M5QrsTM5JINjct9G42xqN8VF9Z8WOiGMj
// SIG // NbvlpcEmmysYl5QyhrEDoFnQTU7bFrD3JX0fIfu1sbLW
// SIG // eBqXwbp4Z8yACTtphK2VbzOvi4vc0RCmRNzvYQQ2PjZ7
// SIG // NaTXE4Gu3vggAJ+rtzUTAfJotvOSqcMgNwLZa1Y+ET/l
// SIG // b0VyjrYwFuHtg0QWyQjP5350LTpv086pyVUh4A3w/Os5
// SIG // hTGFZgFe5bCyMnpY09M0yPdHaQ/56oYUsSIcyKyVAgMB
// SIG // AAGjggFJMIIBRTAdBgNVHQ4EFgQUt7A4cdtYQ5oJjE1Z
// SIG // qrSonp41RFIwHwYDVR0jBBgwFoAUn6cVXQBeYl2D9OXS
// SIG // ZacbUzUZ6XIwXwYDVR0fBFgwVjBUoFKgUIZOaHR0cDov
// SIG // L3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jcmwvTWlj
// SIG // cm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAo
// SIG // MSkuY3JsMGwGCCsGAQUFBwEBBGAwXjBcBggrBgEFBQcw
// SIG // AoZQaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9w
// SIG // cy9jZXJ0cy9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIw
// SIG // UENBJTIwMjAxMCgxKS5jcnQwDAYDVR0TAQH/BAIwADAW
// SIG // BgNVHSUBAf8EDDAKBggrBgEFBQcDCDAOBgNVHQ8BAf8E
// SIG // BAMCB4AwDQYJKoZIhvcNAQELBQADggIBAM3cZ7NFUHRM
// SIG // sLKzjl7rJPIkv7oJ+s9kkut0hZif9WSt60SzYGULp1zm
// SIG // dPqc+w8eHTkhqX0GKCp2TTqSzBXBhwHOm8+p6hUxNlDe
// SIG // wGMZUos952aTXblAT3OKBnfVBLQyUavrSjuJGZAW30cN
// SIG // Y3rjVDUlGD+VygQHySaDaviJQbK6/6fQvUUFoqIk3ldG
// SIG // fjnAtnebsVlqh6WWamVc5AZdpWR1jSzN/oxKYqc1BG4S
// SIG // xxlPtcfrAdBz/cU4bxVXqAAf02NZscvJNpRnOALf5kVo
// SIG // 2HupJXCsk9TzP5PNW2sTS3TmwhIQmPxr0E0UqOojUrBJ
// SIG // UOhbITAxcnSa/IMluL1HXRtLQZI+xs2eRtuPOUsKUW71
// SIG // /1YeqsYCLHLvu82ceDVQQvP7GHEEkp2kEjiofbjYErBo
// SIG // 2iCEaxxeX4Z9HvAgA4MsQkbn6e4EFQf13sP+Kn3XgMIv
// SIG // JbqLJeFcQja+SUeOXu5cfkxe0GzTNojdyIwzaHlhOflV
// SIG // RZNrxee3B+yZwd3JHDIvv71uSI/SIzzt9cU2GyHQVqxB
// SIG // SrRtKW6W8Vw7zpVvoVsIv3ljxg+7NiGSlXX1s7zbBNDM
// SIG // Uj9OnzOlHK/3mrOU8YEuRf6RwakW5UCeGamy5MiKu2Yu
// SIG // yKiGBCv4OGhPstNe7ALkEOh8BX12t4ntuYu+gw9L6yCP
// SIG // Y0jWYaQtzAP9MIIHcTCCBVmgAwIBAgITMwAAABXF52ue
// SIG // AptJmQAAAAAAFTANBgkqhkiG9w0BAQsFADCBiDELMAkG
// SIG // A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAO
// SIG // BgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29m
// SIG // dCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0
// SIG // IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5IDIwMTAw
// SIG // HhcNMjEwOTMwMTgyMjI1WhcNMzAwOTMwMTgzMjI1WjB8
// SIG // MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
// SIG // bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
// SIG // cm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNy
// SIG // b3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDCCAiIwDQYJ
// SIG // KoZIhvcNAQEBBQADggIPADCCAgoCggIBAOThpkzntHIh
// SIG // C3miy9ckeb0O1YLT/e6cBwfSqWxOdcjKNVf2AX9sSuDi
// SIG // vbk+F2Az/1xPx2b3lVNxWuJ+Slr+uDZnhUYjDLWNE893
// SIG // MsAQGOhgfWpSg0S3po5GawcU88V29YZQ3MFEyHFcUTE3
// SIG // oAo4bo3t1w/YJlN8OWECesSq/XJprx2rrPY2vjUmZNqY
// SIG // O7oaezOtgFt+jBAcnVL+tuhiJdxqD89d9P6OU8/W7IVW
// SIG // Te/dvI2k45GPsjksUZzpcGkNyjYtcI4xyDUoveO0hyTD
// SIG // 4MmPfrVUj9z6BVWYbWg7mka97aSueik3rMvrg0XnRm7K
// SIG // MtXAhjBcTyziYrLNueKNiOSWrAFKu75xqRdbZ2De+JKR
// SIG // Hh09/SDPc31BmkZ1zcRfNN0Sidb9pSB9fvzZnkXftnIv
// SIG // 231fgLrbqn427DZM9ituqBJR6L8FA6PRc6ZNN3SUHDSC
// SIG // D/AQ8rdHGO2n6Jl8P0zbr17C89XYcz1DTsEzOUyOArxC
// SIG // aC4Q6oRRRuLRvWoYWmEBc8pnol7XKHYC4jMYctenIPDC
// SIG // +hIK12NvDMk2ZItboKaDIV1fMHSRlJTYuVD5C4lh8zYG
// SIG // NRiER9vcG9H9stQcxWv2XFJRXRLbJbqvUAV6bMURHXLv
// SIG // jflSxIUXk8A8FdsaN8cIFRg/eKtFtvUeh17aj54WcmnG
// SIG // rnu3tz5q4i6tAgMBAAGjggHdMIIB2TASBgkrBgEEAYI3
// SIG // FQEEBQIDAQABMCMGCSsGAQQBgjcVAgQWBBQqp1L+ZMSa
// SIG // voKRPEY1Kc8Q/y8E7jAdBgNVHQ4EFgQUn6cVXQBeYl2D
// SIG // 9OXSZacbUzUZ6XIwXAYDVR0gBFUwUzBRBgwrBgEEAYI3
// SIG // TIN9AQEwQTA/BggrBgEFBQcCARYzaHR0cDovL3d3dy5t
// SIG // aWNyb3NvZnQuY29tL3BraW9wcy9Eb2NzL1JlcG9zaXRv
// SIG // cnkuaHRtMBMGA1UdJQQMMAoGCCsGAQUFBwMIMBkGCSsG
// SIG // AQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsGA1UdDwQEAwIB
// SIG // hjAPBgNVHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaAFNX2
// SIG // VsuP6KJcYmjRPZSQW9fOmhjEMFYGA1UdHwRPME0wS6BJ
// SIG // oEeGRWh0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kv
// SIG // Y3JsL3Byb2R1Y3RzL01pY1Jvb0NlckF1dF8yMDEwLTA2
// SIG // LTIzLmNybDBaBggrBgEFBQcBAQROMEwwSgYIKwYBBQUH
// SIG // MAKGPmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kv
// SIG // Y2VydHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3J0
// SIG // MA0GCSqGSIb3DQEBCwUAA4ICAQCdVX38Kq3hLB9nATEk
// SIG // W+Geckv8qW/qXBS2Pk5HZHixBpOXPTEztTnXwnE2P9pk
// SIG // bHzQdTltuw8x5MKP+2zRoZQYIu7pZmc6U03dmLq2HnjY
// SIG // Ni6cqYJWAAOwBb6J6Gngugnue99qb74py27YP0h1AdkY
// SIG // 3m2CDPVtI1TkeFN1JFe53Z/zjj3G82jfZfakVqr3lbYo
// SIG // VSfQJL1AoL8ZthISEV09J+BAljis9/kpicO8F7BUhUKz
// SIG // /AyeixmJ5/ALaoHCgRlCGVJ1ijbCHcNhcy4sa3tuPywJ
// SIG // eBTpkbKpW99Jo3QMvOyRgNI95ko+ZjtPu4b6MhrZlvSP
// SIG // 9pEB9s7GdP32THJvEKt1MMU0sHrYUP4KWN1APMdUbZ1j
// SIG // dEgssU5HLcEUBHG/ZPkkvnNtyo4JvbMBV0lUZNlz138e
// SIG // W0QBjloZkWsNn6Qo3GcZKCS6OEuabvshVGtqRRFHqfG3
// SIG // rsjoiV5PndLQTHa1V1QJsWkBRH58oWFsc/4Ku+xBZj1p
// SIG // /cvBQUl+fpO+y/g75LcVv7TOPqUxUYS8vwLBgqJ7Fx0V
// SIG // iY1w/ue10CgaiQuPNtq6TPmb/wrpNPgkNWcr4A245oyZ
// SIG // 1uEi6vAnQj0llOZ0dFtq0Z4+7X6gMTN9vMvpe784cETR
// SIG // kPHIqzqKOghif9lwY1NNje6CbaUFEMFxBmoQtB1VM1iz
// SIG // oXBm8qGCAtcwggJAAgEBMIIBAKGB2KSB1TCB0jELMAkG
// SIG // A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAO
// SIG // BgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29m
// SIG // dCBDb3Jwb3JhdGlvbjEtMCsGA1UECxMkTWljcm9zb2Z0
// SIG // IElyZWxhbmQgT3BlcmF0aW9ucyBMaW1pdGVkMSYwJAYD
// SIG // VQQLEx1UaGFsZXMgVFNTIEVTTjpGQzQxLTRCRDQtRDIy
// SIG // MDElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAg
// SIG // U2VydmljZaIjCgEBMAcGBSsOAwIaAxUAx2IeGHhk58MQ
// SIG // kzzSWknGcLjfgTqggYMwgYCkfjB8MQswCQYDVQQGEwJV
// SIG // UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMH
// SIG // UmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
// SIG // cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1T
// SIG // dGFtcCBQQ0EgMjAxMDANBgkqhkiG9w0BAQUFAAIFAOcP
// SIG // r1kwIhgPMjAyMjExMDQyMzMzNDVaGA8yMDIyMTEwNTIz
// SIG // MzM0NVowdzA9BgorBgEEAYRZCgQBMS8wLTAKAgUA5w+v
// SIG // WQIBADAKAgEAAgIiQwIB/zAHAgEAAgIRhDAKAgUA5xEA
// SIG // 2QIBADA2BgorBgEEAYRZCgQCMSgwJjAMBgorBgEEAYRZ
// SIG // CgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqG
// SIG // SIb3DQEBBQUAA4GBALUhW0rAJUav0fSn2rVzws1tNm/+
// SIG // ilf/XXNQ+IM/ZgYf57j+qAYupAszZAPn6YGMXHLI4YJs
// SIG // HIlQhz0PgEOjih2uuLS+pb6y/O4U7iTcW+dqm8qulKhP
// SIG // x2SVseCOop0i023QcrJW1UOe6gkyPaA2PJtCW04hC98q
// SIG // 0yD8oTK6UFwtMYIEDTCCBAkCAQEwgZMwfDELMAkGA1UE
// SIG // BhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNV
// SIG // BAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
// SIG // b3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRp
// SIG // bWUtU3RhbXAgUENBIDIwMTACEzMAAAG59gANZVRPvAMA
// SIG // AQAAAbkwDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3
// SIG // DQEJAzENBgsqhkiG9w0BCRABBDAvBgkqhkiG9w0BCQQx
// SIG // IgQgmZkXbKYa3MYmxk+HVcXuAjet/EeJ6CLHinK3NZmo
// SIG // 2twwgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCBk
// SIG // 60bO8W85uTAfJVEO3vX2aLaQFcgcGpdwsOoi+foP9DCB
// SIG // mDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
// SIG // YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
// SIG // VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNV
// SIG // BAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEw
// SIG // AhMzAAABufYADWVUT7wDAAEAAAG5MCIEIEpB3xr7eyxp
// SIG // TDMMf8hGiLLzDeIEhxmj1CIruH9UfJ8sMA0GCSqGSIb3
// SIG // DQEBCwUABIICAESpOTcYG8AhB0lvbrcHzJKCV4osDyuc
// SIG // cCSBdZZQjDJvvnZjWJZ2SP0bG3ydGqgsDXgKPpUfn2ci
// SIG // EDI2gHtWRdk4hR7uwC8U0u8dOWstnSwewWO0HGRaKLkK
// SIG // jdPq/BTFFWRYxm3QUBCU4YmT1hO/XRt9/7/q9FM3WLJf
// SIG // 9TP6f1vvjJhedvmdXmv8EygJTt4epppZEM4gLVmRm83W
// SIG // /FhRU/ORatm8SmoJf/+eogu0yO411X81yB3xEGoHX/Z+
// SIG // bSkyWBeE2eCkjKoIo53HTFhA9o84nRHev+Jvti3ALnEg
// SIG // J5IfGw4VvPfT3DoWYGB3xxC8SkDQB2p40NoEE3Jds9m6
// SIG // mWjoGDFwNj4aso4OMSEFPMcP602MmNcxcoIQ+QCGsQid
// SIG // rzgjDznfuI2auvxHmNhxvTfnwB/XjrndvtVgvmwP3cqs
// SIG // UME+riiQvhqYYgOOYKSIHNMgIaKMud/LAJkqYIHUVo6h
// SIG // VYZSlHa7MLQ7z5yG8dMvlsj8wM+ljSZAJlYlr7Pa8IWE
// SIG // p36zq298FbKsK20WqvQsptLyBaVSZwCyYNcha80cdwm7
// SIG // QfMfgkTUMj0C1UTDmqBBfLL7TPiUYNK6gIH7wi6pP2JW
// SIG // 77rA4b3wQijfhKyCD6DnzCuSdsyLI0r9aEEzpO2sY5w4
// SIG // qVKKFi/w3TkRaDjhlR16MQIzI93++CBSuFAc
// SIG // End signature block
