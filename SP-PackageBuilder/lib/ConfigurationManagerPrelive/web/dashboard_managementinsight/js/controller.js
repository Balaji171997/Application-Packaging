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
// SIG // MIIomQYJKoZIhvcNAQcCoIIoijCCKIYCAQExDzANBglg
// SIG // hkgBZQMEAgEFADB3BgorBgEEAYI3AgEEoGkwZzAyBgor
// SIG // BgEEAYI3AgEeMCQCAQEEEBDgyQbOONQRoqMAEEvTUJAC
// SIG // AQACAQACAQACAQACAQAwMTANBglghkgBZQMEAgEFAAQg
// SIG // Flrx6E1C6Ieu15Z0eeh51kYwVlB0VvaYjzkzZY5JsTWg
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
// SIG // ghpsMIIaaAIBATCBlTB+MQswCQYDVQQGEwJVUzETMBEG
// SIG // A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
// SIG // ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
// SIG // MSgwJgYDVQQDEx9NaWNyb3NvZnQgQ29kZSBTaWduaW5n
// SIG // IFBDQSAyMDExAhMzAAAEhJjiEuB4ozFdAAAAAASEMA0G
// SIG // CWCGSAFlAwQCAQUAoIH3MBkGCSqGSIb3DQEJAzEMBgor
// SIG // BgEEAYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEE
// SIG // AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCCH4j+vFBj21kew
// SIG // 8GQk7w9eFZ/VxTBK1gTT3t4U4ao7qDCBigYKKwYBBAGC
// SIG // NwIBDDF8MHqgXIBaAE0AaQBjAHIAbwBzAG8AZgB0AC4A
// SIG // VABvAG8AbABrAGkAdAAuAFcAcABmAC4AVQBJAC4AQwBv
// SIG // AG4AdAByAG8AbABzAC4AVwBlAGIAVgBpAGUAdwAuAGQA
// SIG // bABsoRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
// SIG // BgkqhkiG9w0BAQEFAASCAQCS6avMm+FSvwgB0y3Ya5rD
// SIG // uFsSNHVkzVBGe8T2wJTxKKACMRKfTz4LJveufZUIFVye
// SIG // B+ZluGvtwfPWR0u8/jUNLGYfDEm9Iyp/gBhJ6cRgOlgJ
// SIG // PLs8eDGGu3bMPr1IarBODnzoBcRQ63MpQSkl7u8JYXH5
// SIG // DBNJcXWGO4JVlViMjALEOQU1PAIqc/v+AFY2biCjREIj
// SIG // RT+URw5Uk5c4sY4tqaUe8yfHDKAXBkzE44uS49RWBdIh
// SIG // 13pCsTNaqCXqY5LIfsR3nGPl0IQG5GLgpsnn7ofGmh6W
// SIG // gcYnbgpniu/Kh9IZ7zDqi8ok7n+OFiieAd9GGYl971o7
// SIG // LsFszptQFl0soYIXrTCCF6kGCisGAQQBgjcDAwExgheZ
// SIG // MIIXlQYJKoZIhvcNAQcCoIIXhjCCF4ICAQMxDzANBglg
// SIG // hkgBZQMEAgEFADCCAVoGCyqGSIb3DQEJEAEEoIIBSQSC
// SIG // AUUwggFBAgEBBgorBgEEAYRZCgMBMDEwDQYJYIZIAWUD
// SIG // BAIBBQAEIFadqgAMnaGqXtGNZtmrf9Lk+FuN3RhM0Dhy
// SIG // K7V2h/XOAgZo8pGSAekYEzIwMjUxMDIzMDI0NzA0LjM4
// SIG // N1owBIACAfSggdmkgdYwgdMxCzAJBgNVBAYTAlVTMRMw
// SIG // EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
// SIG // b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
// SIG // b24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9w
// SIG // ZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNoaWVs
// SIG // ZCBUU1MgRVNOOjY1MUEtMDVFMC1EOTQ3MSUwIwYDVQQD
// SIG // ExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloIIR
// SIG // +zCCBygwggUQoAMCAQICEzMAAAIVGAPTgQcmfFMAAQAA
// SIG // AhUwDQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMx
// SIG // EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
// SIG // ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
// SIG // dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3Rh
// SIG // bXAgUENBIDIwMTAwHhcNMjUwODE0MTg0ODIwWhcNMjYx
// SIG // MTEzMTg0ODIwWjCB0zELMAkGA1UEBhMCVVMxEzARBgNV
// SIG // BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
// SIG // HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEt
// SIG // MCsGA1UECxMkTWljcm9zb2Z0IElyZWxhbmQgT3BlcmF0
// SIG // aW9ucyBMaW1pdGVkMScwJQYDVQQLEx5uU2hpZWxkIFRT
// SIG // UyBFU046NjUxQS0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1p
// SIG // Y3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0G
// SIG // CSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDDcdXeFXEv
// SIG // SURg9XTdd40pnnXtUhuB7GGUM92lfANLQFi3E/CLhdil
// SIG // lHWV3S7pyvZeO66B2DnQNTHlYcvRCFjZ32+QlKTTasT/
// SIG // vmFwq33WbYiHbztBHFEyYW7cEXrjrqTyqnm5e197q5yK
// SIG // rj1hpLyn53O/e5NqsPiFDxRPstr3mk4mJGrHF3So4YsQ
// SIG // K8csRc9eKg1LH2nKHOGbqW3t7MvEl4VVi3FKGRq8+hk3
// SIG // R04KJh6HgqCgqjJqDMy5KIsKIxRbhR7hCybrnwUk0ZM2
// SIG // HtXmpdhUDqTnGPDlZ5Z0o7PSL0DmMFxtj19U6j9wDyLV
// SIG // vK3NwNPFvedy1yXLz85h42y2Rpv8iyrcLF7W+r3p8gcT
// SIG // X5kaYmORrWyh3Co/JxWn/a1v4GO6U8vkPquBRdM8XzhT
// SIG // zZEsodXntsHx8dGmCeNxYFC5c+BV5JekRFaKa3Q0XaUI
// SIG // 4vOqCu9L+9ip17kuf1iUoqEBn/EMTRMsgivr4j/YlO1c
// SIG // /fid+NMQ1WowEhJZxqQjEDAZvdEHnIcLHKcgU1Utx8oC
// SIG // wR0LlTZ6bR8C+ZW/Syieqe/Xty5piLZ4ItaGgrUhzzkP
// SIG // Duz+WFxesGljif9GXmXfAfOzi84iG7zsMjLlBRoS6kSz
// SIG // JjQ1aqAjgFaXq/XCCx76XwNYV5Reh+FS4KBVO5Mc3cry
// SIG // J2gxufxDd51QgQIDAQABo4IBSTCCAUUwHQYDVR0OBBYE
// SIG // FIkhd/FyoDAWoaP2N3BC11Kpp2PXMB8GA1UdIwQYMBaA
// SIG // FJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYw
// SIG // VKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9w
// SIG // a2lvcHMvY3JsL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAl
// SIG // MjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRg
// SIG // MF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9z
// SIG // b2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIw
// SIG // VGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwG
// SIG // A1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUH
// SIG // AwgwDgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUA
// SIG // A4ICAQB3jYe1X6QZu/HMsFMLk7u+QIgE/L8HCmMLN4vn
// SIG // eECIQ55un5V02fCb0ZUJ9ircox+uPhS8pBNQBpLlmTB7
// SIG // WC9neWNJKcI7JLk7A2712mDfDD5BbZ45xIuTJUBYWsuf
// SIG // oiKDdML/NYy9WGpe10WEbYonWVJs3bbZyxjcTf8GsaW4
// SIG // CW8RP2CbFXLLE3Ln3/skXnMgZwmJvJ3Gz3gkvUG0+Bck
// SIG // 59nND7/eJNzp4O2ZpZPoMp2cmhynzCRcpY8iwER+QPqT
// SIG // VCK3C+3SYes5FqHvlKN5w4q3ihZrJUuQ9OGjXZ7SieAS
// SIG // DVyN7l/FJka2GsytYq8jhHscQLuTyZof148DdWIfQJVJ
// SIG // I559o9MYzMiEcKjmneMblIxzI7d4D24RphAkhMmUsbcH
// SIG // DAabKljsL/z+ePVI6GDHUeAnTLA4kv3F8/gA5xaYJ9uy
// SIG // qAZsJoLtYfmwg13N8xqvxXtg0WqRsIZQqFzwakjIT4wq
// SIG // fJWffeOy5oYCU1GDt1VFRKhgsnG9SzD0Y7DIGkHBsT2y
// SIG // o4ub4ew7TSgXbc8yKjtYVdwVNkCOne6OKEEB8utcgKAY
// SIG // 4c92RnTja7Utmo5yeWvdfO+Ax76Y8/Jqxbx/Su3MmPdX
// SIG // kT8QqLJCU/GP0x+rbH2GKaeVdYZkJU94QFE6s1sNgF9r
// SIG // NPIs0I5OxG2Sw5JXcUG0+elC0s3vnjCCB3EwggVZoAMC
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
// SIG // BRDBcQZqELQdVTNYs6FwZvKhggNWMIICPgIBATCCAQGh
// SIG // gdmkgdYwgdMxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
// SIG // YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
// SIG // VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNV
// SIG // BAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMg
// SIG // TGltaXRlZDEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNO
// SIG // OjY1MUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3Nv
// SIG // ZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4D
// SIG // AhoDFQCPp5N6Nu5gTUh+Nt+u3q1d68JRIKCBgzCBgKR+
// SIG // MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5n
// SIG // dG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
// SIG // aWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1p
// SIG // Y3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqG
// SIG // SIb3DQEBCwUAAgUA7KOnDTAiGA8yMDI1MTAyMjE4NTUw
// SIG // OVoYDzIwMjUxMDIzMTg1NTA5WjB0MDoGCisGAQQBhFkK
// SIG // BAExLDAqMAoCBQDso6cNAgEAMAcCAQACAi3VMAcCAQAC
// SIG // AhK7MAoCBQDspPiNAgEAMDYGCisGAQQBhFkKBAIxKDAm
// SIG // MAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAIAgEA
// SIG // AgMBhqAwDQYJKoZIhvcNAQELBQADggEBAKd4ICae7N3K
// SIG // 17sNWOKMsEWRCv5kRv1NqHxcYocfiI3uEx8vVARPKa1n
// SIG // N9/WEK5LcmvpigdJVxjxvEOMQnAz5Ga3/XE4WPi6zVWh
// SIG // xxyrjY7h+mZXpeIuSQJY4X3P1bfW0ClERx+erA8dR1uU
// SIG // 9xp/8zSYzYujNYRG7CnSPKkNSubzOmjms/RvxR7xxVic
// SIG // J3R+eGImmw+2yG3E8mut7IKS0CF6VG8Y1zZM1/rz8B8A
// SIG // z4iO9hPMXuRnaWGeRxbIhi88ra1DuorcIHe1JdTLhCxw
// SIG // lnxpZEQe01LJyma6PNmzWZOH9PoJzv+G5z6gHVyppBP6
// SIG // tfNtK8YVR+eH0CKEqz0uLkgxggQNMIIECQIBATCBkzB8
// SIG // MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
// SIG // bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
// SIG // cm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNy
// SIG // b3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAhUY
// SIG // A9OBByZ8UwABAAACFTANBglghkgBZQMEAgEFAKCCAUow
// SIG // GgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqG
// SIG // SIb3DQEJBDEiBCCxj/WBxtihGF4C3E3JEKjt0pdXeMJE
// SIG // Q5WQsKuBaRBNFTCB+gYLKoZIhvcNAQkQAi8xgeowgecw
// SIG // geQwgb0EIHAQ9HY8OtMUtyu1CwqtSLujPkk1EIX8pEcy
// SIG // KFI17uyKMIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzAR
// SIG // BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
// SIG // bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
// SIG // bjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAg
// SIG // UENBIDIwMTACEzMAAAIVGAPTgQcmfFMAAQAAAhUwIgQg
// SIG // Ytcu8GXVUPo1dsbuL7yn44Iz71TJ1Ua5Qm6EXtGwDiQw
// SIG // DQYJKoZIhvcNAQELBQAEggIAD7ggGpUQvtfwy9AwQ6AI
// SIG // Rqa1fT8xeNPEjEmJVYirKunPSkxNB70HpiiFX4UlsWbH
// SIG // qF2weY74CkWwCCiNGO0ShrhGYNSb1f5IdKbqKMUql8S5
// SIG // fd6fVukviMAGEr8bcpckpS4qvgEa5Ruavc/oQJ1TlYug
// SIG // +8PPLIotBX2R97t1WZiLlTcSmhgdgzTdVDJAckQ5it2n
// SIG // mmcvVWdwgdKWFaw4Sp4k79xvCphUxyt8aijcqepJXjhM
// SIG // sxGLgaPqxmklJUqfEtYpXcYW1OAKvH9Gk05MhtLH35nt
// SIG // 0gNWoCCbd9s6MYi+ry1t0p21NQhXSAoHbWRhLaXX4mIU
// SIG // mCqDYLo9oZRSS8KAOAXgZS/9VMUcVlFrty4bIbYcP0ne
// SIG // 4WZlvz38QcOAXCxq9E0buVjU3IXDcUdMe04A9jl6C+0d
// SIG // jBoC8ONfNQ5290WlGjGoxN0RbdaP1+zG/skc5iz6v3hW
// SIG // 14WtmvvuDUjhB0ID+uGZ0pa+9mNcbbwArSIrmMMU7Hfx
// SIG // 239azsL8Qgu77qmRJv0/zM+MpVGejdW7CriwX6sJ1Lxp
// SIG // 8T6jusAjGe9HDI7hxkSB0gI5db3aaPJ6K8n/WYI6i60f
// SIG // Zem/rFg4XNjTnrzh/poTbcW6hQx3Ce7FNvu5onKRe+w0
// SIG // UlwgUciLIVNeV6vbaNjQZpRAyAN/c8SLKPM3xCOlA0VIkZE=
// SIG // End signature block
