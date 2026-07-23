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
        // *** VARIABLE DECLARATIONS
        var COLL_DISP_LIMIT = 5; // determines the amount of collections displayed in the dropdown filter
        $scope.SMS_DeviceCollections = {}; //temp storage for collections data
        $scope.selectedCollId = "SMS00001";
        $scope.selectedColName = "All Systems";
        $scope.strings;
        $scope.OfficeProPlus;
        $scope.selectedArch = 'x86'; //intialize current architecture chosen for filter
        $scope.ReadinessData = true;
     

        adminUI.initializeController($scope, function () {

            // *** DATA QUERIES AND PREPARATION ***
            //gets collections data to load the Collections dropdown filter
            adminUI.wmiQuery("SELECT CollectionID, Name, MemberCount FROM SMS_Collection Where CollectionType=2 ORDER BY Name",
                SMS_DeviceCollectionsReceived);
            $scope.OfficeProPlus = [$scope.strings.SixtyFourBitArch, $scope.strings.ThirtyTwoBitArch];
            //drawCharts();

        });

        LoadDataAsync();

        async function LoadDataAsync() {

            $scope.isO365InstallerOn = await callMethodAsync("IsO365InstallerOn", null);
            $scope.$apply();

        }
        $scope.getString = function (stringName) {
            return $scope.strings[stringName];
        };
        async function SMS_DeviceCollectionsReceived(res) {
            res = JSON.parse(res);
            if (res.length === 0) {
                console.log("SMS_Collection returned no results");
                $scope.collectionsData = ChartState.NoDataFound;
                $scope.$apply();
                return;
            }
            const locCollections = res.slice(0, COLL_DISP_LIMIT);
            const localizedPromises = locCollections.map((item) => {

                return new Promise((resolve, reject) => {
                    callMethod("GetCollectionAliasName", item.Name, function (response, returnCode) {
                        if (returnCode !== 0) {
                            console.error("Error retrieving alias name for collection:", item.Name);
                            reject(new Error("Failed to retrieve alias name"));
                        } else {
                            item.Name = (typeof response === 'string' && response.startsWith('"'))
                                ? JSON.parse(response)
                                : response;
                            resolve();
                        }
                    });
                });
            });

           try {
                await Promise.all(localizedPromises);
            } catch (error) {
                console.error("Error in alias name retrieval:", error);
                $scope.collectionsData = ChartState.Error;
                $scope.$apply();
                return;
            }

            $scope.SMS_DeviceCollections.All = locCollections;
            $scope.SMS_DeviceCollections.Selected = locCollections[0];


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
                    onclick: async function (d) {
                        if (id == "#readinessChart") {

                            await adminUI.sendNewRequestSync("DrillThroughReadinessChart", JSON.stringify([d.name, $scope.selectedArch, $scope.selectedCollId]));
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
        function createReadinessDonutChart(id, data, color) {
            if (noDataInColumns(data)) {
                $scope.createEmptyDonutChart(id);
            }
            else {

                c3.generate({
                    bindto: id,
                    data: {
                        columns: data,
                        type: 'donut',
                        onclick: async function (d) {

                            await adminUI.sendNewRequestSync("DrillThroughReadninessChart", JSON.stringify([d.name, $scope.selectedArch]));

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
                        onclick: async function (d) {
                            if (drillThroughEnabled && (id == "#addinReadinessChart")) {
                                await adminUI.sendNewRequestSync("DrillThroughAddinReadinessChart", JSON.stringify([d.name, $scope.selectedArch]));
                            }
                            else if (drillThroughEnabled && (id == "#addinSupportChart")) {

                                await adminUI.sendNewRequestSync("DrillThroughAddinSupportChart", JSON.stringify([d.name, $scope.selectedArch]));
                            }
                            else if (drillThroughEnabled && (id == "#devicesWithMacrosChart")) {

                                await adminUI.sendNewRequestSync("DrillThroughDevicesWithMacrosChart", JSON.stringify([d.name, $scope.selectedArch, $scope.selectedCollId]));

                            }
                            else if (drillThroughEnabled && (id == "#macroReadinessChart")) {

                                await adminUI.sendNewRequestSync("DrillThroughMacroReadinessChart", JSON.stringify([d.name, $scope.selectedArch, $scope.selectedCollId]));
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

        // Helper Functions

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
                    onclick: async function (d, element) {
                        if (id == "#topAddinVersionChart") {
                            var category = strings[d.x + 1];
                            var entityID = data1[d.x + 1];
                            var adoption = data2[d.x + 1];
                            var support = data3[d.x + 1];

                            await adminUI.sendNewRequestSync("DrillThroughAddinVersionChart", JSON.stringify([category, entityID, adoption, support, $scope.selectedArch]));

                        }
                        else if (id == "#macroAdvisoryChart") {
                            var category = strings[d.x + 1];

                            await adminUI.sendNewRequestSync("DrillThroughMacroAdvisoryChart", JSON.stringify([category, $scope.selectedCollId]));
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
        $scope.LaunchWizardCollectionPicker = async function () {
            try {
                // Collection is a string
                var collection = await adminUI.sendNewRequestSync("LaunchWizardCollectionPicker", null);

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
                        //Localize the name
                        callMethod("GetCollectionAliasName", $scope.SMS_DeviceCollections.All[0].Name, function callback(response, returnCode) {
                            $scope.SMS_DeviceCollections.All[0].Name = JSON.parse(response);
                        });
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
        $scope.keyPressToggle = async function (event, id) {
            if (event.keyCode == 13) {   // This is the Enter keypress
                switch (id) {
                    case 'readinessChart':
                        await adminUI.sendNewRequestSync("DrillThroughReadinessChart", JSON.stringify(['AllDeviceStates', $scope.selectedArch, $scope.selectedCollId]));
                        break;
                    case 'addinReadinessChart':
                        await adminUI.sendNewRequestSync("DrillThroughAddinReadinessChart", JSON.stringify(['AllAddinReadiness', $scope.selectedArch]));
                        break;
                    case 'addinSupportChart':
                        await adminUI.sendNewRequestSync("DrillThroughAddinSupportChart", JSON.stringify(['AllAddinSupport', $scope.selectedArch]));
                        break;
                    case 'topAddinVersionChart':
                        await adminUI.sendNewRequestSync("DrillThroughAddinVersionChart", JSON.stringify(['All', 'All', 'All', 'All', $scope.selectedArch]));
                        break;
                    case 'devicesWithMacrosChart':
                        await adminUI.sendNewRequestSync("DrillThroughDevicesWithMacrosChart", JSON.stringify(['AllDevicesMacros', $scope.selectedArch, $scope.selectedCollId]));
                        break;
                    case 'macroReadinessChart':
                        await adminUI.sendNewRequestSync("DrillThroughMacroReadinessChart", JSON.stringify(['AllMacroReadiness', $scope.selectedArch, $scope.selectedCollId]));
                        break;
                    case 'macroAdvisoryChart':
                        await adminUI.sendNewRequestSync("DrillThroughMacroAdvisoryChart", JSON.stringify(['AllMacroAdvisory', $scope.selectedCollId]));
                        break;
                }
            }
        };

        // handle architecture dropdown selection
        $scope.select_OfficeProArch = async function () {
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
            var OfficeReadinessCounts = await callJsonParseMethodAsync("GetOfficeReadinessCounts", JSON.stringify([$scope.selectedCollId, $scope.selectedArch]));
            var readinessCounts = {
                'Ready': OfficeReadinessCounts.ReadyCount,
                'NeedsReview': OfficeReadinessCounts.NeedsReviewCount,
                'NotAssessed': OfficeReadinessCounts.NotAssessedCount
            };
         

            var ProplusInstalledCounts = await callJsonParseMethodAsync("GetOfficeProPlusInstallCounts", JSON.stringify([$scope.selectedCollId, $scope.selectedArch]));
            var proplusData = [ProplusInstalledCounts.ProplusDeviceCount, ProplusInstalledCounts.TotalClients];
            var proplusString = (ProplusInstalledCounts.ProplusDeviceCount == 1) ? " device" : " devices";
        
            var AddinReadinessCounts = await callJsonParseMethodAsync("GetAddinReadinessCounts", $scope.selectedArch);
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
         
            var AddinSupportCounts = await callJsonParseMethodAsync("GetAddinSupportCounts", $scope.selectedArch);
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
          
            var AddinVersionCounts = await callJsonParseMethodAsync("GetAddinVersionCounts", $scope.selectedArch);
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

            $scope.strings.AriaTopAddinsVersion = (firstAddinVersionCount > 0) ? (firstAddinName + ": " + firstAddinVersionCount + ", ") : " " +
                (secondAddinVersionCount > 0) ? (secondAddinName + ": " + secondAddinVersionCount + ", ") : " " +
                    (thirdAddinVersionCount > 0) ? (thirdAddinName + ": " + thirdAddinVersionCount + ", ") : " " +
                        (fourthAddinVersionCount > 0) ? (fourthAddinName + ": " + fourthAddinVersionCount + ", ") : " " +
                            (fifthAddinVersionCount > 0) ? (fifthAddinName + ": " + fifthAddinVersionCount) : " ";
           
            var DevicesWithMacrosCounts = await callJsonParseMethodAsync("GetDevicesWithMacrosCounts", JSON.stringify([$scope.selectedArch, $scope.selectedCollId]));
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
          
            var MacroReadinessCounts = await callJsonParseMethodAsync("GetMacroReadinessCounts", JSON.stringify([$scope.selectedArch, $scope.selectedCollId]));
            var macroReadinessCountsData = [
                [$scope.strings.MacroReadiness_Ready, MacroReadinessCounts.ReadyCount],
                [$scope.strings.MacroReadiness_NeedsReview, MacroReadinessCounts.NeedsReviewCount],
                [$scope.strings.MacroInventory_NotAllScanned, MacroReadinessCounts.NotAllScanned]
            ];

            var str = [];
            macroReadinessCountsData.forEach(function (k, v) { str.push(k[0] + ": " + k[1] + ",  "); });
            $scope.strings.AriaMacroReadiness = str.join("");

            var macroReadinessCountsColor = ["#008000", "#D62728", "#006ABA"];

           
            var MacroSeverityDeviceCounts = await callJsonParseMethodAsync("GetMacroAdvisoryCounts", $scope.selectedCollId);
            var macroSeverityStrings = ['x', $scope.strings.CodeDesignAwareness, $scope.strings.LimitedRemediationRequired, $scope.strings.MinimalValidationRecommended, $scope.strings.SignificantRemediationRequired];
            var macroSeverityDeviceCountsData = [$scope.strings.Counts, MacroSeverityDeviceCounts.CodeDesignCount, MacroSeverityDeviceCounts.LimRemCount, MacroSeverityDeviceCounts.MinValidationCount, MacroSeverityDeviceCounts.SigRemCount];
            var blankData = ['', 0, 0, 0, 0, 0];
            $scope.strings.AriaMacroAdvisories = $scope.strings.CodeDesignAwareness + ": " + MacroSeverityDeviceCounts.CodeDesignCount + ", " +
                $scope.strings.LimitedRemediationRequired + ": " + MacroSeverityDeviceCounts.LimRemCount + ", " +
                $scope.strings.MinimalValidationRecommended + ": " + MacroSeverityDeviceCounts.MinValidationCount + ", " +
                $scope.strings.SignificantRemediationRequired + ": " + MacroSeverityDeviceCounts.SigRemCount;

            // Draw all charts
            $scope.ProplusReadiness = ChartState.DataReady;
            setTimeout(() => {
                createGaugeChart("#proplusDevicesChart", proplusData, $scope.strings.DeploymentLabel);
                createOfficeReadinessBarChart("#readinessChart", readinessCounts, $scope);
            }, 300);
            
           
            $scope.alertClick = async function () {
               
                return await callJsonParseMethodAsync("DrillThroughAddinReadinessChart", JSON.stringify(["Potential Issues", $scope.selectedArch, $scope.publicAddins]));
            };

            createDonutChart("#addinReadinessChart", addinReadinessCountsData, addinReadinessCountsColor, addinReadinessTitle, true);
            createDonutChart("#addinSupportChart", addinSupportCountsData, addinSupportCountsColor, supportAddinsTitle, true);
            createHorizontalBarChart("#topAddinVersionChart", addinNameStrings, addinVersionCountData, addinEntityIDs, addinAdoption, addinSupport);
            createDonutChart("#devicesWithMacrosChart", devicesWithMacrosCountsData, devicesWithMacrosCountsColor, devicesMacrosTitle, true);
            createDonutChart("#macroReadinessChart", macroReadinessCountsData, macroReadinessCountsColor, "", true);
            createHorizontalBarChart("#macroAdvisoryChart", macroSeverityStrings, macroSeverityDeviceCountsData, blankData, blankData, blankData);


            $scope.$apply();

        };

        //*** BUTTON CODE LAUNCH WIZARDS
        // launch wizard to create a new Office 365 Application
        $scope.launchO365Installer = async function () {
            try {
      
                await adminUI.sendNewRequestSync("LaunchO365Installer", null);

            }
            catch (err) {
                console.log("launch Office 365 Install Wizard failed");
            }
        };

        function drawCharts() {
            $scope.select_OfficeProArch();
        }




     





    });

}());

// SIG // Begin signature block
// SIG // MIIomQYJKoZIhvcNAQcCoIIoijCCKIYCAQExDzANBglg
// SIG // hkgBZQMEAgEFADB3BgorBgEEAYI3AgEEoGkwZzAyBgor
// SIG // BgEEAYI3AgEeMCQCAQEEEBDgyQbOONQRoqMAEEvTUJAC
// SIG // AQACAQACAQACAQACAQAwMTANBglghkgBZQMEAgEFAAQg
// SIG // 8LRxrnr914a/qJZm5+9WGw99XIE8hZ1e1hn96Qv4cxGg
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
// SIG // AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCBsF5q4qVG3Reer
// SIG // yWhoMed38Xt0y2FckvcYJJVmtcsu5DCBigYKKwYBBAGC
// SIG // NwIBDDF8MHqgXIBaAE0AaQBjAHIAbwBzAG8AZgB0AC4A
// SIG // VABvAG8AbABrAGkAdAAuAFcAcABmAC4AVQBJAC4AQwBv
// SIG // AG4AdAByAG8AbABzAC4AVwBlAGIAVgBpAGUAdwAuAGQA
// SIG // bABsoRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
// SIG // BgkqhkiG9w0BAQEFAASCAQCyybWWfK/P75StjscBpMxy
// SIG // 8uiQ8UaCLi2ZJ/gCikAwVjvQpxizlHHTem10x51qL7pE
// SIG // nlf6MxxN8Rz99Ym+3H1DYT5mN4Q0VWkXavEq4zyBY6cN
// SIG // Ej5pD3qTBo8O4A8dFme1tYfq6VOCAOvP4tV0P02UCFcM
// SIG // VVKqveIOQtG2QoB+JOpp2A8nAlvmijEL6sW4mMCvX2Uv
// SIG // 288LoMn5M7U6D7li1Pm1a5O2G8T5oem5HEgR/IEL69OO
// SIG // DtvRyQDR45GzfDqmtG65suINetcrT0+wXzNhH/JpwfDj
// SIG // wVFHQK7PL5/neU8nQNW3oEGvp7C5T61jJGRdq2CX1z/R
// SIG // X42Diz17XbM8oYIXrTCCF6kGCisGAQQBgjcDAwExgheZ
// SIG // MIIXlQYJKoZIhvcNAQcCoIIXhjCCF4ICAQMxDzANBglg
// SIG // hkgBZQMEAgEFADCCAVoGCyqGSIb3DQEJEAEEoIIBSQSC
// SIG // AUUwggFBAgEBBgorBgEEAYRZCgMBMDEwDQYJYIZIAWUD
// SIG // BAIBBQAEINsYihlzNYDMkTO4TaprAeSohLqrRzbQA35V
// SIG // EemPA9fGAgZo8pGR+5oYEzIwMjUxMDIzMDI0NTU1LjM2
// SIG // OFowBIACAfSggdmkgdYwgdMxCzAJBgNVBAYTAlVTMRMw
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
// SIG // SIb3DQEJBDEiBCAzJz9CHzQ6eIceMW8VsHu7OMxhHG97
// SIG // WDIWc7ydvLTwxjCB+gYLKoZIhvcNAQkQAi8xgeowgecw
// SIG // geQwgb0EIHAQ9HY8OtMUtyu1CwqtSLujPkk1EIX8pEcy
// SIG // KFI17uyKMIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzAR
// SIG // BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
// SIG // bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
// SIG // bjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAg
// SIG // UENBIDIwMTACEzMAAAIVGAPTgQcmfFMAAQAAAhUwIgQg
// SIG // Ytcu8GXVUPo1dsbuL7yn44Iz71TJ1Ua5Qm6EXtGwDiQw
// SIG // DQYJKoZIhvcNAQELBQAEggIAeb56//9QIpExT3De+9am
// SIG // n6bF4NO1Om8cF7keNOY0Y3AdmofHo6xvIqGI2x4tM99G
// SIG // 3hnvVdKr6OO2W4A2otynWVaLZIBcD8/AVIZrHwyQKLt6
// SIG // nntM75SztRqroL0h/voLLav9L+shCs/LWxIp04KfIp8Q
// SIG // Cpb8pFryjm4MSAmVX0+8gsTelYsNi8P4lNJJ+1pVXtSv
// SIG // 5ElinpbFIknmxfdtEL3l6zWY3o3IvQ2FFNGVYXNYuyVL
// SIG // cSOq4xJ6nh3rUI9/Qs3a32X6dxB2XYh1TpT09gESHzxO
// SIG // HJteRwFad9IsSFat3JZj5G0H/AUujB/737crkGTXe0Dj
// SIG // EJOH9aMJkvf/aX5feNMsw6xPT+6c8N+gPk9cD6G6avdz
// SIG // X1sEEgeN/V3xikmDk5YeZrM9sqxkNV52ZVDy2i5cltiv
// SIG // a8BKKeleSwrbTtDrRy8ysBUWB5LyVRZHfijoD2afmOor
// SIG // v17a2iXXeqk/8FOF1yKNndWi7x87AsaYncPgNsJyQqot
// SIG // +jA2epE4iruXFScJGaPNs90za7XFgk6YMButWW+RW0m+
// SIG // i6I9U1KKUx1+zT7AWMu8l2coK+GfjsKZedgdKVYh/3Fi
// SIG // wR0Gstqj/YrJbuRmkr+zTTCwcUbm22XH7Q8A8wx8RJiv
// SIG // NRfBkJ+ZNOgA02bGOBakKklnJhCivKJEtP8+mrPoYMnMIrU=
// SIG // End signature block
