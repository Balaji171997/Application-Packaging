//-----------------------------------------------------------------------------
// <copyright file="controller.js" company="Microsoft">
//    Copyright (c) 2018 Microsoft Corporation.  All rights reserved.
// </copyright>
// <purpose>
// </purpose>
// <notes>
// </notes>
//-----------------------------------------------------------------------------

(function () {
    "use strict";

    var dashboard = angular.module("dashboard", []);

    dashboard.controller("dashboardController", function ($scope) {

        adminUI.initializeController($scope, async function () {
            $scope.suppressRefresh = false;

            // Chart States
            $scope.ChartState = ChartState; // For use in ng-expression in html
            $scope.healthPercentageData = ChartState.Loading;
            $scope.clientVersionData = ChartState.Loading;
            $scope.osVersionData = ChartState.Loading;
            $scope.trendsByScenario = ChartState.Loading;

            // Filter data
            $scope.CollectionList;
            $scope.CollectionListFirst;
            $scope.days = 3;
            $scope.offline = false; // Show offline and online
            $scope.failure = false; // Show only failures

            $scope.collectionValue;
            $scope.ariaReady = 0;
            $scope.search = '';
            $scope.DefaultCollectionId;
            $scope.firstLoad = true;
            $scope.trendInterval = 31;
            $scope.queryText;

            // Variables for Client Failure Counts
            $scope.ch = true;
            $scope.policyRequest = true;
            $scope.sw = true;
            $scope.hw = true;
            $scope.ddr = true;
            $scope.statusMessage = true;

            // Client data
            $scope.clientVersion;
            $scope.osVersion;
            $scope.clientHealth;
            $scope.scenarioHealth;

            // WMI values
            $scope.collections;
            $scope.trendsByScenario;
            $scope.lastSummarization;
            $scope.dashboardData;

            // Client health failures values
            $scope.clientHealthFailure;
            $scope.sliderValue = $scope.trendInterval;
            $scope.combined;

            // Drill through
            $scope.baseClientVersion;
            $scope.baseOSVersion;
            $scope.osVersionDrillThrough;
            $scope.clientVersionDrillThrough;
            $scope.clientHealthDrillThrough;
            $scope.scenarioHealthDrillThrough;

            /// <summary>Gets a string calling getString in utility to display on the dashboard</summary>
            /// <param name="stringName">The name of the string in our resource file</param>
            /// <returns>The string that will be displayed on the dashboard</returns
            $scope.getString = function (stringName) {
                return $scope.strings[stringName];
            };

            // Accessibility
            $scope.offlineString = $scope.getString("ClientOffline");
            $scope.failureString = $scope.getString("Failure");
            $scope.clientDays = $scope.getString("ClientDays");

            // Strings to work around double-binding issue 
            $scope.percentHealthy = $scope.getString("PercentageHealthy");
            $scope.percentHealthyDesc = $scope.getString("PercentageHealthyDesc");
            $scope.learn = $scope.getString("LearnMore");
            $scope.filter = $scope.getString('Filter');
            $scope.browse = $scope.getString('Browse');

            await LoadDataAsync();
            $scope.$apply();
        });

        async function LoadDataAsync() {
            execute();
        };


        ////////////////////////////////////////////
        // Functions/Callbacks for refreshing the page data

        function refreshComplete(res) {
            $scope.dashboardData = res;
            refreshCollectionsCallback(res[0]); //$scope.collections
            refreshClientDataCallback(res[1]);  //$scope.dashboardData, XML format
            refreshTrendDataCallback(res[2]);   //$scope.trendsByScenario
        }

        async function refreshDashboard(collection) {
            $scope.healthPercentageData = ChartState.Loading;
            $scope.clientVersionData = ChartState.Loading;
            $scope.osVersionData = ChartState.Loading;
            $scope.trendsByScenario = ChartState.Loading;

            //get current scope based on filter state
            $scope.queryText = {
                "Collection": "", //will be set based on collections results in C#
                "Offline": ($scope.offline ? 0 : 1),
                "Failure": ($scope.failure ? 1 : 0),
                "Active": $scope.days,
                "clientHealth": ($scope.ch ? 1 : 0),
                "policyRequest": ($scope.policyRequest ? 1 : 0),
                "softwareInventory": ($scope.sw ? 1 : 0),
                "hardwareInventory": ($scope.hw ? 1 : 0),
                "ddr": ($scope.ddr ? 1 : 0),
                "statusMessage": ($scope.statusMessage ? 1 : 0)
            };

            adminUI.sendNewRequest("RefreshClientHealthDash", JSON.stringify([$scope.queryText, collection]), function callback(response, returnCode) {
                refreshComplete(JSON.parse(response));
            });
        }

        /////////////////////////////////////////////
        // Chart state parsing functions, update charts when refreshDashboard is called

        function refreshCollectionsCallback(res) {
            if (res.length == 0) {
                $scope.collections = ChartState.NoDataFound;
                $scope.$apply();
                return;
            }
            var collectionData = res;
            $scope.collections = ChartState.DataReady;

            //needs to be array of arrays, with each inner array being [CollectionID, Name]
            var collectionsArr = [];
            for (let i = 0; i <= collectionData.length - 1; i++) {
                var innerArray = [];
                innerArray.push(collectionData[i].CollectionID);
                innerArray.push(collectionData[i].Name);
                collectionsArr.push(innerArray);
            }
            $scope.collections = collectionsArr;
            if ($scope.collectionValue != undefined && $scope.collectionValue != null) {
                getCollectionList($scope.collectionValue.collectionId);
            } else {
                getCollectionList();
            }

            $scope.$apply();
        }

        function refreshClientDataCallback(res) {
            if (res.length == 0) {
                $scope.dashboardData = ChartState.NoDataFound;
                $scope.$apply();
                return;
            }

            parseXmlDashboardData(res);

            // Update chart states
            if (parseInt($scope.clientHealth[1]) === 0) {
                $scope.healthPercentageData = ChartState.NoDataFound;
            } else {
                $scope.healthPercentageData = ChartState.DataReady;
            }
            if ($scope.clientVersion.length > 0) {
                $scope.clientVersionData = ChartState.DataReady;
                $scope.osVersionData = ChartState.DataReady;
            } else {
                $scope.clientVersionData = ChartState.NoData;
                $scope.osVersionData = ChartState.NoData;
            }
            $scope.createDonut("#ClientVersionDetails", $scope.clientVersion);
            $scope.createDonut("#ClientTypes", $scope.osVersion);
            $scope.createGauge("#percentageHealthyGauge", $scope.clientHealth);
            $scope.createStackedBar("#ClientFailureCountsSansSummaries", $scope.scenarioHealth);

            if ($scope.brightness < 125) {
                SetColorToAllTextInChart("#percentageHealthyGauge", $scope.theme.ForeGroundColor);
                SetColorToAllTextInChart("#ClientTypes", $scope.theme.ForeGroundColor);
                SetColorToAllTextInChart("#ClientVersionDetails", $scope.theme.ForeGroundColor);
                SetColorToAllTextInChart("#ClientFailureCountsSansSummaries", $scope.theme.ForeGroundColor);
            }

            $scope.$apply();
        }

        function refreshTrendDataCallback(res) {
            if (res.length == 0) {
                $scope.trendsByScenario = ChartState.NoDataFound;
                $scope.$apply();
                return;
            }
            $scope.trendsByScenario = ChartState.DataReady;
            $scope.trendsByScenario = res;
            $scope.updateLineGraph("evalBtn");
            $scope.$apply();
        }


        /// <summary>get a range for the drop down days selector on the dashboard</summary>
        /// <param name="start">Int representing beginning of dropdown range</param>
        /// <param name="end">Int representing end of dropdown range</param>
        /// <returns>Array with range of number from start to end</returns>
        $scope.range = function (start, end) {
            var result = [];
            for (var i = start; i <= end; i++) {
                result.push(i);
            }
            return result;
        };

        /// <summary>Parses through a string searching for any number of {0} tags and replaces them with passed in args</summary>
        /// <param name="stringName">The name of the string in resource file with arguments formatted</param>
        /// <returns>String to be displayed on the dashboard, or argument/s if unparse-able</returns>
        $scope.formatString = function (format) {
            var args = Array.prototype.slice.call(arguments, 1);
            return format.replace(/{(\d+)}/g, function (match, number) {
                return (typeof args[number] != 'undefined') ? args[number] : match;
            });
        }

        /// <summart>Parses XML chart data and sets scope, called by refreshClientDataCallback</summary>
        /// <returns></returns>
        function parseXmlDashboardData(res) {
            // Scenario Health Combined Values
            var combinedAny = 0;
            var totalEvaluation = 0;

            if (res !== null && res !== undefined && res.length > 0) {
                $scope.ariaReady = 1;
                for (var i = 0; i < res.length; i++) {
                    var xmlValue = "<parent>" + res[i].XmlValue + "</parent>";
                    var parser = new DOMParser();
                    var xmlDoc = parser.parseFromString(xmlValue, "text/xml");

                    // Appropriately put the the tables in rows
                    if (parseInt(res[i].Id) === 0) {
                        // Client Health Percentage
                        // T = TotalClient
                        // H = HealthyClient
                        var totalClient = xmlDoc.getElementsByTagName("T")[0].childNodes[0].nodeValue;
                        var healthyClient = xmlDoc.getElementsByTagName("H")[0].childNodes[0].nodeValue;
                        $scope.clientHealth = [$scope.getString("PercentageHealthy"), parseInt(totalClient), parseInt(healthyClient)];

                    } else if (parseInt(res[i].Id) === 1) {
                        // Client Version Count
                        var count = 0;
                        var base = [];
                        var clientVerArray = [];

                        // Increment until we have no more data
                        while (xmlDoc.getElementsByTagName("C")[count] !== undefined) {
                            var clientVersionCountArr = [];

                            // C = ClientVersionCount
                            // V = ClientVersion
                            var clientVersionCount = xmlDoc.getElementsByTagName("C")[count].childNodes[0].nodeValue;
                            var clientVersion = xmlDoc.getElementsByTagName("V")[count].childNodes[0].nodeValue
                            clientVersionCountArr.push(clientVersion, clientVersionCount);
                            clientVerArray.push(clientVersionCountArr);

                            // Base used for drill through
                            base.push(clientVersion);
                            count++;
                        }
                        // Sort the values
                        clientVerArray.sort(function (first, compare) {
                            if (parseInt(first[1]) === parseInt(compare[1])) {
                                return 0;
                            } else {
                                return (parseInt(first[1]) < parseInt(compare[1])) ? -1 : 1;
                            }
                        });

                        // Get the top N values and replace rest with other
                        if (clientVerArray.length > 3) {
                            var other = 0;
                            var otherArray = [];
                            var newArray = [];

                            for (var j = 0; j < clientVerArray.length; j++) {
                                // All but smallest 3 will be placed in other
                                if (j < clientVerArray.length - 3) {
                                    other += parseInt(clientVerArray[j][1]);
                                } else {
                                    newArray.push([clientVerArray[j][0], parseInt(clientVerArray[j][1])]);
                                }
                            }
                            otherArray.push($scope.getString("Other"), other);
                            newArray.push(otherArray);

                            // Override the old array
                            clientVerArray = newArray;
                        }
                        $scope.clientVersion = clientVerArray;
                        $scope.baseClientVersion = base;
                    } else if (parseInt(res[i].Id) === 2) {

                        // OS Version Count
                        var count = 0;
                        var base = [];
                        var clientOSVerArray = [];

                        // Incremement until we have no more data
                        while (xmlDoc.getElementsByTagName("C")[count] !== undefined) {
                            var clientOSVersionCountArr = [];

                            // C = ClientOSVersionCount
                            // O = OperatingSystemVersion
                            var osVersionCount = xmlDoc.getElementsByTagName("C")[count].childNodes[0].nodeValue;
                            var operatingSystemVersion = xmlDoc.getElementsByTagName("O")[count].childNodes[0].nodeValue
                            clientOSVersionCountArr.push(operatingSystemVersion, osVersionCount);
                            clientOSVerArray.push(clientOSVersionCountArr);

                            // Base used for drill through
                            base.push(operatingSystemVersion);
                            count++;
                        }

                        // Sort the values
                        clientOSVerArray.sort(function (first, compare) {
                            if (parseInt(first[1]) === parseInt(compare[1])) {
                                return 0;
                            } else {
                                return (parseInt(first[1]) < parseInt(compare[1])) ? -1 : 1;
                            }
                        });

                        // Get the top N values and replace rest with other
                        if (clientOSVerArray.length > 3) {
                            var other = 0;
                            var otherArray = [];
                            var newArray = [];

                            for (var j = 0; j < clientOSVerArray.length; j++) {
                                // All but smallest 3 will be placed in other
                                if (j < clientOSVerArray.length - 3) {
                                    other += parseInt(clientOSVerArray[j][1]);
                                } else {
                                    newArray.push([clientOSVerArray[j][0], parseInt(clientOSVerArray[j][1])]);
                                }
                            }
                            otherArray.push($scope.getString("Other"), other);
                            newArray.push(otherArray);

                            // Override the old array
                            clientOSVerArray = newArray;
                        }
                        $scope.osVersion = clientOSVerArray;
                        $scope.baseOSVersion = base;
                    } else if (parseInt(res[i].Id) === 3) {

                        // Scenario Health
                        var scenarioHealthArray = [];

                        // T = TotalEvaluation
                        // E = LastEvaluationHealthy
                        // P = IsActivePolicyRequest
                        // S = IsActiveSW
                        // H = IsActiveHW
                        // D = IsActiveDDR
                        // M = IsActiveStatusMessage
                        totalEvaluation = xmlDoc.getElementsByTagName("T")[0].childNodes[0].nodeValue;
                        var lastEvaluationHealthy = 100 * (xmlDoc.getElementsByTagName("E")[0].childNodes[0].nodeValue / totalEvaluation);
                        var isActivePolicyRequest = 100 * (xmlDoc.getElementsByTagName("P")[0].childNodes[0].nodeValue / totalEvaluation);
                        var isActiveSW = 100 * (xmlDoc.getElementsByTagName("S")[0].childNodes[0].nodeValue / totalEvaluation);
                        var isActiveHW = 100 * (xmlDoc.getElementsByTagName("H")[0].childNodes[0].nodeValue / totalEvaluation);
                        var isActiveDDR = 100 * (xmlDoc.getElementsByTagName("D")[0].childNodes[0].nodeValue / totalEvaluation);
                        var isActiveStatusMessage = 100 * (xmlDoc.getElementsByTagName("M")[0].childNodes[0].nodeValue / totalEvaluation);

                        scenarioHealthArray.push(['x', $scope.getString('ClientEvalId'), $scope.getString('PolicyRequestId'), $scope.getString('SoftwareInventoryId'), $scope.getString('HardwareInventoryId'), $scope.getString('DDRId'), $scope.getString('StatusMessages')]);
                        scenarioHealthArray.push([$scope.getString('Success'), lastEvaluationHealthy, isActivePolicyRequest, isActiveSW, isActiveHW, isActiveDDR, isActiveStatusMessage]);
                        scenarioHealthArray.push([$scope.getString('Fail'), 100 - lastEvaluationHealthy, 100 - isActivePolicyRequest, 100 - isActiveSW, 100 - isActiveHW, 100 - isActiveDDR, 100 - isActiveStatusMessage]);
                        $scope.scenarioHealth = scenarioHealthArray;
                    } else if (parseInt(res[i].Id) === 4) {

                        // Scenario Health Any
                        // C = Combined
                        combinedAny = xmlDoc.getElementsByTagName("C")[0].childNodes[0].nodeValue;
                    } else if (parseInt(res[i].Id) === 6) {

                        // Error Code
                        var count = 0;
                        var clientErrorArray = [];
                        var clientErrorString = "";

                        while (xmlDoc.getElementsByTagName("E")[count] !== undefined) {
                            // E = ErrorCode
                            // C = Count

                            var errorCode = xmlDoc.getElementsByTagName("E")[count].childNodes[0].nodeValue;
                            var errorCodeCount = xmlDoc.getElementsByTagName("C")[count].childNodes[0].nodeValue;
                            count++;

                            // If value is NULL, we skip to next
                            if (errorCode === undefined) {
                                continue;
                            }
                            // Don't display success code
                            if (parseInt(errorCode) === 0) {
                                continue;
                            }
                            // Get the client error string from resource file
                            if (errorCode.charAt(0) === '-') {
                                errorCode = errorCode.substring(1);
                            }
                            clientErrorString = $scope.getString('Error' + errorCode);
                            if (clientErrorString === undefined || clientErrorString == "" || clientErrorString == null) {
                                clientErrorString = xmlDoc.getElementsByTagName("E")[count].childNodes[0].nodeValue;
                            }
                            clientErrorArray[count] =
                            {
                                failure: clientErrorString,
                                count: errorCodeCount,
                                errorCode: '-' + errorCode
                            }
                        }
                        // If there are no errors display no error message
                        if (clientErrorArray.length === 0) {
                            clientErrorArray.push({
                                failure: $scope.getString("NoError"),
                                count: "",
                                errorCode: ""
                            });
                        }
                        $scope.clientHealthFailure = clientErrorArray;
                        }
                }
                // If user has selected multiple scenarios to filter
                if (!(!$scope.ch && !$scope.policyRequest && !$scope.sw && !$scope.hw && !$scope.ddr && !$scope.statusMessage)) {
                    var ScenarioCounts = [];
                    var ScenarioCountsTitle = [];
                    var ScenarioCountsSuccess = [];
                    var ScenarioCountsFailure = [];

                    // Array with values for whether or not each combined value button was pressed
                    var combinedFlag = [];
                    combinedFlag.push($scope.ch);
                    combinedFlag.push($scope.policyRequest);
                    combinedFlag.push($scope.sw);
                    combinedFlag.push($scope.hw);
                    combinedFlag.push($scope.ddr);
                    combinedFlag.push($scope.statusMessage);

                    ScenarioCountsTitle.push('x');
                    ScenarioCountsSuccess.push($scope.getString('Success'));
                    ScenarioCountsFailure.push($scope.getString('Fail'));

                    for (var j = 0; j < combinedFlag.length; j++) {
                        // If the value is true we add the value to our client failure array
                        if (combinedFlag[j]) {
                            ScenarioCountsTitle.push($scope.scenarioHealth[0][j + 1]);
                            ScenarioCountsSuccess.push($scope.scenarioHealth[1][j + 1]);
                            ScenarioCountsFailure.push($scope.scenarioHealth[2][j + 1]);
                        }
                    }
                    // Add all of the values to the ScenarioCounts table
                    ScenarioCounts.push(ScenarioCountsTitle);
                    ScenarioCounts.push(ScenarioCountsSuccess);
                    ScenarioCounts.push(ScenarioCountsFailure);

                    $scope.combined = combinedAny;
                    let gaugearray = [$scope.getString("allClientsWithFailures"), $scope.clientHealth[1], combinedAny];
                    $scope.createRedGauge("#percentageUnhealthy", gaugearray);

                    if ($scope.brightness < 125) {
                        SetColorToAllTextInChart("#percentageUnhealthy", $scope.theme.ForeGroundColor);
                    }

                    $scope.scenarioHealth = ScenarioCounts;
                }
            }
        }

        //////////////////////////////////////////////////////////
        // functions to load drill through string queries

        /// <summary>Gets list of unhealthy clients for drill through</summary>
        /// <returns>Returns list of clients for drill through</returns>
        function loadHealthPercentageDrillThrough() {
            var offline = $scope.offline ? 0 : 1;

            $scope.clientHealthDrillThrough = "SELECT cdr.* FROM SMS_CombinedDeviceResources AS cdr LEFT JOIN SMS_CH_ClientHealth AS ch" +
                " ON ch.MachineID = cdr.ResourceID WHERE (ch.OnlineStatus = " + offline + " OR ch.OnlineStatus = 1)" +
                " AND ch.LastActiveTime > DATEADD(dd, -" + $scope.days + ", GETDATE()) AND ch.SiteID = \"" + $scope.CollectionListFirst.collectionId +
                "\" AND ch.LastEvaluationHealthy NOT LIKE 1";
        }
   
        /// <summary>Gets list of clients based on client system version for drill through</summary>
        /// <returns>Returns list of clients for drill through</returns>
        function loadClientVersionDrillThrough(ClientVersion) {
            var offline = $scope.offline ? 0 : 1;
            var failure = $scope.failure ? 1 : 0;
            var base = $scope.baseClientVersion;

            // Set lastEvaluationExclude
            var lastEvaluationExclude = (failure === 1) ? 1 : -1;

            var clientVersionString = "";
            // Check if we are selecting the other tag
            if (ClientVersion === $scope.getString("Other")) {
                for (var i = 0; i < $scope.clientVersion.length; i++) {
                    for (var j = 0; j < base.length; j++) {
                        if (base[j] === $scope.clientVersion[i][0]) {
                            base.splice(j, 1);
                            break;
                        }
                    }
                }
                if (base.length > 0) {
                    clientVersionString = " AND (";
                    // Iterate through the base array to get clients
                    for (var value in base) {
                        if (parseInt(value) === 0) {
                            clientVersionString += "SUBSTRING(ch.Client_Version0, 6, 4) LIKE \"" + base[parseInt(value)] + "\"";
                        } else {
                            clientVersionString += " OR SUBSTRING(ch.Client_Version0, 6, 4) LIKE \"" + base[parseInt(value)] + "\"";
                        }
                    }
                    clientVersionString += ")";
                }
            } else {
                clientVersionString = " AND SUBSTRING(ch.Client_Version0, 6, 4) LIKE " + ClientVersion;
            }
            $scope.clientVersionDrillThrough = "SELECT cdr.* FROM SMS_CombinedDeviceResources AS cdr LEFT JOIN SMS_CH_ClientHealth AS ch" +
                " ON ch.MachineID = cdr.ResourceID WHERE (ch.OnlineStatus = " + offline + " OR ch.OnlineStatus = 1)" +
                " AND ch.LastActiveTime > DATEADD(dd, -" + $scope.days + ", GETDATE()) AND ch.SiteID = \"" + $scope.CollectionListFirst.collectionId +
                "\" AND ch.LastEvaluationHealthy NOT LIKE " + lastEvaluationExclude + clientVersionString;
        }

        /// <summary>Gets list of clients based on operating system version for drill through</summary>
        /// <returns>Returns list of clients for drill through</returns>
        function loadOSVersionDrillThrough(OSVersion) {
            var offline = $scope.offline ? 0 : 1;
            var failure = $scope.failure ? 1 : 0;
            var base = $scope.baseOSVersion;

            // Set lastEvaluationExclude
            var lastEvaluationExclude = (failure === 1) ? 1 : -1;

            var OSVersionString = "";
            // Check if we are selecting the other tag
            if (OSVersion === $scope.getString("Other")) {
                for (var i = 0; i < $scope.osVersion.length; i++) {
                    for (var j = 0; j < base.length; j++) {
                        if (base[j] === $scope.osVersion[i][0]) {
                            base.splice(j, 1);
                            break;
                        }
                    }
                }
                if (base.length > 0) {
                    OSVersionString = " AND (";
                    // Iterate through the base array to get clients
                    for (var value in base) {
                        if (parseInt(value) === 0) {
                            OSVersionString += "ch.Operating_System_Name_and0 LIKE \"" + base[parseInt(value)] + "\"";
                        } else {
                            OSVersionString += " OR ch.Operating_System_Name_and0 LIKE \"" + base[parseInt(value)] + "\"";
                        }
                    }
                    OSVersionString += ")";
                }
            } else {
                OSVersionString = " AND ch.Operating_System_Name_and0 LIKE \"" + OSVersion + "\"";
            }
            $scope.osVersionDrillThrough = "SELECT cdr.* FROM SMS_CombinedDeviceResources AS cdr LEFT JOIN SMS_CH_ClientHealth AS ch" +
                " ON ch.MachineID = cdr.ResourceID WHERE (ch.OnlineStatus = " + offline + " OR ch.OnlineStatus = 1)" +
                " AND ch.LastActiveTime > DATEADD(dd, -" + $scope.days + ", GETDATE()) AND ch.SiteID = \"" + $scope.CollectionListFirst.collectionId +
                "\" AND ch.LastEvaluationHealthy NOT LIKE " + lastEvaluationExclude + OSVersionString;
        }

        /// <summary>Gets list of clients based on scenario health issues for drill through</summary>
        /// <returns>Returns list of clients for drill through</returns>
        function loadScenarioHealthDrillThrough(scenario, value) {
            var offline = $scope.offline ? 0 : 1;
            var failure = $scope.failure ? 1 : 0;
            var success = 0;

            if (value === $scope.getString("Success")) {
                success = 1;
            }
            // Set lastEvaluationExclude
            var lastEvaluationExclude = (failure === 1) ? 1 : -1;
            // Get the clients
            var dataString = "";
            if ($scope.scenarioHealth[0][scenario + 1] === $scope.getString("All")) {
                dataString = "SELECT cdr.* FROM SMS_CombinedDeviceResources AS cdr LEFT JOIN SMS_CH_ClientHealth AS ch" +
                " ON ch.MachineID = cdr.ResourceID WHERE (ch.OnlineStatus = " + offline + " OR ch.OnlineStatus = 1)" +
                " AND ch.LastActiveTime > DATEADD(dd, -" + $scope.days + ", GETDATE()) AND ch.SiteID = \"" + $scope.CollectionListFirst.collectionId +
                "\" AND ch.LastEvaluationHealthy NOT LIKE " + lastEvaluationExclude;
                if (success === 1) {
                    // Success scenario
                    var last = "";

                    if ($scope.ch === true) {
                        last += " AND (ch.LastEvaluationHealthy LIKE 1 OR (ch.LastHealthEvaluation IS NULL AND ch.LastEvaluationHealthy NOT LIKE 1))";
                    }
                    if ($scope.policyRequest === true) {
                        last += " AND (ch.IsActivePolicyRequest LIKE 1 OR (ch.LastPolicyRequest IS NULL AND ch.IsActivePolicyRequest NOT LIKE 1))";
                    }
                    if ($scope.sw === true) {
                        last += " AND (ch.IsActiveSW LIKE 1 OR (ch.LastSW IS NULL AND ch.IsActiveSW NOT LIKE 1))";
                    }
                    if ($scope.hw === true) {
                        last += " AND (ch.IsActiveHW LIKE 1 OR (ch.LastHW IS NULL AND ch.IsActiveHW NOT LIKE 1))";
                    }
                    if ($scope.ddr === true) {
                        last += " AND (ch.IsActiveDDR LIKE 1 OR (ch.LastDDR IS NULL AND ch.IsActiveDDR NOT LIKE 1))";
                    }
                    if ($scope.statusMessage === true) {
                        last += " AND (ch.IsActiveStatusMessages LIKE 1 OR (ch.LastStatusMessage IS NULL AND ch.IsActiveStatusMessages NOT LIKE 1))";
                    }
                    dataString += last;
                } else {
                    // Error scenario
                    var last = "";

                    if ($scope.ch === true) {
                        last += " AND (ch.LastEvaluationHealthy = 0 AND ch.LastHealthEvaluation IS NOT NULL)";
                    }
                    if ($scope.policyRequest === true) {
                        last += " AND (ch.IsActivePolicyRequest = 0 AND ch.LastPolicyRequest IS NOT NULL)";
                    }
                    if ($scope.sw === true) {
                        last += " AND (ch.IsActiveSW = 0 AND ch.LastSW IS NOT NULL)";
                    }
                    if ($scope.hw === true) {
                        last += " AND (ch.IsActiveHW = 0 AND ch.LastHW IS NOT NULL)";
                    }
                    if ($scope.ddr === true) {
                        last += " AND (ch.IsActiveDDR = 0 AND ch.LastDDR IS NOT NULL)";
                    }
                    if ($scope.statusMessage === true) {
                        last += " AND (ch.IsActiveStatusMessages = 0 AND ch.LastStatusMessage IS NOT NULL)";
                    }
                    dataString += last;
                }
            } else if ($scope.scenarioHealth[0][scenario + 1] === $scope.getString("Any")) {
                dataString = "SELECT cdr.* FROM SMS_CombinedDeviceResources AS cdr LEFT JOIN SMS_CH_ClientHealth AS ch" +
                    " ON ch.MachineID = cdr.ResourceID WHERE (ch.OnlineStatus = " + offline + " OR ch.OnlineStatus = 1)" +
                    " AND ch.LastActiveTime > DATEADD(dd, -" + $scope.days + ", GETDATE()) AND ch.SiteID = \"" + $scope.CollectionListFirst.collectionId +
                    "\" AND ch.LastEvaluationHealthy NOT LIKE " + lastEvaluationExclude;
                if (success === 1) {
                    // Success scenario
                    var last = " AND (";
                    var first = -1;

                    if ($scope.ch === true) {
                        if (first !== -1) {
                            last += " OR ";
                        }
                        first = 1;
                        last += "(ch.LastEvaluationHealthy = 1 OR (ch.LastEvaluationHealthy NOT LIKE 1 AND ch.LastHealthEvaluation IS NULL))";
                    }
                    if ($scope.policyRequest === true) {
                        if (first !== -1) {
                            last += " OR ";
                        }
                        first = 1;
                        last += "(ch.IsActivePolicyRequest = 1 OR (ch.IsActivePolicyRequest NOT LIKE 1 AND ch.LastPolicyRequest IS NULL))";
                    }
                    if ($scope.sw === true) {
                        if (first !== -1) {
                            last += " OR ";
                        }
                        first = 1;
                        last += "(ch.IsActiveSW = 1 OR (ch.IsActiveSW NOT LIKE 1 AND ch.LastSW IS NULL))";
                    }
                    if ($scope.hw === true) {
                        if (first !== -1) {
                            last += " OR ";
                        }
                        first = 1;
                        last += "(ch.IsActiveHW = 1 OR (ch.IsActiveHW NOT LIKE 1 AND ch.LastHW IS NULL))";
                    }
                    if ($scope.ddr === true) {
                        if (first !== -1) {
                            last += " OR ";
                        }
                        first = 1;
                        last += "(ch.IsActiveDDR = 1 OR (ch.IsActiveDDR NOT LIKE 1 AND ch.LastDDR IS NULL))";
                    }
                    if ($scope.statusMessage === true) {
                        if (first !== -1) {
                            last += " OR ";
                        }
                        first = 1;
                        last += "(ch.IsActiveStatusMessages = 1 OR (ch.IsActiveStatusMessages NOT LIKE 1 AND ch.LastStatusMessage IS NULL))";
                    }
                    last += ")";
                } else {
                    // Error scenario
                    var last = " AND (";
                    var first = -1;

                    if ($scope.ch === true) {
                        if (first !== -1) {
                            last += " OR ";
                        }
                        first = 1;
                        last += "(ch.LastEvaluationHealthy = 0 AND ch.LastHealthEvaluation IS NOT NULL)";
                    }
                    if ($scope.policyRequest === true) {
                        if (first !== -1) {
                            last += " OR ";
                        }
                        first = 1;
                        last += "(ch.IsActivePolicyRequest = 0 AND ch.LastPolicyRequest IS NOT NULL)";
                    }
                    if ($scope.sw === true) {
                        if (first !== -1) {
                            last += " OR ";
                        }
                        first = 1;
                        last += "(ch.IsActiveSW = 0 AND ch.LastSW IS NOT NULL)";
                    }
                    if ($scope.hw === true) {
                        if (first !== -1) {
                            last += " OR ";
                        }
                        first = 1;
                        last += "(ch.IsActiveHW = 0 AND ch.LastHW IS NOT NULL)";
                    }
                    if ($scope.ddr === true) {
                        if (first !== -1) {
                            last += " OR ";
                        }
                        first = 1;
                        last += "(ch.IsActiveDDR = 0 AND ch.LastDDR IS NOT NULL)";
                    }
                    if ($scope.statusMessage === true) {
                        if (first !== -1) {
                            last += " OR ";
                        }
                        first = 1;
                        last += "(ch.IsActiveStatusMessages = 0 AND ch.LastStatusMessage IS NOT NULL)";
                    }
                    last += ")";

                    dataString += last;
                }
            } else {
                dataString = "SELECT cdr.* FROM SMS_CombinedDeviceResources AS cdr LEFT JOIN SMS_CH_ClientHealth AS ch" +
                    " ON ch.MachineID = cdr.ResourceID WHERE (ch.OnlineStatus = " + offline + " OR ch.OnlineStatus = 1)" +
                    " AND ch.LastActiveTime > DATEADD(dd, -" + $scope.days + ", GETDATE()) AND ch.SiteID = \"" + $scope.CollectionListFirst.collectionId +
                    "\" AND ch.LastEvaluationHealthy NOT LIKE " + lastEvaluationExclude;
                if (success === 1) {
                    // Success scenario
                    var last = "";

                    switch ($scope.scenarioHealth[0][scenario + 1]) {
                        case $scope.getString("ClientEvalId"):
                            last = " AND (ch.LastEvaluationHealthy = 1 OR (ch.LastHealthEvaluation IS NULL AND ch.LastEvaluationHealthy NOT LIKE 1))";
                            break;
                        case $scope.getString("PolicyRequestId"):
                            last = " AND (ch.IsActivePolicyRequest = 1 OR (ch.LastPolicyRequest IS NULL AND ch.IsActivePolicyRequest NOT LIKE 1))";
                            break;
                        case $scope.getString("SoftwareInventoryId"):
                            last = " AND (ch.IsActiveSW = 1 OR (ch.LastSW IS NULL AND ch.IsActiveSW NOT LIKE 1))";
                            break;
                        case $scope.getString("HardwareInventoryId"):
                            last = " AND (ch.IsActiveHW = 1 OR (ch.LastHW IS NULL AND ch.IsActiveHW NOT LIKE 1))";
                            break;
                        case $scope.getString("DDRId"):
                            last = " AND (ch.IsActiveDDR = 1 OR (ch.LastDDR IS NULL AND ch.IsActiveDDR NOT LIKE 1))";
                            break;
                        case $scope.getString("StatusMessageId"):
                            last = " AND (ch.IsActiveStatusMessages = 1 OR (ch.LastStatusMessage IS NULL AND ch.IsActiveStatusMessages NOT LIKE 1))";
                            break;
                        default:
                            last = "";
                    }
                    dataString += last;
                } else {
                    // Error scenario
                    var last = "";

                    switch ($scope.scenarioHealth[0][scenario + 1]) {
                        case $scope.getString("ClientEvalId"):
                            last = " AND (ch.LastEvaluationHealthy NOT LIKE 1 AND ch.LastHealthEvaluation IS NOT NULL)";
                            break;
                        case $scope.getString("PolicyRequestId"):
                            last = " AND (ch.IsActivePolicyRequest NOT LIKE 1 AND ch.LastPolicyRequest IS NOT NULL)";
                            break;
                        case $scope.getString("SoftwareInventoryId"):
                            last = " AND (ch.IsActiveSW NOT LIKE 1 AND ch.LastSW IS NOT NULL)";
                            break;
                        case $scope.getString("HardwareInventoryId"):
                            last = " AND (ch.IsActiveHW NOT LIKE 1 AND ch.LastHW IS NOT NULL)";
                            break;
                        case $scope.getString("DDRId"):
                            last = " AND (ch.IsActiveDDR NOT LIKE 1 AND ch.LastDDR IS NOT NULL)";
                            break;
                        case $scope.getString("StatusMessageId"):
                            last = " AND (ch.IsActiveStatusMessages NOT LIKE 1 AND ch.LastStatusMessage IS NOT NULL)";
                            break;
                        default:
                            last = "";
                    }
                    dataString += last;
                }
            }
            $scope.scenarioHealthDrillThrough = dataString;
        }

        /// <summary>Gets list of clients based on errors/failures for drill through</summary>
        /// <returns>Returns list of clients for drill through</returns>
        $scope.loadClientErrorsDrillThrough = async function (errorCode) {
            var offline = $scope.offline ? 0 : 1;
            var failure = $scope.failure ? 1 : 0;

            // Set lastEvaluationExclude
            var lastEvaluationExclude = (failure === 1) ? 1 : -1;

            var clientErrorDrillThrough =
            "SELECT cdr.* FROM SMS_CombinedDeviceResources AS cdr LEFT JOIN SMS_CH_ClientHealth AS ch ON ch.MachineID = cdr.ResourceID" +
            " WHERE (ch.OnlineStatus = " + offline + " OR ch.OnlineStatus = 1)" +
            " AND ch.LastActiveTime > DATEADD(dd, -" + $scope.days + ", GETDATE()) AND ch.SiteID = \"" + $scope.CollectionListFirst.collectionId +
            "\" AND ch.LastEvaluationHealthy NOT LIKE " + lastEvaluationExclude + " AND ch.ErrorCode = " + errorCode;

            adminUI.sendNewRequest("DrillThroughVersion", JSON.stringify([clientErrorDrillThrough, $scope.getString("ClientHealthDashboard") + " " + $scope.getString("Top")]));
        }

        /////////////////////////////////////////////////////////////////////////
        // helper&chart functions

        /// <summary>Sets up all Aria strings for accessibility use</summary>
        /// <returns>Aria strings for narrator use</returns>
        function setupAria() {

            var tabidx = 0;    // dynamic .TabIndex assignment begins with Charts/Tables

            // Setup aria for the filters
            var clientCollectionSummaryText = $scope.getString('clientCollection') + ". " + $scope.collectionValue.name;
            var clientCollectionAriaLabel = document.getElementById("clientCollectionAria");
            clientCollectionAriaLabel.setAttribute("aria-label", clientCollectionSummaryText);

            var clientDaysSummaryText = $scope.clientDays;
            var clientDaysAriaLabel = document.getElementById("clientDaysAria");
            clientDaysAriaLabel.setAttribute("aria-label", clientDaysSummaryText);

            // Setup aria string for Percentage Healthy chart
            if ($scope.healthPercentageData == ChartState.DataReady) {
                var percentageHealthySummaryText = $scope.formatString($scope.getString("PercentageIs"), (100 * parseInt($scope.clientHealth[2]) / parseInt($scope.clientHealth[1])));
                var percentageHealthyAriaLabel = document.getElementById("PercentageHealthyAria");
                percentageHealthyAriaLabel.setAttribute("aria-label", percentageHealthySummaryText);
            } else {
                var percentageHealthyAriaLabel = document.getElementById("PercentageHealthyAria");
                percentageHealthyAriaLabel.removeAttribute("aria-label");
            }

            // Set up aria string for Percentage Unhealthy Chart
            if ($scope.healthPercentageData == ChartState.DataReady) {
                var errorPercent;
                if ($scope.combined == 0) {
                    errorPercent = "0"
                } else {
                    errorPercent = "" + (100 * parseInt($scope.combined) / parseInt($scope.clientHealth[1]))
                }
                var percentageUnhealthySummaryText = $scope.formatString($scope.getString("PercentageUnhealthyIs"), errorPercent);
                var percentageUnhealthyAriaLabel = document.getElementById("PercentageUnhealthyAria");
                percentageUnhealthyAriaLabel.setAttribute("aria-label", percentageUnhealthySummaryText);
            } else {
                var percentageUnhealthyAriaLabel = document.getElementById("PercentageUnhealthyAria");
                percentageUnhealthyAriaLabel.removeAttribute("aria-label");
            }

            // Setup aria string for Client Version Details chart & table
            var clientVersionDetailsSummaryText = "";
            var clientVersionTable = document.getElementById('ClientVersionDetailsTable');
            tabidx = 11;

            // Set back to starting state before inserting new lines
            clientVersionTable.innerHTML = "<div class=\"row\">" +
                "<div class=\"cell\" tabindex=\"10\">" + $scope.getString("clientVersion") + "</div>" +
                "<div class=\"cell\" tabindex=\"11\">" + $scope.getString("Count") + "</div>" +
                "</div>"
            for (var value in $scope.clientVersion) {
                clientVersionDetailsSummaryText += $scope.getString("clientVersion") + ", " + $scope.clientVersion[value][0] + ", " + $scope.getString("Count") + ", " + $scope.clientVersion[value][1] + ", ";
                clientVersionTable.innerHTML += "<div class=\"row\">" +
                    "<div class=\"cell\" tabindex=\"" + tabidx++ + "\">" + $scope.clientVersion[value][0] + "</div>" +
                    "<div class=\"cell\" tabindex=\"" + tabidx++ + "\">" + $scope.clientVersion[value][1] + "</div>" +
                    "</div>"
            }
            if ($scope.clientVersionData !== ChartState.DataReady) {
                clientVersionDetailsSummaryText = $scope.getString("NoFailure");
            }
            var clientVersionDetailsAriaLabel = document.getElementById("ClientVersionDetailsAria");
            clientVersionDetailsAriaLabel.setAttribute("aria-label", clientVersionDetailsSummaryText)

            // Setup aria string for Client Operating System Version chart & table
            var clientTypesSummaryText = "";
            var clientTypesTable = document.getElementById('ClientOSVersionDetailsTable');
            tabidx = 16;

            // Reset state before inserting new lines
            clientTypesTable.innerHTML = "<div class=\"row\">" +
                "<div class=\"cell\" tabindex=\"15\">" + $scope.getString("OSVersion") + "</div>" +
                "<div class=\"cell\" tabindex=\"16\">" + $scope.getString("Count") + "</div>" +
                "</div>"
            for (var value in $scope.osVersion) {
                clientTypesSummaryText += $scope.getString("OSVersion") + ", " + $scope.osVersion[value][0] + ", " + $scope.getString("Count") + ", " + $scope.osVersion[value][1] + ", ";
                clientTypesTable.innerHTML += "<div class=\"row\">" +
                    "<div class=\"cell\" tabindex=\"" + tabidx++ + "\">" + $scope.osVersion[value][0] + "</div>" +
                    "<div class=\"cell\" tabindex=\"" + tabidx++ + "\">" + $scope.osVersion[value][1] + "</div>" +
                    "</div>"
            }
            if ($scope.osVersionData !== ChartState.DataReady) {
                clientTypesSummaryText = $scope.getString("NoFailure");
            }
            var clientTypesSummaryAriaLabel = document.getElementById("ClientTypesAria");
            clientTypesSummaryAriaLabel.setAttribute("aria-label", clientTypesSummaryText);

            // Setup aria string for Client Scenario Health Counts chart
            var clientFailureCountsSummaryText = "";
            for (var value in $scope.scenarioHealth[0]) {
                // Skip the labels for the data
                if ($scope.scenarioHealth[0][value] === "x") {
                    continue;
                }
                clientFailureCountsSummaryText += $scope.formatString($scope.getString("Scenario"), $scope.scenarioHealth[0][value], $scope.scenarioHealth[1][value], $scope.scenarioHealth[2][value]);
            }
            var clientFailureCountsAriaLabel = document.getElementById("ClientFailureCountAria");
            clientFailureCountsAriaLabel.setAttribute("aria-label", clientFailureCountsSummaryText);

            // Setup aria string for Health Trends by Scenario chart
            var stringMap = {
                "evalBtn": "ClientEvalId",
                "softwareBtn": "SoftwareInventoryId",
                "hardwareBtn": "HardwareInventoryId",
                "statusBtn": "StatusMessageId",
                "DDRBtn": "DDRId",
                "PolicyBtn": "PolicyRequestId",
            }
            var idMap = {
                "evalBtn": "ClientsHealthy",
                "softwareBtn": "ClientsActiveSW",
                "hardwareBtn": "ClientsActiveHW",
                "statusBtn": "ClientsActiveStatusMessage",
                "DDRBtn": "ClientsActiveDDR",
                "PolicyBtn": "ClientsActivePolicyRequest",
            };
            var idList = ["evalBtn", "softwareBtn", "hardwareBtn", "statusBtn", "DDRBtn", "PolicyBtn"];
            var healthTrendsByScenarioText = "";

            //find selected trends or start with default
            var selectedEl = "";
            idList.forEach(function (identifier) {
                var el = document.getElementById(identifier)
                if (el.classList.contains("selected")) {
                    selectedEl = identifier;
                }
            });
            if (selectedEl === "") {
                selectedEl = "evalBtn"
            }

            //build and attach aria-string from currently selected data
            var selectedData = $scope.parseTrendData(idMap[selectedEl]);
            var dates = selectedData.dates;
            var nums = selectedData.numbers;
            if (dates.length > $scope.sliderValue) {
                var start = (dates.length - $scope.sliderValue) - 1;
                dates = dates.slice(start, dates.length);
                nums = nums.slice(start, nums.length);
            }
            var valueArr = [];
            for (var i = 1; i <= dates.length - 1; i++) {
                var date = dates[i].split('-').slice(1).join('/')
                valueArr.push(date + ", " + (100 * nums[i]).toFixed(2) + ", ")
            }
            var valueString = valueArr.join('');
            healthTrendsByScenarioText = $scope.formatString($scope.getString("HealthTrendScenario"), $scope.getString(stringMap[selectedEl]), valueString);
            var lineChart = document.getElementById("TrendsByScenario")
            lineChart.setAttribute("aria-label", healthTrendsByScenarioText)
        }

        /// <summary>Checks if a string is null or empty</summary>
        /// <param name="string">The string that we want to validate</param>
        /// <returns>True or false, dependant on whther or not the string is valid</returns>
        function validateString(string) {
            var returnVal = true;
            // Check for null, empty, or unknown string
            if (string === null || string === "" || string.charAt(0) === '?') {
                returnVal = false;
            }
            return returnVal;
        }

        /// <summary>Gets list of collections</summary>
        /// <returns>Returns a list of collections in this hierarchy</returns>
        async function getCollectionList(selectedCollection) {
            var res = [];
            var firstCount = 0;
            var systemsValue = 0;
            var name = "";
            for (var collection in $scope.collections) {
                // Validate the strings to ensure the dashboard does not display invalid entries
                if (collection !== null && validateString($scope.collections[collection][0]) && validateString($scope.collections[collection][1])) {

                    // Value not localized
                    name = $scope.collections[collection][1];

                    // Check if the collections are any of the default collections
                    // 1) All Desktop and Server Clients
                    // 2) All Mobile Devices
                    // 3) All Systems
                    // 4) All Unknown Computers
                    if ($scope.collections[collection][0] === 'SMSDM003'
                        || $scope.collections[collection][0] === 'SMSDM001'
                        || $scope.collections[collection][0] === 'SMS00001'
                        || $scope.collections[collection][0] === 'SMS000US') {
                        name = $scope.getString($scope.collections[collection][1].split(' ').join('_'));
                    }

                    // Create an item for the collection
                    var collectionItem = {
                        collectionId: $scope.collections[collection][0],
                        name: name
                    }
                    // Get count to ensure all systems is default value
                    if ($scope.collections[collection][1] !== $scope.getString("All_Systems")) {
                        firstCount++;
                    } else if ($scope.collections[collection][1] === $scope.getString("All_Systems")) {
                        systemsValue = firstCount;
                    }
                    res.push(collectionItem);
                }
            }
            $scope.CollectionList = res;
            $scope.DefaultCollectionId = await callMethodAsync("FindDefaultCollection", null);

            if ($scope.DefaultCollectionId.length === 0 && selectedCollection === undefined) {
                // No default set, use All Systems
                $scope.CollectionListFirst = $scope.CollectionList[systemsValue];
                $scope.collectionValue = {
                    name: $scope.CollectionListFirst.name,
                    collectionId: $scope.CollectionListFirst.collectionId
                }
            }
            else if ($scope.DefaultCollectionId.length > 0 && selectedCollection === undefined) {
                // if a default collection is found, no alternate passed in, set default to CollectionListFirst
                $scope.CollectionList.forEach(function (value) {
                    if (value.collectionId === $scope.DefaultCollectionId) {
                        $scope.CollectionListFirst = value;
                    }
                });
                $scope.collectionValue = {
                    name: $scope.CollectionListFirst.name,
                    collectionId: $scope.CollectionListFirst.collectionId
                }
            }
            else {
                // a specific collection was selected in collection picker
                $scope.CollectionList.forEach(function (value) {
                    //sanity check to make sure selected collection exists
                    if (value.collectionId === selectedCollection) {
                        $scope.collectionValue = {
                            name: $scope.CollectionListFirst.name,
                            collectionId: selectedCollection
                        }
                    }
                })
            }
            // update Aria
            setupAria();
            $scope.$apply();
        }

        /// <summary>Modify tooltip to display data instead of percentages</summary>
        /// <param name="d">Tooltip[ data</param>
        /// <param name="defaultTitleFormat">Default tooltip title format</param>
        /// <param name="defaultValueFormat">Default tooltip value format</param>
        /// <param name="color">Tooltip background color</param>
        /// <returns>HTML code for the tooltip modification</returns>
        function tooltip_contents(d, defaultTitleFormat, defaultValueFormat, color) {
            var $$ = this;
            var config = $$.config;
            var titleFormat = config.tooltip_format_title || defaultTitleFormat;
            var nameFormat = config.tooltip_format_name || function (name) {
                return name;
            };

            var text;
            var title;
            var value;
            var name;
            var bgcolor;

            for (var i = 0; i < d.length; i++) {
                if (!(d[i] && (d[i].value || d[i].value === 0))) {
                    continue;
                }
                // Title
                if (!text) {
                    title = titleFormat ? titleFormat(d[i].x) : d[i].x;
                    text = "<table class='" + $$.CLASS.tooltip + "'>" + (title || title === 0 ? "<tr><th colspan='2'>" + title + "</th></tr>" : "");
                }
                // Contents
                name = nameFormat(d[i].name);
                value = d[i].value;
                bgcolor = $$.levelColor ? $$.levelColor(d[i].value) : color(d[i].id);

                text += "<tr class='" + $$.CLASS.tooltipName + "-" + d[i].id + "'>";
                text += "<td class='name'><span style='background-color:" + bgcolor + "'></span>" + name + "</td>";
                text += "<td class='value'>" + value + "</td>";
                text += "</tr>";
            }
            return text + "</table>";
        }

        /// <summary>Modify tooltip to display data and percentages</summary>
        /// <param name="d">Tooltip[ data</param>
        /// <param name="defaultTitleFormat">Default tooltip title format</param>
        /// <param name="defaultValueFormat">Default tooltip value format</param>
        /// <param name="color">Tooltip background color</param>
        /// <returns>HTML code for the tooltip modification</returns>
        function tooltip_scenario(d, defaultTitleFormat, defaultValueFormat, color) {
            var $$ = this;
            var config = $$.config;
            var titleFormat = config.tooltip_format_title || defaultTitleFormat;
            var nameFormat = config.tooltip_format_name || function (name) {
                return name;
            };

            var text;
            var title;
            var value;
            var name;
            var bgcolor;

            for (var i = 0; i < d.length; i++) {
                if (!(d[i] && (d[i].value || d[i].value === 0))) {
                    continue;
                }
                // Title
                if (!text) {
                    title = titleFormat ? titleFormat(d[i].x) : d[i].x;
                    text = "<table class='" + $$.CLASS.tooltip + "'>" + (title || title === 0 ? "<tr><th colspan='3'>" + title + "</th></tr>" : "");
                }
                // Contents
                name = nameFormat(d[i].name);
                value = d[i].value;
                bgcolor = $$.levelColor ? $$.levelColor(d[i].value) : color(d[i].id);

                text += "<tr class='" + $$.CLASS.tooltipName + "-" + d[i].id + "'>";
                text += "<td class='name'><span style='background-color:" + bgcolor + "'></span>" + name + "</td>";
                text += "<td class='value'>" + d3.format(".2f")(value) + "%" + "</td>";
                if ($scope.failure == 1) {
                    text += "<td class='value'>" + Math.round(value / 100 * ($scope.clientHealth[1] - $scope.clientHealth[2])) + "</td>";
                } else {
                    text += "<td class='value'>" + Math.round(value / 100 * $scope.clientHealth[1]) + "</td>";
                }
                text += "</tr>";
            }
            return text + "</table>";
        }

        /// <summary>Launches the collection picker wizard</summary>
        /// <returns>Returns the collection that we want to load data for</returns>
        $scope.LaunchCollectionPickerWizard = async function () {
            // Get the collection from the wizard
            var collections = await callMethodAsync("LaunchWizardCollectionPicker", null);
            var collectionName = "";

            // If empty string and clicked out don't reload
            if (collections === "") {
                return;
                return
            }
            // Get the value from CollectionListFirst
            for (var collection in $scope.CollectionList) {
                if ($scope.CollectionList[collection].collectionId === collections) {
                    collectionName = $scope.CollectionList[collection].name;
                    break;
                }
            }

            // Create collection value object
            $scope.collectionValue = {
                collectionId: collections,
                name: collectionName
            }

            $scope.CollectionListFirst = $scope.collectionValue;
            $scope.refresh($scope.collectionValue.collectionId);
        }

        /// <summary>parse through trendData List for selected data and return in format useable by linechart</summary>
        /// <param name=selectedCategory>name of client heatlh category</param>
        /// <returns>object formatted for c3 line chart consumption</returns>
        $scope.parseTrendData = function (selectedCategory) {
            const trends = $scope.trendsByScenario;
            const categoryDecoder = {
                "ClientsHealthy": "ClientEvalId",
                "ClientsActiveSW": "SoftwareInventoryId",
                "ClientsActiveHW": "HardwareInventoryId",
                "ClientsActiveStatusMessage": "StatusMessageId",
                "ClientsActiveDDR": "DDRId",
                "ClientsActivePolicyRequest": "PolicyRequestId"
            }
            let chartData = {
                name: $scope.getString(categoryDecoder[selectedCategory]),
                dates: [],
                numbers: []
            };
            let siteCodes = []; //to track siteCodes touched
            let sites = {}; //to track percent results for each siteCode on each date
            if (trends.length > 0) {
                trends.forEach(function (item) {
                    let date = item.Date.slice(0, 10); //"YYYY-MM-DD" first 10 chars

                    //account for inactive clients
                    if (item[selectedCategory] > item.ClientsActive) {
                        item[selectedCategory] = item[selectedCategory] - item.ClientsInactive;
                    }
                    let percentClients = item.ClientsTotal != 0 ? (item[selectedCategory] / (item.ClientsActive)).toFixed(2) : 0;

                    //account for different SiteCodes
                    //first instance of this site
                    if (siteCodes.indexOf(item.SiteCode) == -1) {
                        siteCodes.push(item.SiteCode);
                        sites[item.SiteCode] = {};
                        sites[item.SiteCode].dates = [date,];
                        if (chartData.dates.indexOf(date) == -1) { chartData.dates.push(date); };
                        sites[item.SiteCode].nums = [percentClients,];
                    } else {
                        //duplicate site code
                        let dateIndex = sites[item.SiteCode].dates.indexOf(date);
                        if (dateIndex != -1) {
                            //duplicate date in duplicate SiteCode, overwrite with most current data
                            sites[item.SiteCode].nums[dateIndex] = percentClients;
                        } else {
                            //new date old SiteCode
                            sites[item.SiteCode].dates.push(date);
                            if (chartData.dates.indexOf(date) == -1) { chartData.dates.push(date); };
                            sites[item.SiteCode].nums.push(percentClients);
                        }
                    }
                })
                chartData.dates.forEach(function (date) {
                    //collect and aggregate data for all sites. 
                    let sum = 0;
                    let count = 0;
                    siteCodes.forEach(function (code) {
                        let dateI = sites[code].dates.indexOf(date);
                        if (dateI != -1) {
                            sum = sum + parseFloat(sites[code].nums[dateI]);
                            count = count + 1;
                        };
                    })
                    let overallPercent = 0;
                    if (count != 0) { overallPercent = sum / count; }
                    chartData.numbers.push(overallPercent)
                })

                //find the last date in the list store it for rendering in the UI.
                let dateString = chartData.dates[chartData.dates.length - 1].split('-');
                let year = parseInt(dateString[0]);
                let month = parseInt(dateString[1]) - 1;
                let day = parseInt(dateString[2]);
                let localDate = new Date(year, month, day).toLocaleDateString();
                $scope.lastSummarization = $scope.formatString($scope.getString("LastSummarization"), localDate);
            } else {
                //there is no data
                chartData.name = $scope.getString('NoFailure');
            }
            return chartData;
        }

        /// <summary>Create a stacked bar chart</summary>
        /// <param name="idToBindTo">Id to bind the chart to</param>
        /// <param name="columns">The columns of the data in the table that we will be putting into our charts</param>
        /// <returns>Stacked bar chart chart</returns>
        $scope.createStackedBar = async function (idToBindTo, columns) {
            // Check if there is data
            if (columns === null || columns === undefined) {
                return;
            }
            $scope.stackedBarChart = c3.generate({
                bindto: idToBindTo,
                data: {
                    x: 'x',
                    columns: columns,
                    type: 'bar',
                    onclick: function (d) {
                        loadScenarioHealthDrillThrough(d.x, d.id);
                        adminUI.sendNewRequest("DrillThroughVersion", JSON.stringify([$scope.scenarioHealthDrillThrough, columns[0][d.index + 1] + " " + d.name]));
                    },
                    groups: [
                        [$scope.getString('Success'), $scope.getString('Fail')]
                    ],
                    color: function (incolor, data) {
                        var colors = ['#107C10', '#D83B01'];
                        if (data.id === $scope.getString('Success')) {
                            return '#107C10'
                        }
                        else if (data.id === $scope.getString('Fail')) {
                            return '#D83B01'
                        }
                        if (data === $scope.getString('Success')) {
                            return '#107C10'
                        }
                        else if (data === $scope.getString('Fail')) {
                            return '#D83B01'
                        }
                    },
                    order: null
                },
                axis: {
                    x: {
                        type: 'category',
                        tick: {
                            rotate: 155,
                            multilineL: false
                        }
                    },
                    y: {
                        tick: {
                            values: [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100],
                            count: 11
                        }
                    },
                    rotated: true
                },
                size: {
                    height: 260
                },
                tooltip: {
                    contents: tooltip_scenario
                },
            });
        };

        /// <summary>Create a gauge chart</summary>
        /// <param name="idToBindTo">Id to bind the chart to</param>
        /// <param name="columns">The columns of the data in the table that we will be putting into our charts</param>
        /// <returns>Gauge chart</returns>
        $scope.createGauge = function (idToBindTo, columns) {
            // Check if there is data
            if (columns === null || columns === undefined) {
                return;
            }
            var column = columns;
            // See whether or not we have data in the chart
            if (columns[1] === 0) {
                column = [];
            } else {
                column = [[column[0], column[2]]];
            }
            $scope.gaugeChart = c3.generate({
                bindto: idToBindTo,
                data: {
                    columns: column,
                    type: 'gauge',
                    onclick: function (d) {
                        loadHealthPercentageDrillThrough();
                        adminUI.sendNewRequest("DrillThroughVersion", JSON.stringify([$scope.clientHealthDrillThrough, $scope.getString("PercentageHealthy")]));
                    },
                },
                gauge: {
                    min: 0,
                    max: columns[1],
                    label: {
                        format: function (value) {
                            if (isNaN(value / columns[1])) {
                                return 0
                            } else {
                                return d3.format("0.2%")(value / columns[1]);
                            }
                        }
                    }
                },
                color: {
                    pattern: ['#D83B01', '#107C10'],
                    threshold: {
                        unit: 'percentage',
                        values: [columns[1] * 0.8, columns[1]]
                    }
                },
                size: {
                    height: 180
                }
            });
        };

        /// <summary>Create a gauge chart with a red gauge</summary>
        /// <param name="idToBindTo">Id to bind the chart to</param>
        /// <param name="columns">The columns of the data in the table that we will be putting into our charts</param>
        /// <returns>Gauge chart</returns>
        $scope.createRedGauge = async function (idToBindTo, columns) {
            // Check if there is data
            if (columns === null || columns === undefined) {
                return;
            }
            var column = columns;
            // See whether or not we have data in the chart
            if (columns[1] === 0) {
                column = [];
            } else {
                column = [[column[0], column[2]]];
            }
            $scope.gaugeChart = c3.generate({
                bindto: idToBindTo,
                data: {
                    columns: column,
                    type: 'gauge',
                    onclick: async function (d) {
                        loadHealthPercentageDrillThrough();
                        callMethodAsync("DrillThroughVersion", JSON.stringify([$scope.clientHealthDrillThrough, $scope.getString("PercentageHealthy")]));
                    },
                },
                gauge: {
                    min: 0,
                    max: columns[1],
                    label: {
                        format: function (value) {
                            if (isNaN(value / columns[1])) {
                                return 0
                            } else {
                                return d3.format("0.2%")(value / columns[1]); 
                            }
                        }
                    }
                },
                color: {
                    pattern: ['#107C10', '#D83B01'],
                    threshold: {
                        unit: 'percentage',
                        values: [columns[1] * .01, columns[1]] //always render red
                    }
                },
                size: {
                    height: 180
                }
            });
        };

        $scope.toggleClientVersionChart = function () {
            var clientVersionDetailsTable = document.getElementById('ClientVersionDetailsTable');
            var clientVersionDetailsChart = document.getElementById('ClientVersionDetailsAria');
            var showChartButton = document.getElementById('showClientVersionChartButton');
            if (clientVersionDetailsTable.style.display == 'none' || clientVersionDetailsTable.style.display == '') {
                clientVersionDetailsTable.style.display = 'table';
                clientVersionDetailsChart.style.display = 'none';
                showClientVersionChartButton.innerHTML = $scope.getString('ShowChart');
            }
            else if (clientVersionDetailsTable.style.display = 'table') {
                clientVersionDetailsTable.style.display = 'none';
                clientVersionDetailsChart.style.display = 'block';
                showClientVersionChartButton.innerHTML = $scope.getString('ShowTable');
            }
        }

        $scope.toggleClientOSVersionChart = function () {
            var clientOSVersionDetailsTable = document.getElementById('ClientOSVersionDetailsTable');
            var clientOSVersionDetailsChart = document.getElementById('ClientTypesAria');
            var showChartButton = document.getElementById('showClientOSVersionChartButton');
            if (ClientOSVersionDetailsTable.style.display == 'none' || clientOSVersionDetailsTable.style.display == '') {
                clientOSVersionDetailsTable.style.display = 'table';
                clientOSVersionDetailsChart.style.display = 'none';
                showClientOSVersionChartButton.innerHTML = $scope.getString('ShowChart');
            }
            else if (ClientOSVersionDetailsTable.style.display = 'table') {
                ClientOSVersionDetailsTable.style.display = 'none';
                clientOSVersionDetailsChart.style.display = 'block';
                showClientOSVersionChartButton.innerHTML = $scope.getString('ShowTable');
            }
        }

        /// <summary>Create a donut chart</summary>
        /// <param name="idToBindTo">Id to bind the chart to</param>
        /// <param name="columns">The columns of the data in the table that we will be putting into our charts</param>
        /// <returns>Donut chart</returns>
        $scope.createDonut = async function (idToBindTo, columns) {
            // Check if there is data
            if (columns === null || columns === undefined) {
                return;
            }
            var pattern = ["#00B7C3", "#005B70", "#0078D7", "#9B0062", "#004E8C", "#5C2E91", "#8378DE", "#E3008C"];

            // If we have clients then data displays that clients are healthy in empty instance
            var emptyLabel = $scope.getString('NoData');
            if ($scope.clientHealth[1] != 0) {
                emptyLabel = $scope.getString('NoFailure');
            }

            $scope.pieChart = c3.generate({
                bindto: idToBindTo,
                data: {
                    columns: columns,
                    type: 'donut',
                    onclick: function (d) {
                        if (idToBindTo === "#ClientVersionDetails") {
                            loadClientVersionDrillThrough(d.id);
                            adminUI.sendNewRequest("DrillThroughVersion", JSON.stringify([$scope.clientVersionDrillThrough, d.id]));
                        } else if (idToBindTo === "#ClientTypes") {
                            loadOSVersionDrillThrough(d.id);
                            adminUI.sendNewRequest("DrillThroughVersion", JSON.stringify([$scope.osVersionDrillThrough, d.id]));
                        }
                    },
                    empty: {
                        label: {
                            text: emptyLabel
                        }
                    }
                },
                tooltip: {
                    contents: tooltip_contents
                },
                color: {
                    pattern: pattern
                },
                donut: {
                    width: 45
                }
            });
            $scope.pieChart.resize({
                height: 250,
                width: 250
            });
        };

        /// <summary>Create a line graph</summary>
        /// <param name="idToBindTo">Id to bind the chart to</param>
        /// <param name="columns">The data that we will be putting into our charts</param>
        /// <returns>Line graph chart</returns>
        $scope.createLineGraph = function (idToBindTo, columns) {
            if (columns === null || columns === undefined) {
                return;
            }
            /*
             columns will be an object, that looks like this
                 {
                    name: "clients total",
                    dates: [2021-08-18, 2021-08-19, 2021-08-20, 2021-08-21],
                    numbers: [.40, .50, .60, 1.00]
                 } 
             */
            let dateArray = ['x',];
            let numArray = [columns.name,];

            //draw initial slider label with initial values.
            var newSliderLabelText = $scope.formatString($scope.getString("DaysToInclude"), $scope.sliderValue);
            var sliderLabelElement = document.getElementById('slider-label');
            sliderLabelElement.innerHTML = newSliderLabelText;
            document.getElementById('days-filter-slider').max = $scope.trendInterval;
            document.getElementById('days-filter-slider').AriaValueMax = $scope.trendInterval;

            if ($scope.firstLoad) {
                var slider = document.getElementById('days-filter-slider');
                slider.value = $scope.trendInterval;
                slider.AriaValueMax = $scope.trendInterval;
                $scope.firstLoad = false;
            }

            //check if collected data is smaller than days requested
            if (columns.dates.length > $scope.sliderValue) {
                //slice off dates not included in Time interval set by slider element
                let start = (columns.dates.length - $scope.sliderValue) - 1;
                //slice result -> length for columns.numbers and columns.dates
                columns.dates = columns.dates.slice(start, columns.dates.length);
                columns.numbers = columns.numbers.slice(start, columns.numbers.length);
            }

            //date and numbers array sizes will always match, there is a 1:1 relationship in the DB with the date as PK.
            for (let i = 1; i < columns.dates.length; i++) {
                //iterating from one to reduce array size without slicing off the last date
                dateArray.push(columns.dates[i]);
                numArray.push(columns.numbers[i]);
            }

            $scope.lineGraph = c3.generate({
                bindto: idToBindTo,
                padding: {
                    right: 40,
                    bottom: 20
                },
                data: {
                    x: 'x',
                    xFormat: '%Y-%m-%d',
                    columns: [
                        dateArray,
                        numArray
                     ],
                },
                axis: {
                    x: {
                        type: 'timeseries',
                        tick: {
                            format: '%m/%d'
                        }
                    },
                    y: {
                        max: 1.0,
                        min: 0,
                        tick: {
                            format: d3.format("%"),
                            values: [0, .20, .40, .60, .80, 1.00],
                            count: 6
                        }
                    }
                },
                size: {
                    height: 350,
                    width: 1000
                }
            });
        }

        /// <summary>Updates scenario trend line graph to contain only selected length of time</summary>
        /// <returns></returns>
        $scope.handleSliderChange = function () {
            //slider handling
            var sliderVal = document.getElementById('days-filter-slider').value;
            $scope.sliderValue = sliderVal;

            var newSliderLabelText = $scope.formatString($scope.getString("DaysToInclude"), $scope.sliderValue);
            var sliderLabelElement = document.getElementById('slider-label');
            sliderLabelElement.innerHTML = newSliderLabelText;

            //get active button to find category that needs updating
            var idList = ['evalBtn', 'softwareBtn', 'hardwareBtn', 'statusBtn', 'DDRBtn', 'PolicyBtn'];
            
            let activeCategory = false;
            idList.forEach(function (id) {
                var el = document.getElementById(id);
                if (el.classList.contains("selected")) {
                    activeCategory = id;
                }
            });
            activeCategory ? $scope.updateLineGraph(activeCategory) : $scope.updateLineGraph("evalBtn");
        };

        /// <summary>Updates scenario trend line graph to contain only selected category</summary>
        /// <param name="category">the scenario category to be displayed</param>
        /// <param name="id">the id of the button being clicked</param>
        /// <returns></returns>
        $scope.updateLineGraph = function (id) {
            var idMap = {
                "evalBtn": "ClientsHealthy",
                "softwareBtn": "ClientsActiveSW",
                "hardwareBtn": "ClientsActiveHW",
                "statusBtn": "ClientsActiveStatusMessage",
                "DDRBtn": "ClientsActiveDDR",
                "PolicyBtn": "ClientsActivePolicyRequest",
            };

            //update button state to show which line chart button is active.
            var idList = ["evalBtn", "softwareBtn", "hardwareBtn", "statusBtn", "DDRBtn", "PolicyBtn"];
            idList.forEach(function (identifier) {
                var el = document.getElementById(identifier)
                el.classList.remove("selected");
            });
            var el = document.getElementById(id);
            el.classList.add("selected");

            //draw graph
            $scope.createLineGraph('#TrendsByScenario', $scope.parseTrendData(idMap[id]));

            if ($scope.brightness < 125) {
                SetColorToAllTextInChart("#TrendsByScenario", $scope.theme.ForeGroundColor);
            }

            //update Aria
            setupAria();
        };

        /* ---- Execution code ---- */
        

        async function execute(collection) {
            refreshDashboard(collection)
            if ($scope.ariaReady === 1) {
                setupAria();
            }
        }

        // Refresh dashboard on filter changes
        $scope.refresh = function refresh(collection) {
            execute(collection);
        };
    })
    .directive('dashboardChart', defineChartDirective);
}());

// SIG // Begin signature block
// SIG // MIInygYJKoZIhvcNAQcCoIInuzCCJ7cCAQExDzANBglg
// SIG // hkgBZQMEAgEFADB3BgorBgEEAYI3AgEEoGkwZzAyBgor
// SIG // BgEEAYI3AgEeMCQCAQEEEBDgyQbOONQRoqMAEEvTUJAC
// SIG // AQACAQACAQACAQACAQAwMTANBglghkgBZQMEAgEFAAQg
// SIG // nfqj/PlmVrHVhLpEAJHLnNuU9XiDS2dPMSLDHsOdWaOg
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
// SIG // SEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCGaEw
// SIG // ghmdAgEBMIGVMH4xCzAJBgNVBAYTAlVTMRMwEQYDVQQI
// SIG // EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
// SIG // HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAm
// SIG // BgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENB
// SIG // IDIwMTECEzMAAALMjrWWpr3RyU4AAAAAAswwDQYJYIZI
// SIG // AWUDBAIBBQCgga4wGQYJKoZIhvcNAQkDMQwGCisGAQQB
// SIG // gjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcC
// SIG // ARUwLwYJKoZIhvcNAQkEMSIEINTdrCZnhrMEvnF5dNaa
// SIG // cKvz50mUgXi1jbj02xyA2MUsMEIGCisGAQQBgjcCAQwx
// SIG // NDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRw
// SIG // Oi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEB
// SIG // BQAEggEAeirnOOOo2BboXRXp+CxDHVe2exiq9hggmSLg
// SIG // nWF954Nqaa8R0p+L41THB0v9JfJjwEHPgAnB5t0HKXYY
// SIG // jAgUtuEGJ/GVIr3t7of81hYqQildsX8sjxD3axUIh/Ly
// SIG // jkO8rMEMc3iqZs8BtLVZrBz/85IruTxV7wDNw/4DbuH2
// SIG // CK5+4+Ccmk5OiWBoxXkruUhApI8YvA1rkQIbvpE2nUZZ
// SIG // JG5TW6mZdNt+2vyzcqNby47XIyyELdhg2FhFtj0A5uqF
// SIG // nEiR+T03tIZh6q1Vc/bvcFfOzdgiFYAx3WW9ufZEFv2J
// SIG // eQEwcQJaIaMXQwXa7dHFyY1zS5fMLNvCykNlNnTP/qGC
// SIG // FyswghcnBgorBgEEAYI3AwMBMYIXFzCCFxMGCSqGSIb3
// SIG // DQEHAqCCFwQwghcAAgEDMQ8wDQYJYIZIAWUDBAIBBQAw
// SIG // ggFYBgsqhkiG9w0BCRABBKCCAUcEggFDMIIBPwIBAQYK
// SIG // KwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCAtbFYs
// SIG // oevTs91Fl9D8DHkILw4zMCQ2dQ5b6x323kgtlQIGY2Pf
// SIG // aYHJGBIyMDIyMTEwNDE3MjMzOS43NVowBIACAfSggdik
// SIG // gdUwgdIxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
// SIG // aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
// SIG // ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsT
// SIG // JE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGlt
// SIG // aXRlZDEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046RkM0
// SIG // MS00QkQ0LUQyMjAxJTAjBgNVBAMTHE1pY3Jvc29mdCBU
// SIG // aW1lLVN0YW1wIFNlcnZpY2WgghF7MIIHJzCCBQ+gAwIB
// SIG // AgITMwAAAbn2AA1lVE+8AwABAAABuTANBgkqhkiG9w0B
// SIG // AQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
// SIG // aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
// SIG // ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQD
// SIG // Ex1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAe
// SIG // Fw0yMjA5MjAyMDIyMTdaFw0yMzEyMTQyMDIyMTdaMIHS
// SIG // MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
// SIG // bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
// SIG // cm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNy
// SIG // b3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQx
// SIG // JjAkBgNVBAsTHVRoYWxlcyBUU1MgRVNOOkZDNDEtNEJE
// SIG // NC1EMjIwMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1T
// SIG // dGFtcCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOC
// SIG // Ag8AMIICCgKCAgEA40k+yWH1FsfJAQJtQgg3EwXm5CTI
// SIG // 3TtUhKEhNe5sulacA2AEIu8JwmXuj/Ycc5GexFyZIg0n
// SIG // +pyUCYsis6OdietuhwCeLGIwRcL5rWxnzirFha0RVjtV
// SIG // jDQsJzNj7zpT/yyGDGqxp7MqlauI85ylXVKHxKw7F/fT
// SIG // I7uO+V38gEDdPqUczalP8dGNaT+v27LHRDhq3HSaQtVh
// SIG // L3Lnn+hOUosTTSHv3ZL6Zpp0B3LdWBPB6LCgQ5cPvznC
// SIG // /eH5/Af/BNC0L2WEDGEw7in44/3zzxbGRuXoGpFZe53n
// SIG // hFPOqnZWv7J6fVDUDq6bIwHterSychgbkHUBxzhSAmU9
// SIG // D9mIySqDFA0UJZC/PQb2guBI8PwrLQCRfbY9wM5ug+41
// SIG // PhFx5Y9fRRVlSxf0hSCztAXjUeJBLAR444cbKt9B2ZKy
// SIG // UBOtuYf/XwzlCuxMzkkg2Ny30bjbGo3xUX1nxY6IYyM1
// SIG // u+WlwSabKxiXlDKGsQOgWdBNTtsWsPclfR8h+7WxstZ4
// SIG // GpfBunhnzIAJO2mErZVvM6+Li9zREKZE3O9hBDY+Nns1
// SIG // pNcTga7e+CAAn6u3NRMB8mi285KpwyA3AtlrVj4RP+Vv
// SIG // RXKOtjAW4e2DRBbJCM/nfnQtOm/TzqnJVSHgDfD86zmF
// SIG // MYVmAV7lsLIyeljT0zTI90dpD/nqhhSxIhzIrJUCAwEA
// SIG // AaOCAUkwggFFMB0GA1UdDgQWBBS3sDhx21hDmgmMTVmq
// SIG // tKienjVEUjAfBgNVHSMEGDAWgBSfpxVdAF5iXYP05dJl
// SIG // pxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8v
// SIG // d3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNy
// SIG // b3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAxMCgx
// SIG // KS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAC
// SIG // hlBodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3Bz
// SIG // L2NlcnRzL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQ
// SIG // Q0ElMjAyMDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBYG
// SIG // A1UdJQEB/wQMMAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQE
// SIG // AwIHgDANBgkqhkiG9w0BAQsFAAOCAgEAzdxns0VQdEyw
// SIG // srOOXusk8iS/ugn6z2SS63SFmJ/1ZK3rRLNgZQunXOZ0
// SIG // +pz7Dx4dOSGpfQYoKnZNOpLMFcGHAc6bz6nqFTE2UN7A
// SIG // YxlSiz3nZpNduUBPc4oGd9UEtDJRq+tKO4kZkBbfRw1j
// SIG // euNUNSUYP5XKBAfJJoNq+IlBsrr/p9C9RQWioiTeV0Z+
// SIG // OcC2d5uxWWqHpZZqZVzkBl2lZHWNLM3+jEpipzUEbhLH
// SIG // GU+1x+sB0HP9xThvFVeoAB/TY1mxy8k2lGc4At/mRWjY
// SIG // e6klcKyT1PM/k81baxNLdObCEhCY/GvQTRSo6iNSsElQ
// SIG // 6FshMDFydJr8gyW4vUddG0tBkj7GzZ5G2485SwpRbvX/
// SIG // Vh6qxgIscu+7zZx4NVBC8/sYcQSSnaQSOKh9uNgSsGja
// SIG // IIRrHF5fhn0e8CADgyxCRufp7gQVB/Xew/4qfdeAwi8l
// SIG // uosl4VxCNr5JR45e7lx+TF7QbNM2iN3IjDNoeWE5+VVF
// SIG // k2vF57cH7JnB3ckcMi+/vW5Ij9IjPO31xTYbIdBWrEFK
// SIG // tG0pbpbxXDvOlW+hWwi/eWPGD7s2IZKVdfWzvNsE0MxS
// SIG // P06fM6Ucr/eas5TxgS5F/pHBqRblQJ4ZqbLkyIq7Zi7I
// SIG // qIYEK/g4aE+y017sAuQQ6HwFfXa3ie25i76DD0vrII9j
// SIG // SNZhpC3MA/0wggdxMIIFWaADAgECAhMzAAAAFcXna54C
// SIG // m0mZAAAAAAAVMA0GCSqGSIb3DQEBCwUAMIGIMQswCQYD
// SIG // VQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
// SIG // A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
// SIG // IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQg
// SIG // Um9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgMjAxMDAe
// SIG // Fw0yMTA5MzAxODIyMjVaFw0zMDA5MzAxODMyMjVaMHwx
// SIG // CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
// SIG // MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
// SIG // b3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jv
// SIG // c29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMIICIjANBgkq
// SIG // hkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA5OGmTOe0ciEL
// SIG // eaLL1yR5vQ7VgtP97pwHB9KpbE51yMo1V/YBf2xK4OK9
// SIG // uT4XYDP/XE/HZveVU3Fa4n5KWv64NmeFRiMMtY0Tz3cy
// SIG // wBAY6GB9alKDRLemjkZrBxTzxXb1hlDcwUTIcVxRMTeg
// SIG // Cjhuje3XD9gmU3w5YQJ6xKr9cmmvHaus9ja+NSZk2pg7
// SIG // uhp7M62AW36MEBydUv626GIl3GoPz130/o5Tz9bshVZN
// SIG // 7928jaTjkY+yOSxRnOlwaQ3KNi1wjjHINSi947SHJMPg
// SIG // yY9+tVSP3PoFVZhtaDuaRr3tpK56KTesy+uDRedGbsoy
// SIG // 1cCGMFxPLOJiss254o2I5JasAUq7vnGpF1tnYN74kpEe
// SIG // HT39IM9zfUGaRnXNxF803RKJ1v2lIH1+/NmeRd+2ci/b
// SIG // fV+AutuqfjbsNkz2K26oElHovwUDo9Fzpk03dJQcNIIP
// SIG // 8BDyt0cY7afomXw/TNuvXsLz1dhzPUNOwTM5TI4CvEJo
// SIG // LhDqhFFG4tG9ahhaYQFzymeiXtcodgLiMxhy16cg8ML6
// SIG // EgrXY28MyTZki1ugpoMhXV8wdJGUlNi5UPkLiWHzNgY1
// SIG // GIRH29wb0f2y1BzFa/ZcUlFdEtsluq9QBXpsxREdcu+N
// SIG // +VLEhReTwDwV2xo3xwgVGD94q0W29R6HXtqPnhZyacau
// SIG // e7e3PmriLq0CAwEAAaOCAd0wggHZMBIGCSsGAQQBgjcV
// SIG // AQQFAgMBAAEwIwYJKwYBBAGCNxUCBBYEFCqnUv5kxJq+
// SIG // gpE8RjUpzxD/LwTuMB0GA1UdDgQWBBSfpxVdAF5iXYP0
// SIG // 5dJlpxtTNRnpcjBcBgNVHSAEVTBTMFEGDCsGAQQBgjdM
// SIG // g30BATBBMD8GCCsGAQUFBwIBFjNodHRwOi8vd3d3Lm1p
// SIG // Y3Jvc29mdC5jb20vcGtpb3BzL0RvY3MvUmVwb3NpdG9y
// SIG // eS5odG0wEwYDVR0lBAwwCgYIKwYBBQUHAwgwGQYJKwYB
// SIG // BAGCNxQCBAweCgBTAHUAYgBDAEEwCwYDVR0PBAQDAgGG
// SIG // MA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAU1fZW
// SIG // y4/oolxiaNE9lJBb186aGMQwVgYDVR0fBE8wTTBLoEmg
// SIG // R4ZFaHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9j
// SIG // cmwvcHJvZHVjdHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYt
// SIG // MjMuY3JsMFoGCCsGAQUFBwEBBE4wTDBKBggrBgEFBQcw
// SIG // AoY+aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraS9j
// SIG // ZXJ0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcnQw
// SIG // DQYJKoZIhvcNAQELBQADggIBAJ1VffwqreEsH2cBMSRb
// SIG // 4Z5yS/ypb+pcFLY+TkdkeLEGk5c9MTO1OdfCcTY/2mRs
// SIG // fNB1OW27DzHkwo/7bNGhlBgi7ulmZzpTTd2YurYeeNg2
// SIG // LpypglYAA7AFvonoaeC6Ce5732pvvinLbtg/SHUB2Rje
// SIG // bYIM9W0jVOR4U3UkV7ndn/OOPcbzaN9l9qRWqveVtihV
// SIG // J9AkvUCgvxm2EhIRXT0n4ECWOKz3+SmJw7wXsFSFQrP8
// SIG // DJ6LGYnn8AtqgcKBGUIZUnWKNsIdw2FzLixre24/LAl4
// SIG // FOmRsqlb30mjdAy87JGA0j3mSj5mO0+7hvoyGtmW9I/2
// SIG // kQH2zsZ0/fZMcm8Qq3UwxTSwethQ/gpY3UA8x1RtnWN0
// SIG // SCyxTkctwRQEcb9k+SS+c23Kjgm9swFXSVRk2XPXfx5b
// SIG // RAGOWhmRaw2fpCjcZxkoJLo4S5pu+yFUa2pFEUep8beu
// SIG // yOiJXk+d0tBMdrVXVAmxaQFEfnyhYWxz/gq77EFmPWn9
// SIG // y8FBSX5+k77L+DvktxW/tM4+pTFRhLy/AsGConsXHRWJ
// SIG // jXD+57XQKBqJC4822rpM+Zv/Cuk0+CQ1ZyvgDbjmjJnW
// SIG // 4SLq8CdCPSWU5nR0W2rRnj7tfqAxM328y+l7vzhwRNGQ
// SIG // 8cirOoo6CGJ/2XBjU02N7oJtpQUQwXEGahC0HVUzWLOh
// SIG // cGbyoYIC1zCCAkACAQEwggEAoYHYpIHVMIHSMQswCQYD
// SIG // VQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
// SIG // A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
// SIG // IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQg
// SIG // SXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJjAkBgNV
// SIG // BAsTHVRoYWxlcyBUU1MgRVNOOkZDNDEtNEJENC1EMjIw
// SIG // MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBT
// SIG // ZXJ2aWNloiMKAQEwBwYFKw4DAhoDFQDHYh4YeGTnwxCT
// SIG // PNJaScZwuN+BOqCBgzCBgKR+MHwxCzAJBgNVBAYTAlVT
// SIG // MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
// SIG // ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9y
// SIG // YXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0
// SIG // YW1wIFBDQSAyMDEwMA0GCSqGSIb3DQEBBQUAAgUA5w+v
// SIG // WTAiGA8yMDIyMTEwNDIzMzM0NVoYDzIwMjIxMTA1MjMz
// SIG // MzQ1WjB3MD0GCisGAQQBhFkKBAExLzAtMAoCBQDnD69Z
// SIG // AgEAMAoCAQACAiJDAgH/MAcCAQACAhGEMAoCBQDnEQDZ
// SIG // AgEAMDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkK
// SIG // AwKgCjAIAgEAAgMHoSChCjAIAgEAAgMBhqAwDQYJKoZI
// SIG // hvcNAQEFBQADgYEAtSFbSsAlRq/R9KfatXPCzW02b/6K
// SIG // V/9dc1D4gz9mBh/nuP6oBi6kCzNkA+fpgYxccsjhgmwc
// SIG // iVCHPQ+AQ6OKHa64tL6lvrL87hTuJNxb52qbyq6UqE/H
// SIG // ZJWx4I6inSLTbdByslbVQ57qCTI9oDY8m0JbTiEL3yrT
// SIG // IPyhMrpQXC0xggQNMIIECQIBATCBkzB8MQswCQYDVQQG
// SIG // EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
// SIG // BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
// SIG // cnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGlt
// SIG // ZS1TdGFtcCBQQ0EgMjAxMAITMwAAAbn2AA1lVE+8AwAB
// SIG // AAABuTANBglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcN
// SIG // AQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEi
// SIG // BCB03OY/5iLVR3quOoZ3Xfiuc8kIrcLdho5Ey0IbxdBI
// SIG // 2zCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EIGTr
// SIG // Rs7xbzm5MB8lUQ7e9fZotpAVyBwal3Cw6iL5+g/0MIGY
// SIG // MIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
// SIG // c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
// SIG // BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UE
// SIG // AxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAC
// SIG // EzMAAAG59gANZVRPvAMAAQAAAbkwIgQgSkHfGvt7LGlM
// SIG // Mwx/yEaIsvMN4gSHGaPUIiu4f1R8nywwDQYJKoZIhvcN
// SIG // AQELBQAEggIAgXSIjLstecy2MqROeRIZjUvPTIPHrXsY
// SIG // rVyU4amvjsP2YtFK2UkTQOb6LRgGjNbjPMHaCsG+6mmb
// SIG // K5g2EudUxokU8viFWXzhAwYn0bS+0LYxFZ/xj/RzZkgC
// SIG // 4lkjOUjd1AboWbg+AV9yVmspJrxMwXgsbxonStTOx9yR
// SIG // EmtF+wnDyj13ovwubudIdqJ081LQf/ZPoCUjatDftjmL
// SIG // 5T+E62judxsEX7YaKqD4BhZpaBcPyt7CnktSU2QeOODB
// SIG // iXusdNKwcY5lhrJXAJc2aFnt16U4OrHWqb2ju9KEN/1g
// SIG // 9163kVKZ84EKtNovxrOwN9LvnNXX5NbF2qWWSsYaHYhf
// SIG // BFQpHRi7O32dnIaiXN9J1D2kJ4CgiHzqRUGaNFMNo8V9
// SIG // aERg9l+8JQYffNFmLbu76tq12N+8g5lRp5fCTdQrJqd2
// SIG // hrM4NW3qU4qjBcPFZNTkbWUWmdXLlqUHg3r7fDe4+JFa
// SIG // 9VYwYdgN/ccYkrwJzMFHVOdSE/+4JaAZvlx8dc5EBP5R
// SIG // w2TNA91SoC+JQqcZ9RQrUNfoEFp0ugYZhzBBotfydbup
// SIG // BePYQYm3CpdJcnLB2oVSvbLPFojtiISrfRAyHKihahM4
// SIG // E5oC7RVi0fJ1ZPViShMADTTi2IfOzJmqbrMnZ+Lb5+8n
// SIG // 1pxkYmWelec78TNG1XrVddUgIi7U5PWXMEg=
// SIG // End signature block
