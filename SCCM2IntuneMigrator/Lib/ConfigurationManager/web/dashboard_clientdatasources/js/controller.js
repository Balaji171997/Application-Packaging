(function () {

    "use strict";
    var dashboard = angular.module("dashboard", []);
    var contentChartMetaData = {};

    var colors = {
        ManagementPointBytes: "#00B7C3",
        DPBytes: "#00B7C3",
        SPBytes: "#9B0062",
        BranchCacheBytes: "#0078D7",
        CloudDPBytes: "#005B70",
        DOPeerBytes: "#004E8C",
        //    DOCacheServerBytes: "#5C2E91",
        WUMUBytes: "#8378DE",
    };

    var sourceColors = {
        DPFallbackCount: "#00B7C3",
        CloudDPFallbackCount: "#005B70",
    };

    // helper for client data sources
    async function GetClientDataSourcesFx(fnname, name, selectionType, gpid, days, callback) {
        var id = setCallbackFunction(callback);
        await callMethodAsync(fnname, JSON.stringify([name, selectionType, gpid, days, id]));
    };

    async function GetClientDataSourcesContentStatsCall(selectionType, gpid, days, callback) {
        var id = setCallbackFunction(callback);
        await callMethodAsync("GetClientDataSourcesContentStats", JSON.stringify([selectionType, gpid, days, id]));
    };


    dashboard.controller("dashboardController", function ($scope) {
        $scope.ChartState = ChartState;
        $scope.suppressRefresh = false;
        $scope.contentData = ChartState.Loading;
        $scope.packageChartData = ChartState.Loading;
        $scope.deviceCountData = ChartState.Loading;
        $scope.fallbackCountData = ChartState.Loading;
        $scope.strings;
        $scope.selectionType = 0;
        $scope.boundaryGroupName;
        $scope.boundaryGroupID = 0;

        adminUI.initializeController($scope, async function () {
            //Load static data to be used in controller
            $scope.getString = function (stringName) {
                return $scope.strings[stringName];
            };
            $scope.sourceNames = {
                SPBytes: $scope.getString("PeerCache"),
                BranchCacheBytes: $scope.getString("BranchCache"),
                CloudDPBytes: $scope.getString("CloudDistributionPoint"),
                DPBytes: $scope.getString("DistributionPoint"),
                DOPeerBytes: $scope.getString("DOPeerBytes"),
                //DOCacheServerBytes: $scope.strings["DOCacheServerBytes"],
                WUMUBytes: $scope.getString("WUMUBytes"),
            };

            $scope.fallbackNames = {
                DPFallbackCount: $scope.strings.DPFallbackCount,
                CloudDPFallbackCount: $scope.strings.CloudDPFallbackCount
            };

            $scope.sourceTypeNames = {
                1: "CloudDPBytes",
                2: "ManagementPointBytes",
                3: "SPBytes",
                4: "DPBytes",
                5: "BranchCacheBytes",
                6: "DOPeerBytes",
                //7: "DOCacheServerBytes",
                8: "WUMUBytes"
            };

            ////////////////////////////////////////////
            // Generate values for the time period dropdown
            $scope.timePeriods =
                [
                    {
                        label: $scope.strings["_1Week"],
                        value: 7
                    },
                    {
                        label: $scope.strings["_2Weeks"],
                        value: 14
                    },
                    {
                        label: $scope.strings["_3Weeks"],
                        value: 21
                    },
                    {
                        label: $scope.strings["_1Month"],
                        value: 30
                    },
                    {
                        label: $scope.strings["_2Month"],
                        value: 60
                    },
                    {
                        label: $scope.strings["_3Month"],
                        value: 100
                    },
                ];

            $scope.timePeriod = $scope.timePeriods[0];
            $scope.setupAria();
            setUserControlState(false);

            ////////////////////////////////////////////
            // Initialize the dashboard using the first boundary group returned by SMS_ClientDownloadSourcesBoundaries
            // Query result format: [{GroupID, Name}]

            adminUI.wmiQuery("SELECT GroupID, Name FROM SMS_ClientDownloadSourcesBoundaries order by Name", function (res) {

                res = JSON.parse(res);
                var boundaryGroups = res;

                $scope.suppressRefresh = true;

                if (boundaryGroups.length == 0) {
                    document.getElementById("allBoundaryGroupsAria").checked = true;
                    $scope.selectionType = 1;
                } else {
                    document.getElementById("boundaryGroupAria").checked = true;
                    $scope.selectionType = 0;
                    $scope.boundaryGroup = boundaryGroups[0];
                    $scope.boundaryGroupName = boundaryGroups[0].Name;
                    $scope.boundaryGroupID = Number(boundaryGroups[0].GroupID);
                }

                $scope.$apply();

                $scope.suppressRefresh = false;

                refreshDataSources();
            });
            ////////////////////////////////////////////
            // Setup watches on input fields so we can regerenate the dashboard when necessary.

            $scope.$watch("timePeriod", refreshDataSources_WatchChangedOnly);
            $scope.$watch("boundaryGroup", refreshDataSources_WatchChangedOnly);
            $scope.$watch("boundaryGroupName", refreshDataSources_WatchChangedOnly);
            $scope.$watch("boundaryGroupID", refreshDataSources_WatchChangedOnly);
            $scope.$watch("selectedDataSource", refreshDataSources_WatchChangedOnly);

            $scope.$apply();
        });

        var selections = document.forms['clientSelection'].elements['clientType'];
        for (var i = 0, len = selections.length; i < len; i++) {
            selections[i].onclick = dataSourceRadioButtonOnClick;
        }

        // Setup aria for the filters
        $scope.setupAria = function () {

            var reportPeriodSummaryText = $scope.strings["ReportPeriod"];
            var reportPeriodAriaLabel = document.getElementById("time-period-select");
            reportPeriodAriaLabel.setAttribute("aria-label", reportPeriodSummaryText);

            var dataSourcesDescSummaryText = $scope.strings['ClientSelection'] + ". " + $scope.strings['RadioButtonsInstructions'] + ". ";
            var dataSourcesDescAriaLabel = document.getElementById("dataSourcesDesc");
            dataSourcesDescAriaLabel.setAttribute("aria-label", dataSourcesDescSummaryText);

            var boundaryGroupSummaryText = $scope.strings['SingleBoundaryGroup'] + ". " + $scope.boundaryGroupName;
            var boundaryGroupAriaLabel = document.getElementById("boundaryGroupAria");
            boundaryGroupAriaLabel.setAttribute("aria-label", boundaryGroupSummaryText);

            var allBoundaryGroupsSummaryText = $scope.strings['AllBoundaryGroups'] + ". ";
            var allBoundaryGroupsAriaLabel = document.getElementById("allBoundaryGroupsAria");
            allBoundaryGroupsAriaLabel.setAttribute("aria-label", allBoundaryGroupsSummaryText);

            var internetClientsSummaryText = $scope.strings['InternetClients'] + ". ";
            var internetClientsAriaLabel = document.getElementById("internetClientsAria");
            internetClientsAriaLabel.setAttribute("aria-label", internetClientsSummaryText);

            var outsideClientsSummaryText = $scope.strings['ClientsOutsideBG'] + ". ";
            var outsideClientsAriaLabel = document.getElementById("outsideClientsAria");
            outsideClientsAriaLabel.setAttribute("aria-label", outsideClientsSummaryText);
        };
        /*
         * Parameters:
         * n - number of bytes
         * decimalPlaces - OPTIONAL, defaults to 2
         */
        function formatBytesString(n, decimalPlaces) {
            decimalPlaces = typeof decimalPlaces !== 'undefined' ? decimalPlaces : 2; // set default value to 2
            var suffixes = ["Bytes", "KB", "MB", "GB", "TB", "PB"];
            while (n > 1024 && suffixes.length > 1) {
                suffixes.splice(0, 1);
                n /= 1024;
            }
            return roundToDecimalPlaces(n, decimalPlaces) + " " + $scope.strings[suffixes[0]];
        }

        ////////////////////////////////////////////
        // Helpers for enabling/disabling user controls while data is loading

        function setUserControlState(enabled) {
            var disabled = !enabled;
            document.getElementById('time-period-select').disabled = disabled;
            document.getElementById('boundaryGroupAria').disabled = disabled;
            document.getElementById('allBoundaryGroupsAria').disabled = disabled;
            document.getElementById('internetClientsAria').disabled = disabled;
            document.getElementById('outsideClientsAria').disabled = disabled;

            if (enabled && document.getElementById('boundaryGroupAria').checked) {
                document.getElementById('browseButton').disabled = false;
                document.getElementById('displayLabel').disabled = false;
            } else {
                document.getElementById('browseButton').disabled = true;
                document.getElementById('displayLabel').disabled = true;
            }
        }

        ////////////////////////////////////////////
        // Chart updating functions, called by refreshDataSources

        function refreshDeviceCountCallback(res) {
            if (res.length == 0) {
                console.log("GetClientDataSourcesDeviceCount returned no results");
                $scope.deviceCountData = ChartState.NoDataFound;
                $scope.$apply();
                return;
            }

            var data = null
            data = res[0]
            $scope.deviceCountData = ChartState.DataReady;

            var DPCount = parseInt(data.DPCount);
            var ClientCount = parseInt(data.DPUsingClientCount);
            var PeerClientCount = parseInt(data.PeerClientCount);
            var ClientPeerToPeerCount = parseInt(data.PeerUsingClientCount);

            $scope.deviceCounts = data;

            // Setup aria string for data source usage table
            var dataSourceDPSummaryText = $scope.strings['DataSourceType'] + ", " + $scope.strings['DistributionPoint'] + " . " + $scope.strings['DataSourceCount'] + ", " + DPCount + " . " + $scope.strings['ClientsUsingSource'] + ", " + ClientCount + " . ";
            var dataSourceDPAriaLabel = document.getElementById("dataSourceDPAria");
            dataSourceDPAriaLabel.setAttribute("aria-label", dataSourceDPSummaryText);

            var dataSourceDPSummaryText = $scope.strings['DataSourceType'] + ", " + $scope.strings['PeerCache'] + " . " + $scope.strings['DataSourceCount'] + ", " + PeerClientCount + " . " + $scope.strings['ClientsUsingSource'] + ", " + ClientPeerToPeerCount + " . ";
            var dataSourceDPAriaLabel = document.getElementById("dataSourcePeerAria");
            dataSourceDPAriaLabel.setAttribute("aria-label", dataSourceDPSummaryText);
            $scope.$apply();
        }

        function refreshContentCallback(res) {
            if (res.length == 0) {
                console.log("GetClientDataSourcesContent returned no results");
                $scope.contentData = ChartState.NoDataFound;
                $scope.$apply();
                return;
            }

            var data = res[0];
            $scope.contentData = ChartState.DataReady;

            data.SPBytes *= (1024 * 1024);
            data.BranchCacheBytes *= (1024 * 1024);
            data.DPBytes *= (1024 * 1024);
            data.CloudDPBytes *= (1024 * 1024);
            data.DOPeerBytes *= (1024 * 1024);
            //data.DOCacheServerBytes *= (1024 * 1024);
            data.WUMUBytes *= (1024 * 1024);

            $scope.contentSourceCounts = {
                SPBytes: (data.SPBytes / 1048576).toFixed(1),
                BranchCacheBytes: (data.BranchCacheBytes / 1048576).toFixed(1),
                DPBytes: (data.DPBytes / 1048576).toFixed(1),
                CloudDPBytes: (data.CloudDPBytes / 1048576).toFixed(1),
                DOPeerBytes: (data.DOPeerBytes / 1048576).toFixed(1),
                WUMUBytes: (data.WUMUBytes / 1048576).toFixed(1)
            }



            //var totalBytes = (data.SPBytes + data.BranchCacheBytes + data.DPBytes + data.CloudDPBytes + data.DOPeerBytes + data.DOCacheServerBytes + data.WUMUBytes) * (1024 * 1024);
            var totalBytes = (data.SPBytes + data.BranchCacheBytes + data.DPBytes + data.CloudDPBytes + data.DOPeerBytes + data.WUMUBytes) * (1024 * 1024);

            //var chartData = convertObjectToArrayOfArrays(data, ["DPBytes", "CloudDPBytes", "BranchCacheBytes", "SPBytes", "DOPeerBytes", "DOCacheServerBytes", "WUMUBytes"])
            var chartData = convertObjectToArrayOfArrays(data, ["DPBytes", "CloudDPBytes", "BranchCacheBytes", "SPBytes", "DOPeerBytes", "WUMUBytes"])

            createSourceBytesDonutChart("#content-types", chartData);

            // Setup aria string for content sources donut chart
            var contentSourcesDetailsSummaryText = "";
            for (var value in chartData) {
                var formattedBytes = formatBytesString(chartData[value][1], 2);
                contentSourcesDetailsSummaryText += $scope.strings[chartData[value][0]] + ", " + formattedBytes + ". ";
            }
            var contentSourcesDetailsAriaLabel = document.getElementById("content-types");
            contentSourcesDetailsAriaLabel.setAttribute("aria-label", contentSourcesDetailsSummaryText);

            // Accessibility. In high contrast mode set all text to white
            if ($scope.brightness < 125) {
                SetColorToAllTextInChart("#content-types", 'white');
            }

            // meta data used in tooltips, not to draw chart
            $scope.$apply();
        }

        function refreshFallbackCountCallback(res) {
            if (res.length == 0) {
                console.log("GetClientDataSourcesFallbackCount returned no results");
                $scope.fallbackCountData = ChartState.NoDataFound;
                $scope.$apply();
                return;
            }

            var data = res[0];
            $scope.fallbackCountData = ChartState.DataReady;

            var totalFallbackCounts = (data.DPFallbackCount + data.CloudDPFallbackCount);

            var chartData = [];
            var firstRow = [$scope.strings.NumberOfDownloads];
            firstRow.push(data["DPFallbackCount"]);
            firstRow.push(data["CloudDPFallbackCount"]);
            chartData.push(firstRow);
            var secondRow = [$scope.strings.DownloadType, $scope.fallbackNames["DPFallbackCount"], $scope.fallbackNames["CloudDPFallbackCount"]];
            chartData.push(secondRow);



            var c3Obj = {
                bindto: "#fallback-counts",
                size: {
                    height: 250,
                    width: 330
                },
                data: {
                    x: $scope.strings.DownloadType,
                    names: $scope.fallbackNames,
                    columns: chartData,
                    type: "bar",
                    order: null,
                    color: function (color, data) {
                        return sourceColors['DPFallbackCount'];
                    }
                },
                axis: {
                    rotated: false,
                    x: {
                        type: 'category',
                        categories: [""]
                    },
                    y: {
                        tick: {
                            format: function (x) {
                                return (x == Math.floor(x)) ? x : "";
                            }
                        },
                        label: {
                            text: $scope.strings.NumberOfDownloads,
                            position: 'outer-middle',
                        }
                    }
                },
                legend: {
                    show: false
                },
                tooltip: {
                    grouped: false,
                    format: {
                        // Tooltip shows number of fallback counts instead of ratio
                        value: function (value, ratio, id) {
                            return value;
                        }
                    }
                }
            }
            c3.generate(c3Obj);

            // Setup aria string for fallback chart
            var fallbackDetailsSummaryText = "";
            for (var value in chartData) {
                fallbackDetailsSummaryText += $scope.strings[chartData[value][0]] + ", " + chartData[value][1] + ". ";
            }
            var fallbackDetailsAriaLabel = document.getElementById("fallback-counts");
            fallbackDetailsAriaLabel.setAttribute("aria-label", fallbackDetailsSummaryText)

            // Accessibility. In high contrast mode set all text to white
            if ($scope.brightness < 125) {
                SetColorToAllTextInChart("#fallback-counts", 'white');
            }

            $scope.$apply();
        }



        function refreshContentStatsCallback(res) {
   
            if (res.length == 0) {
                console.log("GetClientDataSourcesContentStats returned no results");
                $scope.packageChartData = ChartState.NoDataFound;
                $scope.$apply();
                return;
            }


            $scope.packageChartData = ChartState.DataReady;

            var c3ChartArr = {
                DPBytes: ['DPBytes'],
                CloudDPBytes: ['CloudDPBytes'],
                BranchCacheBytes: ['BranchCacheBytes'],
                SPBytes: ['SPBytes'],
                DOPeerBytes: ['DOPeerBytes'],
                //DOCacheServerBytes: ['DOCacheServerBytes'],
                WUMUBytes: ['WUMUBytes'],
            };

            // construct the data object to be as follows
            /*
                * {contentName: {PeerCacheBytes: 500, DistributionPointBytes: 250}
                *
                */

            // these loops shouldn't be lengthy since there's a max of 10 apps returned and each one can only have downloads from up to 4 source types

            var data = {};
            for (var i = 0; i < res.length; i++) {
                var row = res[i];
                if (data[row.ContentName] == null)
                    data[row.ContentName] = {}

                data[row.ContentName][$scope.sourceTypeNames[row.SourceType]] = parseInt(row.BytesDownloaded) * (1024 * 1024);
            }

            // calculate totals for each app
            for (var content in data) {
                data[content].totalBytes = 0;
                for (var sourceType in c3ChartArr) {
                    data[content].totalBytes += data[content][sourceType] || 0;
                }
            }

            // convert data to an array and sort the apps by their total bytes
            var sortingHelper = [];
            for (var content in data) {
                sortingHelper.push({ name: content, totalBytes: data[content].totalBytes });
            }

            sortingHelper.sort(function (app1, app2) {
                return app2.totalBytes - app1.totalBytes;
            });

            // loop over each app
            // add their bytes for each source type into the chart data arrays
            var contentNames = [];
            for (var i = 0; i < sortingHelper.length; i++) {
                var contentName = sortingHelper[i].name;
                contentNames.push(contentName)
                for (var sourceType in c3ChartArr) {
                    var numBytesDownloaded = data[contentName][sourceType] || 0;
                    c3ChartArr[sourceType].push(numBytesDownloaded);
                }
            }

            //set back to initial state of content table
            var topContentTable = document.getElementById('top-content-table');

            topContentTable.innerHTML = "<div class=\"row\">" +
                " <div class=\"cell\">" + $scope.strings["ContentName"] + "</div>" +
                " <div class=\"cell\">" + $scope.strings["DistributionPoint"] + "</div>" +
                " <div class=\"cell\">" + $scope.strings["CloudDistributionPoint"] + "</div>" +
                " <div class=\"cell\">" + $scope.strings["BranchCache"] + "</div>" +
                " <div class=\"cell\">" + $scope.strings["PeerCache"] + "</div>" +
                " <div class=\"cell\">" + $scope.strings["DOPeerBytes"] + "</div>" +
                " <div class=\"cell\">" + $scope.strings["WUMUBytes"] + "</div>" +
                "</div>"

            // only display up to 5 contents
            for (var i = 0; i < contentNames.length && i < 5; i++) {
                var dpBytes = (typeof c3ChartArr.DPBytes[i + 1] === 'undefined') ? 0 : c3ChartArr.DPBytes[i + 1];
                var cloudDpBytes = (typeof c3ChartArr.CloudDPBytes[i + 1] === 'undefined') ? 0 : c3ChartArr.CloudDPBytes[i + 1];
                var branchCacheBytes = (typeof c3ChartArr.BranchCacheBytes[i + 1] === 'undefined') ? 0 : c3ChartArr.BranchCacheBytes[i + 1];
                var spBytes = (typeof c3ChartArr.SPBytes[i + 1] === 'undefined') ? 0 : c3ChartArr.SPBytes[i + 1];
                var doPeerBytes = (typeof c3ChartArr.DOPeerBytes[i + 1] === 'undefined') ? 0 : c3ChartArr.DOPeerBytes[i + 1];
                var wumuBytes = (typeof c3ChartArr.WUMUBytes[i + 1] === 'undefined') ? 0 : c3ChartArr.WUMUBytes[i + 1];
                topContentTable.innerHTML += "<div class=\"row\">" +
                    "<div class=\"cell\">" + contentNames[i] + "</div>" +
                    "<div class=\"cell\">" + (dpBytes / 1048576).toFixed(1) + "</div>" +
                    "<div class=\"cell\">" + (cloudDpBytes / 1048576).toFixed(1) + "</div>" +
                    "<div class=\"cell\">" + (branchCacheBytes / 1048576).toFixed(1) + "</div>" +
                    "<div class=\"cell\">" + (spBytes / 1048576).toFixed(1) + "</div>" +
                    "<div class=\"cell\">" + (doPeerBytes / 1048576).toFixed(1) + "</div>" +
                    "<div class=\"cell\">" + (wumuBytes / 1048576).toFixed(1) + "</div>" +
                    "</div>"
            }


            // dynamically resize package sources chart to avoid label overlap
            var chart = document.getElementById('package-sources-chart');
            chart.style.height = (410 + 40 * contentNames.length) + "px";

            var c3Obj = {
                bindto: "#package-sources",
                size: {
                    height: 350 + 40 * contentNames.length,
                    width: 1025
                },
                data: {
                    columns: [
                        c3ChartArr.DPBytes,
                        c3ChartArr.CloudDPBytes,
                        c3ChartArr.BranchCacheBytes,
                        c3ChartArr.SPBytes,
                        c3ChartArr.DOPeerBytes,
                        //c3ChartArr.DOCacheServerBytes,
                        c3ChartArr.WUMUBytes,
                    ],
                    type: "bar",
                    order: null,
                    color: function (color, data) {
                        if ((typeof data === 'string' || data instanceof String) && data in colors) {
                            return colors[data]
                        } else if (data.id != null) {
                            return colors[data.id]
                        } else {
                            return color;
                        }
                    },
                    groups: [Object.keys(c3ChartArr)],
                    names: $scope.sourceNames
                },
                legend: {
                    position: 'right'
                },
                axis: {
                    rotated: true,
                    y: {
                        tick: {
                            format: function (bytes) { return formatBytesString(bytes, 1); },
                            count: 5
                        }
                    },
                    x: {
                        type: 'category',
                        categories: contentNames
                    }
                }
            };

            c3.generate(c3Obj);


            // Setup aria string for top distributed content chart
            var topDistributedContentDetailsSummaryText = "";
            for (var i = 0; i < sortingHelper.length; i++) {
                var contentName = sortingHelper[i].name;
                topDistributedContentDetailsSummaryText += contentName + " , ";
                for (var sourceType in c3ChartArr) {
                    var formattedBytes = formatBytesString(data[contentName][sourceType]);
                    if (formattedBytes != "NaN bytes") {
                        topDistributedContentDetailsSummaryText += $scope.strings[sourceType] + "," + formattedBytes + " . ";
                    }
                }
            }
            var topDistributedContentDetailsAriaLabel = document.getElementById("package-sources");
            topDistributedContentDetailsAriaLabel.setAttribute("aria-label", topDistributedContentDetailsSummaryText);

            // Accessibility. In high contrast mode set all text to white
            if ($scope.brightness < 125) {
                SetColorToAllTextInChart("#package-sources", 'white');
            }

            $scope.$apply();
        }

        ////////////////////////////////////////////
        // Functions/Callbacks for refreshing the page data

        function refreshComplete(res) {
            refreshDeviceCountCallback(res[0]);
            refreshContentCallback(res[1]);
            refreshFallbackCountCallback(res[2]);
            refreshContentStatsCallback(res[3]);
            setUserControlState(true);
        }

        async function refreshDataSources() {
            $scope.contentData = ChartState.Loading;
            $scope.packageChartData = ChartState.Loading;
            $scope.deviceCountData = ChartState.Loading;
            $scope.fallbackCountData = ChartState.Loading;
            setUserControlState(false);
         
            var res = await callJsonParseMethodAsync("RefreshClientDataSourcesData", JSON.stringify([$scope.selectionType, $scope.boundaryGroupID, $scope.timePeriod.value]));
            refreshComplete(res);
        }

        function refreshDataSources_WatchChangedOnly(newValue, oldValue) {
            if ((!$scope.suppressRefresh) && (newValue != oldValue) && (oldValue != null)) { // this is a way to prevent the wql from being called twice when the page loads since both parameters change when they are first set
                refreshDataSources();
            }
        }

        ////////////////////////////////////////////
        // Main function for creating the source bytes donut chart

        function createSourceBytesDonutChart(c3ChartSelector, columns) {
            var c3ChartObject = createDonutChart(c3ChartSelector, columns)
            angular.merge(c3ChartObject, {
                size: {
                    height: 250,
                    width: 330
                },
                data: {
                    names: $scope.sourceNames,
                    color: function (color, data) {
                        if ((typeof data === 'string' || data instanceof String) && data in colors) {
                            return colors[data]
                        } else if (data.id != null) {
                            return colors[data.id]
                        } else {
                            return color;
                        }
                    },
                    order: null,
                },
                legend: {
                    position: "bottom",
                },
                donut: {
                    label: {
                        format: undefined //this removes the default in createDonutChart() that shows that value instead of the ratio
                    },
                    width: 45
                },
                tooltip: {
                    format: {
                        value: function (value) {
                            return formatBytesString(value);
                        }
                    }
                }
            });

            c3.generate(c3ChartObject);

            // Accessibility. In high contrast mode set all text to white
            if ($scope.brightness < 125) {
                SetColorToAllTextInChart("#content-types", 'white');
            }

            $scope.$apply();
        }

        // helper method to launch the single boundary group picker
        $scope.LaunchBoundaryGroupPickerWizard = async function () {

            var data = await callJsonParseMethodAsync("LaunchBoundaryGroupWizard", null);
            if (data == "") {
                return;
            }
            if (data.length == 0) {
                $scope.boundaryGroupName = "NaN";
                $scope.boundaryGroupID = 0;
                $scope.$apply();
                return;
            }
            $scope.boundaryGroupName = data[0].Name;
            $scope.boundaryGroupID = Number(data[0].GroupID);
            $scope.$apply();
        }

        $scope.toggleClientContentSourcesChart = function () {
            var clientContentSourcesTable = document.getElementById('content-sources-table');
            var clientContentSourcesChart = document.getElementById('content-sources-chart');
            var showChartButton = document.getElementById('showClientContentSourcesChartButton');
            if (clientContentSourcesTable.style.display == 'none' || clientContentSourcesTable.style.display == '') {
                clientContentSourcesTable.style.display = 'table';
                clientContentSourcesChart.style.display = 'none';
                showChartButton.innerHTML = $scope.strings["ShowChart"];
            }
            else if (clientContentSourcesTable.style.display = 'table') {
                clientContentSourcesTable.style.display = 'none';
                clientContentSourcesChart.style.display = 'block';
                showChartButton.innerHTML = $scope.strings["ShowTable"];
            }
        }

        $scope.toggleTopContentChart = function () {
            var topContentTable = document.getElementById('top-content-table');
            var topContentChart = document.getElementById('top-content-chart');
            var showChartButton = document.getElementById('showTopContentChartButton');
            var topContentTableFootnote = document.getElementById('top-content-table-footnote');
            if (topContentTable.style.display == 'none' || topContentTable.style.display == '') {
                topContentTable.style.display = 'table';
                topContentChart.style.display = 'none';
                topContentTableFootnote.style.display = 'block';
                showChartButton.innerHTML = $scope.strings["ShowChart"];
            }
            else if (topContentTable.style.display = 'table') {
                topContentTable.style.display = 'none';
                topContentTableFootnote.style.display = 'none';
                topContentChart.style.display = 'block';
                showChartButton.innerHTML = $scope.strings["ShowTable"];
            }
        }

        ////////////////////////////////////////////
        // Add OnClick handlers for the radio buttons
        // All of the radio buttons have a name of 'clientType'.
        // Knowing this we can search the 'clientSelection' form for all elements named 'clientType'

        function dataSourceRadioButtonOnClick() {
            // if the radio button is not single boundary group, disable browse buttons
            var singleBoundary = document.getElementById('boundaryGroupAria');
            if (singleBoundary.checked) {
                document.getElementById('browseButton').disabled = false;
                document.getElementById('displayLabel').disabled = false;
            } else {
                document.getElementById('browseButton').disabled = true;
                document.getElementById('displayLabel').disabled = true;
            }
            // set the selectionType value based on the selected radio button
            $scope.selectionType = Number(this.value);
            refreshDataSources();
        }


    })
}());

// SIG // Begin signature block
// SIG // MIInyAYJKoZIhvcNAQcCoIInuTCCJ7UCAQExDzANBglg
// SIG // hkgBZQMEAgEFADB3BgorBgEEAYI3AgEEoGkwZzAyBgor
// SIG // BgEEAYI3AgEeMCQCAQEEEBDgyQbOONQRoqMAEEvTUJAC
// SIG // AQACAQACAQACAQACAQAwMTANBglghkgBZQMEAgEFAAQg
// SIG // 418nohzSJzpU2/RDdLdG/nTCGEqAgk1tln3aIqcoScqg
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
// SIG // ARUwLwYJKoZIhvcNAQkEMSIEIObTu7C8vJi1OMQtMKxI
// SIG // +FvDuCfUDOEkbDWvebU10q5WMEIGCisGAQQBgjcCAQwx
// SIG // NDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRw
// SIG // Oi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEB
// SIG // BQAEggEAK1nUC4l7Ww+o/6ebDFnQxaogizCF7++/cXOa
// SIG // 26S3J95jCiDWykPgE9Bqi+/huRhylMoPlU8FZKiowzwF
// SIG // KCZiWSk4hv95I1kowcwhuN5spAlaMf+5PsUxuNW5wciA
// SIG // tmsVuxZRC1+oukBHuHAO/VM4RnuVcs3WjsHY4nKnD+Lm
// SIG // vOSHAhruo/vze+lFxveFAs5IE6QQoGFPqf5iyu8dut4c
// SIG // Tw8xJ46dzhmRtm98OQSpRMvNcn5Bjue+WDSDP/SAL9jl
// SIG // sRwoEFnkm/hRHJ8JxICO9X38txfiumx1Sx9ZECJFiLrP
// SIG // 4ffPjLb9Ju0x9kVSaPcW/9ZrizQyJP5S2bsq13tBwKGC
// SIG // FykwghclBgorBgEEAYI3AwMBMYIXFTCCFxEGCSqGSIb3
// SIG // DQEHAqCCFwIwghb+AgEDMQ8wDQYJYIZIAWUDBAIBBQAw
// SIG // ggFZBgsqhkiG9w0BCRABBKCCAUgEggFEMIIBQAIBAQYK
// SIG // KwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCAbz5Mn
// SIG // htjRC7SSix6UH1BhyQ0u8lxADUUxpB8XKvHY9gIGY2Ph
// SIG // hC7BGBMyMDIyMTEwNDE3MjMzOS4wNzFaMASAAgH0oIHY
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
// SIG // sGqvYcgTrNuja7S+9eW/av/5J4VjbkvwQYFjAoLGnwIw
// SIG // gfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCApVb08
// SIG // M25w+tYGWsmlGtp1gy1nPcqWfqgMF3nlWYVzBTCBmDCB
// SIG // gKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
// SIG // aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
// SIG // ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMT
// SIG // HU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMz
// SIG // AAABuh8/GffBdb18AAEAAAG6MCIEILveL+81/fgI1uLT
// SIG // 9XPqAMVR3MPdwkQQqt8OF70GQ6BiMA0GCSqGSIb3DQEB
// SIG // CwUABIICAD/Wq5GR6JeFg+RwfqjY7y7fq7RjIUvWnpwt
// SIG // t9hwQMRTttdJq9+ZYdj20TKewbKbyR6bCj3Pljfrz85N
// SIG // PD5i/UPpBjL/9xjY1KcjnKzNK5VMDlOO5YlbtY0Iq07J
// SIG // O2VyoqQuYYXb21m7poZIpEi/gYt0/CMZbXrocL0ioF0l
// SIG // 903tZi6IuD2GrwuZvFJBN30aX51dnzYwmQ8ZyUITLB2d
// SIG // /tMlGyY8i7wfhelZhCguL6w2Cg6+9ktIIr5bdn9d/N1V
// SIG // Od0tpu7lIlad5KdJjJeoeN2h6O7z6MbwWmG1UsPIVlta
// SIG // DxPUedKHvMsVZxVPvcfgf+8Kw0HrWMIQcCxrfd3z9GzF
// SIG // xMSX5YoJHMliEUf5MmfVF+Dt3B8hPfStaYE/Z7EBjkhP
// SIG // bsJfHKef0tjgkMiZdrJVh5sI22DaBV8X/Px4KhPtlb6+
// SIG // 5iZZHnC33VB1d9h4ReIyA75eALdrY/jKSrE9pWYl93d2
// SIG // DAaTqBa2fEwxPKN7JSskFmqIMnuUlem/hWTGVhrme7t7
// SIG // i8lNXNLNpnxX1Oy9F839ovH4lZXdAJM3/HImJuhik66O
// SIG // YhTzCqMa1G3w349I5Ve5If0zybm/ucMjQoLjNa+3Yy6Z
// SIG // vVFGvaeZHTYtb1kPbMigdkyTUQSxYTaw6HPj/aapceoG
// SIG // /OLE+QcSLItrbA+/cSOoYqFwk7vtNhmK
// SIG // End signature block
