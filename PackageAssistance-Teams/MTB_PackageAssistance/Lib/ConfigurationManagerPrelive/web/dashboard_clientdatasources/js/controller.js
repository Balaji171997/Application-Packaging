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

            setAriaShowTableTopDistCont();
            setAriaShowTableClientContentSource();

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

            setInitialStateOfContentTable();
           
            // only display up to 5 contents
            for (var i = 0; i < contentNames.length && i < 5; i++) {
                var dpBytes = (typeof c3ChartArr.DPBytes[i + 1] === 'undefined') ? 0 : c3ChartArr.DPBytes[i + 1];
                var cloudDpBytes = (typeof c3ChartArr.CloudDPBytes[i + 1] === 'undefined') ? 0 : c3ChartArr.CloudDPBytes[i + 1];
                var branchCacheBytes = (typeof c3ChartArr.BranchCacheBytes[i + 1] === 'undefined') ? 0 : c3ChartArr.BranchCacheBytes[i + 1];
                var spBytes = (typeof c3ChartArr.SPBytes[i + 1] === 'undefined') ? 0 : c3ChartArr.SPBytes[i + 1];
                var doPeerBytes = (typeof c3ChartArr.DOPeerBytes[i + 1] === 'undefined') ? 0 : c3ChartArr.DOPeerBytes[i + 1];
                var wumuBytes = (typeof c3ChartArr.WUMUBytes[i + 1] === 'undefined') ? 0 : c3ChartArr.WUMUBytes[i + 1];


                var topContentTable = document.getElementById('top-content-table');

                var div = "div";
                var row = "row";
                var cell = "cell";

                var addFirstDivRow = document.createElement(div);
                addFirstDivRow.className = row;

                var addContentNamesCell = document.createElement(div);
                addContentNamesCell.className = cell;
                addContentNamesCell.appendChild(document.createTextNode(contentNames[i]));

                var addDpBytesCell = document.createElement(div);
                addDpBytesCell.className = cell;
                addDpBytesCell.appendChild(document.createTextNode((dpBytes / 1048576).toFixed(1)));

                var addCloudDpBytesCell = document.createElement(div);
                addCloudDpBytesCell.className = cell;
                addCloudDpBytesCell.appendChild(document.createTextNode((cloudDpBytes / 1048576).toFixed(1)));


                var addBranchCacheBytesCell = document.createElement(div);
                addBranchCacheBytesCell.className = cell;
                addBranchCacheBytesCell.appendChild(document.createTextNode((branchCacheBytes / 1048576).toFixed(1)));


                var addSpBytesCell = document.createElement(div);
                addSpBytesCell.className = cell;
                addSpBytesCell.appendChild(document.createTextNode((spBytes / 1048576).toFixed(1)));

                var addDoPeerBytesCell = document.createElement(div);
                addDoPeerBytesCell.className = cell;
                addDoPeerBytesCell.appendChild(document.createTextNode((doPeerBytes / 1048576).toFixed(1)));


                var addWumuBytesCell = document.createElement(div);
                addWumuBytesCell.className = cell;
                addWumuBytesCell.appendChild(document.createTextNode((wumuBytes / 1048576).toFixed(1)));

                addFirstDivRow.appendChild(addContentNamesCell);
                addFirstDivRow.appendChild(addDpBytesCell);
                addFirstDivRow.appendChild(addCloudDpBytesCell);
                addFirstDivRow.appendChild(addBranchCacheBytesCell);
                addFirstDivRow.appendChild(addSpBytesCell);
                addFirstDivRow.appendChild(addDoPeerBytesCell);
                addFirstDivRow.appendChild(addWumuBytesCell);
                
                if (topContentTable.childNodes[i + 2]) {
                    topContentTable.replaceChild(addFirstDivRow, topContentTable.childNodes[i + 2]);
                }
                else {
                    topContentTable.appendChild(addFirstDivRow);
                }

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
                showChartButton.textContent = $scope.strings["ShowChart"];
                setAriaShowChartClientContentSource();
                document.getElementById('content-sources-table').focus();
            }
            else if (clientContentSourcesTable.style.display = 'table') {
                clientContentSourcesTable.style.display = 'none';
                clientContentSourcesChart.style.display = 'block';
                showChartButton.textContent = $scope.strings["ShowTable"];
                setAriaShowTableClientContentSource();
                document.getElementById('content-types').focus();
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
                showChartButton.textContent = $scope.strings["ShowChart"];
                setAriaShowChartTopDistCont();
                document.getElementById('top-content-table').focus();
            }
            else if (topContentTable.style.display = 'table') {
                topContentTable.style.display = 'none';
                topContentTableFootnote.style.display = 'none';
                topContentChart.style.display = 'block';
                showChartButton.textContent = $scope.strings["ShowTable"];
                setAriaShowTableTopDistCont();
                document.getElementById('package-sources').focus();
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

        function setInitialStateOfContentTable() {

            var topContentTable = document.getElementById('top-content-table');

            var div = "div";
            var row = "row";
            var cell = "cell";

            var addFirstDivRow = document.createElement(div);
            addFirstDivRow.className = row;

            var addContentNameCell = document.createElement(div);
            addContentNameCell.className = cell;
            addContentNameCell.appendChild(document.createTextNode($scope.strings["ContentName"]));

            var addDPCell = document.createElement(div);
            addDPCell.className = cell;
            addDPCell.appendChild(document.createTextNode($scope.strings["DistributionPoint"]));

            var addCDPCell = document.createElement(div);
            addCDPCell.className = cell;
            addCDPCell.appendChild(document.createTextNode($scope.strings["CloudDistributionPoint"]));


            var addDBranchCacheCell = document.createElement(div);
            addDBranchCacheCell.className = cell;
            addDBranchCacheCell.appendChild(document.createTextNode($scope.strings["BranchCache"]));


            var addPeerCacheCell = document.createElement(div);
            addPeerCacheCell.className = cell;
            addPeerCacheCell.appendChild(document.createTextNode($scope.strings["PeerCache"]));

            var addDOPeerBytesCell = document.createElement(div);
            addDOPeerBytesCell.className = cell;
            addDOPeerBytesCell.appendChild(document.createTextNode($scope.strings["DOPeerBytes"]));


            var addWUMUBytesCell = document.createElement(div);
            addWUMUBytesCell.className = cell;
            addWUMUBytesCell.appendChild(document.createTextNode($scope.strings["WUMUBytes"]));

            addFirstDivRow.appendChild(addContentNameCell);
            addFirstDivRow.appendChild(addDPCell);
            addFirstDivRow.appendChild(addCDPCell);
            addFirstDivRow.appendChild(addDBranchCacheCell);
            addFirstDivRow.appendChild(addPeerCacheCell);
            addFirstDivRow.appendChild(addDOPeerBytesCell);
            addFirstDivRow.appendChild(addWUMUBytesCell);

            topContentTable.replaceChild(addFirstDivRow, topContentTable.childNodes[1]);         

        }

        function setAriaShowTableTopDistCont() {
            var showTableTopDistContText = $scope.strings['ShowTableTopDistCont'];
            var showTableTopDistContAriaLabel = document.getElementById("showTopContentChartButton");
            showTableTopDistContAriaLabel.setAttribute("aria-label", showTableTopDistContText);

        }

        function setAriaShowChartTopDistCont() {
            var showChartTopDistContText = $scope.strings['ShowChartTopDistCont'];
            var showChartTopDistContAriaLabel = document.getElementById("showTopContentChartButton");
            showChartTopDistContAriaLabel.setAttribute("aria-label", showChartTopDistContText);

        }

        function setAriaShowChartClientContentSource() {
            var showChartClientContentSourceText = $scope.strings['ShowChartClientContentSource'];
            var showChartClientContentSourceAriaLabel = document.getElementById("showClientContentSourcesChartButton");
            showChartClientContentSourceAriaLabel.setAttribute("aria-label", showChartClientContentSourceText);

        }

        function setAriaShowTableClientContentSource() {
            var showTableClientContentSourceText = $scope.strings['ShowTableClientContentSource'];
            var showTableClientContentSourceAriaLabel = document.getElementById("showClientContentSourcesChartButton");
            showTableClientContentSourceAriaLabel.setAttribute("aria-label", showTableClientContentSourceText);
        }

        
       


    })
}());

// SIG // Begin signature block
// SIG // MIIonAYJKoZIhvcNAQcCoIIojTCCKIkCAQExDzANBglg
// SIG // hkgBZQMEAgEFADB3BgorBgEEAYI3AgEEoGkwZzAyBgor
// SIG // BgEEAYI3AgEeMCQCAQEEEBDgyQbOONQRoqMAEEvTUJAC
// SIG // AQACAQACAQACAQACAQAwMTANBglghkgBZQMEAgEFAAQg
// SIG // XE94AGgOtiAwGEbFITM1IQ2Kg+GBkNrgGi92HZcBKySg
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
// SIG // AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCBRz/HmKTB3H8qQ
// SIG // CiZ0QLpwVDC6a2djyVAW9lkAC8fByTCBigYKKwYBBAGC
// SIG // NwIBDDF8MHqgXIBaAE0AaQBjAHIAbwBzAG8AZgB0AC4A
// SIG // VABvAG8AbABrAGkAdAAuAFcAcABmAC4AVQBJAC4AQwBv
// SIG // AG4AdAByAG8AbABzAC4AVwBlAGIAVgBpAGUAdwAuAGQA
// SIG // bABsoRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
// SIG // BgkqhkiG9w0BAQEFAASCAQAitROwHqxSLWBBRMwGd6xq
// SIG // RqHP7SaeWb0Frhu7Q7Zm4JnG/rsAm3za8qKyEbAFqrBu
// SIG // 5ozOY1bZpJqP24EVcCZ7RSHRxw3WfIKdfaavOLIkxiHP
// SIG // QvYBkqFWp15WprrXh0KJPlxpdowk0/ZyIPZNC0plrmaM
// SIG // sRA4fTkEmuOUhzZlxS0/lD2aydcLV7aRytLSIo1tL4JX
// SIG // VRLtsYlyJ9Fuekf1hkX+qSgEKzxQ6EWCWFov6sBcoUa+
// SIG // fjDGCY2a0lzuKD/DIttzUGcXahTYLJXPsVQlgwS8lR0t
// SIG // ec6W8NkbFzVtqQu4M9CsKFnSPT9lBh6k7NJqITm91si3
// SIG // ElYyuY3QeBc8oYIXsDCCF6wGCisGAQQBgjcDAwExghec
// SIG // MIIXmAYJKoZIhvcNAQcCoIIXiTCCF4UCAQMxDzANBglg
// SIG // hkgBZQMEAgEFADCCAVoGCyqGSIb3DQEJEAEEoIIBSQSC
// SIG // AUUwggFBAgEBBgorBgEEAYRZCgMBMDEwDQYJYIZIAWUD
// SIG // BAIBBQAEII9H2KNvr7Sz31916cymdz2R1TjvdvnGiPMT
// SIG // 7FMRMWTpAgZo8qG4uXQYEzIwMjUxMDIzMDI0NjAwLjIx
// SIG // OVowBIACAfSggdmkgdYwgdMxCzAJBgNVBAYTAlVTMRMw
// SIG // EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
// SIG // b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
// SIG // b24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9w
// SIG // ZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNoaWVs
// SIG // ZCBUU1MgRVNOOjZGMUEtMDVFMC1EOTQ3MSUwIwYDVQQD
// SIG // ExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloIIR
// SIG // /jCCBygwggUQoAMCAQICEzMAAAIcCVUV18NZB9EAAQAA
// SIG // AhwwDQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMx
// SIG // EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
// SIG // ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
// SIG // dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3Rh
// SIG // bXAgUENBIDIwMTAwHhcNMjUwODE0MTg0ODMxWhcNMjYx
// SIG // MTEzMTg0ODMxWjCB0zELMAkGA1UEBhMCVVMxEzARBgNV
// SIG // BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
// SIG // HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEt
// SIG // MCsGA1UECxMkTWljcm9zb2Z0IElyZWxhbmQgT3BlcmF0
// SIG // aW9ucyBMaW1pdGVkMScwJQYDVQQLEx5uU2hpZWxkIFRT
// SIG // UyBFU046NkYxQS0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1p
// SIG // Y3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0G
// SIG // CSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCjDTEQBRoU
// SIG // jLIshd4XN4jwgrIE43a7QOvTYhITmn0bkJRd+cW7ZLQT
// SIG // WBYIy8NamilfqVHGOaCepovcG2daUFVOjzFQ1Fm7beJ7
// SIG // hgEwAkHtS3qaeqcdXC8MnEY7hMPdKesJ37KDfkH1AV6O
// SIG // rejj44HK9ePKdrKlnK6RxBouwpC+jETwSUcfvNw5cQla
// SIG // ZTeudfNpb9LhIfc4+GhRtNNzLqdSArHmlFaJDbhQQ8tj
// SIG // NzEYmOqOTP4aIJYY8UcMx1bzqVpa+YKyWi5A+w3Z4GTx
// SIG // 3ElwRmZbiXqnhO2Ghdx97EQD1h1hozPXRoyFk2l2w1oO
// SIG // 0NBQwMQLeTUPUzLr0xdI+VSYP3EXIOWReJVrsEISnddx
// SIG // W2pODMcbCvbwkPqgTvMQ9h65k6K4IFdNlKj/CTe1sOWw
// SIG // RJsg9XqKdiqvPGIxiqXF8J3MLcKKaH381P8uT39pT4jL
// SIG // Jz1vc5pPR1nzCAtpUMIYQtEyurIiZ0Ue/Qy51y3Nb+Q+
// SIG // xXclr25+kpa6MSI3cJb/9fyEVr2PkiY15DNwyK3cyhJq
// SIG // gbCduJklfUjKJsimGWpxxcWTihNNI5AGwBTDxTSDA6cz
// SIG // lQkPyYFQF3rk2no0GTHZy+IngjfgbJcUJbLLkW3VCwFj
// SIG // JV8Abco6EJ88dB/yVDMm8uvnthbRsP/FWzgCDiBNLopk
// SIG // 3IUR9f2MV1GWvQIDAQABo4IBSTCCAUUwHQYDVR0OBBYE
// SIG // FFreY4LMHy7vOm8OHwwYpVgsKTtkMB8GA1UdIwQYMBaA
// SIG // FJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYw
// SIG // VKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9w
// SIG // a2lvcHMvY3JsL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAl
// SIG // MjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRg
// SIG // MF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9z
// SIG // b2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIw
// SIG // VGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwG
// SIG // A1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUH
// SIG // AwgwDgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUA
// SIG // A4ICAQCSVvrD915qJ3cG6NAK1YUF7Sf2mTJHL7LJYSDv
// SIG // SIPCgnm7R7Q77gZ6s3N1lvXNM+wcnwQYzKjUrvK0vbX6
// SIG // mZ0UxOXX08Lw4nljan5cpRDLZ0P6GCBEyYmANCyBs4LE
// SIG // dh476ODi36+DrXBSui/PMuQffPQ8lde+g24GP0t1r0KI
// SIG // 0x3rTjnUq5t730CtJ/pkyPe3SnisVuBJrMOz7xMn7woD
// SIG // kZVpiM8eP2uUy4jdaOiERz1qmdDqEyMxyTeOUdkjCW5V
// SIG // h5RATSqOYCl8y1MATNsxR1jywtO6cvUaRsNJ4qf07uWU
// SIG // Eac23IzW4z0x2/VXJaHTP8iuJAoiOe2qobKgXQe8Mc4V
// SIG // kLJQME8t+XKK7tjXND+w+i6exv3poF9B2reHcs6fq36b
// SIG // 0Sc3P8bozPNa+kmTpiBMdMip5A38X9emI+9t96Teer89
// SIG // hsvdq76QF9FQeIIVdK+3qWivQcLrbq9SbP1k087HARYu
// SIG // 5xyibGzLcnBYfv2+wz/sBGqgbmHp3o1qF9o65E/hcj3G
// SIG // 10fc9r80IvJCPEpfIvHPBDON12RfYSlMmeXKm6E+YR15
// SIG // rn1TPYTfTcvHJdKcoG8awCfJZgB+d6OvdgCIv1is3aXZ
// SIG // 2fX3xGkDgMKb1C1liLALSrZ+5S+6Lfg988hRkHJ/vAe6
// SIG // 5a7nSFj1YvHWQ4wjzHKjsAjpNo2ucjCCB3EwggVZoAMC
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
// SIG // OjZGMUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3Nv
// SIG // ZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4D
// SIG // AhoDFQBaZOIDTW7mbGr+dXGJEksw6yRUZ6CBgzCBgKR+
// SIG // MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5n
// SIG // dG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
// SIG // aWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1p
// SIG // Y3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqG
// SIG // SIb3DQEBCwUAAgUA7KO3NDAiGA8yMDI1MTAyMjIwMDQw
// SIG // NFoYDzIwMjUxMDIzMjAwNDA0WjB3MD0GCisGAQQBhFkK
// SIG // BAExLzAtMAoCBQDso7c0AgEAMAoCAQACAhhkAgH/MAcC
// SIG // AQACAhOAMAoCBQDspQi0AgEAMDYGCisGAQQBhFkKBAIx
// SIG // KDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAI
// SIG // AgEAAgMBhqAwDQYJKoZIhvcNAQELBQADggEBAFy+ffRz
// SIG // LZatShXbKNLAtTBkBeQ6EUdMxqvzUgeD7FVW4R9wPMat
// SIG // a4ZM/dlBBmDSnOopynVf1wvZbyro+wA7yupds5djL6Tn
// SIG // II1NR7fSY6RYM3v6kKcFCUhmGu9DSk5YpxlN68wipGT3
// SIG // ycB0/wJZE26lAz9s+bECZTNt6cbjHmnjiArQxNBKJB/U
// SIG // VC+pJkbjIPvOco0+baZFt3PtG9YcsdD0OiIzAFwxbzag
// SIG // VZU0572BM9yBimfKHSxSZ6QnFbMXW76/pcDQkGNr/4qL
// SIG // i3RJYlMqO4T01MtkzLfB9/mM2i3aaxH65x0Q1hrD6YdQ
// SIG // 9VJhtMr0aqvR4ZVBUULL0ybG7+QxggQNMIIECQIBATCB
// SIG // kzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
// SIG // Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
// SIG // TWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1N
// SIG // aWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAA
// SIG // AhwJVRXXw1kH0QABAAACHDANBglghkgBZQMEAgEFAKCC
// SIG // AUowGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8G
// SIG // CSqGSIb3DQEJBDEiBCACehjjzq3sgfWZiIT8ZmlsexJc
// SIG // +muNVu61z12rcmu2MzCB+gYLKoZIhvcNAQkQAi8xgeow
// SIG // gecwgeQwgb0EIKAgaSY2F2jv4oTt1aEj4TYK3HZEtahi
// SIG // +8mh0IhyIcdoMIGYMIGApH4wfDELMAkGA1UEBhMCVVMx
// SIG // EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
// SIG // ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
// SIG // dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3Rh
// SIG // bXAgUENBIDIwMTACEzMAAAIcCVUV18NZB9EAAQAAAhww
// SIG // IgQgxUNpuzqbgbMKgAtMn8Y9XFutNIGB7poEbD04uiId
// SIG // fVwwDQYJKoZIhvcNAQELBQAEggIAa4Bi0vWveXSEpo2N
// SIG // MN4AJRBel2kTZhHxBKE9yBAgmTTTtGe49YrWioXkTxOE
// SIG // XPzbctnSYZ2PR6XFq7uCnK1HjaglivqO0NoYPs96MjPI
// SIG // 6jU51a1PKCflYCiMKXhBus6xmAMxDTLoFtd/mrnD91nf
// SIG // h1EEPHl/+OWuqWkHxazs9gXUmGJXnnaE5D4FGjJ15EYD
// SIG // EaPNI82bYjtCc664jpksrgFEPTf+5eW1E1zzKXfP3Om3
// SIG // Npfc6+bCUUAgu3ry0oTLAL5s/GgkJdpMrwmh/eOmn2Tk
// SIG // Q+FDYxx5Kqd9WFavjwC+NDbLfkNmEBx4nomeQtzJ4Aru
// SIG // thfbbM35YMPfvrSEsSqPsAbSUfAHXScd+WGTvuYtL3B1
// SIG // luHZv0qYC5ayL2lCr92u/RpcDUURnumfVxlTnWywXbaG
// SIG // edHlUxURCpdUkE/cWFpWx2C28A8lqxoKpYaPMxOmiaWP
// SIG // 9xPvPqfWAJlSiWOkUpcZNO6Hx14+1+5fco2w0IFDf286
// SIG // /EMv/m5bTl5JPfi6/W+UWUG9vgOUsfnvrD2D2rgGdtah
// SIG // X1LOuW2mzRr9yrK7Bd0DJrDLKulNas4Sv+26HxNyAVit
// SIG // MS2bzEZTcjUlTH7h94qpTHLTy0xCQw4sdeJ9oIEXL/e+
// SIG // 33ypLA23HNdONwccoKP4kSzjEU+71oqGno21rYaZKF08
// SIG // k14NQ28=
// SIG // End signature block
