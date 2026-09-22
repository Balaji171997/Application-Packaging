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

            // language info
            $scope.language;

            await LoadDataAsync();
            $scope.$apply();
        });

        async function LoadDataAsync() {
            $scope.language = await callMethodAsync("GetCultureInfo", null);
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
            var clientCollectionSummaryText = $scope.getString('ClientHealthCollection') + ", " + $scope.collectionValue.name +
                ", " + $scope.getString('Browse');
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
            clientVersionTable.innerHTML = "<div class=\"row\" role=\"row\">" +
                "<div class=\"cell\" role=\"cell\" tabindex=\"10\">" + $scope.getString("clientVersion") + "</div>" +
                "<div class=\"cell\" role=\"cell\" tabindex=\"11\">" + $scope.getString("Count") + "</div>" +
                "</div>"
            for (var value in $scope.clientVersion) {
                clientVersionDetailsSummaryText += $scope.getString("clientVersion") + ", " + $scope.clientVersion[value][0] + ", " + $scope.getString("Count") + ", " + $scope.clientVersion[value][1] + ", ";
                clientVersionTable.innerHTML += "<div class=\"row\" role=\"row\">" +
                    "<div class=\"cell\" role=\"cell\" tabindex=\"" + tabidx + "\">" + $scope.clientVersion[value][0] + "</div>" +
                    "<div class=\"cell\" role=\"cell\" tabindex=\"" + tabidx + "\">" + $scope.clientVersion[value][1] + "</div>" +
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
            clientTypesTable.innerHTML = "<div class=\"row\" role=\"row\">" +
                "<div class=\"cell\" role=\"cell\" tabindex=\"15\">" + $scope.getString("OSVersion") + "</div>" +
                "<div class=\"cell\" role=\"cell\" tabindex=\"16\">" + $scope.getString("Count") + "</div>" +
                "</div>"
            for (var value in $scope.osVersion) {
                clientTypesSummaryText += $scope.getString("OSVersion") + ", " + $scope.osVersion[value][0] + ", " + $scope.getString("Count") + ", " + $scope.osVersion[value][1] + ", ";
                clientTypesTable.innerHTML += "<div class=\"row\" role=\"row\">" +
                    "<div class=\"cell\" role=\"cell\" tabindex=\"" + tabidx + "\">" + $scope.osVersion[value][0] + "</div>" +
                    "<div class=\"cell\" role=\"cell\" tabindex=\"" + tabidx + "\">" + $scope.osVersion[value][1] + "</div>" +
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
                        || $scope.collections[collection][0] === 'SMS000US'
                        || $scope.collections[collection][0] === 'SMS000PS'
                        || $scope.collections[collection][0] === 'SMS000KM') {
                        name = $scope.getString($scope.collections[collection][1].split(' ').join('_').split('-').join('_'));
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
                let localDate = new Date(year, month, day).toLocaleDateString($scope.language);
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
                            format: d3.format("0.0%"),
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
// SIG // MIIonAYJKoZIhvcNAQcCoIIojTCCKIkCAQExDzANBglg
// SIG // hkgBZQMEAgEFADB3BgorBgEEAYI3AgEEoGkwZzAyBgor
// SIG // BgEEAYI3AgEeMCQCAQEEEBDgyQbOONQRoqMAEEvTUJAC
// SIG // AQACAQACAQACAQACAQAwMTANBglghkgBZQMEAgEFAAQg
// SIG // yNQAL4e/rMBGdsikFStEvssQIfEMJLlpyrE1/m55+Nmg
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
// SIG // ghpvMIIaawIBATCBlTB+MQswCQYDVQQGEwJVUzETMBEG
// SIG // A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
// SIG // ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
// SIG // MSgwJgYDVQQDEx9NaWNyb3NvZnQgQ29kZSBTaWduaW5n
// SIG // IFBDQSAyMDExAhMzAAAEhJjiEuB4ozFdAAAAAASEMA0G
// SIG // CWCGSAFlAwQCAQUAoIH3MBkGCSqGSIb3DQEJAzEMBgor
// SIG // BgEEAYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEE
// SIG // AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCBkr96I/M0J9F2a
// SIG // 8Wpw6hkOCY+ygRoob3E24x7iHrcb/TCBigYKKwYBBAGC
// SIG // NwIBDDF8MHqgXIBaAE0AaQBjAHIAbwBzAG8AZgB0AC4A
// SIG // VABvAG8AbABrAGkAdAAuAFcAcABmAC4AVQBJAC4AQwBv
// SIG // AG4AdAByAG8AbABzAC4AVwBlAGIAVgBpAGUAdwAuAGQA
// SIG // bABsoRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
// SIG // BgkqhkiG9w0BAQEFAASCAQCF4+TjfVbon+v8DbeYI4Qc
// SIG // 9sBmjeBQPuCntA5zy/3/3Ne9lxY+gIr/jYxaksbM3p2H
// SIG // xiPELYeKQaWxGD2foziTdIJ04LHPxZ8VfPIbHDQY8MHY
// SIG // 5uwGzLUkHr4WqskVkgAMWME+zkQ/xDzN189AAsgMbuOr
// SIG // tFFbGAg6dusBNyfaXCABHpmVgU30RU3kvtUgIRX9zmwU
// SIG // IgmXDhBViLdUOKWcN0tdqPpkwMGivfJeTazpDMLk6McG
// SIG // K4UfKaARQA76A8UdJ+SUZFlmI+9sJPAXBD1JVczwNQKK
// SIG // MBuZOtgze5AZaEkT4xl+hrUJ/SethJSKAXRLPTkQDZ7T
// SIG // A5p40Y+R+kJkoYIXsDCCF6wGCisGAQQBgjcDAwExghec
// SIG // MIIXmAYJKoZIhvcNAQcCoIIXiTCCF4UCAQMxDzANBglg
// SIG // hkgBZQMEAgEFADCCAVoGCyqGSIb3DQEJEAEEoIIBSQSC
// SIG // AUUwggFBAgEBBgorBgEEAYRZCgMBMDEwDQYJYIZIAWUD
// SIG // BAIBBQAEIKJ/q6/BLYpNBBZz49OdHSxBiou2erAvk7rr
// SIG // OhB1vhjNAgZo8e4BPdMYEzIwMjUxMDIzMDI0NzI5LjM3
// SIG // NVowBIACAfSggdmkgdYwgdMxCzAJBgNVBAYTAlVTMRMw
// SIG // EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
// SIG // b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
// SIG // b24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9w
// SIG // ZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNoaWVs
// SIG // ZCBUU1MgRVNOOjQwMUEtMDVFMC1EOTQ3MSUwIwYDVQQD
// SIG // ExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloIIR
// SIG // /jCCBygwggUQoAMCAQICEzMAAAIZXrLYVHX0sY0AAQAA
// SIG // AhkwDQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMx
// SIG // EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
// SIG // ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
// SIG // dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3Rh
// SIG // bXAgUENBIDIwMTAwHhcNMjUwODE0MTg0ODI2WhcNMjYx
// SIG // MTEzMTg0ODI2WjCB0zELMAkGA1UEBhMCVVMxEzARBgNV
// SIG // BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
// SIG // HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEt
// SIG // MCsGA1UECxMkTWljcm9zb2Z0IElyZWxhbmQgT3BlcmF0
// SIG // aW9ucyBMaW1pdGVkMScwJQYDVQQLEx5uU2hpZWxkIFRT
// SIG // UyBFU046NDAxQS0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1p
// SIG // Y3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0G
// SIG // CSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCmoUjJSTMj
// SIG // LGkvdDTdaYu7Lgb1ghRJzOeEqv5wc5P7+7s9qvEj3qDH
// SIG // FvVata4DEHyqMYt+xsibHxXei4rWdRx/5H+eyddqzn+J
// SIG // OBX9OXdBNEZPQN65cE1ukepz7ALU2JPIDvqAueKu9IES
// SIG // gHOWuk1AUSe7B1s8sIulNLcpZIK7knTZv5EVZH+RwXNX
// SIG // GeGgTeAhp5RG2sYoYFkYosFe+qCCQMQ20qS+29FPfbEu
// SIG // 8C8v9GlF67nPXxmiMKzvZlKhrvgPLxhtpawObc5k6klF
// SIG // nFmw8oIdnrE2qAUp/TE0ePS32/RDdb7bPmABVpqwkkK9
// SIG // HnZKXRcnYA5/eXQtJ61eBQDmAPkhDVG8SyVOY2dKi5Os
// SIG // YgPcPWeNjuYG7Sm6Ih08raMr/VZ55/b5hHhxClZCR4Fm
// SIG // ZeJ2H0C5Z2XDEpAvXksnorZ3DzL+388GGYvK3pAB/QJ6
// SIG // lZF2BmczK1UBS5YfCVlFX0ktjtpfwPnl4v35w4ulfdsY
// SIG // 06Y3bhSkhbyq1lqpdp6wW8g5bbck0uFppBW85uvV67sY
// SIG // T/kyfjd778Nu11iX9ss/YhDXFgQl1JtxSQMV9bcqVkSH
// SIG // 6cEoO1pGc1GRuAiDEhsp1Pfw4pDBn9oDi5KyICDqcQ+J
// SIG // YEca7K0ijnBTvkzlV2OESqpMd9di7wEmLoZPO9ZP716R
// SIG // 8xd7OoKSSzFobwIDAQABo4IBSTCCAUUwHQYDVR0OBBYE
// SIG // FIBo6jkdZq03OpmfUgXV9wPqevchMB8GA1UdIwQYMBaA
// SIG // FJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYw
// SIG // VKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9w
// SIG // a2lvcHMvY3JsL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAl
// SIG // MjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRg
// SIG // MF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9z
// SIG // b2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIw
// SIG // VGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwG
// SIG // A1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUH
// SIG // AwgwDgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUA
// SIG // A4ICAQBfHNVkstcEV+gIIJOJjswdd1vtyK8lJN+sdgkL
// SIG // k6TY03vk2nNMxP1XZNwhCN9DcAVRuHU0EBi0xS7DELoP
// SIG // hx4RcbmVcCdu+QL1iN4tUNHIiZdhiZ+3vP5CmX23cL/x
// SIG // rS2Kqc7PxR7z8Ngu0xOC9Yyeyos2MgsNoiY5+ccjfpMs
// SIG // KMYV7xFgtcZ0JR04uV8B0wZ4/FJMDdMAA5z4ZBuY9aOu
// SIG // C4tZvG+eXc1WNG+sFlWTEUyhVkfR/uobAM5KGOme/mdi
// SIG // dDjy58vS4HPnZFs8Z1fgW/35QY6sGmuZwfOYi60W0l5z
// SIG // ZjiS6M21MrbAEaBaxwQ5WEWJpV2N7xUsnsxU0oTlOay4
// SIG // YzeNMuvWe5HkAUazdQqQ/uDdxAPhwcrtd0uJObt7rTpA
// SIG // n5ap5CwANgT129T3AhRsj0OXhRwgSsXD4UdpZJOuR8nh
// SIG // K8uaEqeXmSGGknWwXfPp7UHF6lSWJcerNEuIdaKFYhYR
// SIG // IXwgcSUXc87Fs/hUmocGJi9pcxXRLJGDCgPrNd11tSdf
// SIG // 1ZHokvYGWoCOMfEg3B6Wyn9WHEBZOHO4wDnwvG8T9UDO
// SIG // N8UXhabtrVkAuYlXDegv+z+7GjU6ni1xP6F9n243WG0L
// SIG // Uk3gO5GoV8u22O6gCZRChs7nNQVHO8KfwKT+GI75vNHX
// SIG // myqSOXEszIyOmRz95/hJRSKQPjry9TCCB3EwggVZoAMC
// SIG // AQICEzMAAAAVxedrngKbSZkAAAAAABUwDQYJKoZIhvcN
// SIG // AQELBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
// SIG // YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
// SIG // VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAwBgNV
// SIG // BAMTKU1pY3Jvc29mdCBSb290IENlcnRpZmljYXRlIEF1
// SIG // dGhvcml0eSAyMDEwMB4XDTIxMDkzMDE4MjIyNVoXDTMw
// SIG // MDkzMDE4MzIyNVowfDELMAkGA1UEBhMCVVMxEzARBgNV
// SIG // BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
// SIG // HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEm
// SIG // MCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENB
// SIG // IDIwMTAwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIK
// SIG // AoICAQDk4aZM57RyIQt5osvXJHm9DtWC0/3unAcH0qls
// SIG // TnXIyjVX9gF/bErg4r25PhdgM/9cT8dm95VTcVrifkpa
// SIG // /rg2Z4VGIwy1jRPPdzLAEBjoYH1qUoNEt6aORmsHFPPF
// SIG // dvWGUNzBRMhxXFExN6AKOG6N7dcP2CZTfDlhAnrEqv1y
// SIG // aa8dq6z2Nr41JmTamDu6GnszrYBbfowQHJ1S/rboYiXc
// SIG // ag/PXfT+jlPP1uyFVk3v3byNpOORj7I5LFGc6XBpDco2
// SIG // LXCOMcg1KL3jtIckw+DJj361VI/c+gVVmG1oO5pGve2k
// SIG // rnopN6zL64NF50ZuyjLVwIYwXE8s4mKyzbnijYjklqwB
// SIG // Sru+cakXW2dg3viSkR4dPf0gz3N9QZpGdc3EXzTdEonW
// SIG // /aUgfX782Z5F37ZyL9t9X4C626p+Nuw2TPYrbqgSUei/
// SIG // BQOj0XOmTTd0lBw0gg/wEPK3Rxjtp+iZfD9M269ewvPV
// SIG // 2HM9Q07BMzlMjgK8QmguEOqEUUbi0b1qGFphAXPKZ6Je
// SIG // 1yh2AuIzGHLXpyDwwvoSCtdjbwzJNmSLW6CmgyFdXzB0
// SIG // kZSU2LlQ+QuJYfM2BjUYhEfb3BvR/bLUHMVr9lxSUV0S
// SIG // 2yW6r1AFemzFER1y7435UsSFF5PAPBXbGjfHCBUYP3ir
// SIG // Rbb1Hode2o+eFnJpxq57t7c+auIurQIDAQABo4IB3TCC
// SIG // AdkwEgYJKwYBBAGCNxUBBAUCAwEAATAjBgkrBgEEAYI3
// SIG // FQIEFgQUKqdS/mTEmr6CkTxGNSnPEP8vBO4wHQYDVR0O
// SIG // BBYEFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMFwGA1UdIARV
// SIG // MFMwUQYMKwYBBAGCN0yDfQEBMEEwPwYIKwYBBQUHAgEW
// SIG // M2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMv
// SIG // RG9jcy9SZXBvc2l0b3J5Lmh0bTATBgNVHSUEDDAKBggr
// SIG // BgEFBQcDCDAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMA
// SIG // QTALBgNVHQ8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAf
// SIG // BgNVHSMEGDAWgBTV9lbLj+iiXGJo0T2UkFvXzpoYxDBW
// SIG // BgNVHR8ETzBNMEugSaBHhkVodHRwOi8vY3JsLm1pY3Jv
// SIG // c29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNSb29D
// SIG // ZXJBdXRfMjAxMC0wNi0yMy5jcmwwWgYIKwYBBQUHAQEE
// SIG // TjBMMEoGCCsGAQUFBzAChj5odHRwOi8vd3d3Lm1pY3Jv
// SIG // c29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dF8y
// SIG // MDEwLTA2LTIzLmNydDANBgkqhkiG9w0BAQsFAAOCAgEA
// SIG // nVV9/Cqt4SwfZwExJFvhnnJL/Klv6lwUtj5OR2R4sQaT
// SIG // lz0xM7U518JxNj/aZGx80HU5bbsPMeTCj/ts0aGUGCLu
// SIG // 6WZnOlNN3Zi6th542DYunKmCVgADsAW+iehp4LoJ7nvf
// SIG // am++Kctu2D9IdQHZGN5tggz1bSNU5HhTdSRXud2f8449
// SIG // xvNo32X2pFaq95W2KFUn0CS9QKC/GbYSEhFdPSfgQJY4
// SIG // rPf5KYnDvBewVIVCs/wMnosZiefwC2qBwoEZQhlSdYo2
// SIG // wh3DYXMuLGt7bj8sCXgU6ZGyqVvfSaN0DLzskYDSPeZK
// SIG // PmY7T7uG+jIa2Zb0j/aRAfbOxnT99kxybxCrdTDFNLB6
// SIG // 2FD+CljdQDzHVG2dY3RILLFORy3BFARxv2T5JL5zbcqO
// SIG // Cb2zAVdJVGTZc9d/HltEAY5aGZFrDZ+kKNxnGSgkujhL
// SIG // mm77IVRrakURR6nxt67I6IleT53S0Ex2tVdUCbFpAUR+
// SIG // fKFhbHP+CrvsQWY9af3LwUFJfn6Tvsv4O+S3Fb+0zj6l
// SIG // MVGEvL8CwYKiexcdFYmNcP7ntdAoGokLjzbaukz5m/8K
// SIG // 6TT4JDVnK+ANuOaMmdbhIurwJ0I9JZTmdHRbatGePu1+
// SIG // oDEzfbzL6Xu/OHBE0ZDxyKs6ijoIYn/ZcGNTTY3ugm2l
// SIG // BRDBcQZqELQdVTNYs6FwZvKhggNZMIICQQIBATCCAQGh
// SIG // gdmkgdYwgdMxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
// SIG // YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
// SIG // VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNV
// SIG // BAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMg
// SIG // TGltaXRlZDEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNO
// SIG // OjQwMUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3Nv
// SIG // ZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4D
// SIG // AhoDFQAxdin9aqp3JvR6eKCst/GXQicDPqCBgzCBgKR+
// SIG // MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5n
// SIG // dG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
// SIG // aWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1p
// SIG // Y3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqG
// SIG // SIb3DQEBCwUAAgUA7KOsKzAiGA8yMDI1MTAyMjE5MTY1
// SIG // OVoYDzIwMjUxMDIzMTkxNjU5WjB3MD0GCisGAQQBhFkK
// SIG // BAExLzAtMAoCBQDso6wrAgEAMAoCAQACAgcYAgH/MAcC
// SIG // AQACAhJQMAoCBQDspP2rAgEAMDYGCisGAQQBhFkKBAIx
// SIG // KDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAI
// SIG // AgEAAgMBhqAwDQYJKoZIhvcNAQELBQADggEBAERj8WHZ
// SIG // 1/TlYM4Ptc08Z668cw80qY+Zx+pBex8mTuvvmBi5M/GM
// SIG // rz/G3p2J7KBj/hG92ddCu4JLLcjexvDYfLJvWkLVexa4
// SIG // nKeuz5SKKMwuo1Yxwu6ovJ0gmW8pfnSU7z1JVApuzIWP
// SIG // 0lxygfN3Pndckh4VSVQr2BA6QHYgBL/3rFiPXcj1kGNe
// SIG // crpec5Zo/uli3KSqeW4IcwavzHGbwRsMlRL0l/iHRuMw
// SIG // VWXnkoA6xgnCF4uSfjnsQtfuhpd3gndc/4I5BS6e+i7i
// SIG // aimhkJ0J6wyB49zMWRPMIXwVazXyxjNFUqB2Afbx1QRy
// SIG // 2lnMIaOw1HYWO3n7UvZfafG3Rc0xggQNMIIECQIBATCB
// SIG // kzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
// SIG // Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
// SIG // TWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1N
// SIG // aWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAA
// SIG // AhlesthUdfSxjQABAAACGTANBglghkgBZQMEAgEFAKCC
// SIG // AUowGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8G
// SIG // CSqGSIb3DQEJBDEiBCCATN7fwu8ZdXa8QOMFo72boPkc
// SIG // g7ZaeIyW7z5v60XiDTCB+gYLKoZIhvcNAQkQAi8xgeow
// SIG // gecwgeQwgb0EINyRfrfcTXLUQXfZXXzNByuyCPMj37ct
// SIG // 7uaW+TY55u2GMIGYMIGApH4wfDELMAkGA1UEBhMCVVMx
// SIG // EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
// SIG // ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
// SIG // dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3Rh
// SIG // bXAgUENBIDIwMTACEzMAAAIZXrLYVHX0sY0AAQAAAhkw
// SIG // IgQgOyStiHS4g1F0q4lrwCt903H7NO0Iw7r1tIrJxX/l
// SIG // XJowDQYJKoZIhvcNAQELBQAEggIADpAb4prrS/12vOxH
// SIG // 6RkwMt4z7ua2dopsnhOA/tZrDayXEqIugEQsrd8C7UuQ
// SIG // SNHNx2dFUGKNF337XiMSCllxqMVHaxL220Uiw55mvNXA
// SIG // gi2O2YPBVL+um/6CLLAr0UIORlyCLUzSuRu5yFf/2B7B
// SIG // gYePqr+tSpR8B7XwMMgmbk6xHbeeIk8YjT9FZ1uAKW6b
// SIG // iW2pJzI3H/buIQ78uSnGBwm/xKWP4losNX32+VRenxR6
// SIG // 4M/pei1AevS3F/k4GrcK3uXX2bPU8HH/PvSCth0DOad9
// SIG // X76NSrzZJLAeaBxwjMPkR+cZYS6gF4D/w0knEg44zKw4
// SIG // uGJaunlbj+UekZum4TVDdoC1eKq17HRkoO4EbVvSEW08
// SIG // 1Zaq6KFoc7nuM4sqMKXRq1rkA0/OICJCv6DFpwOG1pvm
// SIG // mH9SY8kSbKadJXQC6zq4FSbfHGqD6IMZviEl5fc8NZvf
// SIG // +t0wR/LmZOKNoQOpqZ0D0t98Wr5eA2ojuzpmwK1kV31n
// SIG // sbxkssUZwv19c6nic2HdfFIGDWiPWbh0M1gpocAH4bhx
// SIG // t1GNqzzHYzYqwdtAgY4neb7gNeX6u/0fGWflg8aIwLHQ
// SIG // KetwZEihKh5Z5yQxtwwTk4zSI8zYohY/3ixp78tg5X51
// SIG // 6HdR6fKodHkNJ3lFSghBYOyAQVd3N9ZW4L2d6LXvYxVN
// SIG // 9Gcu/hY=
// SIG // End signature block
