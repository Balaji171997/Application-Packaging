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
                showChartButton.innerHTML = $scope.strings.ShowChart;
            }
            else if (w10Table.style.display = 'table') {
                w10Table.style.display = 'none';
                w10Chart.style.display = 'block';
                showChartButton.innerHTML = $scope.strings.ShowTable;
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
            table.innerHTML = ""; //Set data to null in case it exists
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
            addDiv.innerHTML = await callMethodAsync("AddRows", JSON.stringify([item, count]));

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
// SIG // MIInyAYJKoZIhvcNAQcCoIInuTCCJ7UCAQExDzANBglg
// SIG // hkgBZQMEAgEFADB3BgorBgEEAYI3AgEEoGkwZzAyBgor
// SIG // BgEEAYI3AgEeMCQCAQEEEBDgyQbOONQRoqMAEEvTUJAC
// SIG // AQACAQACAQACAQACAQAwMTANBglghkgBZQMEAgEFAAQg
// SIG // KKZFGrLzHYmke6L+uK0WyX9ej9CZTZtANu8GwIf34Yyg
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
// SIG // SEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCGZ8w
// SIG // ghmbAgEBMIGVMH4xCzAJBgNVBAYTAlVTMRMwEQYDVQQI
// SIG // EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
// SIG // HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAm
// SIG // BgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENB
// SIG // IDIwMTECEzMAAALMjrWWpr3RyU4AAAAAAswwDQYJYIZI
// SIG // AWUDBAIBBQCgga4wGQYJKoZIhvcNAQkDMQwGCisGAQQB
// SIG // gjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcC
// SIG // ARUwLwYJKoZIhvcNAQkEMSIEIGe0ndj+vLL1Ul3epTFz
// SIG // N/8TmsGIwSknsjzAdIqIxxrRMEIGCisGAQQBgjcCAQwx
// SIG // NDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRw
// SIG // Oi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEB
// SIG // BQAEggEAEvj/yFOxPsTUGJEPhTE9vB6FQr5hdrpmC7NG
// SIG // Xtb8YT+LOPjht6trWat4J+MPzgqwxB0T9tZ8w/alwBaM
// SIG // 6iyia0OPvb+Y/9ATkVXwJQo3tevswXNNyuHeRE3VAag4
// SIG // ZDPOXZA8DLrD/ATtJ6DJ0nl8FVi1j3eEm00MvbChI3Is
// SIG // j8/lQToUwZkKqZJcF+5jJ9CKOEGcUf2OTzy80OAEv16G
// SIG // P29cYRN7Qa1I0iQu5PlPR5cnbeDDOfXBQAucvB+wp5Ew
// SIG // xUPtlTaxpe3Jx+WOjC2UXcNy6hINiNc8Qg3xC+j7KYRf
// SIG // 8V9kFExp3SjSWnmsqLPVUHWip7vs2oFMDpf0UScV/aGC
// SIG // FykwghclBgorBgEEAYI3AwMBMYIXFTCCFxEGCSqGSIb3
// SIG // DQEHAqCCFwIwghb+AgEDMQ8wDQYJYIZIAWUDBAIBBQAw
// SIG // ggFZBgsqhkiG9w0BCRABBKCCAUgEggFEMIIBQAIBAQYK
// SIG // KwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCB+4Doo
// SIG // G4XCySP7YPYQ6nj7T/8ovsm21i3MCXjSuf5JZwIGY2Ph
// SIG // hC7ZGBMyMDIyMTEwNDE3MjMzOS44MjlaMASAAgH0oIHY
// SIG // pIHVMIHSMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
// SIG // aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
// SIG // ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQL
// SIG // EyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExp
// SIG // bWl0ZWQxJjAkBgNVBAsTHVRoYWxlcyBUU1MgRVNOOkQw
// SIG // ODItNEJGRC1FRUJBMSUwIwYDVQQDExxNaWNyb3NvZnQg
// SIG // VGltZS1TdGFtcCBTZXJ2aWNloIIReDCCBycwggUPoAMC
// SIG // AQICEzMAAAG6Hz8Z98F1vXwAAQAAAbowDQYJKoZIhvcN
// SIG // AQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
// SIG // c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
// SIG // BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UE
// SIG // AxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAw
// SIG // HhcNMjIwOTIwMjAyMjE5WhcNMjMxMjE0MjAyMjE5WjCB
// SIG // 0jELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
// SIG // b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
// SIG // Y3Jvc29mdCBDb3Jwb3JhdGlvbjEtMCsGA1UECxMkTWlj
// SIG // cm9zb2Z0IElyZWxhbmQgT3BlcmF0aW9ucyBMaW1pdGVk
// SIG // MSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVTTjpEMDgyLTRC
// SIG // RkQtRUVCQTElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUt
// SIG // U3RhbXAgU2VydmljZTCCAiIwDQYJKoZIhvcNAQEBBQAD
// SIG // ggIPADCCAgoCggIBAIhOFYMzkjWAE9UVnXF9hRGv0xBR
// SIG // xc+I5Hu3hxVFXyK3u38xusEb0pLkwjgGtDsaLLbrlMxq
// SIG // X3tFb/3BgEPEC3L0wX76gD8zHt+wiBV5mq5BWop29qRr
// SIG // gMJKKCPcpQnSjs9B/4XMFFvrpdPicZDv43FLgz9fHqMq
// SIG // 0LJDw5JAHGDS30TCY9OF43P4d44Z9lE7CaVS2pJMF3L4
// SIG // 53MXB5yYK/KDbilhERP1jxn2yl+tGCRguIAsMG0oeOhX
// SIG // aw8uSGOhS6ACSHb+ebi0038MFHyoTNhKf+SYo4OpSY3x
// SIG // P4+swBBTKDoYP1wH+CfxG6h9fymBJQPQZaqfl0riiDLj
// SIG // mDunQtH1GD64Air5k9Jdwhq5wLmSWXjyFVL+IDfOpdix
// SIG // J6f5o+MhE6H4t31w+prygHmd2UHQ657UGx6FNuzwC+Sp
// SIG // AHmV76MZYac4uAhTgaP47P2eeS1ockvyhl9ya+9JzPfM
// SIG // kug3xevzFADWiLRMr066EMV7q3JSRAsnCS9GQ08C4FKP
// SIG // bSh8OPM33Lng0ffxANnHAAX/DE7cHcx7l9jaV3Acmkj7
// SIG // oqir4Eh2u5YxwiaTE37XaMumX2ES3PJ5NBaXq7YdLJwy
// SIG // SD+U9pk/tl4dQ1t/Eeo7uDTliOyQkD8I74xpVB0T31/6
// SIG // 7KHfkBkFVvy6wye21V+9IC8uSD++RgD3RwtN2kE/AgMB
// SIG // AAGjggFJMIIBRTAdBgNVHQ4EFgQUimLm8QMeJa25j9MW
// SIG // eabI2HSvZOUwHwYDVR0jBBgwFoAUn6cVXQBeYl2D9OXS
// SIG // ZacbUzUZ6XIwXwYDVR0fBFgwVjBUoFKgUIZOaHR0cDov
// SIG // L3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jcmwvTWlj
// SIG // cm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAo
// SIG // MSkuY3JsMGwGCCsGAQUFBwEBBGAwXjBcBggrBgEFBQcw
// SIG // AoZQaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9w
// SIG // cy9jZXJ0cy9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIw
// SIG // UENBJTIwMjAxMCgxKS5jcnQwDAYDVR0TAQH/BAIwADAW
// SIG // BgNVHSUBAf8EDDAKBggrBgEFBQcDCDAOBgNVHQ8BAf8E
// SIG // BAMCB4AwDQYJKoZIhvcNAQELBQADggIBAF/I8U6hbZhv
// SIG // Dcn96nZ6tkbSEjXPvKZ6wroaXcgstEhpgaeEwleLuPXH
// SIG // LzEWtuJuYz4eshmhXqFr49lbAcX5SN5/cEsP0xdFayb7
// SIG // U5P94JZd3HjFvpWRNoNBhF3SDM0A38sI2H+hjhB/VfX1
// SIG // XcZiei1ROPAyCHcBgHLyQrEu6mnb3HhbIdr8h0Ta7WFy
// SIG // lGhLSFW6wmzKusP6aOlmnGSac5NMfla6lRvTYHd28rbb
// SIG // CgfSm1RhTgoZj+W8DTKtiEMwubHJ3mIPKmo8xtJIWXPn
// SIG // Xq6XKgldrL5cynLMX/0WX65OuWbHV5GTELdfWvGV3DaZ
// SIG // rHPUQ/UP31Keqb2xjVCb30LVwgbjIvYS77N1dARkN8F/
// SIG // 9pJ1gO4IvZWMwyMlKKFGojO1f1wbjSWcA/57tsc+t2bl
// SIG // rMWgSNHgzDr01jbPSupRjy3Ht9ZZs4xN02eiX3eG297N
// SIG // rtC6l4c/gzn20eqoqWx/uHWxmTgB0F5osBuTHOe77DyE
// SIG // A0uhArGlgKP91jghgt/OVHoH65g0QqCtgZ+36mnCEg6I
// SIG // OhFoFrCc0fJFGVmb1+17gEe+HRMM7jBk4O06J+IooFrI
// SIG // 3e3PJjPrQano/MyE3h+zAuBWGMDRcUlNKCDU7dGnWvH3
// SIG // XWwLrCCIcz+3GwRUMsLsDdPW2OVv7v1eEJiMSIZ2P+M7
// SIG // L20Q8aznU4OAMIIHcTCCBVmgAwIBAgITMwAAABXF52ue
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
// SIG // oXBm8qGCAtQwggI9AgEBMIIBAKGB2KSB1TCB0jELMAkG
// SIG // A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAO
// SIG // BgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29m
// SIG // dCBDb3Jwb3JhdGlvbjEtMCsGA1UECxMkTWljcm9zb2Z0
// SIG // IElyZWxhbmQgT3BlcmF0aW9ucyBMaW1pdGVkMSYwJAYD
// SIG // VQQLEx1UaGFsZXMgVFNTIEVTTjpEMDgyLTRCRkQtRUVC
// SIG // QTElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAg
// SIG // U2VydmljZaIjCgEBMAcGBSsOAwIaAxUAdqNHe113gCJ8
// SIG // 7aZIGa5QBUqIwvKggYMwgYCkfjB8MQswCQYDVQQGEwJV
// SIG // UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMH
// SIG // UmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
// SIG // cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1T
// SIG // dGFtcCBQQ0EgMjAxMDANBgkqhkiG9w0BAQUFAAIFAOcP
// SIG // sXYwIhgPMjAyMjExMDQyMzQyNDZaGA8yMDIyMTEwNTIz
// SIG // NDI0NlowdDA6BgorBgEEAYRZCgQBMSwwKjAKAgUA5w+x
// SIG // dgIBADAHAgEAAgIDDDAHAgEAAgIRdTAKAgUA5xEC9gIB
// SIG // ADA2BgorBgEEAYRZCgQCMSgwJjAMBgorBgEEAYRZCgMC
// SIG // oAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3
// SIG // DQEBBQUAA4GBAF7P2VmK9E7u9eQPQl8zrH/2faSve+Ee
// SIG // 503loMwa+OCfGVZUczGM9r8dvRRzjI9DYot1Xscfwlf9
// SIG // LnGskclgnp8DFyRS+2GgOywOVJNdlvHyJ2JcG5av4S8V
// SIG // c2N01LjqHBurqdWUCb/YYqA60Gi/zeRDmRALuzpfYs3Z
// SIG // msOL23aYMYIEDTCCBAkCAQEwgZMwfDELMAkGA1UEBhMC
// SIG // VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcT
// SIG // B1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
// SIG // b3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUt
// SIG // U3RhbXAgUENBIDIwMTACEzMAAAG6Hz8Z98F1vXwAAQAA
// SIG // AbowDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJ
// SIG // AzENBgsqhkiG9w0BCRABBDAvBgkqhkiG9w0BCQQxIgQg
// SIG // gyFFR9Rhw+kVpE0GApKb0xJ0hNntikMz2r3AY5i/cacw
// SIG // gfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCApVb08
// SIG // M25w+tYGWsmlGtp1gy1nPcqWfqgMF3nlWYVzBTCBmDCB
// SIG // gKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
// SIG // aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
// SIG // ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMT
// SIG // HU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMz
// SIG // AAABuh8/GffBdb18AAEAAAG6MCIEILveL+81/fgI1uLT
// SIG // 9XPqAMVR3MPdwkQQqt8OF70GQ6BiMA0GCSqGSIb3DQEB
// SIG // CwUABIICAB/vRcc6kZXW2MgFK5H+oQc9gih/ssJ7MhvZ
// SIG // znzCScGJLEXjMokNXtUEbIucI4nfUnBfgZQXo3nkXpPE
// SIG // m8iU1PX8FjIRw3mE4tG2y2Ck+w/0Gr+y3/ANfJg0+aUm
// SIG // 2HKvY2ige1EFvaAOGWk32CgTJGAiXpPS77B/QVqTweh7
// SIG // 6DCdDsc9U1rq6yXOMioC70jBL/UZHo2CVMtTf3HELTx+
// SIG // TujLJP0O1iTODRRh/iNIFEWNO7GUpCZcPwMEb8oLWluL
// SIG // gOybmrNXSQFiFi4MYO9Py7D8wO4ngfgvJsIdXo2gWD1d
// SIG // VLopVZLfZom576RijeYMuNc3jDBNIID5mRhjuXvWB0ag
// SIG // odFVQe3nBg81ejQDw6TCmGpDsEU9BYHiwXIo8naKp6jM
// SIG // T2ffFTBvQsOHLcDPWsCgM98AhBGQWsp1bWCDx3x7f4XG
// SIG // Mw4zy2CDmtqRiFQplxSAzOZEBAYR+5tBgVFRcF4YC12M
// SIG // 11thZ4F2KcMKa71/yVLS/xt3Ts/GZIvYbaSs/m3I0NUv
// SIG // y8mo9EOYAJBWan7m5MRhoKCIWaV16Fz1tn90q0AVB9nJ
// SIG // T3fmIF9ApeFxemdFz+F5lxhzNRB+yXi54M2AKkxdMUgG
// SIG // x7L1WiCinkw8r1THt5kY7IRwC+mM/uBYJ2UT3rznGMz6
// SIG // a83IKM7aqZ3NsYhLHnp7MjuV0fBWJ79+
// SIG // End signature block
