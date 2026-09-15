(function () {
    "use strict";
    var dashboard = angular.module("dashboard", []);
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
        var NonOfficeClientsTable;
        var O365ClientsTable;
        var O365VersionsTable;
        var O365languagesTable;
        var O365ChannelsTable;
        var channelNames;
 
        adminUI.initializeController($scope, function () {
            NonOfficeClientsTable = "NonOfficeClientsTable";
            O365ClientsTable = "O365ClientsTable";
            O365VersionsTable = "O365VersionsTable";
            O365languagesTable = "O365languagesTable";
            O365ChannelsTable = "O365ChannelsTable"; 
            $scope.setupAria();
            channelNames = {
                "InsidersChannel" : {
                    "long": $scope.strings.InsidersChannelLong,
                    "short": $scope.strings.InsidersChannelShort
                },
                "MonthlyChannel": {
                    "long": $scope.strings.MonthlyChannelLong,
                    "short": $scope.strings.MonthlyChannelShort
                },
               
                "TargetedChannel": {
                    "long": $scope.strings.TargetedChannelLong,
                    "short": $scope.strings.TargetedChannelShort
                },
                
                "BroadChannel": {
                    "long": $scope.strings.BroadChannelLong,
                    "short": $scope.strings.BroadChannelShort
                },
                
                "PerpetualVL2019": {
                    "long": $scope.strings.PerpetualVL2019Long,
                    "short": $scope.strings.PerpetualVL2019Short
                },
              
                "MonthlyEnterpriseChannel": {
                    "long": $scope.strings.MonthlyEnterpriseChannelLong,
                    "short": $scope.strings.MonthlyEnterpriseChannelShort
                },
               
                "BetaChannel": {
                    "long": $scope.strings.BetaChannelLong,
                    "short": $scope.strings.BetaChannelShort
                },
               
            };

            // *** DATA QUERIES AND PREPARATION ***
            //gets collections data to load the Collections dropdown filter
            adminUI.wmiQuery("SELECT CollectionID, Name, MemberCount FROM SMS_Collection Where CollectionType=2 ORDER BY LocalMemberCount DESC",
            SMS_DeviceCollectionsReceived);

            //get ADRs to load the ADR dropdown filter
            adminUI.wmiQuery("SELECT DISTINCT AutoDeploymentID, Name FROM SMS_O365ADRs", SMS_ADRCollectionsReceived);
            
        });

        LoadDataAsync();

        async function LoadDataAsync() {
         
            $scope.isO365InstallerOn = await callMethodAsync("IsO365InstallerOn",null);
            $scope.hasAdrPermission = await callMethodAsync("HasADRPermissions",null);
            $scope.hasClientSettingsPermissions = await callMethodAsync("HasClientSettingsPermissions",null);
            $scope.$apply();
        }

        $scope.getString = function (stringName) {
            return $scope.strings[stringName];
        };

        $scope.keyPressDrillThrough = async function (event, id) {
            if (event.keyCode == 13) {
                switch (id) {                  
                    case 'O365Versions':
                        await callMethodAsync("OnModelTypeClick",JSON.stringify([$scope.SMS_DeviceCollections.Selected.CollectionID, $scope.SMS_DeviceCollections.Selected.Name, '']));
                        break;
                }
            }
        };

        // *** VARIABLE DECLARATIONS
        var COLL_DISP_LIMIT = 5; // determines the amount of collections displayed in the dropdown filter
        $scope.SMS_DeviceCollections = {}; //temp storage for collections data
        $scope.ADRS = []; // list of ADRs for dropdown selector

        async function SMS_DeviceCollectionsReceived(res) {
            res = JSON.parse(res);
            
            if (res.length === 0) {
                console.log("SMS_Collection returned no results");
                $scope.collectionsData = ChartState.NoDataFound;
                $scope.$apply();
                return;
            }
            
            const locCollections = res.slice(0, COLL_DISP_LIMIT);
            const localizedPromises = locCollections.map((item) => {             
                return new Promise((resolve, reject) => {
                    callMethod("GetCollectionAliasName", item.Name, function (response, returnCode) {
                        if (returnCode !== 0) {
                            console.error("Error retrieving alias name for collection:", item.Name);
                            reject(new Error("Failed to retrieve alias name"));
                        } else {
                            item.Name = (typeof response === 'string' && response.startsWith('"'))
                                        ? JSON.parse(response)
                                        : response;
                            resolve();
                        }
                    });
                });
            });
            
            await Promise.all(localizedPromises);
            
            $scope.SMS_DeviceCollections.All = locCollections;
            $scope.SMS_DeviceCollections.Selected = locCollections[0];
            
            $scope.collectionsData = ChartState.DataReady;
            $scope.SMS_DeviceCollectionChanged();
            
            $scope.$apply();           
        };

        function SMS_ADRCollectionsReceived(res) {
            res = res = JSON.parse(res);

            if (res.length == 0) {
                $scope.adrData = ChartState.NoDataFound;
                $scope.adrsExist = false;
                console.log("SMS_O365ADRs returned no results");
                return;
            }

            $scope.adrData = ChartState.DataReady;
            $scope.ADRS = res;
            $scope.ADR_choice = $scope.ADRS[0]; // default ADR dropdown 
            $scope.select_ADRchoice();
            $scope.$apply();
        }

        async function getO365Data(collection) {
            var channelMapping = await callJsonParseMethodAsync("clientChannel", null);
            var clientCounts = await callJsonParseMethodAsync("GetO365ClientCounts",collection.CollectionID);
            var versionCounts = await callJsonParseMethodAsync("GetO365VersionCounts",collection.CollectionID);
            var languageCounts = await callJsonParseMethodAsync("GetO365LanguageCounts",collection.CollectionID);
            var channelCounts = await callJsonParseMethodAsync("GetO365ChannelCounts",collection.CollectionID);
            var officeReadinessCounts86 = await callJsonParseMethodAsync("GetOfficeReadinessCounts",JSON.stringify([collection.CollectionID,'x86']));
            var officeReadinessCounts64 = await callJsonParseMethodAsync("GetOfficeReadinessCounts",JSON.stringify([collection.CollectionID,'x64']));
            var officeReadinessTotal = parseInt(officeReadinessCounts64.ReadyCount) + parseInt(officeReadinessCounts64.NotAssessedCount) + parseInt(officeReadinessCounts64.NeedsReviewCount) +
                parseInt(officeReadinessCounts86.ReadyCount) + parseInt(officeReadinessCounts86.NotAssessedCount) + parseInt(officeReadinessCounts86.NeedsReviewCount);
            if (officeReadinessTotal != 0) {
                $scope.$apply;
            }
            var clients, officeClients, nonOfficeClients, versions, languages, channels;
            // lengths will be 0 if query returns nothing, and charts will not render
            if (clientCounts.length == 0 || versionCounts.length == 0 || languageCounts.length == 0 || channelCounts.length == 0) {
                console.log("SMS_O365UpdatesDashboard returned no results");
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
            officeClients[$scope.getString("O365ClientsManaged")] = clientCounts.ManagedOffice365Clients.toString();
            officeClients[$scope.getString("O365ClientsUnmanaged")] = (clientCounts.Office365Clients - clientCounts.ManagedOffice365Clients).toString();
            nonOfficeClients[$scope.getString("NonOfficeClients")] = (clientCounts.MemberCount - clientCounts.Office365Clients).toString();

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
                if (channelMapping[el.cfgUpdateChannel00] != null) {
                    var mapToName = channelMapping[el.cfgUpdateChannel00];
                    channels[channelNames[mapToName].long] = el.NumOnChannel;
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
                showChartButton.textContent = $scope.strings["ShowChart"];
            }
            else if (o365Table.style.display == 'table') {
                o365Table.style.display = 'none';
                o365Chart.style.display = 'block';
                showChartButton.textContent = $scope.strings["ShowTable"];
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

            table.textContent = ""; //Set data to null in case it exists
            table.role = 'table';
            table.tabIndex = 0;

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
        $scope.appendChildItem = async function (table, item, count) {
            var div = 'div';
            var row = 'row';
            var cell = 'cell';

            // create new div element
            var addDiv = document.createElement(div);
            addDiv.className = row;
            addDiv.role = row;
            addDiv.tabIndex = 0;

            // Create first cell
            var addFirstCell = document.createElement(div);
            addFirstCell.className = cell;
            addFirstCell.role = cell;
            addFirstCell.tabIndex = 0;
            addFirstCell.textContent = item;

            //Create second cell
            var addSecondCell = document.createElement(div);
            addSecondCell.className = cell;
            addSecondCell.role = cell;
            addSecondCell.tabIndex = 0;
            addSecondCell.textContent = count;

            //Add item and Count
            addDiv.appendChild(addFirstCell);
            addDiv.appendChild(addSecondCell);

            table.appendChild(addDiv);
        };

        $scope.select_ADRchoice = function () {
            $scope.select_ADR = $scope.ADR_choice.AutoDeploymentID;
            $scope.deploymentChartData = ChartState.Loading;
            adminUI.wmiQuery("SELECT * FROM SMS_O365ADRs WHERE AutoDeploymentID = '" + $scope.select_ADR + "'", function(res) {
              res = JSON.parse(res)
              var totalRes = [];
              for (var i = 0; i < res.length; i++) {
                adminUI.wmiQuery("SELECT NumberSuccess, NumberErrors, NumberTargeted  from SMS_DeploymentSummary WHERE DeploymentID = '" + res[0].AssociatedDeploymentID + "'", function(depResults) {
                  if (depResults.length == 0) {
                    console.log("SMS_DeploymentSummary returned no results");
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
        $scope.launchO365Installer = async function () {
            try {
                await callMethodAsync("LaunchO365Installer",null);
            }
            catch (err) {
                console.log("launch Office 365 Install Wizard failed");
            }
        };

        // launch wizard to create a new ADR
        $scope.launchWizardADR = async function() {
        try {
            await callMethodAsync("LaunchWizardADR",null);
        } catch (err) {
            console.log("launch ADR wizard failed");
        }
        };

        // launch wizard to create a new Client Agent Settings
        $scope.launchWizardClientAgent = async function() {
        try {
            await callMethodAsync("LaunchWizardClientAgent",null);
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
        $scope.LaunchWizardCollectionPicker = async function () {
            try {
                // Collection is a string
                var collection = await callMethodAsync("LaunchWizardCollectionPicker",null);

                //get get collection object
                adminUI.wmiQuery("SELECT CollectionID, Name, MemberCount FROM SMS_Collection Where CollectionType=2 and CollectionID='"+ collection +"'", function (res) {
                    res = JSON.parse(res);

                    if (res.length === 0) {
                        console.log("SMS_Collection returned no results");
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
                        callMethod("GetCollectionAliasName", $scope.SMS_DeviceCollections.All[0].Name, function callback(response, returnCode) {
                            $scope.SMS_DeviceCollections.All[0].Name = JSON.parse(response);
                        });
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
        
    }])


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
          onclick: async function (d) {
            await callMethodAsync("OnModelTypeClick",JSON.stringify([coll, colName, d.name]));
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

    async function createLanguagesChart(languages, $scope, domNode, chartTitle) {
        var summaryText = "";
        var chart = document.querySelectorAll(domNode);
		var chartEl = angular.element(chart);
		var tileEl = chartEl.parent();
        var str = [];

        var languageNames = [];
        for (var key in languages) {
            languageNames[key] = await callMethodAsync("GetLanguageString",key);
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
// SIG // MIIomAYJKoZIhvcNAQcCoIIoiTCCKIUCAQExDzANBglg
// SIG // hkgBZQMEAgEFADB3BgorBgEEAYI3AgEEoGkwZzAyBgor
// SIG // BgEEAYI3AgEeMCQCAQEEEBDgyQbOONQRoqMAEEvTUJAC
// SIG // AQACAQACAQACAQACAQAwMTANBglghkgBZQMEAgEFAAQg
// SIG // TCu6ZYDVo54C4+k5MasvOcTY+/5F+3NK7gjYWll1UO+g
// SIG // gg2FMIIGAzCCA+ugAwIBAgITMwAABISY4hLgeKMxXQAA
// SIG // AAAEhDANBgkqhkiG9w0BAQsFADB+MQswCQYDVQQGEwJV
// SIG // UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMH
// SIG // UmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
// SIG // cmF0aW9uMSgwJgYDVQQDEx9NaWNyb3NvZnQgQ29kZSBT
// SIG // aWduaW5nIFBDQSAyMDExMB4XDTI1MDYxOTE4MjEzNVoX
// SIG // DTI2MDYxNzE4MjEzNVowdDELMAkGA1UEBhMCVVMxEzAR
// SIG // BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
// SIG // bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
// SIG // bjEeMBwGA1UEAxMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
// SIG // MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA
// SIG // 7XpKjCg5837MnNU9UKR3xba/q5Iq/JXcyzypjF20Q6Ll
// SIG // VwLLwX3ehPNrT4+GM2kpbhg0KF9zaTCqKCnlRY4zUat+
// SIG // 8sk/4dUEyzAfHaZrGf+9FDPlP7GMb7dT1lsS4zDSF6sw
// SIG // fD4xuoux9mBYJOGDoXxknpL581td3SwLX4w9MIsERD7w
// SIG // jZYpUc+16BXXuSjtNXhYlnrXoePKlDqlGgJCM5wuFwd7
// SIG // BXdS1lJrqVxytOUHyUpp3ovamSQWE7fGYQKxg4e50J/m
// SIG // NYzgN6AYglCeJ9QjGlnQ4a4HTLrtNuqFgG3wt6a6pFJ/
// SIG // C1qdvB/tki3rTRuSkGWcL8t2XJ+/j0BpeQIDAQABo4IB
// SIG // gjCCAX4wHwYDVR0lBBgwFgYKKwYBBAGCN0wIAQYIKwYB
// SIG // BQUHAwMwHQYDVR0OBBYEFATf9G+hYepzHROBQMWBvZFg
// SIG // qW2FMFQGA1UdEQRNMEukSTBHMS0wKwYDVQQLEyRNaWNy
// SIG // b3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQx
// SIG // FjAUBgNVBAUTDTIzMDAxMis1MDUzNjIwHwYDVR0jBBgw
// SIG // FoAUSG5k5VAF04KqFzc3IrVtqMp1ApUwVAYDVR0fBE0w
// SIG // SzBJoEegRYZDaHR0cDovL3d3dy5taWNyb3NvZnQuY29t
// SIG // L3BraW9wcy9jcmwvTWljQ29kU2lnUENBMjAxMV8yMDEx
// SIG // LTA3LTA4LmNybDBhBggrBgEFBQcBAQRVMFMwUQYIKwYB
// SIG // BQUHMAKGRWh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9w
// SIG // a2lvcHMvY2VydHMvTWljQ29kU2lnUENBMjAxMV8yMDEx
// SIG // LTA3LTA4LmNydDAMBgNVHRMBAf8EAjAAMA0GCSqGSIb3
// SIG // DQEBCwUAA4ICAQBi0KbNV1OEU3KAyAyz+kBtzZ0RN6f1
// SIG // kjKetQrPGfiVL98SVhrQc2JgiDZh1Rb+ovKWBf3u/RTS
// SIG // uj9aCo3bsah0onAXYPDI9JPJAxQP9HlNumzwUUFCGolq
// SIG // 4bAzq11nS5u2ZrudeqEKFFnCDbOIwX4wxFVeG5oEGH3v
// SIG // uPzFCcECfYepnxPpHAj+B5T+AoSEAVB6EspmpHEwb2cP
// SIG // kLLe7G3beSp0CpEhDdNQszxtWsApQiOsyyn/7yiMJ6h8
// SIG // P/lr3AK+4MCpVjZi8EzYvNO6/a1rF0HqdUPGDJCLhpmd
// SIG // GtagndxrjpEkc589v9KI3mVWIWcqIQkItQbPsX0ZL/38
// SIG // tB31d5jcjttnRVLx8wWYKhORWxo5lJ60q9cfJQqyvrOA
// SIG // PmzhqdiHozqYVqGRDxjnKPxxM52eS5OsOlvhNictzx6B
// SIG // RNGPE7ZEhOP/NGNpQSYS49u3fLnifCHUIUqS/1s04457
// SIG // mB+w8eaPaVnSBkmhTWLkqjmMa1VuzeABEFUQ2Xqg3H6j
// SIG // xtzuq+UjbMV23e9QwiEFEbVCrLOdzjfr65VdK44igSHc
// SIG // LzDS0PcytI8u+6MA8l16GJEMWpDdrhSATtVDQLwmF47O
// SIG // K8N0kZgV/aomeRDcXJ/6SzJIsm+vEHcB1F8/tXyOnmt/
// SIG // 446TT8+g5XP0THFyFnjDJIbqf1xG8Lu91Prs/zCCB3ow
// SIG // ggVioAMCAQICCmEOkNIAAAAAAAMwDQYJKoZIhvcNAQEL
// SIG // BQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
// SIG // aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
// SIG // ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMT
// SIG // KU1pY3Jvc29mdCBSb290IENlcnRpZmljYXRlIEF1dGhv
// SIG // cml0eSAyMDExMB4XDTExMDcwODIwNTkwOVoXDTI2MDcw
// SIG // ODIxMDkwOVowfjELMAkGA1UEBhMCVVMxEzARBgNVBAgT
// SIG // Cldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAc
// SIG // BgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEoMCYG
// SIG // A1UEAxMfTWljcm9zb2Z0IENvZGUgU2lnbmluZyBQQ0Eg
// SIG // MjAxMTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoC
// SIG // ggIBAKvw+nIQHC6t2G6qghBNNLrytlghn0IbKmvpWlCq
// SIG // uAY4GgRJun/DDB7dN2vGEtgL8DjCmQawyDnVARQxQtOJ
// SIG // DXlkh36UYCRsr55JnOloXtLfm1OyCizDr9mpK656Ca/X
// SIG // llnKYBoF6WZ26DJSJhIv56sIUM+zRLdd2MQuA3WraPPL
// SIG // bfM6XKEW9Ea64DhkrG5kNXimoGMPLdNAk/jj3gcN1Vx5
// SIG // pUkp5w2+oBN3vpQ97/vjK1oQH01WKKJ6cuASOrdJXtjt
// SIG // 7UORg9l7snuGG9k+sYxd6IlPhBryoS9Z5JA7La4zWMW3
// SIG // Pv4y07MDPbGyr5I4ftKdgCz1TlaRITUlwzluZH9TupwP
// SIG // rRkjhMv0ugOGjfdf8NBSv4yUh7zAIXQlXxgotswnKDgl
// SIG // mDlKNs98sZKuHCOnqWbsYR9q4ShJnV+I4iVd0yFLPlLE
// SIG // tVc/JAPw0XpbL9Uj43BdD1FGd7P4AOG8rAKCX9vAFbO9
// SIG // G9RVS+c5oQ/pI0m8GLhEfEXkwcNyeuBy5yTfv0aZxe/C
// SIG // HFfbg43sTUkwp6uO3+xbn6/83bBm4sGXgXvt1u1L50kp
// SIG // pxMopqd9Z4DmimJ4X7IvhNdXnFy/dygo8e1twyiPLI9A
// SIG // N0/B4YVEicQJTMXUpUMvdJX3bvh4IFgsE11glZo+TzOE
// SIG // 2rCIF96eTvSWsLxGoGyY0uDWiIwLAgMBAAGjggHtMIIB
// SIG // 6TAQBgkrBgEEAYI3FQEEAwIBADAdBgNVHQ4EFgQUSG5k
// SIG // 5VAF04KqFzc3IrVtqMp1ApUwGQYJKwYBBAGCNxQCBAwe
// SIG // CgBTAHUAYgBDAEEwCwYDVR0PBAQDAgGGMA8GA1UdEwEB
// SIG // /wQFMAMBAf8wHwYDVR0jBBgwFoAUci06AjGQQ7kUBU7h
// SIG // 6qfHMdEjiTQwWgYDVR0fBFMwUTBPoE2gS4ZJaHR0cDov
// SIG // L2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVj
// SIG // dHMvTWljUm9vQ2VyQXV0MjAxMV8yMDExXzAzXzIyLmNy
// SIG // bDBeBggrBgEFBQcBAQRSMFAwTgYIKwYBBQUHMAKGQmh0
// SIG // dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMv
// SIG // TWljUm9vQ2VyQXV0MjAxMV8yMDExXzAzXzIyLmNydDCB
// SIG // nwYDVR0gBIGXMIGUMIGRBgkrBgEEAYI3LgMwgYMwPwYI
// SIG // KwYBBQUHAgEWM2h0dHA6Ly93d3cubWljcm9zb2Z0LmNv
// SIG // bS9wa2lvcHMvZG9jcy9wcmltYXJ5Y3BzLmh0bTBABggr
// SIG // BgEFBQcCAjA0HjIgHQBMAGUAZwBhAGwAXwBwAG8AbABp
// SIG // AGMAeQBfAHMAdABhAHQAZQBtAGUAbgB0AC4gHTANBgkq
// SIG // hkiG9w0BAQsFAAOCAgEAZ/KGpZjgVHkaLtPYdGcimwuW
// SIG // EeFjkplCln3SeQyQwWVfLiw++MNy0W2D/r4/6ArKO79H
// SIG // qaPzadtjvyI1pZddZYSQfYtGUFXYDJJ80hpLHPM8QotS
// SIG // 0LD9a+M+By4pm+Y9G6XUtR13lDni6WTJRD14eiPzE32m
// SIG // kHSDjfTLJgJGKsKKELukqQUMm+1o+mgulaAqPyprWElj
// SIG // HwlpblqYluSD9MCP80Yr3vw70L01724lruWvJ+3Q3fMO
// SIG // r5kol5hNDj0L8giJ1h/DMhji8MUtzluetEk5CsYKwsat
// SIG // ruWy2dsViFFFWDgycScaf7H0J/jeLDogaZiyWYlobm+n
// SIG // t3TDQAUGpgEqKD6CPxNNZgvAs0314Y9/HG8VfUWnduVA
// SIG // KmWjw11SYobDHWM2l4bf2vP48hahmifhzaWX0O5dY0Hj
// SIG // Wwechz4GdwbRBrF1HxS+YWG18NzGGwS+30HHDiju3mUv
// SIG // 7Jf2oVyW2ADWoUa9WfOXpQlLSBCZgB/QACnFsZulP0V3
// SIG // HjXG0qKin3p6IvpIlR+r+0cjgPWe+L9rt0uX4ut1eBrs
// SIG // 6jeZeRhL/9azI2h15q/6/IvrC4DqaTuv/DDtBEyO3991
// SIG // bWORPdGdVk5Pv4BXIqF4ETIheu9BCrE/+6jMpF3BoYib
// SIG // V3FWTkhFwELJm3ZbCoBIa/15n8G9bW1qyVJzEw16UM0x
// SIG // ghprMIIaZwIBATCBlTB+MQswCQYDVQQGEwJVUzETMBEG
// SIG // A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
// SIG // ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
// SIG // MSgwJgYDVQQDEx9NaWNyb3NvZnQgQ29kZSBTaWduaW5n
// SIG // IFBDQSAyMDExAhMzAAAEhJjiEuB4ozFdAAAAAASEMA0G
// SIG // CWCGSAFlAwQCAQUAoIH3MBkGCSqGSIb3DQEJAzEMBgor
// SIG // BgEEAYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEE
// SIG // AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCDRkkFsalLZrH6D
// SIG // MusNPP89/PGlOWQZbtHcH13KWFC9aTCBigYKKwYBBAGC
// SIG // NwIBDDF8MHqgXIBaAE0AaQBjAHIAbwBzAG8AZgB0AC4A
// SIG // VABvAG8AbABrAGkAdAAuAFcAcABmAC4AVQBJAC4AQwBv
// SIG // AG4AdAByAG8AbABzAC4AVwBlAGIAVgBpAGUAdwAuAGQA
// SIG // bABsoRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
// SIG // BgkqhkiG9w0BAQEFAASCAQCqYYYwdQofzrvRBj17uSb6
// SIG // IgwxdyXh+3m7x83UVVSLa3s24qSd+SSMNKBtbdlYqbR9
// SIG // yDKytUCV6Ujts+RuI14+H+svHQ//lL7SqMNizSilPTDV
// SIG // DrMqckOrN/ypBR3YXrBFRDCuI28OoFZmZy7A9yG43JaQ
// SIG // 69JLB0iYqwdHD7xCHZnk1tnUeorHYUmW6aOY/VNaj8Yu
// SIG // 209kixhryLwPq3jJ9vcm/G/q7DZr9Bhx9jekXFfPob9d
// SIG // ZR0qC7iK/URSbJ9qUBCyFXwxkL6+koWMNlUrB2cKSEk1
// SIG // hFsSmI7td8jqUqmGEU7NJ10XqMbmbxut3yTRqQh1ueEU
// SIG // bXZCrxE+BNruoYIXrDCCF6gGCisGAQQBgjcDAwExgheY
// SIG // MIIXlAYJKoZIhvcNAQcCoIIXhTCCF4ECAQMxDzANBglg
// SIG // hkgBZQMEAgEFADCCAVkGCyqGSIb3DQEJEAEEoIIBSASC
// SIG // AUQwggFAAgEBBgorBgEEAYRZCgMBMDEwDQYJYIZIAWUD
// SIG // BAIBBQAEIINF9z/B/LsrdLPT9EX0qsyc7Pv6uDJLekgp
// SIG // QsUuTKmbAgZo8f/ux7YYEjIwMjUxMDIzMDI0NjAyLjg3
// SIG // WjAEgAIB9KCB2aSB1jCB0zELMAkGA1UEBhMCVVMxEzAR
// SIG // BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
// SIG // bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
// SIG // bjEtMCsGA1UECxMkTWljcm9zb2Z0IElyZWxhbmQgT3Bl
// SIG // cmF0aW9ucyBMaW1pdGVkMScwJQYDVQQLEx5uU2hpZWxk
// SIG // IFRTUyBFU046NEMxQS0wNUUwLUQ5NDcxJTAjBgNVBAMT
// SIG // HE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2WgghH7
// SIG // MIIHKDCCBRCgAwIBAgITMwAAAhgl2ZIF4ufl5AABAAAC
// SIG // GDANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzET
// SIG // MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
// SIG // bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
// SIG // aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFt
// SIG // cCBQQ0EgMjAxMDAeFw0yNTA4MTQxODQ4MjVaFw0yNjEx
// SIG // MTMxODQ4MjVaMIHTMQswCQYDVQQGEwJVUzETMBEGA1UE
// SIG // CBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEe
// SIG // MBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0w
// SIG // KwYDVQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRp
// SIG // b25zIExpbWl0ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNT
// SIG // IEVTTjo0QzFBLTA1RTAtRDk0NzElMCMGA1UEAxMcTWlj
// SIG // cm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZTCCAiIwDQYJ
// SIG // KoZIhvcNAQEBBQADggIPADCCAgoCggIBALHc6OrrkCag
// SIG // H8S57xAXyL4+pJyvqem5zFxBWf0IzzhcsJXIw38yPA4N
// SIG // Z8w5cZu/6am741ocr2syphcjuqmz8ApX0ZyOe4eTgosY
// SIG // KTjghiSUCGUk4jILotwfAz4hbST3H80bdxbJ8Yy18ASI
// SIG // xoJ4xn5kJe83owNVqGC/6gZkIcPxQxU1nm8X6OJtEQgj
// SIG // sX9qsI99Wjo3NmmFHj7SzFx7FyjxR9LaeUiiBf/bScUU
// SIG // oNDWBL0KlYpY3vGkJD3d6swLsdjHORzEiuDTE7VVQmAF
// SIG // g1GeKfuogyPbeQTQgSLH+aKBTVFrcQqp6RWIi2JB3xX8
// SIG // YVVAWfCxhsWLAN+rJw+ubNh3+LfOpNHvFnpR/7rH4WKj
// SIG // jN89smiPK4NPOt9SJMKlM8kKBD6jLB4AXptcaZjhkiFJ
// SIG // 1b07AL/pZhAi9kaq3DmZWWsfCtGooo/IelJFgTdiAP4p
// SIG // GnJE0hlUQUJllmbixVlf0+Mbjc7HAtF+8aOH3rYKbKmh
// SIG // ANI2P0Hr5E7y7+DpTTfXji/CzYe1ZtEeuT+6GmzkA6rV
// SIG // BQMAoI4DydIlf40AmjAHDt0mKRucEgGIiZJOFy4zUpTc
// SIG // VNiHY7NbDkYZe7OywuoTm+21QB1cDje+BsXxTYhCAOgX
// SIG // 7nQDY6UCdJ1HP6aRF6U+KYAwR7GLVfDsikoyrCMTnRUe
// SIG // 3yCSIw3PA71JAgMBAAGjggFJMIIBRTAdBgNVHQ4EFgQU
// SIG // JC6hxFw6G2O3R7qEAgWuLF+2i9EwHwYDVR0jBBgwFoAU
// SIG // n6cVXQBeYl2D9OXSZacbUzUZ6XIwXwYDVR0fBFgwVjBU
// SIG // oFKgUIZOaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3Br
// SIG // aW9wcy9jcmwvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUy
// SIG // MFBDQSUyMDIwMTAoMSkuY3JsMGwGCCsGAQUFBwEBBGAw
// SIG // XjBcBggrBgEFBQcwAoZQaHR0cDovL3d3dy5taWNyb3Nv
// SIG // ZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNyb3NvZnQlMjBU
// SIG // aW1lLVN0YW1wJTIwUENBJTIwMjAxMCgxKS5jcnQwDAYD
// SIG // VR0TAQH/BAIwADAWBgNVHSUBAf8EDDAKBggrBgEFBQcD
// SIG // CDAOBgNVHQ8BAf8EBAMCB4AwDQYJKoZIhvcNAQELBQAD
// SIG // ggIBAJ5I0YY8D4HaCKb7eGIqE/49C1rgcRdwEQSlwxDY
// SIG // IK2irwtKET8G4wJrF5zxJrbqOTA/LifV8PXmK8aqpCuA
// SIG // xfbJ2TKxzH6KMQmvvtYqy8/GKKMwuLXIvmuDd+0m5Hta
// SIG // bdcbPambb5D4GRlp+QXMFX5gMEmSx4tgrmdOmNP1/ren
// SIG // zQZ62zFaLzWg1+Fj3ciPRhM8XyIIA7HJNiKaOFVy/wK3
// SIG // M+6dhe2xGRkbssY4DAvsKApAyWh/8pP8HGaQLIsXuDzn
// SIG // TdA1umW9+Ttw4N/muqawDTHN1iHb3yg5e+T9GqnEG0AE
// SIG // e29H+IB+DTJFHLdFpuBjeSobBNWCu1f8AKgypiuI8d8y
// SIG // 892vB7MWvRwdxsorZZgubA4TpeEExjeZEYuqAqFeISvp
// SIG // CBYJ5Fox4UkTaJs9+kJ2wkhvwRyxJthkVPbt/yOM1HfR
// SIG // NQAveyCRBn8G/tDVm90BHK5MqXRnVsJdCxDm4a0EfQdV
// SIG // e/nnXMjZrF9KdgV9KxaXdT5FyUm8X/CHBIsP25DYGoGR
// SIG // PlZQ7cV3q7i3aOZN5Rjr+6z2LjhGqGWMQ72baRz/T9+s
// SIG // JluCDY0ejSJ59lDPpKz/8Xi50WwwZJvUbJZ6A4Va2pYi
// SIG // gx+tgcYXIC/bYkYDh5XCNMKr1Vi3b/MlvK8ZGsDpYQka
// SIG // k9xChAlvJLVAD8DWwVC5E/qFnLwXMIIHcTCCBVmgAwIB
// SIG // AgITMwAAABXF52ueAptJmQAAAAAAFTANBgkqhkiG9w0B
// SIG // AQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
// SIG // c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
// SIG // BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UE
// SIG // AxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0
// SIG // aG9yaXR5IDIwMTAwHhcNMjEwOTMwMTgyMjI1WhcNMzAw
// SIG // OTMwMTgzMjI1WjB8MQswCQYDVQQGEwJVUzETMBEGA1UE
// SIG // CBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEe
// SIG // MBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYw
// SIG // JAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
// SIG // MjAxMDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoC
// SIG // ggIBAOThpkzntHIhC3miy9ckeb0O1YLT/e6cBwfSqWxO
// SIG // dcjKNVf2AX9sSuDivbk+F2Az/1xPx2b3lVNxWuJ+Slr+
// SIG // uDZnhUYjDLWNE893MsAQGOhgfWpSg0S3po5GawcU88V2
// SIG // 9YZQ3MFEyHFcUTE3oAo4bo3t1w/YJlN8OWECesSq/XJp
// SIG // rx2rrPY2vjUmZNqYO7oaezOtgFt+jBAcnVL+tuhiJdxq
// SIG // D89d9P6OU8/W7IVWTe/dvI2k45GPsjksUZzpcGkNyjYt
// SIG // cI4xyDUoveO0hyTD4MmPfrVUj9z6BVWYbWg7mka97aSu
// SIG // eik3rMvrg0XnRm7KMtXAhjBcTyziYrLNueKNiOSWrAFK
// SIG // u75xqRdbZ2De+JKRHh09/SDPc31BmkZ1zcRfNN0Sidb9
// SIG // pSB9fvzZnkXftnIv231fgLrbqn427DZM9ituqBJR6L8F
// SIG // A6PRc6ZNN3SUHDSCD/AQ8rdHGO2n6Jl8P0zbr17C89XY
// SIG // cz1DTsEzOUyOArxCaC4Q6oRRRuLRvWoYWmEBc8pnol7X
// SIG // KHYC4jMYctenIPDC+hIK12NvDMk2ZItboKaDIV1fMHSR
// SIG // lJTYuVD5C4lh8zYGNRiER9vcG9H9stQcxWv2XFJRXRLb
// SIG // JbqvUAV6bMURHXLvjflSxIUXk8A8FdsaN8cIFRg/eKtF
// SIG // tvUeh17aj54WcmnGrnu3tz5q4i6tAgMBAAGjggHdMIIB
// SIG // 2TASBgkrBgEEAYI3FQEEBQIDAQABMCMGCSsGAQQBgjcV
// SIG // AgQWBBQqp1L+ZMSavoKRPEY1Kc8Q/y8E7jAdBgNVHQ4E
// SIG // FgQUn6cVXQBeYl2D9OXSZacbUzUZ6XIwXAYDVR0gBFUw
// SIG // UzBRBgwrBgEEAYI3TIN9AQEwQTA/BggrBgEFBQcCARYz
// SIG // aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9E
// SIG // b2NzL1JlcG9zaXRvcnkuaHRtMBMGA1UdJQQMMAoGCCsG
// SIG // AQUFBwMIMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBB
// SIG // MAsGA1UdDwQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB8G
// SIG // A1UdIwQYMBaAFNX2VsuP6KJcYmjRPZSQW9fOmhjEMFYG
// SIG // A1UdHwRPME0wS6BJoEeGRWh0dHA6Ly9jcmwubWljcm9z
// SIG // b2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1Jvb0Nl
// SIG // ckF1dF8yMDEwLTA2LTIzLmNybDBaBggrBgEFBQcBAQRO
// SIG // MEwwSgYIKwYBBQUHMAKGPmh0dHA6Ly93d3cubWljcm9z
// SIG // b2Z0LmNvbS9wa2kvY2VydHMvTWljUm9vQ2VyQXV0XzIw
// SIG // MTAtMDYtMjMuY3J0MA0GCSqGSIb3DQEBCwUAA4ICAQCd
// SIG // VX38Kq3hLB9nATEkW+Geckv8qW/qXBS2Pk5HZHixBpOX
// SIG // PTEztTnXwnE2P9pkbHzQdTltuw8x5MKP+2zRoZQYIu7p
// SIG // Zmc6U03dmLq2HnjYNi6cqYJWAAOwBb6J6Gngugnue99q
// SIG // b74py27YP0h1AdkY3m2CDPVtI1TkeFN1JFe53Z/zjj3G
// SIG // 82jfZfakVqr3lbYoVSfQJL1AoL8ZthISEV09J+BAljis
// SIG // 9/kpicO8F7BUhUKz/AyeixmJ5/ALaoHCgRlCGVJ1ijbC
// SIG // HcNhcy4sa3tuPywJeBTpkbKpW99Jo3QMvOyRgNI95ko+
// SIG // ZjtPu4b6MhrZlvSP9pEB9s7GdP32THJvEKt1MMU0sHrY
// SIG // UP4KWN1APMdUbZ1jdEgssU5HLcEUBHG/ZPkkvnNtyo4J
// SIG // vbMBV0lUZNlz138eW0QBjloZkWsNn6Qo3GcZKCS6OEua
// SIG // bvshVGtqRRFHqfG3rsjoiV5PndLQTHa1V1QJsWkBRH58
// SIG // oWFsc/4Ku+xBZj1p/cvBQUl+fpO+y/g75LcVv7TOPqUx
// SIG // UYS8vwLBgqJ7Fx0ViY1w/ue10CgaiQuPNtq6TPmb/wrp
// SIG // NPgkNWcr4A245oyZ1uEi6vAnQj0llOZ0dFtq0Z4+7X6g
// SIG // MTN9vMvpe784cETRkPHIqzqKOghif9lwY1NNje6CbaUF
// SIG // EMFxBmoQtB1VM1izoXBm8qGCA1YwggI+AgEBMIIBAaGB
// SIG // 2aSB1jCB0zELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
// SIG // c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
// SIG // BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEtMCsGA1UE
// SIG // CxMkTWljcm9zb2Z0IElyZWxhbmQgT3BlcmF0aW9ucyBM
// SIG // aW1pdGVkMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046
// SIG // NEMxQS0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29m
// SIG // dCBUaW1lLVN0YW1wIFNlcnZpY2WiIwoBATAHBgUrDgMC
// SIG // GgMVAJ1rRq11orjRPEKyn5uArRq+e8/poIGDMIGApH4w
// SIG // fDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
// SIG // b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
// SIG // Y3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWlj
// SIG // cm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwDQYJKoZI
// SIG // hvcNAQELBQACBQDso74bMCIYDzIwMjUxMDIyMjAzMzMx
// SIG // WhgPMjAyNTEwMjMyMDMzMzFaMHQwOgYKKwYBBAGEWQoE
// SIG // ATEsMCowCgIFAOyjvhsCAQAwBwIBAAICH88wBwIBAAIC
// SIG // El0wCgIFAOylD5sCAQAwNgYKKwYBBAGEWQoEAjEoMCYw
// SIG // DAYKKwYBBAGEWQoDAqAKMAgCAQACAwehIKEKMAgCAQAC
// SIG // AwGGoDANBgkqhkiG9w0BAQsFAAOCAQEAzP7tuerDBmVV
// SIG // wVALhJzdT2tLwR+MbJnIkCpHFonPHxjbozVwcfWPOuNI
// SIG // /4VHAxHtVMKHkZUQiFKup0knRZ8UrwyryTB7OmbaQJS7
// SIG // qVSmTj2+i9nHVhEhzFsNOrr8Gur7kMmEUpkUX7JLZUSF
// SIG // EMmaP3x7kgEG++DfgogFQoxj4LxIkhfOGcaijkoWnA/W
// SIG // iF1r5Fjn7z7IRbfp8piIvNDqfuCQgVvBkqCMpAqWAFqt
// SIG // 9TdsOxKkEimXmWWN4zQLzmwdE+S9fMfsceEx+LxOEr9Q
// SIG // M5Lz9UNZvz5pB4PTAgYdBHS0XtjrjIe+UPlhx2roeDC7
// SIG // 9v5JeOPmBI/3RWUhxFMf8TGCBA0wggQJAgEBMIGTMHwx
// SIG // CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
// SIG // MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
// SIG // b3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jv
// SIG // c29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAACGCXZ
// SIG // kgXi5+XkAAEAAAIYMA0GCWCGSAFlAwQCAQUAoIIBSjAa
// SIG // BgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZI
// SIG // hvcNAQkEMSIEINdKVmttRERe5eg6t9vZTLUZRgirLYW1
// SIG // lSLzzHS5jg1RMIH6BgsqhkiG9w0BCRACLzGB6jCB5zCB
// SIG // 5DCBvQQgmRPcibjkyLSMFmhEupcxiitV3EqM9cp0c2jl
// SIG // c8fXhWowgZgwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEG
// SIG // A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
// SIG // ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
// SIG // MSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQ
// SIG // Q0EgMjAxMAITMwAAAhgl2ZIF4ufl5AABAAACGDAiBCDH
// SIG // pesrNtXsL2kqUjHHsVJcI2rVrXjFlPaYYSxPmaKi2TAN
// SIG // BgkqhkiG9w0BAQsFAASCAgAECGhMMZPIOM1XelQMxRIO
// SIG // 1e/xElMBP7PIrDDKmDESfUaJ5H0NBAs+jOHzGh9zroQ8
// SIG // 3XJzMH3MIRs4bNNg8tAgJxxLqYYtFlBeORPyyvVfbCSw
// SIG // lgcyQPqgwiCsPvLc/b3GPLEyNtn+VPW67OmbGw7M9GUg
// SIG // UXnjWZGMn2v8IFj7Z8P+j90G21WkkUEs2FO1Da/rbae7
// SIG // NFAvzAaqjEoNy8vWYTfJYVjcQlSK8TYGwZWtC61JRRhv
// SIG // 47X3RbmOIeYyhqIa3fKKR+48G+gCWMeBqr2T/ipVKAji
// SIG // l++exF4jDxWGkuOh5CoPcwNBmrbwLzHJ3cpmto6+phSj
// SIG // FGBbLuHFMeKwLK7lDYZgT9xr5vyGnCyHyPOIY8F0qYUT
// SIG // jy6Pw1W8SaAhS/QqpvaZEE0lL73H7s4D5V4U/6EKeffh
// SIG // E0bgXPKA8hYX8F5kKFHv/NzUxus8+z7nOrqVOXl4MxFi
// SIG // n/QJ52UDkceJXOIVIOWa/AgJLjpcOarra8+QslcRNwbA
// SIG // PXAFhEoTF52B6qag0CRYVpK895EiHzEL2udweTsbo0SL
// SIG // zCkUn3UOHEbASION69DcisicBahh35rb3iy3zYG6UMoM
// SIG // SRz0Pgq90ADQMT8kZ05MyZSyrqqqqftDhQA9wMbWTgjx
// SIG // a45QtqhzjZYSQ5iYSuOdKGrDJpJuXeBV6G1ib2uMDaM6wg==
// SIG // End signature block
