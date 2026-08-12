(function () {
    "use strict";

    var dashboard = angular.module("dashboard", []);

    var OsVersionDistributionTableData = "";
    var EnrollmentStatusTableData = "";

    dashboard.controller("dashboardController", function ($scope, $sce) {

        $scope.CoMgmtChartState = ChartState.Loading;

        adminUI.initializeController($scope, function () {

            document.getElementById("memacContainer").innerHTML = $scope.getHtmlString('MemacString');

            adminUI.sendNewRequest("GetWorkloadTransitionCount", null, function callback(response, returnCode) {

                $scope.MDMWorkloadTransitionData = JSON.parse(response);
                initDashboard();
            });
        });

        $scope.getString = function (stringName) {

            return $scope.strings[stringName];
        };

        $scope.getHtmlString = function (stringName) {
            var htmlString = $scope.strings[stringName];
            return $sce.trustAsHtml(htmlString);
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
                var win10EligibleCount = 0;
                var win10NotEligibleCount = 0;
                var otherOSCount = 0;

                if (res != null && res.length > 0) {
                    win10EligibleCount = res[0].Win101709AndAboveCount;
                    win10NotEligibleCount = res[0].Win10Lower1709Count;
                    otherOSCount = res[0].OtherOSCount;
                }

                var tabidx = 16;
                OsVersionDistributionTableData = 
                    "<div class=\"row\">" +
                    "<div class=\"cell\" tabindex=\"" + tabidx++ + "\">" + $scope.getString("Win10Eligible") + "</div>" +
                    "<div class=\"cell\" tabindex=\"" + tabidx++ + "\">" + win10EligibleCount + "</div>" +
                    "</div>" +
                    "<div class=\"row\">" +
                    "<div class=\"cell\" tabindex=\"" + tabidx++ + "\">" + $scope.getString("Win10NotEligible") + "</div>" +
                    "<div class=\"cell\" tabindex=\"" + tabidx++ + "\">" + win10NotEligibleCount + "</div>" +
                    "</div>" +
                    "<div class=\"row\">" +
                    "<div class=\"cell\" tabindex=\"" + tabidx++ + "\">" + $scope.getString("Win7") + "</div>" +
                    "<div class=\"cell\" tabindex=\"" + tabidx++ + "\">" + otherOSCount + "</div>" +
                    "</div>";

                var donutData = [[$scope.getString("Win10Eligible"), win10EligibleCount], [$scope.getString("Win10NotEligible"), win10NotEligibleCount], [$scope.getString("Win7"), otherOSCount]];
                var pattern = ["#79C21A", "#EBD23F", "#C00000"];
                $scope.createDonutChart("#win10VersionsChart", $scope.getString("WinOSChartTitle"), donutData, pattern, false);
            });
        }

        function LoadCoMgmtEnrollStateChart() {
            adminUI.sendNewRequest("GetChartData", JSON.stringify(['{}', "AEC51616-1476-4013-A985-E008127E2F67"]), function (res, returnCode) {
                res = JSON.parse(res);
                var hybridAADCount = 0;
                var aadCount = 0;
                var enrollingHybridCount = 0;
                var hybridErrorCount = 0;
                var aadErrorCount = 0;
                var pendingLogonCount = 0;

                if (res != null && res.length > 0) {
                    hybridAADCount = res[0].HybridAADCount;
                    aadCount = res[0].AADCount;
                    enrollingHybridCount = res[0].EnrollingHybridCount;
                    hybridErrorCount = res[0].HybridErrorCount;
                    aadErrorCount = res[0].AADErrorCount;
                    pendingLogonCount = res[0].PendingLogonCount;
                }

                var tabidx = 37;
                EnrollmentStatusTableData =
                    "<div class=\"row\">" +
                    "<div class=\"cell\" tabindex=\"" + tabidx++ + "\">" + $scope.getString("HybridAADSuccess") + "</div>" +
                    "<div class=\"cell\" tabindex=\"" + tabidx++ + "\">" + hybridAADCount + "</div>" +
                    "</div>" +
                    "<div class=\"row\">" +
                    "<div class=\"cell\" tabindex=\"" + tabidx++ + "\">" + $scope.getString("AADSuccess") + "</div>" +
                    "<div class=\"cell\" tabindex=\"" + tabidx++ + "\">" + aadCount + "</div>" +
                    "</div>" +
                    "<div class=\"row\">" +
                    "<div class=\"cell\" tabindex=\"" + tabidx++ + "\">" + $scope.getString("EnrollingHybrid") + "</div>" +
                    "<div class=\"cell\" tabindex=\"" + tabidx++ + "\">" + enrollingHybridCount + "</div>" +
                    "</div>" +
                    "<div class=\"row\">" +
                    "<div class=\"cell\" tabindex=\"" + tabidx++ + "\">" + $scope.getString("HybridError") + "</div>" +
                    "<div class=\"cell\" tabindex=\"" + tabidx++ + "\">" + hybridErrorCount + "</div>" +
                    "</div>" +
                    "<div class=\"row\">" +
                    "<div class=\"cell\" tabindex=\"" + tabidx++ + "\">" + $scope.getString("AADError") + "</div>" +
                    "<div class=\"cell\" tabindex=\"" + tabidx++ + "\">" + aadErrorCount + "</div>" +
                    "</div>" +
                    "<div class=\"row\">" +
                    "<div class=\"cell\" tabindex=\"" + tabidx++ + "\">" + $scope.getString("PendingLogon") + "</div>" +
                    "<div class=\"cell\" tabindex=\"" + tabidx++ + "\">" + pendingLogonCount + "</div>" +
                    "</div>";

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

                win10VersionDistributionTable.innerHTML =
                    "<div class=\"row\">" +
                        "<div class=\"cell\" tabindex=\"14\">Version</div>" +
                        "<div class=\"cell\" tabindex=\"15\">Count</div>" +
                    "</div>";

                win10VersionDistributionTable.innerHTML += OsVersionDistributionTableData;
                win10VersionDistributionTable.style.display = 'table';
                win10VersionDistributionChart.style.display = 'none';
                showWin10VersionDistributionChartButton.innerHTML = $scope.getString('ShowChart');
            }
            else if (win10VersionDistributionTable.style.display = 'table') {
                win10VersionDistributionTable.style.display = 'none';
                win10VersionDistributionChart.style.display = 'block';
                showWin10VersionDistributionChartButton.innerHTML = $scope.getString('ShowTable');
            }
        }

        $scope.toggleEnrollmentStatusChart = function () {
            var enrollmentStatusTable = document.getElementById('enrollmentStatusTable');
            var coMgmtEnrollStateChart = document.getElementById('coMgmtEnrollStateChart');
            var showEnrollmentStatusChartButton = document.getElementById('showEnrollmentStatusChartButton');

            if (enrollmentStatusTable.style.display == 'none' || enrollmentStatusTable.style.display == '') {

                enrollmentStatusTable.innerHTML =
                    "<div class=\"row\">" +
                    "<div class=\"cell\" tabindex=\"35\">Version</div>" +
                    "<div class=\"cell\" tabindex=\"36\">Count</div>" +
                    "</div>";

                enrollmentStatusTable.innerHTML += EnrollmentStatusTableData;
                enrollmentStatusTable.style.display = 'table';
                coMgmtEnrollStateChart.style.display = 'none';
                showEnrollmentStatusChartButton.innerHTML = $scope.getString('ShowChart');
            }
            else if (enrollmentStatusTable.style.display = 'table') {
                enrollmentStatusTable.style.display = 'none';
                coMgmtEnrollStateChart.style.display = 'block';
                showEnrollmentStatusChartButton.innerHTML = $scope.getString('ShowTable');
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
// SIG // MIInywYJKoZIhvcNAQcCoIInvDCCJ7gCAQExDzANBglg
// SIG // hkgBZQMEAgEFADB3BgorBgEEAYI3AgEEoGkwZzAyBgor
// SIG // BgEEAYI3AgEeMCQCAQEEEBDgyQbOONQRoqMAEEvTUJAC
// SIG // AQACAQACAQACAQACAQAwMTANBglghkgBZQMEAgEFAAQg
// SIG // kBesRBKP5I93XyrWjaKcDXBN/SWhfxNIdD9+rT57azGg
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
// SIG // ARUwLwYJKoZIhvcNAQkEMSIEIPWJR2/OjJT4YWkQVRxk
// SIG // wvPO1iMg54G4MWY8akIV0W4SMEIGCisGAQQBgjcCAQwx
// SIG // NDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRw
// SIG // Oi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEB
// SIG // BQAEggEANtD8ofO9r0TxWvn9q9SrVgCT/1VpX1leYWCy
// SIG // FHs+VmPmrX/8Ex0zYLYWWxM42Np3ChEF3HXON8X4yNsX
// SIG // ctmP1lrBcblXbmvevSgkVY0iriGfTF5UBNny8w6QYJ+9
// SIG // 0Zpbj3Pyl25fndmBKZYrzkwj6hA+x05IikbqZJLcAJ5/
// SIG // DfR1lU53sy1JOw43H/LyrkA+lSlTJ0KU8YdUrNzzeOB5
// SIG // XPOjnWJZXSKHbUnNkZJHq/tz3pI6zGf/NeiL6IWXspaq
// SIG // AdV0L0S50BLwFmY4l4P93gxWQC4KzHq+PFOVMsYNZ67B
// SIG // HQtzXknAsrRa1Rg8vjkqJRsFADCxZn/wGcm0+ir8yqGC
// SIG // FywwghcoBgorBgEEAYI3AwMBMYIXGDCCFxQGCSqGSIb3
// SIG // DQEHAqCCFwUwghcBAgEDMQ8wDQYJYIZIAWUDBAIBBQAw
// SIG // ggFZBgsqhkiG9w0BCRABBKCCAUgEggFEMIIBQAIBAQYK
// SIG // KwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCCu9+G4
// SIG // qC39mk+dVGNxwe26YMUeAoxm9Z5kxPFsiV5a0gIGY2Pf
// SIG // aYIFGBMyMDIyMTEwNDE3MjM0My44ODZaMASAAgH0oIHY
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
// SIG // IgQg7EgopfLmBvVSc86uckNA3BhN/uQ2CyiqgVcK8wnh
// SIG // pNIwgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCBk
// SIG // 60bO8W85uTAfJVEO3vX2aLaQFcgcGpdwsOoi+foP9DCB
// SIG // mDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
// SIG // YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
// SIG // VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNV
// SIG // BAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEw
// SIG // AhMzAAABufYADWVUT7wDAAEAAAG5MCIEIEpB3xr7eyxp
// SIG // TDMMf8hGiLLzDeIEhxmj1CIruH9UfJ8sMA0GCSqGSIb3
// SIG // DQEBCwUABIICAJgjXKg9hWrVyfGqFyo3KuwijmUNCheO
// SIG // NLbR1OlRhRSH9UdNBDrIoPLuG7gwavsHaXYbVpDbzMGP
// SIG // qxZM3nsXDceSl8VsGm1snxpHh4Bb2FybvJ65YhKhlyDs
// SIG // Nc1GkJbsAeR0cRlNFy98IuDzRHFRqn0Kpqk5pW6sH9KO
// SIG // g1OiPccYvS5YJTXL1JRW3gsPUEE6x4FqvtQAXd4ZKpxy
// SIG // 7LH4/cf7kQk5m8tNeNWmiLeSvuqyypemk1S86Zkuvqs7
// SIG // FS33M3Fk2uHVjXqzsCUrRqemxTtGKoI2B9WzbGGe7rRj
// SIG // QplZ9Cd7jH8U3jsgkZkviB8ZkOWiXARjXN9LpSHYwTVm
// SIG // Nffuk7iGDotL4ozyIwb0bKPQdYUlbZzNUTJGngXSgv9B
// SIG // a3B/S3kxYrdr5+j1FhTmtpXd97My850utoiegcwQ0O/i
// SIG // BZ27hoqngtynEz9lcuFjTs4h+1AYuBB2mVkY+xY32NZj
// SIG // YMuhEhd+i1NEJSljN2Bx2sODmf1VmiP5E5OMPkbD/PYG
// SIG // gn6HWcTaWty+j7sROXtD0L8LhyWVYqrcLGRMYb7lrdRs
// SIG // PxIAfSJLKsQCkg+bHpZlyCbHPyUijsVDJAeEmzbcqJYC
// SIG // 8axFu/gTjpsBopp75tBUg7gW5XxfWcWQbWqB97wXSWBv
// SIG // Jen1GRlMWSfkx7h2bWwM0WbpbkJiqK/Y4n0n
// SIG // End signature block
