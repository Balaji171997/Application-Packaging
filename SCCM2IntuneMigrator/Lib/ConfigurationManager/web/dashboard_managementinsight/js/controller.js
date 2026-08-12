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

    dashboard.controller("dashboardController", function ($scope) 
    {
        adminUI.initializeController($scope, async function () {

            /// <summary>Gets a string calling getString in utility to display on the dashboard</summary>
            /// <param name="stringName">The name of the string in our resource file</param>
            /// <returns>The string that will be displayed on the dashboard</returns>
            $scope.getString = function (stringName) {
                return $scope.strings[stringName];
            };

            $scope.search = ""; // set the default search/filter term

            // Filter variables
            $scope.managementInsightsRules;
            $scope.managementInsightsRulesFirst;
            $scope.managementInsightsGroups;
            $scope.managementInsightsGroupsFirst;

            // Cleaned rules
            $scope.miRules;
            $scope.miGroups;
            $scope.miPriority;
            $scope.miPercentage;
            $scope.miTime;

            // Filters
            $scope.critical = true;
            $scope.recommended = true;
            $scope.optional = true;
            $scope.completed = false;

            $scope.managementInsightRulesData = await callJsonParseMethodAsync("GetManagementInsightRules", null);

            // Sorted table
            $scope.miSortedGroups;

            // Filter string
            $scope.filter = $scope.getString('Filter');

            // Accessibility
            $scope.criticalString = $scope.getString("Critical");
            $scope.recommendedString = $scope.getString("Recommended");
            $scope.optionalString = $scope.getString("Optional");
            $scope.completedString = $scope.getString("Completed");

            // Drill through for table
            $scope.drillThrough = async function (groupName) {
                var groupId = "";

                // Find the group id associated to the group name
                for (var group in $scope.managementInsightRulesData) {
                    if ($scope.managementInsightRulesData[group].group === groupName) {
                        groupId = $scope.managementInsightRulesData[group].groupId;
                        break;
                    }
                }

                // If we fetch the id, then drill through to the appropriate group page
                if (!(groupId === undefined)) {
                    await callMethodAsync("ManagementInsightsGroupDrill", JSON.stringify([groupId, groupName]));
                }
            }

            await LoadDataAsync();
            $scope.$apply();

        });

        async function LoadDataAsync() {
            prepareRuleFilter();
            prepareGroupFilter();
            execute();
        };


        /// <summary> modify tooltip to display more information</summary>
        function tooltip_contents(d, defaultTitleFormat, defaultValueFormat, color) {
            var $$ = this;
            var config = $$.config;
            var titleFormat = config.tooltip_format_title || defaultTitleFormat;
            var nameFormat = config.tooltip_format_name || function (name) {
                return name;
            };
            var valueFormat = config.tooltip_format_value || defaultValueFormat;

            var text;
            var title;
            var value;
            var name;
            var bgcolor;

            for (var i = 0; i < d.length; i++) {
                if (!(d[i] && (d[i].value || d[i].value === 0))) { continue; }

                if (!text) {
                    title = titleFormat ? titleFormat(d[i].x) : d[i].x;
                    text = "<table class='" + $$.CLASS.tooltip + "'>" + (title || title === 0 ? "<tr><th colspan='2'>" + title + "</th></tr>" : "");
                }

                name = nameFormat(d[i].name);
                value = d[i].value;
                bgcolor = $$.levelColor ? $$.levelColor(d[i].value) : color(d[i].id);

                text += "<tr class='" + $$.CLASS.tooltipName + "-" + d[i].id + "'>";
                text += "<td class='name'><span style='background-color:" + bgcolor + "'></span>" + name + "</td>";

                // If decimal round to 2 DP, otherwise leave as int
                if (value % 1 === 0) {
                    text += "<td class='value'>" + value + "</td>";
                } else {
                    text += "<td class='value'>" + d3.format(".2f")(value) + "</td>";
                }

                text += "</tr>";
            }
            return text + "</table>";
        }

        /// <summary>Sets up all Aria strings for accessibility use</summary>
        /// <returns>Aria strings for narrator use</returns>
        function setupAria() {
            // Setup aria for management insights index gauge
            var managementInsightsIndexSummaryText = $scope.getString("IndexIs") + " " + $scope.miPercentage[1];
            var managementInsightsIndexAriaLabel = document.getElementById("ManagementInsightsIndexAria");
            managementInsightsIndexAriaLabel.setAttribute("aria-label", managementInsightsIndexSummaryText);

            // Setup aria for management insights groups donut
            var managementInsightsGroupSummaryText = "";
            for (var value in $scope.miGroups) {
                managementInsightsGroupSummaryText += $scope.getString("Group") + ", " + $scope.miGroups[value][0] + ", " + $scope.getString("Count") + ", " + $scope.miGroups[value][1] + ", ";
            }
            var managementInsightsGroupAriaLabel = document.getElementById("ManagementInsightsGroupsAria");
            managementInsightsGroupAriaLabel.setAttribute("aria-label", managementInsightsGroupSummaryText);

            // Setup aria for management insights priority donut
            var managementInsightsPrioritySummaryText = "";
            for (var value in $scope.miPriority) {
                managementInsightsPrioritySummaryText += $scope.getString("Priority") + ", " + $scope.miPriority[value][0] + ", " + $scope.getString("Count") + ", " + $scope.miPriority[value][1] + ", ";
            }
            var managementInsightsPriorityAriaLabel = document.getElementById("ManagementInsightsPriorityAria");
            managementInsightsPriorityAriaLabel.setAttribute("aria-label", managementInsightsPrioritySummaryText);
        }

        /// <summary>Get all management insight rules for filtering</summary>
        function prepareRuleFilter() {
            var res = [];

            // First "all rules" checkbox
            var first =
            {
                    ruleName: $scope.getString("AllRules"),
                    ruleId: "11111111-1111-1111-1111-111111111111",
                    groupID: "11111111-1111-1111-1111-111111111111",
                    checked: true
            };
            res.push(first);

            // Get all of the insight rules
            for (var item in $scope.managementInsightRulesData) {
                var data;
                data =
                    {
                        ruleName: $scope.managementInsightRulesData[item].name,
                        ruleId: $scope.managementInsightRulesData[item].id,
                        groupID: $scope.managementInsightRulesData[item].groupId,
                        group: $scope.managementInsightRulesData[item].group,
                        checked: true
                    };
                res.push(data);
            }
            $scope.managementInsightsRules = res;
            $scope.managementInsightsRulesFirst = $scope.managementInsightsRules[0];
        }

        /// <summary>Get all management insight groups for filtering</summary>
        function prepareGroupFilter() {
            var res = [];
            var groupDict = {};

            // First "all groups" checkbox
            var first =
                {
                    groupID: "11111111-1111-1111-1111-111111111111",
                    groupName: $scope.getString("AllGroups"),
                    checked: true
                };
            res.push(first);

            // Get all of the insight groups
            for (var item in $scope.managementInsightsRules) {
                var contains = false;

                // If the rule is the all rules rule, skip
                if ($scope.managementInsightsRules[item].groupID === "11111111-1111-1111-1111-111111111111") {
                    continue;
                }

                // Check group, if group exists iterate value, if does not exist add with value
                for (var groupItem in res) {
                    if (res[groupItem].groupID === $scope.managementInsightsRules[item].groupID) {
                        contains = true;
                        continue;
                    }
                }

                // If it doesn't contain after iterating then we add it
                if (!contains) {
                    var data =
                        {
                            groupID: $scope.managementInsightsRules[item].groupID,
                            groupName: $scope.managementInsightsRules[item].group,
                            checked: true
                        };
                    res.push(data);
                }
            }
            $scope.managementInsightsGroups = res;
            $scope.managementInsightsGroupsFirst = $scope.managementInsightsGroups[0];
        }

        /// <summary>Calculate percentage of compliance as per management insight rules</summary>
        /// <param name=""></param>
        /// <returns>Value for percentage</returns>
        function getManagementInsightsPercentage() {
            var res = [];

            var totalRules = 0;
            var totalCompliance = 0;

            for (var item in $scope.managementInsightRulesData) {
                // Check filters for criticality
                switch ($scope.managementInsightRulesData[item].priority) {
                    case "1":
                        if (!$scope.optional) {
                            continue;
                        }
                        totalRules += 1;
                        // Check if complete
                        if ($scope.managementInsightRulesData[item].status === "1") {
                            totalCompliance += 1;
                        }
                        break;
                    case "2":
                        if (!$scope.recommended) {
                            continue;
                        }
                        totalRules += 2;
                        // Check if complete
                        if ($scope.managementInsightRulesData[item].status === "1") {
                            totalCompliance += 2;
                        }
                        break;
                    case "4":
                        if (!$scope.critical) {
                            continue;
                        }
                        totalRules += 4;
                        // Check if complete
                        if ($scope.managementInsightRulesData[item].status === "1") {
                            totalCompliance += 4;
                        }
                        break;
                    default:
                        break;
                }
            }
            // To prevent division by 0
            if (totalRules === 0) {
                totalRules = 1;
            }
            if (totalCompliance === 0) {
                totalCompliance = 1;
            }
            res = [$scope.getString("ManagementInsightsIndex"), 100 * totalCompliance / totalRules];
            $scope.miPercentage = res;
        }

        /// <summary>Gets all the management insights groups available in management insights</summary>
        /// <param name=""></param>
        /// <returns>A list of all of the management insights groups by count</returns>
        function getManagementInsightsGroup()
        {
            var res = [];
            var groupDict = {};

            for (var item in $scope.miRules) {
                // Check group, if group exists iterate value, if does not exist add with value
                if (groupDict[$scope.managementInsightRulesData[item].group] === undefined) {
                    groupDict[$scope.managementInsightRulesData[item].group] = 1;
                } else {
                    var value = groupDict[$scope.managementInsightRulesData[item].group];
                    groupDict[$scope.managementInsightRulesData[item].group] = value + 1;
                }
            }
            // Push the group values to the UI
            for (var key in groupDict) {
                res.push([key, groupDict[key]]);
            }
            $scope.miGroups = res;
        }

        /// <summary>Gets a list of active management insight rules over the last 60 days</summary>
        /// <param name=""></param>
        /// <returns>A list of all of the management insights groups and counts over the last 60 days</returns>
        function getInsightsOverTime()
        {
            var res = [];
            var groupDict = {};

            for (var item in $scope.miRules) {
                // Check group, if group exists iterate value, if does not exist add with value
                if (groupDict[$scope.managementInsightRulesData[item].group] === undefined) {
                    groupDict[$scope.managementInsightRulesData[item].group] = 1;
                } else {
                    var value = groupDict[$scope.managementInsightRulesData[item].group];
                    groupDict[$scope.managementInsightRulesData[item].group] = value + 1;
                }
            }
            // Get the data over the last 60 days seperated in 5 day intervals
            var dateAxis = [];
            dateAxis.push("date");

            for (var i = 0; i < 12; i++) {
                var date = new Date();
                date.setDate(date.getDate() - (5 * i));
                dateAxis.push((date.getYear() + 1900) + "-" + (date.getMonth() + 1) + "-" + date.getDate());
            }
            res.push(dateAxis);

            // Push the group values to the UI
            for (var key in groupDict) {
                // Get the data over the last 60 days
                var days = [];
                days.push(key);

                for (var j = 0; j < 12; j++) {
                    var randomValue = Math.floor(Math.random() * 3) - 1;
                    if (randomValue > groupDict[key]) {
                        randomValue = 0;
                    }
                    days.push(groupDict[key] + randomValue);
                }
                res.push(days);
            }
            $scope.miTime = res;
        }

        /// <summary>Gets all the management insights priority available in management insights</summary>
        /// <param name=""></param>
        /// <returns>A list of all of the management insights priority by count</returns>
        function getManagementInsightsPriority() {
            var res = [];
            var criticalCount = 0;
            var recommendedCount = 0;
            var optionalCount = 0;
            var unknownCount = 0;

            for (var item in $scope.miRules) {
                switch ($scope.miRules[item].priority)
                {
                    case $scope.getString("Critical"):
                        criticalCount++;
                        break;
                    case $scope.getString("Recommended"):
                        recommendedCount++;
                        break;
                    case $scope.getString("Optional"):
                        optionalCount++;
                        break;
                    case $scope.getString("Unknown"):
                        unknownCount++;
                        break;
                    default:
                        unknownCount++;
                        break;
                }
            }

            // Add counts to the resource array
            res.push([$scope.getString("Critical"), criticalCount]);
            res.push([$scope.getString("Recommended"), recommendedCount]);
            res.push([$scope.getString("Optional"), optionalCount]);
            if (unknownCount !== 0)
            {
                res.push([$scope.getString("Unknown"), unknownCount]);
            }

            $scope.miPriority = res;
        }

        /// <summary>Gets all the management insights rules available in management insights based on the groups selected</summary>
        /// <param name=""></param>
        /// <returns>A list of all of the management insights rules</returns>
        function getManagementInsightsRules()
        {
            var res = [];

            var priorityString = "";
            var statusString = "";

            for (var item in $scope.managementInsightRulesData) {
                // Check if rule is completed and completed is checked
                if (!$scope.completed) {
                    if ($scope.managementInsightRulesData[item].status === "1") {
                        continue;
                    }
                }

                // Check filters for criticality
                switch ($scope.managementInsightRulesData[item].priority)
                {
                    case "1":
                        // Check if optional filter is on
                        if (!$scope.optional) {
                            continue;
                        }
                        break;
                    case "2":
                        // Check if recommended filter is on
                        if (!$scope.recommended) {
                            continue;
                        }
                        break;
                    case "4":
                        // Check if critical filter is on
                        if (!$scope.critical) {
                            continue;
                        }
                        break;
                    default:
                        break;
                }

                // 4) Critical, 2) Recommended, 1) Optional
                priorityString = ($scope.managementInsightRulesData[item].priority === "1") ? $scope.getString("Optional") :
                                 ($scope.managementInsightRulesData[item].priority === "2") ? $scope.getString("Recommended") :
                                 ($scope.managementInsightRulesData[item].priority === "4") ? $scope.getString("Critical") : $scope.getString("Unknown");

                status = ($scope.managementInsightRulesData[item].status === "-1") ? $scope.getString("ActionNeeded") :
                         ($scope.managementInsightRulesData[item].status === "0") ? $scope.getString("InProgress") :
                         ($scope.managementInsightRulesData[item].status === "1") ? $scope.getString("Complete") : $scope.getString("Unknown");

                var lastRun = $scope.managementInsightRulesData[item].lastRunTime;
                // If lastRun is not in date time format it returns ??, in this situation have it be an unknown string
                if (lastRun.charAt(0) === '?')
                {
                    lastRun = "";
                }

                res[item] =
                    {
                        insightName: $scope.managementInsightRulesData[item].name,
                        group: $scope.managementInsightRulesData[item].group,
                        priority: priorityString,
                        priorityBit: $scope.managementInsightRulesData[item].priority,
                        lastChange: lastRun,
                        progress: status
                    }
            }
            $scope.miRules = res;
        }

        /// <summary>Checks to see if there is data in the columns, if data exists</summary>
        /// <param name="columns">The columns of the data in the table that we will be putting into our charts</param>
        /// <returns>True if data exists in the columns, false otherwise</returns>
        function dataInColumns(columns) 
        {
            // Check if the columns exist
            if (columns === null || typeof (columns) === "undefined") {
                return false;
            }
            var data = false;  // By default let there be no data in the columns
            var zeroData = 0; // If all the data is 0 then assume there is no data
            // Check if there is data by iterating through all the elements in the columns
            for (var i = 0; i < columns.length; i++)  {
                // If the columns are not empty and there is at least one column there exists data
                if (columns[i][1] !== null)  {
                    data = true;
                    // Used to check if all values are 0
                    if (columns[i][1] === 0)  {
                        zeroData++;
                    }
                } else {
                    data = false;
                }
            }
            // Check if all values are 0
            if (zeroData === columns.length) {
                data = false;
            } else {
                data = true;
            }
            return data;
        }

        /// <summary>Create a gauge chart</summary>
        $scope.createGauge = function (idToBindTo, columns)
        {
            $scope.gaugeChart = c3.generate({
                bindto: idToBindTo,
                data: {
                    columns: [
                        [columns[0], columns[1]]
                    ],
                    type: "gauge",
                },
                gauge: {
                    label: {
                        format: function (value) {
                            return d3.format("0.2%")(value/100);
                        }
                    }
                },
                tooltip: {
                    contents: tooltip_contents
                },
                color: {
                    pattern: ["#00B7C3"],
                    threshold: {
                        values: [0]
                    }
                },
            });

            if ($scope.brightness < 125) {
                SetColorToAllTextInChart(idToBindTo, 'white');
            }
        };

        /// <summary>Create a donut chart</summary>
        $scope.createDonut = async function (idToBindTo, columns, drillThroughEnabled)
        {
            var labels = true;
            var data = dataInColumns(columns);
            var pattern = ["#00B7C3", "#038387","#005B70", "#0078D7", "#9B0062", "#004E8C", "#5C2E91", "#8378DE", "#E3008C"];

            // Checks to see if data exists, if not generate an empty chart
            if (!data) {
                labels = false;                                 // If there is not data there will be no labels
                pattern = ["#A0AEB2"];                          // If there is no data the default graph colour will be grey
                columns = [[$scope.getString("Complete"), 1]];         // If there is no data there will only be one entry in the graph
            }

            // If no drill through, show pointer cursor instead of hand
            if (!drillThroughEnabled) {
                d3.select(idToBindTo).selectAll(".c3-arc").style("cursor", "auto");
            }
            $scope.donutChart =c3.generate({
                bindto: idToBindTo,
                data: {
                    columns: columns,
                    type: "donut",
                    onclick: function (d, element) {
                        if (drillThroughEnabled) {
                            var valueID;

                            // Get the id associated to the donut value id
                            for (var item in $scope.managementInsightsGroups) {
                                if (d.id === $scope.managementInsightsGroups[item].groupName) {
                                    valueID = $scope.managementInsightsGroups[item].groupID;
                                    continue;
                                }
                            }
                            if (!(valueID === undefined)) {
                                adminUI.sendNewRequestSync("ManagementInsightsGroupDrill", JSON.stringify([valueID, d.id]));
                            }
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
                    // If there is no data the label will state 0
                    labels: {
                        format: function (value, ratio) {
                            if (labels) {
                                return value;
                            } else {
                                return 0;
                            }
                        }
                    },
                    expand: labels,
                }
            });
            $scope.donutChart.resize({
                height: 290,
                width: 290
            });

            if ($scope.brightness < 125) {
                SetColorToAllTextInChart(idToBindTo, 'white');
            }
        };

        /// <summary>Create an area chart</summary>
        $scope.createAreaChart = async function (idToBindTo, columns)
        {
            $scope.areaChart = c3.generate({
                bindto: idToBindTo,
                data: {
                    x: "date",
                    columns: columns,
                    type: "area-spline"
                },
                tooltip: {
                    contents: tooltip_contents
                },
                axis: {
                    x: {
                        label: {
                            text: $scope.getString("Date"),
                            position: "outer-center"
                        },
                        type: "timeseries",
                        tick: {
                            format: "%Y-%m-%d"
                        }
                    },
                    y: {
                        label: {
                            text: $scope.getString("ManagementInsightsGroupsCount"),
                            position: "outer-middle"
                        }
                    }
                }
            });
            $scope.areaChart.resize({
                height: 250
            });

            if ($scope.brightness < 125) {
                SetColorToAllTextInChart(idToBindTo, 'white');
            }
        };

        

        async function execute()
        {
            getManagementInsightsRules();
            getManagementInsightsPriority();
            getManagementInsightsPercentage();
            getManagementInsightsGroup();
            getInsightsOverTime();

            setupAria();

            // ManagementInsightsIndex
            $scope.createGauge("#ManagementInsightsIndex", $scope.miPercentage);

            // ManagementInsightsGroups
            $scope.createDonut("#ManagementInsightsGroups", $scope.miGroups, true);

            // ManagementInsightsPriority
            $scope.createDonut("#ManagementInsightsPriority", $scope.miPriority, false);

            // Insights over time

            // $scope.createAreaChart("#InsightsOverTime", $scope.miTime);

        }

        // On new MPs the dashboard refreshes
        $scope.refresh = function refresh()
        {
            // Display all the dashboards
            execute();
        };
    });
}());
// SIG // Begin signature block
// SIG // MIInywYJKoZIhvcNAQcCoIInvDCCJ7gCAQExDzANBglg
// SIG // hkgBZQMEAgEFADB3BgorBgEEAYI3AgEEoGkwZzAyBgor
// SIG // BgEEAYI3AgEeMCQCAQEEEBDgyQbOONQRoqMAEEvTUJAC
// SIG // AQACAQACAQACAQACAQAwMTANBglghkgBZQMEAgEFAAQg
// SIG // Flrx6E1C6Ieu15Z0eeh51kYwVlB0VvaYjzkzZY5JsTWg
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
// SIG // ARUwLwYJKoZIhvcNAQkEMSIEIIfiP68UGPbWR7DwZCTv
// SIG // D14Vn9XFMErWBNPe3hThqjuoMEIGCisGAQQBgjcCAQwx
// SIG // NDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRw
// SIG // Oi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEB
// SIG // BQAEggEAGVpyt6Z2xuSKsPNjappfrmr9NRxSdEa/TWSu
// SIG // 2zUqMl+/yn5+b3ds8ZXoePTuF93wQDFZCptjEVn5JQkk
// SIG // Xh09dYB8rGKkdfDx7GxNZCJmQv/PTTK2sjkILgELIT0I
// SIG // U4lQ9OIOAZPH8nok9ifmfmaprRm8wauza4bmOs9xC6Vp
// SIG // CvXSwGO2okp+6xf18dwAx1UJqbHDIoc50jlBAHzXOUtD
// SIG // Vq8aqKf9uBKutIK3eUuJNzwlnoywRmYJ+3HYpkDx8w5W
// SIG // saje8k1bRrMS+kECncofVCE8KN+A3TJawJdIiGGJg0/x
// SIG // 7D8iMmQ9fPXwuXk7c52ev53R3KaKzN03tv8BpRE+D6GC
// SIG // FywwghcoBgorBgEEAYI3AwMBMYIXGDCCFxQGCSqGSIb3
// SIG // DQEHAqCCFwUwghcBAgEDMQ8wDQYJYIZIAWUDBAIBBQAw
// SIG // ggFZBgsqhkiG9w0BCRABBKCCAUgEggFEMIIBQAIBAQYK
// SIG // KwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCBynZ7z
// SIG // 6cOIjSitRkgje8+R41xhuYohH5kQc8ySY6f8xQIGY2Pe
// SIG // fFXzGBMyMDIyMTEwNDE3MjMzOS44NDJaMASAAgH0oIHY
// SIG // pIHVMIHSMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
// SIG // aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
// SIG // ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQL
// SIG // EyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExp
// SIG // bWl0ZWQxJjAkBgNVBAsTHVRoYWxlcyBUU1MgRVNOOkEy
// SIG // NDAtNEI4Mi0xMzBFMSUwIwYDVQQDExxNaWNyb3NvZnQg
// SIG // VGltZS1TdGFtcCBTZXJ2aWNloIIRezCCBycwggUPoAMC
// SIG // AQICEzMAAAG4CNTBuHngUUkAAQAAAbgwDQYJKoZIhvcN
// SIG // AQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
// SIG // c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
// SIG // BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UE
// SIG // AxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAw
// SIG // HhcNMjIwOTIwMjAyMjE2WhcNMjMxMjE0MjAyMjE2WjCB
// SIG // 0jELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
// SIG // b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
// SIG // Y3Jvc29mdCBDb3Jwb3JhdGlvbjEtMCsGA1UECxMkTWlj
// SIG // cm9zb2Z0IElyZWxhbmQgT3BlcmF0aW9ucyBMaW1pdGVk
// SIG // MSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVTTjpBMjQwLTRC
// SIG // ODItMTMwRTElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUt
// SIG // U3RhbXAgU2VydmljZTCCAiIwDQYJKoZIhvcNAQEBBQAD
// SIG // ggIPADCCAgoCggIBAJwbsfwRHERn5C95QPGn37tJ5vOi
// SIG // Y9aWjeIDxpgaXaYGiqsw0G0cvCK3YulrqemEf2CkGSdc
// SIG // OJAF++EqhOSqrO13nGcjqw6hFNnsGwKANyzddwnOO0jz
// SIG // 1lfBIIu77TbfNvnaWbwSRu0DTGHA7n7PR0MYJ9bC/Hop
// SIG // StpbFf606LKcTWnwaUuEdAhx6FAqg1rkgugiuuaaxKyx
// SIG // RkdjFZLKFXEXL9p01PtwS0fG6vZiRVnEKgeal2TeLvdA
// SIG // IqapBwltPYifgqnp7Z4VJMcPo0TWmRNVFOcHRNwWHehN
// SIG // 9xg6ugIGXPo7hMpWrPgg4moHO2epc0T36rgm9hlDrl28
// SIG // bG5TakmV7NJ98kbF5lgtlrowT6ecwEVtuLd4a0gzYqha
// SIG // nW7zaFZnDft5yMexy59ifETdzpwArj2nJAyIsiq1PY3X
// SIG // Pm2mUMLlACksqelHKfWihK/Fehw/mziovBVwkkr/G0F1
// SIG // 9OWgR+MBUKifwpOyQiLAxrqvVnfCY4QjJCZiHIuS15HC
// SIG // Q/TIt/Qj4x1WvRa1UqjnmpLu4/yBYWZsdvZoq8SXI7iO
// SIG // s7muecAJeEkYlM6iOkMighzEhjQK9ThPpoAtluXbL7qI
// SIG // HGrfFlHmX/4soc7jj1j8uB31U34gJlB2XphjMaT+E+O9
// SIG // SImk/6GRV9Sm8C88Fnmm2VdwMluCNAUzPFjfvHx3AgMB
// SIG // AAGjggFJMIIBRTAdBgNVHQ4EFgQUxP1HJTeFwzNYo1nj
// SIG // fucXuUfQaW4wHwYDVR0jBBgwFoAUn6cVXQBeYl2D9OXS
// SIG // ZacbUzUZ6XIwXwYDVR0fBFgwVjBUoFKgUIZOaHR0cDov
// SIG // L3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jcmwvTWlj
// SIG // cm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAo
// SIG // MSkuY3JsMGwGCCsGAQUFBwEBBGAwXjBcBggrBgEFBQcw
// SIG // AoZQaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9w
// SIG // cy9jZXJ0cy9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIw
// SIG // UENBJTIwMjAxMCgxKS5jcnQwDAYDVR0TAQH/BAIwADAW
// SIG // BgNVHSUBAf8EDDAKBggrBgEFBQcDCDAOBgNVHQ8BAf8E
// SIG // BAMCB4AwDQYJKoZIhvcNAQELBQADggIBAJ9uk8miwpMo
// SIG // Kw3D996piEzbegAGxkABHYn2vP2hbqnkS9U97s/6QlyZ
// SIG // OhGFsVudaiLeRZZTsaG5hR0oCuBINZ/lelo5xzHc+mBO
// SIG // pBXpxSaW1hqoxaCLsVH1EBtz7in25Hjy+ejuBcilH6EZ
// SIG // 0ZtNxmWGIQz8R0AuS0Tj4VgJXHIlXP9dVOiyGo9Velrk
// SIG // +FGx/BC+iEuCaKd/IsypHPiCUCh52DGc91s2S7ldQx1H
// SIG // 4CljOAtanDfbvSejASWLo/s3w0XMAbDurWNns0XidAF2
// SIG // RnL1PaxoOyz9VYakNGK4F3/uJRZnVgbsCYuwNX1BmSwM
// SIG // 1ZbPSnggNSGTZx/FQ20Jj/ulrK0ryAbvNbNb4kkaS4a7
// SIG // 67ifCqvUOFLlUT8PN43hhldxI6yHPMOWItJpEHIZBiTN
// SIG // KblBsYbIrghb1Ym9tfSsLa5ZJDzVZNndRfhUqJOyXF+C
// SIG // Vm9OtVmFDG9kIwM6QAX8Q0if721z4VOzZNvD8ktg1lI+
// SIG // XjXgXDJVs3h47sMu9GXSYzky+7dtgmc3iRPkda3YVRdm
// SIG // PJtNFN0NLybcssE7vhFCij75eDGQBFq0A4KVG6uBdr6U
// SIG // TWwE0VKHxBz2BpGvn7BCs+5yxnF+HV6CUickDqqPi/II
// SIG // 7Zssd9EbP9uzj4luldXDAPrWGtdGq+wK0odlGNVuCMxs
// SIG // L3hn8+KiO9UiMIIHcTCCBVmgAwIBAgITMwAAABXF52ue
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
// SIG // VQQLEx1UaGFsZXMgVFNTIEVTTjpBMjQwLTRCODItMTMw
// SIG // RTElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAg
// SIG // U2VydmljZaIjCgEBMAcGBSsOAwIaAxUAcGteVqFx/IbT
// SIG // KXHLeuXCPRPMD7uggYMwgYCkfjB8MQswCQYDVQQGEwJV
// SIG // UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMH
// SIG // UmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
// SIG // cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1T
// SIG // dGFtcCBQQ0EgMjAxMDANBgkqhkiG9w0BAQUFAAIFAOcP
// SIG // rmswIhgPMjAyMjExMDQyMzI5NDdaGA8yMDIyMTEwNTIz
// SIG // Mjk0N1owdzA9BgorBgEEAYRZCgQBMS8wLTAKAgUA5w+u
// SIG // awIBADAKAgEAAgIDAwIB/zAHAgEAAgIRlTAKAgUA5xD/
// SIG // 6wIBADA2BgorBgEEAYRZCgQCMSgwJjAMBgorBgEEAYRZ
// SIG // CgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqG
// SIG // SIb3DQEBBQUAA4GBAAAidQUtaHqE2aaDngRs5NRJQsZ/
// SIG // q/0O78V/Un3Q6IBbcztmp658m9mzw5GkmUPo4HFijYnM
// SIG // nGa5O4CxW1fi+HbQTnc/IEfuCnBAxmGbflaE9RDcDo/P
// SIG // 8j8w5knngwLo2Q+8CvbSszOB9zRqePOr9vI2zp1JdgAH
// SIG // oii4nuHvh4EuMYIEDTCCBAkCAQEwgZMwfDELMAkGA1UE
// SIG // BhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNV
// SIG // BAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
// SIG // b3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRp
// SIG // bWUtU3RhbXAgUENBIDIwMTACEzMAAAG4CNTBuHngUUkA
// SIG // AQAAAbgwDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3
// SIG // DQEJAzENBgsqhkiG9w0BCRABBDAvBgkqhkiG9w0BCQQx
// SIG // IgQgEgesObkBGLqMumnsvA474PIfwEOiQRZtw0iHVdnq
// SIG // yqswgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCAo
// SIG // 69Y4oHA7Q4pS+Y1NsBfrpIYTeWsPeGTami0X0PD7HzCB
// SIG // mDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
// SIG // YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
// SIG // VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNV
// SIG // BAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEw
// SIG // AhMzAAABuAjUwbh54FFJAAEAAAG4MCIEIJDBW67MRKy5
// SIG // 6CRRhSvuyzsbZ09Q6WTDPYgV7mzHGwVWMA0GCSqGSIb3
// SIG // DQEBCwUABIICAD/zis/J9jy1ctOCulSUQYj0xC+UNGI0
// SIG // 5hpmo+EM6EjP7cR+Gu7Dm1joKUqC1RQksukdvlLwSB49
// SIG // +HThjh7CV62OgbI1oPPm3fNqNxbmxcuWZCHa+iJToO23
// SIG // smZK7J0ddMftNjYUdmKXw82uqmWASAQ2xRrCx/3B7fre
// SIG // HcQhZR3PUcnnvzu238Wnt+U+FYteKHrmkrd3ZAEP2R97
// SIG // pZ/sCDxv2A4JPGETS/BFfHsMDpWyTA4S/9KSSsfOJj+H
// SIG // 995g80VHxLXwCIKuBksgTyuCeIxokuq6X8A6bi+3Bb6x
// SIG // byVvpwUxErswkxhdJD0lohNzC8CpBfSg/CWiYmplQvKF
// SIG // 6vacghJyOFhDoaXtk18fH0WMQBNPXaBZ8cQRb+Gh++iq
// SIG // i4DrI+Q4+F5EQVoAsTW8RfjO+Qgtrj347Sf3V3hm3E56
// SIG // L9CRUbcSll7To8/LW3nywPTZoXWLv5wBGBbAbUJx16yA
// SIG // TdVyC18F5r6YDzZaUGVaUqkLMnRvf721aGRYomPa7dce
// SIG // fgN9ETAvL3St2sXdABGQNAUHTRbfscThMZQLGmB4MlMm
// SIG // lWcAmrK7/CCIXKSq5gNhIjRrcOIP1kiVqcA1NV19/6rw
// SIG // NaZLpz5lScH1f5VQc3+S8WZNCpK4bS+zGpjCrgsnlybB
// SIG // PggvN/oas6L/BpeQYtxNGUXyR8voV1+qeiyL
// SIG // End signature block
