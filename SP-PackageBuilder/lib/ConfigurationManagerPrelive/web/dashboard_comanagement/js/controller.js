(function () {
    "use strict";

    var dashboard = angular.module("dashboard", []);

    var win10EligibleCount = 0;
    var win10NotEligibleCount = 0;
    var otherOSCount = 0;
    var hybridAADCount = 0;
    var aadCount = 0;
    var enrollingHybridCount = 0;
    var hybridErrorCount = 0;
    var aadErrorCount = 0;
    var pendingLogonCount = 0;

    dashboard.controller("dashboardController", function ($scope, $sce) {

        $scope.CoMgmtChartState = ChartState.Loading;

        adminUI.initializeController($scope, function () {

            utilityUpdateHTMLString("memacContainer", $scope.getString("MemacString"));

            adminUI.sendNewRequest("GetWorkloadTransitionCount", null, function callback(response, returnCode) {

                $scope.MDMWorkloadTransitionData = JSON.parse(response);
                initDashboard();
            });
        });

        $scope.getString = function (stringName) {

            return $scope.strings[stringName];
        };

        $scope.createDonutChart = function (idToBindTo, chartTitle, chartData, colorPattern, drillthroughEnabled) {


            if (noDataInColumns(chartData)) {
                $scope.createEmptyDonutChart(idToBindTo, chartTitle);
            }
            else {

                GetSummaryText(idToBindTo, chartTitle, chartData);

                c3.generate({
                    bindto: idToBindTo,
                    data: {
                        columns: chartData,
                        type: 'donut'
                    },
                    color: {
                        pattern: colorPattern
                    },
                    tooltip: {
                        format: {
                            // Tooltip shows number of devices instead of ratio
                            value: function (value, ratio, id) {
                                return value;
                            }
                        }
                    }
                });

                // If no drill through, show pointer cursor instead of hand
                if (!drillthroughEnabled) {
                    d3.select(idToBindTo).selectAll(".c3-arc").style("cursor", "auto");
                }

                if ($scope.brightness < 125) {
                    SetColorToAllTextInChart(idToBindTo, 'white');
                }

                $scope.$apply();
            }
        };

        // Creates donut chart with legend on the right. There is no easy way to conditionally change legend's position so far.
        $scope.createDonutChart_long = function (idToBindTo, chartTitle, chartData, colorPattern, drillthroughEnabled) {

            if (noDataInColumns(chartData)) {
                $scope.createEmptyDonutChart(idToBindTo, chartTitle);
            }
            else {

                GetSummaryText(idToBindTo, chartTitle, chartData);

                c3.generate({
                    bindto: idToBindTo,
                    data: {
                        columns: chartData,
                        type: 'donut',
                        onclick: function (d) { if (idToBindTo == "#coMgmtEnrollStateChart") { adminUI.sendNewRequest("DrillThroughEnrollmentStatusChart", d.name, null); } }
                    },
                    legend: {
                        position: 'right'
                    },
                    color: {
                        pattern: colorPattern
                    },
                    tooltip: {
                        format: {
                            // Tooltip shows number of devices instead of ratio
                            value: function (value, ratio, id) {
                                return value;
                            }
                        }
                    }
                });

                // If no drill through, show pointer cursor instead of hand
                if (!drillthroughEnabled) {
                    d3.select(idToBindTo).selectAll(".c3-arc").style("cursor", "auto");
                }

                if ($scope.brightness < 125) {
                    SetColorToAllTextInChart(idToBindTo, 'white');
                }

                $scope.$apply();
            }
        };

        $scope.createEmptyDonutChart = function (idToBindTo, chartTitle) {

            GetSummaryText(idToBindTo, chartTitle, null);

            c3.generate({
                bindto: idToBindTo,
                data: {
                    columns: [['', 1]],
                    type: 'donut',
                },
                interaction: {
                    enabled: false
                },
                color: {
                    pattern: ["#a9a9a9"]
                },
                legend: {
                    show: false
                },
                donut: {
                    label: {
                        format: function (value, ratio) {
                            return 0;
                        },
                    }
                },
                size: {
                    height: 235,
                    width: 235
                }
            });

            if ($scope.brightness < 125) {
                SetColorToAllTextInChart(idToBindTo, 'white');
            }

            $scope.$apply();
        }

        $scope.createHorizontalBarChart = function (idToBindTo, chartTitle, columns, padding) {

            var summaryText = "";
            var chart = document.querySelectorAll(idToBindTo);
            var chartEl = angular.element(chart);
            var tileEl = chartEl.parent();
            var str = [];

            columns.forEach(function (k, v) { str.push(k[0] + ": " + k[1] + ",  "); });
            summaryText = chartTitle + ". " + str.join("");

            var ariaLbl = document.getElementById("workloadTransitionAriaLbl");
            ariaLbl.setAttribute("aria-label", summaryText);

            c3.generate({
                bindto: idToBindTo,
                padding: {
                    left: padding
                },
                data: {
                    x: columns[0][0],
                    columns: columns,
                    type: 'bar'
                },
                axis: {
                    rotated: true,
                    x: {
                        type: 'category'
                    },
                    y: {
                        tick: {
                            format: function (x) { return x % 1 === 0 ? x : ''; }
                        }
                    }
                },
                legend: {
                    show: false
                },
                size: {
                    width: 845,
                    height: 245
                }
            });

            if ($scope.brightness < 125) {
                SetColorToAllTextInChart(idToBindTo, 'white');
            }

            $scope.$apply();
        };

        // generic function to create funnel chart
        $scope.createFunnelBarChart = function (id, chartTitle, data) {

            var chart = document.querySelectorAll(id);
            var chartEl = angular.element(chart);
            var tileEl = chartEl.parent();

            var keys = {};
            keys[0] = $scope.getString("EligibleDevices");
            keys[1] = $scope.getString("Scheduled");
            keys[2] = $scope.getString("Enrolling");
            keys[3] = $scope.getString("Enrolled");

            var str = [];
            data.forEach(function (k, v) { str.push(keys[v] + ": " + k[0] + ",  "); });
            var summaryText = chartTitle + ". " + str.join("");

            var ariaLbl = document.getElementById("funnel");
            ariaLbl.setAttribute("aria-label", summaryText);


            var chart = c3.generate({
                bindto: id,
                data: {
                    columns: [
                        ['data1.1', data[0] / 2],
                        ['data1.2', -data[0] / 2],
                        ['data2.1', data[1] / 2],
                        ['data2.2', -data[1] / 2],
                        ['data3.1', data[2] / 2],
                        ['data3.2', -data[2] / 2],
                        ['data4.1', data[3] / 2],
                        ['data4.2', -data[3] / 2]
                    ],
                    type: 'bar',
                    labels: {
                        format: function (value, ratio) {
                            if (value > 0) {
                                return 2 * value;
                            }
                        },
                    },
                    groups: [
                        ['data1.1', 'data1.2'], ['data2.1', 'data2.2'], ['data3.1', 'data3.2'], ['data4.1', 'data4.2']
                    ]
                },
                bar: {
                    zerobased: false,
                    width: 35
                },
                axis: {
                    rotated: true,
                    x: {
                        show: false
                    },
                    y: {
                        show: false
                    }
                },
                color: {
                    pattern: ['#ff8c00', '#ff8c00', '#9B4F96', '#9B4F96', '#2355be', '#2355be', '#41be23', '#41be23']
                },
                size: {
                    width: 350,
                    height: 200
                },
                tooltip: {
                    show: false
                },
                legend: {
                    show: false
                }
            });
        };

        function initDashboard() {

            LoadCoMgmtStatusFunnelChart();
            LoadCoMgmtEnrollStateChart();
            LoadWorkloadTransitionChart();
            LoadOSDistributionChart();
            LoadFailedEnrollmentsDetails();

            if ($scope.brightness < 125) {
                SetColorToAllHeaders('white');
            }
            else {
                SetColorToAllHeaders('black');
            }
        }

        function LoadCoMgmtStatusFunnelChart() {

            var enrolledCount = 0;
            var enrollingCount = 0;
            var scheduledCount = 0;
            var eligibleCount = 0;

            adminUI.sendNewRequest("GetChartData", JSON.stringify(['{}', "CC3FA376-BAB9-4F68-92E2-14CDB38E0F00"]), function (res, returnCode) {
                res = JSON.parse(res);
                if (res != null && res.length > 0) {
                    eligibleCount = res[0].EligibleCount;
                    scheduledCount = res[0].ScheduledCount;
                    enrollingCount = res[0].EnrollingCount;
                    enrolledCount = res[0].EnrolledCount;
                }

                $scope.createFunnelBarChart("#comgmtFunnelChart", $scope.getString("CoMgmtStatusChartTitle"), [eligibleCount, scheduledCount, enrollingCount, enrolledCount]);
            });
        }

        function LoadWorkloadTransitionChart() {

            var padding = CalculatePadding();
            $scope.createHorizontalBarChart("#workloadTransitionChart", $scope.getString("WorkloadTransitionChartTitle"), $scope.MDMWorkloadTransitionData, padding);
        }

        function LoadOSDistributionChart() {

            adminUI.sendNewRequest("GetChartData", JSON.stringify(['{}', "7C50A563-593A-4520-8B84-CCEDDD5B3B23"]), function (res, returnCode) {
                res = JSON.parse(res);

                if (res != null && res.length > 0) {
                    win10EligibleCount = res[0].Win101709AndAboveCount;
                    win10NotEligibleCount = res[0].Win10Lower1709Count;
                    otherOSCount = res[0].OtherOSCount;
                }

                var donutData = [[$scope.getString("Win10Eligible"), win10EligibleCount], [$scope.getString("Win10NotEligible"), win10NotEligibleCount], [$scope.getString("Win7"), otherOSCount]];
                var pattern = ["#79C21A", "#EBD23F", "#C00000"];
                $scope.createDonutChart("#win10VersionsChart", $scope.getString("WinOSChartTitle"), donutData, pattern, false);
            });
        }

        function LoadCoMgmtEnrollStateChart() {
            adminUI.sendNewRequest("GetChartData", JSON.stringify(['{}', "AEC51616-1476-4013-A985-E008127E2F67"]), function (res, returnCode) {
                res = JSON.parse(res);

                if (res != null && res.length > 0) {
                    hybridAADCount = res[0].HybridAADCount;
                    aadCount = res[0].AADCount;
                    enrollingHybridCount = res[0].EnrollingHybridCount;
                    hybridErrorCount = res[0].HybridErrorCount;
                    aadErrorCount = res[0].AADErrorCount;
                    pendingLogonCount = res[0].PendingLogonCount;
                }

                var donutData = [[$scope.getString("HybridAADSuccess"), hybridAADCount],
                [$scope.getString("AADSuccess"), aadCount],
                [$scope.getString("EnrollingHybrid"), enrollingHybridCount],
                [$scope.getString("HybridError"), hybridErrorCount],
                [$scope.getString("AADError"), aadErrorCount],
                [$scope.getString("PendingLogon"), pendingLogonCount]
                ];

                var pattern = ["#558ED5", "#5ED9FF", "#FF8C00", "#C00000", "#EC008C", "#63707E"];

                $scope.createDonutChart_long("#coMgmtEnrollStateChart", $scope.getString("CoMgmtEnrollStateChartTitle"), donutData, pattern, true);
            });
        }

        function LoadFailedEnrollmentsDetails() {

            // creates a <table> element and a <tbody> element
            var tbl = document.getElementById("errorList");
            var tblBody = document.createElement("tbody");

            adminUI.sendNewRequest("GetChartData", JSON.stringify(['{}', "73E24B93-5C63-422C-B2CF-4336D57FA7AA"]), function (res, returnCode) {
                // If no errors, display "No error to report." message
                if (res == null || res.length == 0) {
                    var row = document.createElement("tr");
                    var cell = document.createElement("td");
                    cell.tabIndex = 53;
                    cell.setAttribute("colspan", 2);
                    var cellText = document.createTextNode($scope.getString("NoErrors"));
                    cell.appendChild(cellText);
                    row.appendChild(cell);
                    tblBody.appendChild(row);
                }
                else {
                    res = JSON.parse(res);
                    var tabIndex = 54;
                    for (var i in res) {

                        var errorText = res[i].EnrollmentErrorDetail;
                        if (errorText == null || errorText == "") {
                            errorText = $scope.getString("Undefined");
                        }

                        var row = document.createElement("tr");

                        var cell_Count = document.createElement("td");
                        var cell_Error = document.createElement("td");
                        // Set style for cell_Error
                        cell_Error.style.textAlign = "left";
                        cell_Error.style.paddingLeft = "10px";
                        cell_Error.style.paddingRight = "10px";

                        cell_Count.tabIndex = tabIndex++;
                        cell_Error.tabIndex = tabIndex++;

                        var cell_Count_val = document.createTextNode(res[i].ClientsCount);
                        var cell_Error_val = document.createTextNode(errorText);

                        cell_Count.appendChild(cell_Count_val);
                        cell_Error.appendChild(cell_Error_val);

                        row.appendChild(cell_Count);
                        row.appendChild(cell_Error);

                        var createClickHandler = function (r) {
                            return function () {
                                var cell = r.getElementsByTagName("td")[1];
                                var errorTxt = cell.innerHTML;
                                adminUI.sendNewRequest("DrillThroughEnrollmentError",cell.innerHTML, null);
                            };
                        };

                        row.onclick = createClickHandler(row);

                        // add the row to the end of the table body
                        tblBody.appendChild(row);
                        tblBody.className = 'errorTblBoby';
                    }
                }
            });

            tbl.appendChild(tblBody);
        }

        function CalculatePadding() {

            var arr = $scope.MDMWorkloadTransitionData[0];
            var longest = arr.concat().sort(function (a, b) { return b.length - a.length; })[0];

            return longest.length + 95;
        }

        // Sets aria-label for accessibility
        function GetSummaryText(idToBindTo, chartTitle, chartData) {

            var chart = document.querySelectorAll(idToBindTo);
            var chartEl = angular.element(chart);
            var tileEl = chartEl.parent();

            if (chartData == null) {
                var summaryText = chartTitle + " 0.";   // TODO in 1902: set summary text to "Empty" or "No data"
            }
            else {
                var str = [];
                chartData.forEach(function (k, v) { str.push(k[0] + ": " + k[1] + ",  "); });
                var summaryText = chartTitle + ". " + str.join("");
            }

            tileEl.attr('aria-label', summaryText);
        }

        $scope.toggleWin10VersionDistributionChart = function() {
            var win10VersionDistributionTable = document.getElementById('win10VersionsTable');
            var win10VersionDistributionChart = document.getElementById('win10VersionsChart');
            var showWin10VersionDistributionChartButton = document.getElementById('showWin10VersionDistributionChartButton');

            if (win10VersionDistributionTable.style.display == 'none' || win10VersionDistributionTable.style.display == '') {
                var addFirstDivRow = appendUpdatedHtmlElement("14", $scope.getString("Version"), $scope.getString("Count"));
                win10VersionDistributionTable.replaceChild(addFirstDivRow, win10VersionDistributionTable.childNodes[1]);
                var addDivRow1 = appendUpdatedHtmlElement("16", $scope.getString("Win10Eligible"), win10EligibleCount);
                var addDivRow2 = appendUpdatedHtmlElement("18", $scope.getString("Win10NotEligible"), win10NotEligibleCount);
                var addDivRow3 =  appendUpdatedHtmlElement("20", $scope.getString("Win7"), otherOSCount);

                win10VersionDistributionTable.childNodes.length < 3 ? win10VersionDistributionTable.appendChild(addDivRow1) : win10VersionDistributionTable.replaceChild(addDivRow1, win10VersionDistributionTable.childNodes[2]);
                win10VersionDistributionTable.childNodes.length < 4 ? win10VersionDistributionTable.appendChild(addDivRow2) : win10VersionDistributionTable.replaceChild(addDivRow2, win10VersionDistributionTable.childNodes[3]);
                win10VersionDistributionTable.childNodes.length < 5 ? win10VersionDistributionTable.appendChild(addDivRow3) : win10VersionDistributionTable.replaceChild(addDivRow3, win10VersionDistributionTable.childNodes[4]);
                
                win10VersionDistributionTable.style.display = 'table';
                win10VersionDistributionChart.style.display = 'none';
                showWin10VersionDistributionChartButton.textContent = $scope.getString('ShowChart');
            }
            else if (win10VersionDistributionTable.style.display = 'table') {
                win10VersionDistributionTable.style.display = 'none';
                win10VersionDistributionChart.style.display = 'block';
                showWin10VersionDistributionChartButton.textContent = $scope.getString('ShowTable');
            }
        }

        $scope.toggleEnrollmentStatusChart = function () {
            var enrollmentStatusTable = document.getElementById('enrollmentStatusTable');
            var coMgmtEnrollStateChart = document.getElementById('coMgmtEnrollStateChart');
            var showEnrollmentStatusChartButton = document.getElementById('showEnrollmentStatusChartButton');

            if (enrollmentStatusTable.style.display == 'none' || enrollmentStatusTable.style.display == '') {
                
                var addFirstDivRow = appendUpdatedHtmlElement("35", $scope.getString("Version"), $scope.getString("Count"));
                enrollmentStatusTable.replaceChild(addFirstDivRow, enrollmentStatusTable.childNodes[1]);
                var addDivRow1 = appendUpdatedHtmlElement("37", $scope.getString("HybridAADSuccess"), hybridAADCount);
                var addDivRow2 = appendUpdatedHtmlElement("39", $scope.getString("AADSuccess"), aadCount);
                var addDivRow3 = appendUpdatedHtmlElement("41", $scope.getString("EnrollingHybrid"), enrollingHybridCount);
                var addDivRow4 = appendUpdatedHtmlElement("43", $scope.getString("HybridError"), hybridErrorCount);
                var addDivRow5 = appendUpdatedHtmlElement("45", $scope.getString("AADError"), aadErrorCount);
                var addDivRow6 = appendUpdatedHtmlElement("47", $scope.getString("PendingLogon"), pendingLogonCount);

                enrollmentStatusTable.childNodes.length < 3 ? enrollmentStatusTable.appendChild(addDivRow1) : enrollmentStatusTable.replaceChild(addDivRow1, enrollmentStatusTable.childNodes[2]);
                enrollmentStatusTable.childNodes.length < 4 ? enrollmentStatusTable.appendChild(addDivRow2) : enrollmentStatusTable.replaceChild(addDivRow2, enrollmentStatusTable.childNodes[3]);
                enrollmentStatusTable.childNodes.length < 5 ? enrollmentStatusTable.appendChild(addDivRow3) : enrollmentStatusTable.replaceChild(addDivRow3, enrollmentStatusTable.childNodes[4]);
                enrollmentStatusTable.childNodes.length < 6 ? enrollmentStatusTable.appendChild(addDivRow4) : enrollmentStatusTable.replaceChild(addDivRow4, enrollmentStatusTable.childNodes[5]);
                enrollmentStatusTable.childNodes.length < 7 ? enrollmentStatusTable.appendChild(addDivRow5) : enrollmentStatusTable.replaceChild(addDivRow5, enrollmentStatusTable.childNodes[6]);
                enrollmentStatusTable.childNodes.length < 8 ? enrollmentStatusTable.appendChild(addDivRow6) : enrollmentStatusTable.replaceChild(addDivRow6, enrollmentStatusTable.childNodes[7]);
                
                enrollmentStatusTable.style.display = 'table';
                coMgmtEnrollStateChart.style.display = 'none';
                showEnrollmentStatusChartButton.textContent = $scope.getString('ShowChart');
            }
            else if (enrollmentStatusTable.style.display = 'table') {
                enrollmentStatusTable.style.display = 'none';
                coMgmtEnrollStateChart.style.display = 'block';
                showEnrollmentStatusChartButton.textContent = $scope.getString('ShowTable');
            }
        }

        // launch property sheet to configure CoMgmt properties
        $scope.launchCoMgmtWizard = function () {
            try {
                adminUI.sendNewRequest("LaunchCoMgmtWizard", null, null);
            }
            catch (err) {
                console.log("launch CoMgmt Wizard failed");
            }
        }

        // Open Co-management Eligible Devices collection
        $scope.openCoMgmtEligibleDevicesCollection = function () {
            try {
                adminUI.sendNewRequest("OpenCoMgmtEligibleDevicesCollection", null, null);
            }
            catch (err) {
                console.log("Open CoMgmtEligibleDevices Collection failed");
            }
        }

        adminUI.sendNewRequest("userHasPermissionToConfigCoMgmt", null, function (response, returnCode)
        {
            $scope.userHasPermissionToConfigCoMgmt = response;
        });
    })
        .directive('dashboardChart', defineChartDirective);
}());
// SIG // Begin signature block
// SIG // MIIomwYJKoZIhvcNAQcCoIIojDCCKIgCAQExDzANBglg
// SIG // hkgBZQMEAgEFADB3BgorBgEEAYI3AgEEoGkwZzAyBgor
// SIG // BgEEAYI3AgEeMCQCAQEEEBDgyQbOONQRoqMAEEvTUJAC
// SIG // AQACAQACAQACAQACAQAwMTANBglghkgBZQMEAgEFAAQg
// SIG // TCugcm98gWYFljTxgVtLgPakuc9dQE1vRccsqL4Dtl6g
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
// SIG // ghpuMIIaagIBATCBlTB+MQswCQYDVQQGEwJVUzETMBEG
// SIG // A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
// SIG // ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
// SIG // MSgwJgYDVQQDEx9NaWNyb3NvZnQgQ29kZSBTaWduaW5n
// SIG // IFBDQSAyMDExAhMzAAAEhJjiEuB4ozFdAAAAAASEMA0G
// SIG // CWCGSAFlAwQCAQUAoIH3MBkGCSqGSIb3DQEJAzEMBgor
// SIG // BgEEAYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEE
// SIG // AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCCi4Echh6LCPrHG
// SIG // L8Im/9K78aPlljX1xODZfSozvCrtJjCBigYKKwYBBAGC
// SIG // NwIBDDF8MHqgXIBaAE0AaQBjAHIAbwBzAG8AZgB0AC4A
// SIG // VABvAG8AbABrAGkAdAAuAFcAcABmAC4AVQBJAC4AQwBv
// SIG // AG4AdAByAG8AbABzAC4AVwBlAGIAVgBpAGUAdwAuAGQA
// SIG // bABsoRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
// SIG // BgkqhkiG9w0BAQEFAASCAQAi6kpeAJr5t2PIsVzJkqzi
// SIG // VuZC0WBifgLNpUiZhwsKSY8FN/8fOl8zqTyP4+6NTQg4
// SIG // 0jgvtxqVAsK/G7cV3QPGLv7bHBZCSLmdMlvuOQ5qh9qB
// SIG // 9WVIJYoVLDgdM2/WhBVw7SBGEy/ivuPeYcQgqkH36s7d
// SIG // ggQTjip4XV37FCYrf6JAuQ7XM1DUF6xNhfMg6L6SQQcy
// SIG // mb9faF+ixPegsWBwOUiF/KU68DMR2HFNVxTgK32FyWZH
// SIG // f+0SczlLAlOXxHMZE750AZuxYPg+lYE0Nqgc0z4XirHS
// SIG // Ib9d77CLT3nO6Vd8aKCbTuFfmNoXHGpfvpp9yqmrBBmm
// SIG // r/FKMKpVRFjsoYIXrzCCF6sGCisGAQQBgjcDAwExgheb
// SIG // MIIXlwYJKoZIhvcNAQcCoIIXiDCCF4QCAQMxDzANBglg
// SIG // hkgBZQMEAgEFADCCAVoGCyqGSIb3DQEJEAEEoIIBSQSC
// SIG // AUUwggFBAgEBBgorBgEEAYRZCgMBMDEwDQYJYIZIAWUD
// SIG // BAIBBQAEID9thuoljhRiB1IQcyIvZTFZygiE9Be2IsaD
// SIG // dHNjjon8AgZo8n1NK3AYEzIwMjUxMDIzMDI0NzQ3Ljg0
// SIG // NVowBIACAfSggdmkgdYwgdMxCzAJBgNVBAYTAlVTMRMw
// SIG // EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
// SIG // b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
// SIG // b24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9w
// SIG // ZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNoaWVs
// SIG // ZCBUU1MgRVNOOjU1MUEtMDVFMC1EOTQ3MSUwIwYDVQQD
// SIG // ExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloIIR
// SIG // /TCCBygwggUQoAMCAQICEzMAAAIb0LK4Amf3cs8AAQAA
// SIG // AhswDQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMx
// SIG // EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
// SIG // ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
// SIG // dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3Rh
// SIG // bXAgUENBIDIwMTAwHhcNMjUwODE0MTg0ODMwWhcNMjYx
// SIG // MTEzMTg0ODMwWjCB0zELMAkGA1UEBhMCVVMxEzARBgNV
// SIG // BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
// SIG // HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEt
// SIG // MCsGA1UECxMkTWljcm9zb2Z0IElyZWxhbmQgT3BlcmF0
// SIG // aW9ucyBMaW1pdGVkMScwJQYDVQQLEx5uU2hpZWxkIFRT
// SIG // UyBFU046NTUxQS0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1p
// SIG // Y3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0G
// SIG // CSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCOxZ3nZlmT
// SIG // MHld7mD+XYaw6MDPfSyDqNXF8UlX7DjEgNXJojcs7xsi
// SIG // mbNi6XcBkeDnRQhDw+tJFkalCoWRE276jdgoniDa4ZgF
// SIG // GSwecdhHS5VIJCDnxOGRjJ6mUZfegC8ZFW48ilC0CJOx
// SIG // HvoD+B2hTscPARtvvdsnBPKtsoeFH5ZozL0NAcjiTlCj
// SIG // j5tkOzSSPvpu+Em90ZT5LzPFAGntQCGMmcWorEi6xIhM
// SIG // TvMIJHjbYQuGSFVU4WorbDqHUwC8gt7vqHFEhw+PRIEv
// SIG // avw723HmeNTj62DasB1TXnembKGprN2lRxxgET3ANEVR
// SIG // 3970KhbHtN2dSJwH4xqLtFPqqx7t7loapfUHtueP9ke+
// SIG // ut8X4EkQiVL2INcBSB6S9dn4VmaO8vA/5037T9yuH76v
// SIG // h7wWScXsRfogl+eY14M3/rxnn2RtonV/4/macph/J0J5
// SIG // mbGsalLS1paQOTfoPeM9Vl+W/Gtz7WuEIiUzm/1qAsQU
// SIG // jXZCIFN+k4E4GvcAYI+T54fT6Vq2NBqO6D7b8EPXapvz
// SIG // bnTQtDK1RZPai1r8didGBK/WO9nT92aXUWzFZjM6cKuN
// SIG // 90H/s3qk3JK3i+f48Y3p0UuKbuTGiz4H1Z9A97MmLd+4
// SIG // rLIMAH3NIc+PVm7ydl95xkn26bjOPsMWC8ldMNOcbmqU
// SIG // bhl1sVFr+ut/OQIDAQABo4IBSTCCAUUwHQYDVR0OBBYE
// SIG // FLa+n3f+XEumk0rw6Rq4nYC82YhQMB8GA1UdIwQYMBaA
// SIG // FJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYw
// SIG // VKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9w
// SIG // a2lvcHMvY3JsL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAl
// SIG // MjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRg
// SIG // MF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9z
// SIG // b2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIw
// SIG // VGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwG
// SIG // A1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUH
// SIG // AwgwDgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUA
// SIG // A4ICAQBmRTVfFAPg5MzcZOG3fZNdKEh88Ggx9KwWwFCo
// SIG // U5mosk7HIk6WUgEWmam860Y0+QLlnyV0bxoKm+AU2j+M
// SIG // NZ5PkWJbnd0CP0qdnGmxDc9/l9HNIYdFzEQw51chXMMn
// SIG // BxlRfRyN/GdrvJ02/x5cH9eTobpLKtHY4fpLUscxbXWb
// SIG // dS8oX54uMg+XjmvGKa4MKgR35p3SU4BcDn+9k4o3mf94
// SIG // 9h4/QtFyFlfRDofyf9mZI8yVuWLcw7znVDT1GZP9kYdr
// SIG // 78V3L5YsOvBxjKRX2ZTL/hNvArDoW11Hpk8fEx0iLWmT
// SIG // xjaYL8bMKrQsKwfS5MV5DpDs1zcxGYRH/eYtZSFtpYeB
// SIG // fUVthyG9HbZv4G6n5g9HlD/QGFpoA3oAgF9waz67+cmg
// SIG // gHLJkoDxxPIKadQj/i9boPi/LCDdcEV/h/YPAUfL96+w
// SIG // L7nwoyX6TbBrTlfaQrRP9sI8uFqi/1lfKhtrB804tgaJ
// SIG // q4pPYVa9vBnMcgUJPGMHDDo+3m5G8IT+OdRx//GGU4Yy
// SIG // fqIo71e3j29lMTZJ8gGT/fiItNEEnoftoY9NNCfNrc59
// SIG // a7X91HJwLpaXmiezc+OcZdNIpLFeWUk+aDpH+6Uaic/9
// SIG // QJignqY34ReN/IMs9cuqyv3X5VMbWtjNEKM/AEUAe/gQ
// SIG // jBoTRqMKt/vl5QYjf6hdTRQ/quWhnzCCB3EwggVZoAMC
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
// SIG // BRDBcQZqELQdVTNYs6FwZvKhggNYMIICQAIBATCCAQGh
// SIG // gdmkgdYwgdMxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
// SIG // YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
// SIG // VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNV
// SIG // BAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMg
// SIG // TGltaXRlZDEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNO
// SIG // OjU1MUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3Nv
// SIG // ZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4D
// SIG // AhoDFQCGhXqvj0zgYF3jUrVFgHVnR/jO4KCBgzCBgKR+
// SIG // MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5n
// SIG // dG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
// SIG // aWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1p
// SIG // Y3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqG
// SIG // SIb3DQEBCwUAAgUA7KOSxjAiGA8yMDI1MTAyMjE3Mjgz
// SIG // OFoYDzIwMjUxMDIzMTcyODM4WjB2MDwGCisGAQQBhFkK
// SIG // BAExLjAsMAoCBQDso5LGAgEAMAkCAQACAW0CAf8wBwIB
// SIG // AAICEtgwCgIFAOyk5EYCAQAwNgYKKwYBBAGEWQoEAjEo
// SIG // MCYwDAYKKwYBBAGEWQoDAqAKMAgCAQACAwehIKEKMAgC
// SIG // AQACAwGGoDANBgkqhkiG9w0BAQsFAAOCAQEAGho0RcM/
// SIG // BoGqYD/t3w9biTFIwXGX0td2Sgins2CQZdiOlynitKzJ
// SIG // 5ZTd5XhArwKasBkWi9EbX0qkTqTtMyI9DLmYRDucLmNg
// SIG // d/giEuSOet/eKP2Wqcpbc96SUGZIPyynQVRKVA+yyirW
// SIG // kduXpzwSHpmIvvEgzPVqzU9seONBkoYYaA4pHGLt+c9P
// SIG // SX9gsEod0LA0kyzMSSo2MIO+KL/op2s/ONd2pqQsdY9O
// SIG // nwhf0oKOdR1cYiWr9hal6zl6xkFlyhbWzuCZATRW95h+
// SIG // wQ1pDJg/h7nQErDnany7CJPgjEx9WX1ABhEmx+iNznyw
// SIG // TFw+o2cUUEGV0Qst15PYvO8BozGCBA0wggQJAgEBMIGT
// SIG // MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5n
// SIG // dG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
// SIG // aWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1p
// SIG // Y3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAAC
// SIG // G9CyuAJn93LPAAEAAAIbMA0GCWCGSAFlAwQCAQUAoIIB
// SIG // SjAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJ
// SIG // KoZIhvcNAQkEMSIEIPPJhyPRQYsXN3RHPzuQWR6nhJ2v
// SIG // VDDWATJ0NsWu8OjrMIH6BgsqhkiG9w0BCRACLzGB6jCB
// SIG // 5zCB5DCBvQQgMCUUlbg9o5jHEAhV3S7iQMA6VFTWem3O
// SIG // nXyVPN0Ni4AwgZgwgYCkfjB8MQswCQYDVQQGEwJVUzET
// SIG // MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
// SIG // bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
// SIG // aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFt
// SIG // cCBQQ0EgMjAxMAITMwAAAhvQsrgCZ/dyzwABAAACGzAi
// SIG // BCBUkprOMBrPIL/n0T1L4HR/JCuzc2g/raQ1CN3ZBcWB
// SIG // AzANBgkqhkiG9w0BAQsFAASCAgAYt21W9Eu4RVfXyBsq
// SIG // Y4f5xId9y/+a1cGa6cjIlj3xaIcy6eekZs4uxAkqRcXl
// SIG // kphiX2noSVVYrIVmm7YRV9mQP5O2yIXLzY6ujgN9M8MX
// SIG // tShYWnv2K4exPZ7hfkHmU/Uq5SsLerudZS+6/TA+o7Zl
// SIG // XMwqC8Kwyw7m/m+8tlEjOKJT5y+xQPhEmwQw0RDD3sd6
// SIG // 5AIq0TYX/bTJ4WGQi/Hg/B5G1K+0G36UVvxdT//9E39F
// SIG // IBTU5lin7T3C5HTqQA60fQSiFWJHhS2xYxmsrrZ/+Q8e
// SIG // fM7nSX1KlAQnxmtLE8uQyE3rS09MNz5CmWxEifRxEHFj
// SIG // 25HN1kqHtUE+Wjg3QL4yNLwbJ7zDAZ0aUOY1p8MXNrVr
// SIG // ZS8J20hwhFEbfY30pZyFPMemZOYpdXnt4liaPp1ALKKg
// SIG // AZUZN3+6BTV4IGjUMnwBxcQAJd95z0Hnvu9SVNTyAb8Y
// SIG // OK7OZeGG4NMcOJKqjEVTbB44BDUsPvont3qy06byafmo
// SIG // cIc13snJ1XUPV5QY9PiISN9rUEouf4qTgZiD6PHAYWIh
// SIG // E7RElo71dGW4d79f+qcyB6j7X0U6kXJnK1M/hwSuMv7l
// SIG // YCccslakEMMLFNtL0Ksss7IW/ReDDgv9DIFAsHmdc0Bd
// SIG // RckBZsTUEf3vvnu4YOLdmSqbpjuS3mr7QQ8Sdx71rYMq
// SIG // dUhbUQ==
// SIG // End signature block
