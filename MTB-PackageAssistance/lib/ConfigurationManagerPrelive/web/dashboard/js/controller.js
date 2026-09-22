/// <dictionary target='parameter'>sce</dictionary>
/// <dictionary target='member'>bindto</dictionary>
/// <dictionary>bindto,sce</dictionary>

(function () {
    "use strict";

    var dashboard = angular.module("dashboard", []);

    dashboard.controller("dashboardController", function ($scope, $sce) {
        $scope.ChartState = ChartState; // for use in ng-expressions in html
        $scope.CollectionsData = ChartState.Loading;
        $scope.barChartData = ChartState.Loading;
        $scope.lineGraphData = ChartState.Loading;
        $scope.donutBuildData = ChartState.Loading;
        $scope.donutQualityData = ChartState.Loading;
        $scope.gaugeChartData = ChartState.Loading;

        // *** VARIABLE DECLARATIONS
        var COLL_DISP_LIMIT = 5; // determines the amount of collections displayed in the dropdown filter
        $scope.SMS_DeviceCollections = {}; //temp storage for collections data
        var W10FeaturesTable = "W10FeaturesTable"
        var W10QualityTable = "W10FQualityTable"

        adminUI.initializeController($scope, async function () {
            //Load static data to be used in controller
            await LoadDataAysnc();

            // *** DATA QUERIES AND PREPARATION ***
            //gets collections data to load the Collections dropdown filter
            adminUI.wmiQuery("SELECT CollectionID, Name, MemberCount FROM SMS_Collection Where CollectionType=2 ORDER BY LocalMemberCount DESC",
                SMS_DeviceCollectionsReceived);
        });

        function SMS_DeviceCollectionsReceived(res) {
            res = JSON.parse(res);

            if (res.length == 0) {
                logger.err("SMS_Collection returned no results");
                $scope.CollectionsData = ChartState.NoDataFound;
                $scope.$apply();
                return;
            }

            // store first n number of results n = COLL_DISP_LIMIT and set default selected to first(largest) collection
            $scope.SMS_DeviceCollections.All = res.slice(0, COLL_DISP_LIMIT);
            $scope.SMS_DeviceCollections.Selected = res[0];

            for (var i = 0; i < $scope.SMS_DeviceCollections.All.length; ++i) {
                callMethod("GetCollectionAliasName", $scope.SMS_DeviceCollections.All[i].Name, function callback(response, returnCode) {
                    $scope.SMS_DeviceCollections.All[i].Name = JSON.parse(response);
                });
            }

            $scope.CollectionsData = ChartState.DataReady;
            $scope.SMS_DeviceCollectionChanged();

            $scope.$apply();
        };

        async function LoadDataAysnc() {
            //Load Data
            await callMethodAsync("LoadData", null);
            
            //IsSetupDiagChartReady
            $scope.isSetupDiagChartReady = await callMethodAsync("IsSetupDiagChartReady", null) === 'True';

            $scope.setupAria();
        };

        //Get Win Chart Data
        async function getWin10Data(collection) {
            var collID = collection.CollectionID;
            var collName = collection.Name;
            await callMethodAsync("Filter", collID);

            var barChartDeviceCounts = await callJsonParseMethodAsync("GetBarChartDeviceCounts", null);

            var barChartErrorNames = await callJsonParseMethodAsync("GetBarChartErrorNames", null);

            var lineGraphTimes = [6, 5, 4, 3, 2, 1, 0];
            var lineGraphColors = ["#00b7c3", "#69797e", "#8378de", "#ffaa44", "#038387"];

            var lineGraphData = await callJsonParseMethodAsync("GetLineGraphData", collID);

            var lineGraphLines = [];

            $scope.donutBuildData = await callJsonParseMethodAsync("GetDonutBuildData", collID);

            $scope.donutQualityData = await callJsonParseMethodAsync("GetDonutQualityData", collID);

            $scope.gaugeChartData = await callJsonParseMethodAsync("GetGaugeChartData", collID);

            var win11GaugeChartData = await callJsonParseMethodAsync("GetWin11GaugeChartData", collID);

            var usageColors = ["#bd0026", "#fd8d3c", "#ffffb2", "#253494", "#41b6c4", "#756bb1", "#df65b0", "#c2e699", "#006837", "#969696"];
            $scope.createDonutChart("#W10-usage", $scope.donutBuildData, $scope.strings.W10Usage, usageColors);
            $scope.createTable(W10FeaturesTable, $scope.donutBuildData);
            var qualityColors = ["#bd0026", "#fd8d3c", "#ffffb2", "#253494", "#41b6c4", "#756bb1", "#df65b0", "#c2e699", "#006837", "#969696"];
            $scope.createDonutChart("#W10-quality", $scope.donutQualityData, $scope.strings.W10Quality, qualityColors);
            $scope.createTable(W10QualityTable, $scope.donutQualityData);
            $scope.createGaugeChart("#W10-latest", $scope.gaugeChartData, $scope.strings.W10 + $scope.strings.W10LatestFeatureUpdate);
            $scope.createGaugeChart("#W11-latest", win11GaugeChartData, $scope.strings.W11 + $scope.strings.W10LatestFeatureUpdate);
            $scope.createBarChart(collID, collName, barChartErrorNames, barChartDeviceCounts, "#CollectionErrors", "#2c5fb0", $scope.strings.CollectionErrors);

            lineGraphData.forEach(function (el) {
                lineGraphLines.push([el.ErrorCode, Number(el.ErrorCount7), Number(el.ErrorCount6), Number(el.ErrorCount5), Number(el.ErrorCount4), Number(el.ErrorCount3), Number(el.ErrorCount2), Number(el.ErrorCount1) + Number(el.ErrorCount2)]);
            });
            $scope.createLineGraph(lineGraphLines, "#ErrorsTimeline", lineGraphColors, lineGraphTimes, $scope.strings.ErrorsTimeline);

            if ($scope.brightness < 125) {
                SetColorToAllTextInChart("#W10-usage", $scope.theme.ForeGroundColor);
                SetColorToAllTextInChart("#W10-quality", $scope.theme.ForeGroundColor);
                SetColorToAllTextInChart("#W10-latest", $scope.theme.ForeGroundColor);
                SetColorToAllTextInChart("#W11-latest", $scope.theme.ForeGroundColor);
                SetColorToAllTextInChart("#ErrorsTimeline", $scope.theme.ForeGroundColor);
                SetColorToAllTextInChart("#CollectionErrors", $scope.theme.ForeGroundColor);
            }
            $scope.$apply();

        };

        //*** DOM CHANGE HANDLERS
        // handle collection dropdown selection
        $scope.SMS_DeviceCollectionChanged = function () {
            $scope.barChartData = ChartState.Loading;
            $scope.lineGraphData = ChartState.Loading;
            $scope.donutBuildData = ChartState.Loading;
            $scope.donutQualityData = ChartState.Loading;
            $scope.gaugeChartData = ChartState.Loading;
            getWin10Data($scope.SMS_DeviceCollections.Selected);
        };

        /*** Donut Chart Data Table ***/
        $scope.toggleFeatureDonutChart = function () {
            $scope.toggleDonutChart(W10FeaturesTable);
        }

        $scope.toggleQualityDonutChart = function () {
            $scope.toggleDonutChart(W10QualityTable);
        }

        $scope.toggleDonutChart = function (w10ChartIdentifier) {
            var w10Table;
            var w10Chart;
            var showChartButton;

            if (w10ChartIdentifier == W10FeaturesTable) {
                w10Table = document.getElementById('windows-usage-table');
                w10Chart = document.getElementById('W10-usage');
                showChartButton = document.getElementById('showW10UsageChartButton');
            }
            else if (w10ChartIdentifier == W10QualityTable) {
                w10Table = document.getElementById('windows-quality-table');
                w10Chart = document.getElementById('W10-quality');
                showChartButton = document.getElementById('showW10QualityChartButton');
            }

            if (w10Table.style.display == 'none' || w10Table.style.display == '') {
                w10Table.style.display = 'table';
                w10Chart.style.display = 'none';
                showChartButton.textContent = $scope.strings.ShowChart;
            }
            else if (w10Table.style.display = 'table') {
                w10Table.style.display = 'none';
                w10Chart.style.display = 'block';
                showChartButton.textContent = $scope.strings.ShowTable;
            }
        }

        $scope.createTable = function (w10ChartIdentifier, data) {
            var table;
            var tableName;

            if (w10ChartIdentifier == W10FeaturesTable) {
                table = document.getElementById("windows-usage-table");
                tableName = $scope.strings.W10Usage;
            }
            else if (w10ChartIdentifier == W10QualityTable) {
                table = document.getElementById("windows-quality-table");
                tableName = $scope.strings.W10Quality;
            }
            table.textContent = ""; //Set data to null in case it exists
            $scope.appendChildItem(table, tableName, $scope.strings.NumberOfDevices);

            data.forEach(function (k, v) {
                $scope.appendChildItem(table, k[0], k[1]);
            });
        }

        // Append rows to corresponding table
        $scope.appendChildItem = async function (table, item, count) {
            var div = 'div';
            var row = 'row';

            // create new div element
            var addDiv = document.createElement(div);
            addDiv.className = row;

            //Add Windows Version and Count

            var windowVersion = document.createElement(div);
            windowVersion.className = 'cell';
            windowVersion.textContent = item;

            var noOfDevices = document.createElement(div);
            noOfDevices.className = 'cell';
            noOfDevices.textContent = count;

            addDiv.appendChild(windowVersion);
            addDiv.appendChild(noOfDevices);

            table.appendChild(addDiv);
        };

        // launch wizard to pick a collection
        $scope.LaunchWizardCollectionPicker = async function () {
            try {
                //Collection is a string
                var collection = await callMethodAsync("LaunchWizardCollectionPicker", null);

                //get get collection object
                adminUI.wmiQuery("SELECT CollectionID, Name, MemberCount FROM SMS_Collection Where CollectionType=2 and CollectionID='" + collection + "'", function (res) {
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

                        callMethod("GetCollectionAliasName", $scope.SMS_DeviceCollections.All[0].Name, function callback(response, returnCode) {
                            $scope.SMS_DeviceCollections.All[0].Name = response;
                        });

                        // Only COLL_DISP_LIMIT items at a time should show in the drop down
                        if ($scope.SMS_DeviceCollections.All.length > COLL_DISP_LIMIT) {
                            $scope.SMS_DeviceCollections.All.pop();
                        }
                    }
                    // Update the selected item in the dropdown 
                    $scope.SMS_DeviceCollections.Selected = $scope.SMS_DeviceCollections.All[selectedIndex];
                    $scope.CollectionsData = ChartState.DataReady;
                    $scope.SMS_DeviceCollectionChanged();
                    $scope.$apply();
                });

            } catch (err) {
                console.log("launch Collection Picker wizard failed.");
            }
        };

        $scope.launchWizard = async function () {
            await callMethodAsync("LaunchWizard", null);
        };

        $scope.createDonutChart = async function (chartSelector, columns, chartTitle, pattern) {
            var enable = true;
            var noData = true;

            if (columns.length != 0) {
                noData = false;
            }


            var versionMap = {};
            columns.forEach(function (k, v) { versionMap[k[0]] = k[1]; });

            var dataKeys = Object.keys(versionMap);
            var chartData = convertObjectToArrayOfArrays(versionMap, dataKeys);

            c3.generate({
                bindto: chartSelector,
                data: {
                    columns: chartData,
                    type: "donut",
                    onclick: async function (d) {
                        if (chartSelector === "#W10-usage") {
                            await callMethodAsync("OnOSVersionClick", d.name);
                        } else {
                            await callMethodAsync("OnBuildNumberClick", d.name);
                        };
                    },
                    onmouseover: function (d, i) {
                        if (chartSelector === "#W10-usage") {
                            console.log("onmouseover", d.name, i);
                        }
                        else {
                            console.log("onmouseover", d.name, i);
                        }
                    },
                    onmouseout: function (d, i) { console.log("onmouseout", d, i); }
                },
                interaction: {
                    enabled: enable
                },
                legend: {
                    position: "right",
                    show: enable
                },
                color: {
                    pattern: pattern
                },
                tooltip: {
                    format: {
                        value: function (value, ratio, id, index) {
                            return value;
                        }
                    }
                },
                donut: {
                    label: {
                        show: false
                    },
                    expand: enable
                },
                size: {
                    width: 325,
                    height: 230
                }
            });

            var chart = document.querySelectorAll(chartSelector);
            var chartEl = angular.element(chart);
            var tileEl = chartEl.parent();
            tileEl.attr('tabindex', '0');

            var summaryText;
            if (noData) {
                enable = false;
                pattern = ['#a9a9a9'];
                columns = [['', 1]];
                summaryText = chartTitle + " " + $scope.strings.NumericTileNoValue;
            } else {
                var str = [];
                columns.forEach(function (k, v) { str.push(k[0] + " " + k[1] + ".  "); });
                summaryText = chartTitle + str.join("");
            }

            tileEl.attr('aria-label', summaryText);
            chartEl.attr('aria-label', summaryText);
        };

        // Gauge Chart
        $scope.createGaugeChart = function (chartSelector, columns, chartTitle) {

            if (columns.length == 0) {
                columns = [['', 0]];
            }
            var label = columns[0][0];

            c3.generate({
                bindto: chartSelector,
                data: {
                    columns: columns,
                    type: "gauge"
                },
                gauge: {
                    label: {
                        format: function (value) {
                            return d3.format(".1f")(value) + "%";
                        },
                        show: true
                    },
                    min: 0, // 0 IS DEFAULT
                    max: 100,
                    units: label,
                },
                color: {
                    pattern: ['#198919']
                },
                legend: {
                    show: false
                }
            });

            var chart = document.querySelectorAll(chartSelector);
            var chartEl = angular.element(chart);
            var tileEl = chartEl.parent();
            tileEl.attr('tabindex', '0');

            var str = [];
            var num = columns[0][1];
            str.push(num + "%");
            var summaryText = chartTitle + ", " + str.join("");

            tileEl.attr('aria-label', summaryText);
            chartEl.attr('aria-label', summaryText);

        };

        //Bar Chart
        $scope.createBarChart = async function (collID, collName, data, counts, domNode, color, chartTitle) {

            //this creates a JSON object that maps an index starting from zero to each errorCode
            var i;
            var indErrorMap = {};
            for (i = 0; i < data.length; i++) {
                indErrorMap[i] = data[i]
            }

            var hexData = [];
            for (i = 0; i < data.length; i++) {
                hexData[i] = await callMethodAsync("ConvertToHexCode", data[i]);
            }

            $scope.barChart = c3.generate({
                bindto: domNode,
                legend: {
                    hide: true
                },
                bar: {
                    width: {
                        ratio: 0.5
                    }
                },
                data: {
                    columns: [counts],
                    type: 'bar',
                    onclick: async function (d) {
                        await callMethodAsync("OnSetupDiagBarClick", JSON.stringify([collID, collName, indErrorMap[d.x]]));
                    }
                },
                axis: {
                    rotated: false,
                    x: {
                        label: $scope.strings.ErrorCode,
                        type: 'category',
                        categories: hexData
                    },
                    y: {
                        label: $scope.strings.NumberOfDevices,
                        tick: {
                            format: function (y) {
                                if (y % 1 > 0) return '';
                                return y;
                            }
                        }
                    }
                },
                size: {
                    height: 280,
                    width: 400
                }
            });

            var chart = document.querySelectorAll(domNode);
            var chartEl = angular.element(chart);
            var tileEl = chartEl.parent();
            tileEl.attr('tabindex', '0');

            // Set aria-label for accessibility
            var str = [];
            for (i = 0; i < hexData.length; i++) {
                if (i == hexData.length - 1)
                    str.push(hexData[i] + ": " + counts[i + 1]);
                else
                    str.push(hexData[i] + ": " + counts[i + 1] + ",  ");
            }
            var summaryText = chartTitle + ". " + str.join("");

            tileEl.attr('aria-label', summaryText);
            chartEl.attr('aria-label', summaryText);
        };

        //Line Graph
        $scope.createLineGraph = function (lines, domNode, colors, times, chartTitle) {

            $scope.lineGraph = c3.generate({
                bindto: domNode,
                data: {
                    columns: lines
                },
                color: {
                    pattern: colors,
                },
                size: {
                    height: 255,
                },
                padding: {
                    left: 60,
                    right: 40,

                },
                axis: {
                    x: {
                        tick: {
                            centered: true,
                        },
                        type: "category",
                        categories: times,
                        label: $scope.strings.PreviousDays
                    },
                    y: {
                        label: $scope.strings.NumberOfDevices,
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
                    width: 400
                }
            });

            var chart = document.querySelectorAll(domNode);
            var chartEl = angular.element(chart);
            var tileEl = chartEl.parent();
            tileEl.attr('tabindex', '0');

            // Set aria-label for accessibility
            var str = [];
            lines.forEach(function (k, v) { str.push(k[0] + ": " + k[1] + ",  " + k[2] + ",  " + k[3] + ",  " + k[4] + ",  " + k[5] + ",  " + k[6] + ",  " + k[7]); });
            var summaryText = chartTitle + ". " + str.join("");

            tileEl.attr('aria-label', summaryText);
            chartEl.attr('aria-label', summaryText);
        };

        // For accessibiltiy of body pane
        $scope.setupAria = function () {
            var W10ServicingDashboardBodyArea = document.getElementById("W10ServicingDashboardBody");
            W10ServicingDashboardBodyArea.setAttribute("aria-label", $scope.strings._W10ServicingDashboardTitle);

            var W10ServicingDashboardBodyDivArea = document.getElementById("W10ServicingDashboardBodyDiv");
            W10ServicingDashboardBodyDivArea.setAttribute("aria-label", $scope.strings._W10ServicingDashboardTitle);
        };
    })
}());

// SIG // Begin signature block
// SIG // MIIomQYJKoZIhvcNAQcCoIIoijCCKIYCAQExDzANBglg
// SIG // hkgBZQMEAgEFADB3BgorBgEEAYI3AgEEoGkwZzAyBgor
// SIG // BgEEAYI3AgEeMCQCAQEEEBDgyQbOONQRoqMAEEvTUJAC
// SIG // AQACAQACAQACAQACAQAwMTANBglghkgBZQMEAgEFAAQg
// SIG // y6yVQUDPVg6YSqnFJ5BBEQ/igsk3snuMKrHhaSWbT2ig
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
// SIG // AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCB+At4d5+Cg1X2u
// SIG // z9JRsE96BMu05MpjhKtoa1fils3NHjCBigYKKwYBBAGC
// SIG // NwIBDDF8MHqgXIBaAE0AaQBjAHIAbwBzAG8AZgB0AC4A
// SIG // VABvAG8AbABrAGkAdAAuAFcAcABmAC4AVQBJAC4AQwBv
// SIG // AG4AdAByAG8AbABzAC4AVwBlAGIAVgBpAGUAdwAuAGQA
// SIG // bABsoRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
// SIG // BgkqhkiG9w0BAQEFAASCAQBKmA3bBR527O3RHERiKkl9
// SIG // oo4a/qnmQXPTXgb3azxTXjoCyGIBVt+EcCuB0jJxl7mB
// SIG // HVXZ896oxcv5HmFBTXvP4oD3FWZoRjY/N5kh8UR1bE6b
// SIG // wVFQwwj9JrGVMJ5zdznPB0GrcQJcjDAJQ0biv6CRFnE2
// SIG // cxDmDW6l7OE6SyJ/XxVHiN9Ox37cbfStLVfOkSMK40We
// SIG // RjwjLFXXFPyRzNCPPnWnSYPU7JuJLqu8KtkWiEHMVbty
// SIG // GcqUABg4qnjtcmxzm11MutapqmKojK4BudGaEeFqrDSL
// SIG // UVK5s+hKeTca9vTS1KjXRc0a0+PeiV6n2lgZLze6u5gr
// SIG // Mbxevf2hvUKpoYIXrTCCF6kGCisGAQQBgjcDAwExgheZ
// SIG // MIIXlQYJKoZIhvcNAQcCoIIXhjCCF4ICAQMxDzANBglg
// SIG // hkgBZQMEAgEFADCCAVoGCyqGSIb3DQEJEAEEoIIBSQSC
// SIG // AUUwggFBAgEBBgorBgEEAYRZCgMBMDEwDQYJYIZIAWUD
// SIG // BAIBBQAEILlFTKp8mttWiZRXt0Er0/mgQdIIe48ILUcY
// SIG // Os/83BZDAgZo8dDt4gsYEzIwMjUxMDIzMDI0NzM2LjMw
// SIG // NVowBIACAfSggdmkgdYwgdMxCzAJBgNVBAYTAlVTMRMw
// SIG // EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
// SIG // b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
// SIG // b24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9w
// SIG // ZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNoaWVs
// SIG // ZCBUU1MgRVNOOjJBMUEtMDVFMC1EOTQ3MSUwIwYDVQQD
// SIG // ExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloIIR
// SIG // +zCCBygwggUQoAMCAQICEzMAAAIQq83kFhjvObAAAQAA
// SIG // AhAwDQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMx
// SIG // EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
// SIG // ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
// SIG // dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3Rh
// SIG // bXAgUENBIDIwMTAwHhcNMjUwODE0MTg0ODEyWhcNMjYx
// SIG // MTEzMTg0ODEyWjCB0zELMAkGA1UEBhMCVVMxEzARBgNV
// SIG // BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
// SIG // HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEt
// SIG // MCsGA1UECxMkTWljcm9zb2Z0IElyZWxhbmQgT3BlcmF0
// SIG // aW9ucyBMaW1pdGVkMScwJQYDVQQLEx5uU2hpZWxkIFRT
// SIG // UyBFU046MkExQS0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1p
// SIG // Y3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0G
// SIG // CSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCNxzirTntn
// SIG // AiCkq7ilNdYt6O9gR25F/7WYiluIkQwVZaZTbGmKn7Mr
// SIG // vEXEoYHUJyVRcFTT9lBnosbwfSAjvK+iyuw8QjUM8H9d
// SIG // xwYK+zApsApySeA64ZMQ8aTsr+8Rlr2HRe3TZvubaf0x
// SIG // 0iOQusWXSkOuIrLPRAcal2H3dfr40Cl8TVMvbhWjTGR6
// SIG // gUakvetf2BeEg4Xn0QydN3ajjkVb+jEyBj2rTLSMY7Qe
// SIG // sItMJmvnR7tNlFI1gDLaXIpu8ojYwqU3XAvMm9lttz/8
// SIG // vezWrcnoqFLQoLZU0QiZh0WBWQl6PjNmod9JxNvH2GMW
// SIG // AWlWQmXjEflUny3Il1cT369TST0BpPZA/VmbdZCZd51K
// SIG // guOMjstbOe4fCegYhcuIkxDM+oqpEgUvfDNysOtl5aC0
// SIG // B0E9uKmCVnkJCezoFqPkxvpr8RkL0bd9olgrlBUd4Tp4
// SIG // uhITCnV3Pla6stc0+ynRVamWmX8UlvyOtFP+M6ge7zmp
// SIG // Fx1imAHJT1bshY92u2GbJ+p4DDSiZVY3knFyiBhsujak
// SIG // A0keWwx1afEik3ljAdsYQ8K6iwEc+TZd334T+lk9BRHq
// SIG // /4Pzl4Q3kD9kz/GI+nFrx0lnzsGlO+6Lv/a5+VQwl/Zh
// SIG // z1ks+AR2FBCjQvAwNJMNPjzLexXs92j6Dmr4yqcnO03/
// SIG // qq3VyBRN7277KQIDAQABo4IBSTCCAUUwHQYDVR0OBBYE
// SIG // FJ7jb4Wul0XZq9tSGWTzoEtIfmR6MB8GA1UdIwQYMBaA
// SIG // FJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYw
// SIG // VKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9w
// SIG // a2lvcHMvY3JsL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAl
// SIG // MjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRg
// SIG // MF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9z
// SIG // b2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIw
// SIG // VGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwG
// SIG // A1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUH
// SIG // AwgwDgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUA
// SIG // A4ICAQC+zis7eijxzM6vE+qedISRRWrvXxDOWsiLLv8R
// SIG // bsmZBewmgXEdZQXRTHQ8PIoUNFc8lW/b0XuSkmQEkmZx
// SIG // CDkdBXtuVRcgxZDWpfQp20VBcj8xEvvtn6krnHWNf61t
// SIG // GQDtrkW3u9a5GgASLTYekUfmb8CSH91+xvHzA6l5wlti
// SIG // +4e7LhobT+0bM5YULEww2EYAgnip1Xzsmdj+4wGaKh2W
// SIG // b4bPfntdZbm2Dceu01le5DS1ZS/bq53icYomj+gtkc/v
// SIG // mnhGm3t0x1gpQX0C5UUHDFhlim+CTXa18r7/I7Crzj9+
// SIG // NdUJ0zzdCdrC1t6duT+Wdtz0qxmib4ae8DiK0AxSlJcV
// SIG // atxGSp1RAs34msbp88GhXz4PxTZDYXheSIJHoRT0nNgr
// SIG // BO68vq3ecW7GeQt02NtODb/K/aPdZoO4IrmVI+Cyd0iI
// SIG // foGS7ZSLcDRpSjoP3P2/5cS4Gz2KhUlo6N//P5SuqDsR
// SIG // KfEbT9PV0pyLu8tDZc2BYVg7786UOO0aiZrWKNfibXg3
// SIG // 2qCtdO5YQbCALuGEGCneJ38sA5/0FJNYDmUGuKWwSh7F
// SIG // cGs6f/XAzeuMbSEizG8Xn9g4rvyZVEZjpjvNgn65e3g5
// SIG // M4UHBp0+/wySWt5Bks+dA+2LCiniuUtRho8KIPhhSpE1
// SIG // sunxKDKj2DSIBxljOdO5z7xDxkiuDDCCB3EwggVZoAMC
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
// SIG // OjJBMUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3Nv
// SIG // ZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4D
// SIG // AhoDFQA6zJ/ZvquI8qedeUiAgvZ/nc9SwqCBgzCBgKR+
// SIG // MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5n
// SIG // dG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
// SIG // aWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1p
// SIG // Y3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqG
// SIG // SIb3DQEBCwUAAgUA7KOPFTAiGA8yMDI1MTAyMjE3MTI1
// SIG // M1oYDzIwMjUxMDIzMTcxMjUzWjB0MDoGCisGAQQBhFkK
// SIG // BAExLDAqMAoCBQDso48VAgEAMAcCAQACAgisMAcCAQAC
// SIG // AhKkMAoCBQDspOCVAgEAMDYGCisGAQQBhFkKBAIxKDAm
// SIG // MAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAIAgEA
// SIG // AgMBhqAwDQYJKoZIhvcNAQELBQADggEBAI8PgQNtAoLF
// SIG // igy48ufBMgRYwobuQ7ldYyST/DC0Go+3GfWy5OgimzYo
// SIG // 9NKbO2UJIXeMwTwOBPJ6EbTd2j01qLKgjJDBO4N3yBAS
// SIG // oSB2YF/fzSf5AbUOp1nDDq0HzCQrGPA2S9fdDdC4QjfY
// SIG // 4tphuV2s6vgPvemF3PlN/fcEuQM3lYWXIMQvIx03gusD
// SIG // gj+Fd01Qv1QYwB1MawDBmc4TNyzFvS6ZBVm/w3EdIhJ8
// SIG // RPFnDYaHmvumTqtY8nZZMen7aJZSzuDiS7vXKTGjUflm
// SIG // och9ZfxpgNWsGHRXJpX+scbp/kTHVDeVhdg/F1JIistY
// SIG // JRc6x0zsVbK86CausOsq2wgxggQNMIIECQIBATCBkzB8
// SIG // MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
// SIG // bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
// SIG // cm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNy
// SIG // b3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAhCr
// SIG // zeQWGO85sAABAAACEDANBglghkgBZQMEAgEFAKCCAUow
// SIG // GgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqG
// SIG // SIb3DQEJBDEiBCCZe0WkUKx8kCvEwrwOxDahBEUj6L0m
// SIG // lR+5Z6oxjZpcADCB+gYLKoZIhvcNAQkQAi8xgeowgecw
// SIG // geQwgb0EIMPVIe5+yPNjn1LWIdRBj2GewpKsk+Dlr0xz
// SIG // hicaY8fGMIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzAR
// SIG // BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
// SIG // bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
// SIG // bjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAg
// SIG // UENBIDIwMTACEzMAAAIQq83kFhjvObAAAQAAAhAwIgQg
// SIG // z7I6Dm/tZNip6TEUfPjsgiiJ1civ/bFbT64FtGyquLEw
// SIG // DQYJKoZIhvcNAQELBQAEggIAOEOBQLUAoz7VtdkpOfuP
// SIG // x0wPSqcg7yi0NJjjeUPeGSxrNgbpWyD6ei5o99RaoAHp
// SIG // 6+hrC7JqpMzdZi6G4fEe+EcvnoUg3WdF/tCe+XKikNOk
// SIG // HSXlC5awURxvfu1LPygNUaY/Ts2brK7/i20O/GHNe2EQ
// SIG // o9dnu+cnuo1LKVBzwJT8vG4uRZzSAcEMsW/HNT4X2Ggz
// SIG // P4HnOlLtOPMfOSpl2mNYu1eRqat3fCvAtQJBZXEj6LX8
// SIG // +OPpIe1fh605PHaSxEpKxZWOLG02A3NchP3VFxsRsM8L
// SIG // jV72sJtoArUzr8kBpot63MwwH0yc8NnSfjjWZ4MMLLG7
// SIG // PIQH8mhVvCwWxpWskhZAc9eMbONypSJPOdwa6QfvXmSU
// SIG // HR/bV1++v3QM4ONYYJ6mO5PMRG/SdlIMATzZBqKxoekn
// SIG // OI6A50jB40oPTgcRSTIZ+odMaFUtZwWCrR3bHmpTbcQr
// SIG // rM3/D0SWSmJN94q6BSCGTG3pX7JPMdSfPRBuC2JbsImG
// SIG // lN2mU1mYR7FNh2QdS3kUKuDgET0V2Z+S3s4HUF6UHizi
// SIG // Y5xidKqo0sYMj4FunVTF+xOK3s15vZiOk2dDqqKntot2
// SIG // SI//7qr48mXNjKyU/Q4ogjS2vj7uHob4UckaXJpE7gn3
// SIG // xX1KGTzokfJyjHEs4wk9JuHUwh7VuY92ryKGlKsvCkq/fO0=
// SIG // End signature block
