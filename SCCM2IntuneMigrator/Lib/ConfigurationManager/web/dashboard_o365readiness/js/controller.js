(function () {
    "use strict";

    var dashboard = angular.module("dashboard", []);

    dashboard.controller("dashboardController", function ($scope) {

        $scope.publicAddins = false;

        $scope.getTileImage = function (tileType) {
            return tileType.toLowerCase() + ".svg";
        };

        $scope.ChartState = ChartState; // for use in ng-expressions in html
        $scope.collectionsData = ChartState.Loading;
        $scope.ProplusReadiness = ChartState.Loading;
        $scope.strings = getStrings([
          "DeviceCollection",
          "Browse",
          "O365Architecture",
          "OfficeProplusReadiness",
          "Office365Installer",
         "O365ProLink",
          "O365ProText",
          "AddinReadiness",
          "AddinSupport",
          "TopAddinVersion",
          "DevicesWithMacros",
          "MacroReadiness",
          "MacroAdvisories",
          "publicAddinsString",
          "CreateReadyCollection",
          "ReadinessState_Ready",
          "ReadinessState_Review",
          "ReadinessState_NotAssessed",
          "ThirtyTwoBitArch",
          "SixtyFourBitArch",
          "NoData",
          "Device",
          "Devices",
          "Addin",
            "Addins",
            "AddinIssues",
            "UniqueAddinsString",
          "UniqueAddin",
          "UniqueAddins",
          "AddinReadiness_Ready",
          "AddinReadiness_Remediation",
          "AddinReadiness_NeedsReview",
          "AddinReadiness_PotentialIssues",
          "AddinSupport_Supported",
          "AddinSupport_NotProvided",
          "MacroInventory_HasMacros",
          "MacroInventory_MayHaveMacros",
          "MacroInventory_NoMacros",
          "MacroInventory_NotAllScanned",
          "MacroReadiness_Ready",
            "MacroReadiness_NeedsReview",
            "GaugeBottomString",
          "UniqueAddinsString",
          "CollectionString",
          "CodeDesignAwareness",
          "LimitedRemediationRequired",
          "MinimalValidationRecommended",
          "SignificantRemediationRequired",
          "O365ProPlus",
          "GaugeTitle",
          "DeviceReadinessTitle",
          "DeploymentLabel",
          "AriaDeploymentLabel",
          "AriaDeviceReadiness",
          "AriaAddInReadiness",
          "AriaAddinSupport",
          "AriaTopAddinsVersion",
          "AriaDevicesWithMacros",
          "AriaMacroReadiness",
          "AriaMacroAdvisories",
          "AddinChartTitle",
          "Counts"
        ]);

        $scope.getString = function (stringName) {
            return $scope.strings[stringName];
        };


        $scope.isO365InstallerOn = bridge.IsO365InstallerOn();

        // *** VARIABLE DECLARATIONS
        var COLL_DISP_LIMIT = 5; // determines the amount of collections displayed in the dropdown filter
        $scope.SMS_DeviceCollections = {}; //temp storage for collections data
        $scope.selectedCollId = "SMS00001";
        $scope.selectedColName = "All Systems";

        $scope.selectedArch = 'x86'; //intialize current architecture chosen for filter
        $scope.ReadinessData = true;
        $scope.strings.AriaDeploymentLabel = "";
        $scope.strings.AriaDeviceReadiness = "";
        $scope.strings.AriaAddInReadiness = "";
        $scope.strings.AriaAddinSupport = "";
        $scope.strings.AriaTopAddinsVersion = "";
        $scope.strings.AriaDevicesWithMacros = "";
        $scope.strings.AriaMacroReadiness = "";
        $scope.strings.AriaMacroAdvisories = "";

        $scope.OfficeProPlus = [$scope.strings.SixtyFourBitArch, $scope.strings.ThirtyTwoBitArch];

        // *** DATA QUERIES AND PREPARATION ***
        //gets collections data to load the Collections dropdown filter
        wmiQuery("SELECT CollectionID, Name, MemberCount FROM SMS_Collection Where CollectionType=2 ORDER BY Name",
          SMS_DeviceCollectionsReceived);

        function SMS_DeviceCollectionsReceived(res) {
            if (res.length == 0) {
                logger.err("SMS_Collection returned no results");
                $scope.collectionsData = ChartState.NoDataFound;
                $scope.$apply();
                return;
            }

            // store first n number of results n = COLL_DISP_LIMIT and set default selected to first(largest) collection
            $scope.SMS_DeviceCollections.All = res.slice(0, COLL_DISP_LIMIT);
            $scope.SMS_DeviceCollections.Selected = res[0];

            for (var i = 0; i < $scope.SMS_DeviceCollections.All.length; ++i) {
                $scope.SMS_DeviceCollections.All[i].Name = bridge.GetCollectionAliasName($scope.SMS_DeviceCollections.All[i].Name);
            }

            $scope.TargetArchitecture = $scope.OfficeProPlus[0];

            $scope.collectionsData = ChartState.DataReady;
            $scope.SMS_DeviceCollectionChanged();
            $scope.$apply();
        };

        $scope.SMS_DeviceCollectionChanged = function () {
            $scope.ProplusReadiness = ChartState.Loading;
            $scope.select_OfficeProArch();
        };

        /// <summary>Creates the Readiness Bar Chart</summary>
        /// <input>id</input>
        /// <input>OfficeProCounts - counts for each ready type for the given architecture</input>
        /// <returns></returns>
        function createOfficeReadinessBarChart(id, OfficeProCounts, $scope) {
            var counts = {};
            counts[$scope.strings.ReadinessState_Ready] = OfficeProCounts.Ready;
            counts[$scope.strings.ReadinessState_Review] = OfficeProCounts.NeedsReview;
            counts[$scope.strings.ReadinessState_NotAssessed] = OfficeProCounts.NotAssessed;

            var columns = {};
            columns = convertObjectToArrayOfArrays(counts, [$scope.strings.ReadinessState_Ready, $scope.strings.ReadinessState_Review]);

            $scope.strings.AriaDeviceReadiness = $scope.strings.DeviceReadinessTitle + ' ' + columns[0] + ',' + columns[1];

            var pattern = ["#008000", "#006ABA"];

            c3.generate({
                bindto: id,
                data: {
                    columns: columns,
                    type: 'bar',
                    onclick: function (d) {
                        if (id == "#readinessChart") {
                            window.external.DrillThroughReadinessChart(d.name, $scope.selectedArch, $scope.selectedCollId);
                        }
                    },
                    tooltip: {
                        show: false
                    },
                },
                grid: {
                    y: {
                        lines: [{ value: 0 }]
                    }
                },
                legend: {
                    position: 'right'
                },
                color: {
                    pattern: pattern
                },
                bar: {
                    width: {
                        ratio: 0.5 // this makes bar width 50% of length between ticks
                    }
                },
                size: {
                    height: 200,
                    width: 400
                },
                axis: {
                    x: {
                        show: true,
                        type: 'category',
                        categories: ['']
                    },
                    y: {
                        label: $scope.strings.Devices,
                        tick: {
                            format: function (y) {
                                if (y % 1 > 0) return '';
                                return y;
                            }
                        }
                    }
                }
            });
        };

        function createReadinessDonutChart(id, data, color)
        {
            if (noDataInColumns(data)) {
                $scope.createEmptyDonutChart(id);
            }
            else {

                c3.generate({
                    bindto: id,
                    data: {
                        columns: data,
                        type: 'donut',
                        onclick: function (d) {
                            window.external.DrillThroughReadinessChart(d.name, $scope.selectedArch);
                        },
                    },
                    color: {
                        pattern: color
                    },
                    donut: {
                        label: {
                            format: function (value) {
                                return value;
                            }
                        }
                    },
                    size: {
                        width: 320,
                        height: 200
                    },
                    legend: {
                        position: 'right'
                    }
                });
            }
        };

        /// <summary>generic function to create donut chart</summary>
        /// <input>id</input>
        /// <input>data array</input>
        /// <input>color array</input>
        /// <input>is drillThroughEnabled</input>
        /// <returns></returns>
        function createDonutChart(id, data, color, titleStr, drillThroughEnabled) {

            if (noDataInColumns(data)) {
                $scope.createEmptyDonutChart(id);
            }
            else {
                c3.generate({
                    bindto: id,
                    data: {
                        columns: data,
                        type: 'donut',
                        onclick: function (d) {
                            if (drillThroughEnabled && (id == "#addinReadinessChart")) {
                                window.external.DrillThroughAddinReadinessChart(d.name, $scope.selectedArch);
                            }
                            else if (drillThroughEnabled && (id == "#addinSupportChart")) {
                                window.external.DrillThroughAddinSupportChart(d.name, $scope.selectedArch);
                            }
                            else if (drillThroughEnabled && (id == "#devicesWithMacrosChart")) {
                                window.external.DrillThroughDevicesWithMacrosChart(d.name, $scope.selectedArch, $scope.selectedCollId);
                            }
                            else (drillThroughEnabled && (id == "#macroReadinessChart"))
                            {
                                window.external.DrillThroughMacroReadinessChart(d.name, $scope.selectedArch, $scope.selectedCollId);
                            }
                        },
                    },
                    color: {
                        pattern: color
                    },
                    donut: {
                        title: titleStr,
                        label: {
                            format: function (value) {
                                return value;
                            }
                        }
                    },
                    size: {
                        width: 320,
                        height: 250,
                    }
                });
            }
        };

        /// <summary>generic function to create empty donut chart</summary>
        /// <input>idToBindTo</input>
        /// <returns></returns>
        $scope.createEmptyDonutChart = function (idToBindTo) {
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
                            return $scope.strings.NoData;
                        },
                    }
                },
                size: {
                    height: 235,
                    width: 235
                }
            });
        };

        function createGaugeChart(id, data, labelStr) {
            $scope.strings.AriaDeploymentLabel = data[0] + '% ' + labelStr;
            c3.generate({
                bindto: id,
                data: {
                    columns: [
                        [$scope.strings.Devices, data[0]]
                    ],
                    type: 'gauge',
                    onclick: function (d, i) { console.log("onclick", d, i); },
                    onmouseover: function (d, i) { console.log("onmouseover", d, i); },
                    onmouseout: function (d, i) { console.log("onmouseout", d, i); }
                },

                gauge: {
                    label: {
                        format: function () {
                            var ratio = Math.round((data[0] / data[1]) * 100);
                            if (isNaN(ratio)) 
                                return '0%';
                            else
                                return ratio + '%';
                        },
                        show: true
                    },
                    min: 0, // 0 IS DEFAULT
                    max: data[1],
                    units: labelStr,
                    width: 48 // FOR ADJUSTING ARC THICKNESS
                },
                color: {
                    pattern: ['#008000', '#008000', '#008000', '#008000'], // the three color levels for the percentage values.
                    threshold: {
                        values: [30, 60, 90, 100]
                    }
                },
                size: {
                    height: 200
                }
            });
        }

        /// <summary>generic function to create horizontal bar chart</summary>
        /// <input>id</input>
        /// <input>strings</input>
        /// <input>data</input>
        /// <returns></returns>
        function createHorizontalBarChart(id, strings, data, data1, data2, data3) {
            var pattern = ["#1966FF"];

            c3.generate({
                bindto: id,
                data: {
                    x: 'x',
                    columns: [strings, data],
                    type: 'bar',
                    onclick: function (d, element) {
                        if (id == "#topAddinVersionChart") {
                            var category = strings[d.x + 1];
                            var entityID = data1[d.x + 1];
                            var adoption = data2[d.x + 1];
                            var support = data3[d.x + 1];
                            window.external.DrillThroughAddinVersionChart(category, entityID, adoption, support, $scope.selectedArch);
                        }
                        else if (id == "#macroAdvisoryChart") {
                            var category = strings[d.x + 1];
                            window.external.DrillThroughMacroAdvisoryChart(category, $scope.selectedCollId);
                        }
                    },
                    labels: true
                },
                legend: {
                    show: false
                },
                bar: {
                    width: {
                        ratio: 0.6 // this makes bar width 50% of length between ticks
                    }
                },
                size: {
                    height: 240,
                    width: 800
                },
                color: {
                    pattern: pattern
                },
                axis: {
                    rotated: true,
                    x: {
                        type: 'category'
                    },
                    y: {
                        show: false
                    }
                }
            });
        }

        //*** DOM CHANGE HANDLERS
        // launch wizard to pick a collection
        $scope.LaunchWizardCollectionPicker = function () {
            try {
                // Collection is a string
                var collection = window.external.LaunchWizardCollectionPicker();

                //get get collection object
                wmiQuery("SELECT CollectionID, Name, MemberCount FROM SMS_Collection Where CollectionType=2 and CollectionID='" + collection + "'", function (res) {

                    if (res.length === 0) {
                        logger.err("SMS_Collection returned no results");
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
                        //Localize the name
                        $scope.SMS_DeviceCollections.All[0].Name = bridge.GetCollectionAliasName($scope.SMS_DeviceCollections.All[0].Name);
                        // Only COLL_DISP_LIMIT items at a time should show in the drop down
                        if ($scope.SMS_DeviceCollections.All.length > COLL_DISP_LIMIT) {
                            $scope.SMS_DeviceCollections.All.pop();
                        }
                    }
                    // Update the selected item in the dropdown 
                    $scope.SMS_DeviceCollections.Selected = $scope.SMS_DeviceCollections.All[selectedIndex];
                    $scope.collectionsData = ChartState.DataReady;

                    $scope.SMS_DeviceCollectionChanged();
                    $scope.$apply();
                });


            } catch (err) {
                console.log("launch Collection Picker wizard failed.");
            }
        };

        // handle Enter key press event
        $scope.keyPressToggle = function (event, id) {
            if (event.keyCode == 13) {   // This is the Enter keypress
                switch (id) {
                    case 'readinessChart':
                        window.external.DrillThroughReadinessChart('AllDeviceStates', $scope.selectedArch, $scope.selectedCollId);
                        break;
                    case 'addinReadinessChart':
                        window.external.DrillThroughAddinReadinessChart('AllAddinReadiness', $scope.selectedArch);
                        break;
                    case 'addinSupportChart':
                        window.external.DrillThroughAddinSupportChart('AllAddinSupport', $scope.selectedArch);
                        break;
                    case 'topAddinVersionChart':
                        window.external.DrillThroughAddinVersionChart('All', 'All', 'All', 'All', $scope.selectedArch);
                        break;
                    case 'devicesWithMacrosChart':
                        window.external.DrillThroughDevicesWithMacrosChart('AllDevicesMacros', $scope.selectedArch, $scope.selectedCollId);
                        break;
                    case 'macroReadinessChart':
                        window.external.DrillThroughMacroReadinessChart('AllMacroReadiness', $scope.selectedArch, $scope.selectedCollId);
                        break;
                    case 'macroAdvisoryChart':
                        window.external.DrillThroughMacroAdvisoryChart('AllMacroAdvisory', $scope.selectedCollId);
                        break;
                }
            }
        };

        // handle architecture dropdown selection
        $scope.select_OfficeProArch = function () {
            $scope.ProplusReadiness = ChartState.Loading;
            if ($scope.SMS_DeviceCollections.Selected == null) {
                $scope.selectedCollId = "SMS00001";
                $scope.selectedColName = "All Systems";
            } else {
                $scope.selectedCollId = $scope.SMS_DeviceCollections.Selected.CollectionID;
                $scope.selectedColName = $scope.SMS_DeviceCollections.Selected.Name;
            }


            if ($scope.TargetArchitecture == $scope.OfficeProPlus[0]) {
                $scope.selectedArch = 'x86';
            }
            else {
                $scope.selectedArch = 'x64';
            }

            var readinessCountsColor = ["#2b83e5", "#f6a813", "#989b9f"];
            var OfficeReadinessCounts = JSON.parse(window.external.GetOfficeReadinessCounts($scope.selectedCollId, $scope.selectedArch));
            var readinessCounts = {
                'Ready': OfficeReadinessCounts.ReadyCount,
                'NeedsReview': OfficeReadinessCounts.NeedsReviewCount,
                'NotAssessed': OfficeReadinessCounts.NotAssessedCount
            };
            //-----------
            var ProplusInstalledCounts = JSON.parse(window.external.GetOfficeProPlusInstallCounts($scope.selectedCollId, $scope.selectedArch));
            var proplusData = [ProplusInstalledCounts.ProplusDeviceCount, ProplusInstalledCounts.TotalClients];
            var proplusString = (ProplusInstalledCounts.ProplusDeviceCount == 1) ? " device" : " devices";
            //-----------
            var AddinReadinessCounts = JSON.parse(window.external.GetAddinReadinessCounts($scope.selectedArch));
            var addinReadinessCountsData = [
                [$scope.strings.AddinReadiness_Ready, AddinReadinessCounts.ReadyCount],
                [$scope.strings.AddinReadiness_Remediation, AddinReadinessCounts.RemediationAvailableCount],
                [$scope.strings.AddinReadiness_NeedsReview, AddinReadinessCounts.NeedsReviewCount],
                [$scope.strings.AddinReadiness_PotentialIssues, AddinReadinessCounts.PotentialIssuesCount]
            ];
            var str = [];
            addinReadinessCountsData.forEach(function (k, v) { str.push(k[0] + ": " + k[1] + ",  "); });
            $scope.strings.AriaAddInReadiness = str.join("");

            var addinReadinessCountsColor = ["#008000", "#D62728", "#006ABA", "#9B4F96"];
            var totalReadinessAddins = AddinReadinessCounts.TotalAddinsCount;
            var addinReadinessTitle = totalReadinessAddins;
            //-----------
            var AddinSupportCounts = JSON.parse(window.external.GetAddinSupportCounts($scope.selectedArch));
            var addinSupportCountsData = [
                [$scope.strings.AddinSupport_Supported, AddinSupportCounts.SupportedCount],
                [$scope.strings.AddinSupport_NotProvided, AddinSupportCounts.NotProvidedCount]
            ];

            var str = [];
            addinSupportCountsData.forEach(function (k, v) { str.push(k[0] + ": " + k[1] + ",  "); });
            $scope.strings.AriaAddinSupport = str.join("");

            var addinSupportCountsColor = ["#008000", "#006ABA"];

            var totalSupportAddins = AddinSupportCounts.UniqueAddinCount;
            var totalSupportAddinsSuffix = (totalSupportAddins == 1) ? $scope.strings.Addin : $scope.strings.Addins;
            var supportAddinsTitle = totalSupportAddins.concat(totalSupportAddinsSuffix);
            //-----------
            var AddinVersionCounts = JSON.parse(window.external.GetAddinVersionCounts($scope.selectedArch));

            var firstAddinVersionCount = (AddinVersionCounts.FirstVersionCount > 0) ? AddinVersionCounts.FirstVersionCount : null;
            var secondAddinVersionCount = (AddinVersionCounts.SecondVersionCount > 0) ? AddinVersionCounts.SecondVersionCount : null;
            var thirdAddinVersionCount = (AddinVersionCounts.ThirdVersionCount > 0) ? AddinVersionCounts.ThirdVersionCount : null;
            var fourthAddinVersionCount = (AddinVersionCounts.FourthVersionCount > 0) ? AddinVersionCounts.FourthVersionCount : null;
            var fifthAddinVersionCount = (AddinVersionCounts.FifthVersionCount > 0) ? AddinVersionCounts.FifthVersionCount : null;

            // to show unicode characters, parse the xml style string into text
            var dom = new DOMParser();
            var firstName = dom.parseFromString(AddinVersionCounts.FirstName, "text/html");
            AddinVersionCounts.FirstName = firstName.documentElement.textContent;
            var firstAddinName = (firstAddinVersionCount > 0) ? AddinVersionCounts.FirstName : " ";

            var secondName = dom.parseFromString(AddinVersionCounts.SecondName, "text/html");
            AddinVersionCounts.SecondName = secondName.documentElement.textContent;
            var secondAddinName = (secondAddinVersionCount > 0) ? AddinVersionCounts.SecondName : " ";

            var thirdName = dom.parseFromString(AddinVersionCounts.ThirdName, "text/html");
            AddinVersionCounts.ThirdName = thirdName.documentElement.textContent;
            var thirdAddinName = (thirdAddinVersionCount > 0) ? AddinVersionCounts.ThirdName : " ";

            var fourthName = dom.parseFromString(AddinVersionCounts.FourthName, "text/html");
            AddinVersionCounts.FourthName = fourthName.documentElement.textContent;
            var fourthAddinName = (fourthAddinVersionCount > 0) ? AddinVersionCounts.FourthName : " ";

            var fifthName = dom.parseFromString(AddinVersionCounts.FifthName, "text/html");
            AddinVersionCounts.FifthName = fifthName.documentElement.textContent;
            var fifthAddinName = (fifthAddinVersionCount > 0) ? AddinVersionCounts.FifthName : " ";

            var firstEntityID = AddinVersionCounts.FirstEntityId;
            var secondEntityID = AddinVersionCounts.SecondEntityId;
            var thirdEntityID = AddinVersionCounts.ThirdEntityId;
            var fourthEntityID = AddinVersionCounts.FourthEntityId;
            var fifthEntityID = AddinVersionCounts.FifthEntityId;

            var firstAdoptionStatus = AddinVersionCounts.FirstAdoptionStatus;
            var secondAdoptionStatus = AddinVersionCounts.SecondAdoptionStatus;
            var thirdAdoptionStatus = AddinVersionCounts.ThirdAdoptionStatus;
            var fourthAdoptionStatus = AddinVersionCounts.FourthAdoptionStatus;
            var fifthAdoptionStatus = AddinVersionCounts.FifthAdoptionStatus;

            var firstSupportStatus = AddinVersionCounts.FirstSupportStatus;
            var secondSupportStatus = AddinVersionCounts.SecondSupportStatus;
            var thirdSupportStatus = AddinVersionCounts.ThirdSupportStatus;
            var fourthSupportStatus = AddinVersionCounts.FourthSupportStatus;
            var fifthSupportStatus = AddinVersionCounts.FifthSupportStatus;

            var addinNameStrings = ['x', firstAddinName, secondAddinName, thirdAddinName, fourthAddinName, fifthAddinName];
            var addinVersionCountData = [$scope.strings.Counts, firstAddinVersionCount, secondAddinVersionCount, thirdAddinVersionCount, fourthAddinVersionCount, fifthAddinVersionCount];
            var addinEntityIDs = ['', firstEntityID, secondEntityID, thirdEntityID, fourthEntityID, fifthEntityID];
            var addinAdoption = ['', firstAdoptionStatus, secondAdoptionStatus, thirdAdoptionStatus, fourthAdoptionStatus, fifthAdoptionStatus];
            var addinSupport = ['', firstSupportStatus, secondSupportStatus, thirdSupportStatus, fourthSupportStatus, fifthSupportStatus];

            $scope.strings.AriaTopAddinsVersion = (firstAddinVersionCount > 0) ? (firstAddinName + ": " + firstAddinVersionCount + ", " ) : " " +
                                                  (secondAddinVersionCount > 0) ? (secondAddinName + ": " + secondAddinVersionCount + ", " ) : " " +
                                                  (thirdAddinVersionCount > 0) ? (thirdAddinName + ": " + thirdAddinVersionCount + ", ") : " " +
                                                  (fourthAddinVersionCount > 0) ? (fourthAddinName + ": " + fourthAddinVersionCount + ", ") : " "  +
                                                  (fifthAddinVersionCount > 0) ? (fifthAddinName + ": " + fifthAddinVersionCount) : " ";
            //-----------
            var DevicesWithMacrosCounts = JSON.parse(window.external.GetDevicesWithMacrosCounts($scope.selectedArch, $scope.selectedCollId));
            var devicesWithMacrosCountsData = [
                [$scope.strings.MacroInventory_NoMacros, DevicesWithMacrosCounts.NoMacrosCount],
                [$scope.strings.MacroInventory_NotAllScanned, DevicesWithMacrosCounts.NotAllScannedMacrosCount],
                [$scope.strings.MacroInventory_HasMacros, DevicesWithMacrosCounts.HasMacrosCount],
                [$scope.strings.MacroInventory_MayHaveMacros, DevicesWithMacrosCounts.MayHaveMacrosCount]
            ];

            var str = [];
            devicesWithMacrosCountsData.forEach(function (k, v) { str.push(k[0] + ": " + k[1] + ",  "); });
            $scope.strings.AriaDevicesWithMacros = str.join("");

            var devicesWithMacrosCountsColor = ["#008000", "#D62728", "#006ABA", "#9B4F96"];

            var totalDevicesMacros = DevicesWithMacrosCounts.TotalDevicesWithMacrosCount;
            var totalDevicesMacrosSuffix = (totalDevicesMacros == 1) ? $scope.strings.Device : $scope.strings.Devices;
            var devicesMacrosTitle = totalDevicesMacros.concat(totalDevicesMacrosSuffix);
            //-----------
            var MacroReadinessCounts = JSON.parse(window.external.GetMacroReadinessCounts($scope.selectedArch, $scope.selectedCollId));
            var macroReadinessCountsData = [
                [$scope.strings.MacroReadiness_Ready, MacroReadinessCounts.ReadyCount],
                [$scope.strings.MacroReadiness_NeedsReview, MacroReadinessCounts.NeedsReviewCount],
                [$scope.strings.MacroInventory_NotAllScanned, MacroReadinessCounts.NotAllScanned]
            ];

            var str = [];
            macroReadinessCountsData.forEach(function (k, v) { str.push(k[0] + ": " + k[1] + ",  "); });
            $scope.strings.AriaMacroReadiness = str.join("");

            var macroReadinessCountsColor = ["#008000", "#D62728", "#006ABA"];

            //------
            var MacroSeverityDeviceCounts = JSON.parse(window.external.GetMacroAdvisoryCounts($scope.selectedCollId));
            var macroSeverityStrings = ['x', $scope.strings.CodeDesignAwareness, $scope.strings.LimitedRemediationRequired, $scope.strings.MinimalValidationRecommended, $scope.strings.SignificantRemediationRequired];
            var macroSeverityDeviceCountsData = [$scope.strings.Counts, MacroSeverityDeviceCounts.CodeDesignCount, MacroSeverityDeviceCounts.LimRemCount, MacroSeverityDeviceCounts.MinValidationCount, MacroSeverityDeviceCounts.SigRemCount];
            var blankData = ['', 0, 0, 0, 0, 0];
            $scope.strings.AriaMacroAdvisories = $scope.strings.CodeDesignAwareness + ": " + MacroSeverityDeviceCounts.CodeDesignCount + ", " +
                                                  $scope.strings.LimitedRemediationRequired + ": " + MacroSeverityDeviceCounts.LimRemCount + ", " +
                                                  $scope.strings.MinimalValidationRecommended + ": " + MacroSeverityDeviceCounts.MinValidationCount + ", " +
                                                  $scope.strings.SignificantRemediationRequired + ": " + MacroSeverityDeviceCounts.SigRemCount;

            // Draw all charts
            createOfficeReadinessBarChart("#readinessChart", readinessCounts, $scope);
            //createReadinessDonutChart("#readinessChart", readinessCounts, readinessCountsColor, "", true);
            $scope.tiles = JSON.parse(window.external.GetNumericTiles(AddinReadinessCounts.PotentialIssuesCount, AddinReadinessCounts.TotalAddinsCount, AddinSupportCounts.SupportedCount));
            $scope.alertClick = function () {
                return JSON.parse(window.external.DrillThroughAddinReadinessChart("Potential Issues", $scope.selectedArch, $scope.publicAddins));
            };

            createDonutChart("#addinReadinessChart", addinReadinessCountsData, addinReadinessCountsColor, addinReadinessTitle, true);
            createDonutChart("#addinSupportChart", addinSupportCountsData, addinSupportCountsColor, supportAddinsTitle, true);
            createHorizontalBarChart("#topAddinVersionChart", addinNameStrings, addinVersionCountData, addinEntityIDs, addinAdoption, addinSupport);
            createDonutChart("#devicesWithMacrosChart", devicesWithMacrosCountsData, devicesWithMacrosCountsColor, devicesMacrosTitle, true);
            createDonutChart("#macroReadinessChart", macroReadinessCountsData, macroReadinessCountsColor, "", true);
            createHorizontalBarChart("#macroAdvisoryChart", macroSeverityStrings, macroSeverityDeviceCountsData, blankData, blankData, blankData);
            createGaugeChart("#proplusDevicesChart", proplusData, $scope.strings.DeploymentLabel);
            $scope.ProplusReadiness = ChartState.DataReady;
            $scope.$apply();
        };

        //*** BUTTON CODE LAUNCH WIZARDS
        // launch wizard to create a new Office 365 Application
        $scope.launchO365Installer = function () {
            try {
                window.external.LaunchO365Installer();
            }
            catch (err) {
                console.log("launch Office 365 Install Wizard failed");
            }
        };

        function drawCharts() {
            $scope.select_OfficeProArch();
        }

        drawCharts();

    });

}());

// SIG // Begin signature block
// SIG // MIInywYJKoZIhvcNAQcCoIInvDCCJ7gCAQExDzANBglg
// SIG // hkgBZQMEAgEFADB3BgorBgEEAYI3AgEEoGkwZzAyBgor
// SIG // BgEEAYI3AgEeMCQCAQEEEBDgyQbOONQRoqMAEEvTUJAC
// SIG // AQACAQACAQACAQACAQAwMTANBglghkgBZQMEAgEFAAQg
// SIG // FpSHuYdECkPPsDpi5A4SGDzhUPXkIr5DKQ+Gr3W4iBug
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
// SIG // ARUwLwYJKoZIhvcNAQkEMSIEILOYHkskX2VBPJrg3Pxo
// SIG // sDHNV0BzuwtRCLFGUMhQq1FhMEIGCisGAQQBgjcCAQwx
// SIG // NDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRw
// SIG // Oi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEB
// SIG // BQAEggEAEJJ/E9Ib/DsUvhQmS8XmnXZkMNASpX80q3yt
// SIG // LtDeth6T4Vf1/X9O3UdkDEZHYHOEDQrgv1o6BYo/M3nG
// SIG // 3lyAYmt1tfIzMF7SvaKG4+UgZxKgO2KEZLrRysq9M3Mw
// SIG // h6ZzFQC7WfnaddMJwm2dGadtbqlSfa4RS/xqSE8PjSJ7
// SIG // M+9Zr+mgAVHbBI/7HBIn8NZvi5PAj0HNRciJEaW3IT67
// SIG // FP+yUfGeaWtajl5D/twMCI3fc6hgojUy3gSpfioUsZTk
// SIG // BwufP3Xloh8RNsJ5AnawuqxcmFFFRzIPbaGcuQaQWM8A
// SIG // NEk8YIf6qi0MjN0BYVcgQoAuPQ7KN2mmkDRUyDdFN6GC
// SIG // FywwghcoBgorBgEEAYI3AwMBMYIXGDCCFxQGCSqGSIb3
// SIG // DQEHAqCCFwUwghcBAgEDMQ8wDQYJYIZIAWUDBAIBBQAw
// SIG // ggFZBgsqhkiG9w0BCRABBKCCAUgEggFEMIIBQAIBAQYK
// SIG // KwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCB2pF3k
// SIG // cDKWckPSXE9mEqqLDsYI0jsTZc/g7ldh4AqgWQIGY2Pf
// SIG // aYHXGBMyMDIyMTEwNDE3MjM0MC40NTFaMASAAgH0oIHY
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
// SIG // IgQgg0m848HWsva96kN38BE5x+pJIP/uE8uMwg2t5vXa
// SIG // hbQwgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCBk
// SIG // 60bO8W85uTAfJVEO3vX2aLaQFcgcGpdwsOoi+foP9DCB
// SIG // mDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
// SIG // YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
// SIG // VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNV
// SIG // BAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEw
// SIG // AhMzAAABufYADWVUT7wDAAEAAAG5MCIEIEpB3xr7eyxp
// SIG // TDMMf8hGiLLzDeIEhxmj1CIruH9UfJ8sMA0GCSqGSIb3
// SIG // DQEBCwUABIICABH/BmCZ5WcllDW0sMqibEFh67RbhnHx
// SIG // FyRPv1QiwcruwQm/KMlWLKVo3oguRsxW6tDZGuui4PzW
// SIG // HHeUmZFkRA29D9qAqpTY5o3GUVAuqRJW3cDcwunTE4IO
// SIG // nWjFubscMRD6BGv6ERN2HBJH/FPILun0+zGOCc/WA3X+
// SIG // x0teY8F5N5Upam3aw2LHkaYQ/JLdz7+1fZgmJMbeS+gP
// SIG // rdkqMLflqx0lqC5lfMNvDIo/KnsTZbMAtc4iml7KQCC5
// SIG // wTF90K9Et9gRa6sDsCyQ44o/3lcwZeav8g1t82qwdN4H
// SIG // WI6wCGhcDNBmWC55GGfTnq6IGPovPkhK2+fNXDEIN32F
// SIG // FGqVJbRutRQ3r/nYzB0Hm6I+n+deIGSl5QfvvAy7uvUg
// SIG // 4TsexXUCeNbrc4qqRjOJ7yT1lDIjCFGkXPoadw1i6VzE
// SIG // C5Op73lgSHbkiDyIXFcHjgARL7nwh3/peveZuYXKATi6
// SIG // oTYsB+g2avU6MyQ1GikiRRqD9Mj9R0tKVQ4CL6x8TB65
// SIG // lfNV5lQb/7eyd4pJPE7UqIM++FWghr7Lt1WLBLlY9RN5
// SIG // upGZXGrfpwZov7STkdmglapG7D5cE6KL8tfPDoS/pxfN
// SIG // 92XuUYvr32KXtS5Ck6rspeTIEG97NmMNTunLuI0L6Gvk
// SIG // Rha1HQ3tUfYHn7nc1t6REh9Opj3/Hvo3wg4g
// SIG // End signature block
