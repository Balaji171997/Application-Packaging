(function () {
    "use strict";
    var dashboard = angular.module("dashboard", []);
    dashboard.run(initChartTemplate);
    dashboard.controller("dashboardController", ['$scope', function ($scope) {
        $scope.ChartState = ChartState; // for use in ng-expressions in html
        $scope.collectionsData = ChartState.Loading;

        //Uncomment after TP
        $scope.RecommendedPilotDevicesStatus = ChartState.Loading;
        $scope.DevicesReadyToDeployStatus = ChartState.Loading;
        $scope.DevicesSendingHealthDataStatus = ChartState.Loading;
        $scope.AddInsNotMeetingHealthGoalsStatus = ChartState.Loading;
        $scope.MacrosNotMeetingHealthGoalsStatus = ChartState.Loading;
        $scope.DevicesNotMeetingHealthGoalsStatus = ChartState.Loading;
        $scope.strings = getStrings([
            "OfficePilot",
            "GeneratePilot",
            "GeneratePilotDefaultMessage",
            "RecommendedPilotDevices",
            "NoDataToDisplay",
            "DeployPilotCollection",
            "DevicesReadyToDeploy",
            "CollectionAreReadyToDeployOffice365Proplus",
            "NoAddInsOrMacros",
            "ReadyDevices",
            "Devices",
            "LearnMore",
            "DetermineWhichDevicesAreReadyToDeploy",
            "DevicesSendingHealthData",
            "WhatInformationIsCollected",
            "AddInsNotMeetingHealthGoals",
            "MacroNotMeetingHealthGoals",
            "DevicesNotMeetingHealthGoals",
            "AddressIssuesDiscoveredDuringPilot",
            "Browse",
            "DeviceCollection",
            "AddIns",
            "Macros",
            "MacroSolutions",
            "ProPlusDevices",
            "ReccomendedPilotDevices",
            "LoadFailures",
            "Crashes",
            "Errors",
            "MultipleIssues",
            "RunTimeErrors",
            "CompileErrors",
            "MacroIssues",
            "Both",
            "AddInIssues",
            "ReadyBasedOnDeploymentAndHealthData",
            "ReadyBasedOnDeployment",
            "WhyDevicesAreRecommendedForPilot",
            "Yes",
            "No",
            "LearnAboutGeneratingAPilot",
            "OpenBracket",
            "CloseBracket",
            "LearnHowToEnableThis",
            "PilotNotGenerated", 
            "PilotGenerationInProgress",
            "PilotGeneratedTime",
            "PilotEvaluate",
            "AddInsHealth",
            "MacrosHealth",
            "DevicesHealth",
            "DevicesDeploy",
            "NoDevicesInPilot", 
            "PlusSignGeneratePilot",
            "PlusSignDeployPilot",
            "GrayPlusSignDeployPilot"
        ]);

        $scope.getString = function (stringName) {
            return $scope.strings[stringName];
        };

        //$scope.noData = true;
        $scope.hasPermissionToCreatePOD = window.external.HasPermissionToCreatePOD();

        // *** VARIABLE DECLARATIONS
        var COLL_DISP_LIMIT = 5; // determines the amount of collections displayed in the dropdown filter
        $scope.SMS_DeviceCollections = {}; //temp storage for collections data

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

            $scope.collectionsData = ChartState.DataReady;
            $scope.SMS_DeviceCollectionChanged();

            $scope.$apply();
        };

        //*** BUTTON CODE LAUNCH WIZARDS
        // generate pilot collection for the given limiting collection
        $scope.generatePilotCollection = function () {
            try {
                var PilotLastUpdateTime = window.external.GetPilotLastUpdateTIme($scope.SMS_DeviceCollections.Selected.CollectionID);

                if (PilotLastUpdateTime) {
                    // set the string in the generate pilot tile
                    document.getElementById('GeneratePilotText').innerText = $scope.getString('PilotEvaluate');
                }
                else {
                    // set the string in the generate pilot tile
                    document.getElementById('GeneratePilotText').innerText = $scope.getString('PilotGenerationInProgress');
                }
               window.external.GenerateOfficePilotCollection($scope.SMS_DeviceCollections.Selected.CollectionID);
            }
            catch (err) {
                console.log("Generate Pilot action failed");
            }
        };

        // bring up deploy wizard with pilot collection pre-populated
        $scope.deployPilotCollection = function () {
            try {
                window.external.DeployOfficePilotCollection($scope.SMS_DeviceCollections.Selected.CollectionID);
            }
            catch (err) {
                console.log("Deploy Pilot action failed");
            }
        };

        //handle Enter key press event
        $scope.keyPressToggle = function (event, action) {
            if (event.keyCode == 13) {
                if (action == 1) { $scope.generatePilotCollection(); }
                if (action == 2) { $scope.deployPilotCollection(); }
            }
        };

        //Strings For StickyNode           
        var AddInHealthString = $scope.strings['AddInsHealth'];
        var MacrosHealthString = $scope.strings['MacrosHealth'];
        var DevicesHealthString = $scope.strings['DevicesHealth'];
        var DevicesDeployString = $scope.strings['DevicesDeploy'];

        $scope.keyPressDrillThrough = function (event, id) {
            if (event.keyCode == 13) {
                switch (id) {                  
                    case 'DevicesReadyToDeploy':
                        window.external.DrillThroughDevicesReadyToDeploy('AllDevicesReadyToDeployStates', DevicesDeployString, $scope.SMS_DeviceCollections.Selected.CollectionID);
                        break;
                    case 'AddInsNotMeetingHealthGoals':
                        window.external.DrillThroughAddInsHealthGoalsChart('AllAddInHealthGoalStates', AddInHealthString, $scope.SMS_DeviceCollections.Selected.CollectionID);
                        break;
                    case 'MacrosNotMeetingHealthGoals':
                        window.external.DrillThroughMacrosHealthGoalsChart('AllMacrosHealthGoalsStates', MacrosHealthString, $scope.SMS_DeviceCollections.Selected.CollectionID);
                        break;
                    case 'DevicesNotMeetingHealthGoals':
                        window.external.DrillThroughDevicesHealthGoalsChart('AllDevicesHealthGoalsStates', DevicesHealthString, $scope.SMS_DeviceCollections.Selected.CollectionID);
                        break;
                }
            }
        };

        // check if pilot was already generated for this collection
        $scope.isPilotGenerated = function () {
            var PilotLastUpdateTime = window.external.GetPilotLastUpdateTIme($scope.SMS_DeviceCollections.Selected.CollectionID);

            if (PilotLastUpdateTime) {
                // set the string in the generate pilot tile
                document.getElementById('GeneratePilotText').innerText = $scope.getString('PilotGeneratedTime') + "\n" + PilotLastUpdateTime;
            }
            else {
                // set the string in the generate pilot tile
                document.getElementById('GeneratePilotText').innerText = $scope.getString('PilotNotGenerated');
            }
        }

        function get0365Pilot(collection) {
            //Getting data from db
            var ReadinessDataCount = JSON.parse(window.external.GetDevicesReadyToDeploy(collection.CollectionID));
            var RecommendedPilotDevicesCount = JSON.parse(window.external.GetRecommendedPilotDevices(collection.CollectionID));
            var PilotChartString = (RecommendedPilotDevicesCount.PilotDeviceCount < 0) ? $scope.strings['NoDataToDisplay'] : $scope.getString('NoDevicesInPilot');
            var DevicesSendingHealthDataCount = JSON.parse(window.external.GetDevicesSendingHealthData(collection.CollectionID));

            var AddInsNotMeetingHealthGoalsCount = JSON.parse(window.external.GetAddInsNotMeetingHealthGoals(collection.CollectionID));
            var MacrosNotMeetingHealthGoalsCount = JSON.parse(window.external.GetMacrosNotMeetingHealthGoals(collection.CollectionID));
            var DevicesNotMeetingHealthGoalsCount = JSON.parse(window.external.GetDevicesNotMeetingHealthGoals(collection.CollectionID));

            //Generating Data For DevicesReadyToDeployChart            
            var ReadyBasedOnDeploymentAndHealthData = $scope.strings['ReadyBasedOnDeploymentAndHealthData'];
            var ReadyBasedOnDeployment = $scope.strings['ReadyBasedOnDeployment'];
            var NoAddInsOrMacros = $scope.strings['NoAddInsOrMacros'];

            var ColumnsDevicesReadyToDeploy = [
                [ReadyBasedOnDeploymentAndHealthData, parseInt(ReadinessDataCount.ReadyBasedOnDeploymentAndHealthData)],
                [ReadyBasedOnDeployment, parseInt(ReadinessDataCount.ReadyBasedOnDeployment)],
                [NoAddInsOrMacros, parseInt(ReadinessDataCount.NoAddInsOrMacros)]
            ];
            var GroupsDevicesReadyToDeploy = [ReadyBasedOnDeploymentAndHealthData, ReadyBasedOnDeployment, NoAddInsOrMacros];
            var LabelDevicesReadyToDeploy = $scope.strings['Devices'];
            var ChartPatternDeploy = ["#107c10", "#B76DFC", "#92490E"];

            //Generating Data For Recommended Pilot Devices            
            var RecommendedPilotDevicesString = $scope.strings['RecommendedPilotDevices'];
            var ColumnsRecommendedPilotDevices = [[RecommendedPilotDevicesString, (RecommendedPilotDevicesCount.PilotDeviceCount < 0) ? null : parseInt(RecommendedPilotDevicesCount.PilotDeviceCount)]];
            var GroupsRecommendedPilotDevices = [RecommendedPilotDevicesString];
            var LabelRecommendedPilotDevices = $scope.strings['Devices'];
            var ChartPatternRecommended = ["#107c10"];

            //Generating Data For Devices Sending Health Data         
            var ColumnsDevicesSendingHealthData = [
                [$scope.strings['Yes'], parseInt(DevicesSendingHealthDataCount.SendingData)],
                [$scope.strings['No'], parseInt(DevicesSendingHealthDataCount.NotSendingData)]
            ];
            var ChartPatternSeding = ["#107c10", "#FFAA1D"];

            //Generating Data For AddIns Not Meeting Health Goals
            var LoadFailuresString = $scope.strings['LoadFailures'];
            var CrashesString = $scope.strings['Crashes'];
            var ErrorsString = $scope.strings['Errors'];
            var MultipleIssuesString = $scope.strings['MultipleIssues'];

            var ColumnsAddInsNotMeetingHealthGoals = [
                [LoadFailuresString, parseInt(AddInsNotMeetingHealthGoalsCount.LoadFailures)],
                [CrashesString, parseInt(AddInsNotMeetingHealthGoalsCount.Crashes)],
                [ErrorsString, parseInt(AddInsNotMeetingHealthGoalsCount.Errors)],
                [MultipleIssuesString, parseInt(AddInsNotMeetingHealthGoalsCount.MultipleIssues)]
            ];


            var GroupsAddInsNotMeetingHealthGoals = [LoadFailuresString, CrashesString, ErrorsString, MultipleIssuesString];
            var LabelAddInsNotMeetingHealthGoals = $scope.strings['AddIns'];
            var ChartPatternAddIns = ["#92490E", "#ffb900", "#0078d4", "#d83b01"];

            //Generating Data For Macros Not Meeting Health Goals
            var CompileErrorsString = $scope.strings['CompileErrors'];
            var RunTimeErrorsString = $scope.strings['RunTimeErrors'];

            var ColumnsMacrosNotMeetingHealthGoals = [
                [LoadFailuresString, parseInt(MacrosNotMeetingHealthGoalsCount.LoadFailures)],
                [RunTimeErrorsString, parseInt(MacrosNotMeetingHealthGoalsCount.RunTimeErrors)],
                [CompileErrorsString, parseInt(MacrosNotMeetingHealthGoalsCount.CompileErrors)],
                [MultipleIssuesString, parseInt(MacrosNotMeetingHealthGoalsCount.MultipleIssues)]
            ];

            var GroupsMacrosNotMeetingHealthGoals = [LoadFailuresString, RunTimeErrorsString, CompileErrorsString, MultipleIssuesString];
            var LabelMacrosNotMeetingHealthGoals = $scope.strings['Macros'];
            var ChartPatternMacros = ["#92490E", "#ffb900", "#0078d4", "#d83b01"];

            //Generating Data For Devices Not Meeting Health Goals
            var AddInIssues = $scope.strings['AddInIssues'];
            var MacroIssues = $scope.strings['MacroIssues'];
            var Both = $scope.strings['Both'];

            var ColumnsDevicesNotMeetingHealthGoals = [
                [AddInIssues, DevicesNotMeetingHealthGoalsCount.AddInIssues],
                [MacroIssues, DevicesNotMeetingHealthGoalsCount.MacroIssues],
                [Both, DevicesNotMeetingHealthGoalsCount.Both]
            ];

            var GroupsDevicesNotMeetingHealthGoals = [AddInIssues, MacroIssues, Both];
            var LabelDevicesNotMeetingHealthGoals = $scope.strings['Devices'];
            var ChartPatternDevices = ["#92490E", "#0078d4", "#d83b01",];


            //Variables to set the position of chart legends
            var LegendPositionRight = 'right';
            var LegendPositionBottomRight = 'bottom-right';

            //Initial Experience String
            var InitialExperienceString = $scope.strings['NoDataToDisplay'];
            var ChartTitle = $scope.strings.DevicesSendingHealthData;            

            //Generate Charts            
            createOfficePilotStackedBarChart(ChartPatternDeploy, ColumnsDevicesReadyToDeploy, LabelDevicesReadyToDeploy, GroupsDevicesReadyToDeploy, '#DevicesReadyToDeploy', LegendPositionBottomRight, InitialExperienceString, collection.CollectionID, DevicesDeployString);

            createOfficePilotStackedBarChart(ChartPatternAddIns, ColumnsAddInsNotMeetingHealthGoals, LabelAddInsNotMeetingHealthGoals, GroupsAddInsNotMeetingHealthGoals, '#AddInsNotMeetingHealthGoals', LegendPositionRight, InitialExperienceString, collection.CollectionID, AddInHealthString);
            createOfficePilotStackedBarChart(ChartPatternMacros, ColumnsMacrosNotMeetingHealthGoals, LabelMacrosNotMeetingHealthGoals, GroupsMacrosNotMeetingHealthGoals, '#MacrosNotMeetingHealthGoals', LegendPositionRight, InitialExperienceString, collection.CollectionID, MacrosHealthString);
            createOfficePilotStackedBarChart(ChartPatternDevices, ColumnsDevicesNotMeetingHealthGoals, LabelDevicesNotMeetingHealthGoals, GroupsDevicesNotMeetingHealthGoals, '#DevicesNotMeetingHealthGoals', LegendPositionRight, InitialExperienceString, collection.CollectionID, DevicesHealthString);

            createDevicesSendingHealthData(ChartPatternSeding, ChartTitle, ColumnsDevicesSendingHealthData, '#DevicesSendingHealthData', InitialExperienceString);
            createRecommendedPilotDevicesChart(ChartPatternRecommended, ColumnsRecommendedPilotDevices, LabelRecommendedPilotDevices, GroupsRecommendedPilotDevices, '#RecommendedPilotDevices', PilotChartString);



            //Setting ChartState to DataReady
            $scope.AddInsNotMeetingHealthGoalsStatus = ChartState.DataReady;
            $scope.MacrosNotMeetingHealthGoalsStatus = ChartState.DataReady;
            $scope.DevicesNotMeetingHealthGoalsStatus = ChartState.DataReady;
            $scope.DevicesReadyToDeployStatus = ChartState.DataReady;
            $scope.RecommendedPilotDevicesStatus = ChartState.DataReady;
            $scope.DevicesSendingHealthDataStatus = ChartState.DataReady;

            $scope.$apply();


        };

        //*** DOM CHANGE HANDLERS
        // handle collection dropdown selection
        $scope.SMS_DeviceCollectionChanged = function () {
            $scope.DevicesReadyToDeployStatus = ChartState.Loading;
            $scope.RecommendedPilotDevicesStatus = ChartState.Loading;
            $scope.DevicesSendingHealthDataStatus = ChartState.Loading;

            $scope.AddInsNotMeetingHealthGoalsStatus = ChartState.Loading;
            $scope.MacrosNotMeetingHealthGoalsStatus = ChartState.Loading;
            $scope.DevicesNotMeetingHealthGoalsStatus = ChartState.Loading;

            // get pilot last update time for this collection 
            $scope.isPilotGenerated($scope.SMS_DeviceCollections.Selected);

            get0365Pilot($scope.SMS_DeviceCollections.Selected);

        };

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

    }])

        .directive('dashboardChart', defineChartDirective);

    function createOfficePilotStackedBarChart(chartColors, barChartData, labelData, groupsData, domNode, LegendPosition, initialExperienceString, collectionID, stickyNodeName) {
      
        if (noDataInColumns(barChartData)) {

            c3.generate({
                bindto: domNode,
                data: {
                    columns: [

                    ],
                    empty: {
                        label: {
                            text: initialExperienceString

                        }
                    }

                },
                axis: {
                    x: {
                        show: false

                    },
                    y: {
                        show: false

                    }
                },
                size: {
                    height: 210,
                    width: 325
                }
            });
        }
        else {
            c3.generate({
                bindto: domNode,
                data: {
                    columns: barChartData,
                    type: 'bar',
                    groups: [
                        groupsData
                    ],
                    onclick: function (d) {
                        if (domNode == "#AddInsNotMeetingHealthGoals") {
                            window.external.DrillThroughAddInsHealthGoalsChart(d.name, stickyNodeName, collectionID);
                        }
                        else if (domNode == "#MacrosNotMeetingHealthGoals") {
                            window.external.DrillThroughMacrosHealthGoalsChart(d.name, stickyNodeName, collectionID);
                        }
                        else if (domNode == "#DevicesNotMeetingHealthGoals") {
                            window.external.DrillThroughDevicesHealthGoalsChart(d.name, stickyNodeName, collectionID);
                        }
                        else if (domNode == "#DevicesReadyToDeploy") {
                            window.external.DrillThroughDevicesReadyToDeploy(d.name, stickyNodeName, collectionID);
                        }
                    },
                    order: null
                },
                color: {
                    pattern: chartColors
                },
                bar: {
                    width: 50
                },
                legend: {
                    reversed: false,
                    position: LegendPosition,
                },
                axis: {
                    x: {
                        show: true,
                        type: 'category',
                        categories: ['']
                    },
                    y: {
                        tick: { 
                            format: function (y) {
                                if (y % 1 > 0) return '';                            
                                return y;
                            }                                                     
                        },
                        label:
                        {
                            text: labelData
                        }
                    }
                },
                size: {
                    height: 210,
                    width: 325
                }

            });
        }
    };


    function GetSummaryText(bindID, chartTitle, chartData) {

        var chart = document.querySelectorAll(bindID);
        var chartEl = angular.element(chart);
        var tileEl = chartEl.parent();

        if (chartData == null) {
            var summaryText = chartTitle + "0.";
        }
        else {
            var str = [];
            chartData.forEach(function (k, v) { str.push(k[0] + ": " + k[1] + ",  "); });
            var summaryText = chartTitle + ". " + str.join("");
        }

        tileEl.attr('aria-label', summaryText);
        chartEl.attr('aria-label', summaryText);
    }

    function createDevicesSendingHealthData(chartColors, chartTitle, chartData, domNode, initialExperienceString) {
        if (noDataInColumns(chartData)) {

            c3.generate({
                bindto: domNode,
                data: {
                    columns: [

                    ],
                    empty: {
                        label: {
                            text: initialExperienceString

                        }
                    }

                },
                axis: {
                    x: {
                        show: false

                    },
                    y: {
                        show: false

                    }
                },
                size: {
                    height: 110,
                    width: 175
                }
            });
        }

        else {           
            c3.generate({
                bindto: domNode,
                size: {
                    height: 100
                },
                data: {
                    columns: chartData,
                    type: 'pie'
                }, 
                color: {
                    pattern: chartColors
                },
                pie:
                {
                    label: {
                        format: function (value, ratio, id) { return value; }
                    }
                },
                legend: {
                    show: true,
                    position: 'right' 

                }
            });

            GetSummaryText(domNode, chartTitle, chartData);
        }
    }

    function createRecommendedPilotDevicesChart(chartColors, barChartData, labelData, groupsData, domNode, initialExperienceString) {
        if (noDataInColumns(barChartData)) {

            c3.generate({
                bindto: domNode,
                data: {
                    columns: [
                    ],
                    empty: {
                        label: {
                            text: initialExperienceString
                        }
                    }
                },
                axis: {
                    x: {
                        show: false
                    },
                    y: {
                        show: false
                    }
                },
                size: {
                    height: 210,
                    width: 325
                }
            });
        }

        else {
            c3.generate({
                bindto: domNode,
                data: {
                    columns: barChartData,
                    type: 'bar',
                    groups: [groupsData
                    ],
                    order: null
                },
                color: {
                    pattern: chartColors
                },
                bar: {
                    width: 50
                },
                legend: {
                    show: false
                },
                axis: {
                    x: {
                        show: true,
                        type: 'category',
                        categories: ['']
                    },
                    y: {
                        tick: {
                            format: function (y) {
                                if (y % 1 > 0) return '';
                                return y;
                            }
                        },
                        label:
                        {
                            text: labelData
                        }
                    }
                },
                size: {
                    height: 200,
                    width: 225
                }
            });
        }
    };

}());
// SIG // Begin signature block
// SIG // MIInywYJKoZIhvcNAQcCoIInvDCCJ7gCAQExDzANBglg
// SIG // hkgBZQMEAgEFADB3BgorBgEEAYI3AgEEoGkwZzAyBgor
// SIG // BgEEAYI3AgEeMCQCAQEEEBDgyQbOONQRoqMAEEvTUJAC
// SIG // AQACAQACAQACAQACAQAwMTANBglghkgBZQMEAgEFAAQg
// SIG // CbMlMhs5LmJwebw+X8cFIgVbIhOCOdPmkKCzfQ3kIyWg
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
// SIG // ARUwLwYJKoZIhvcNAQkEMSIEIJHUm9QsmHCCyuBRfRb9
// SIG // SKthPguSB4ivK6TO74oVRxfVMEIGCisGAQQBgjcCAQwx
// SIG // NDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRw
// SIG // Oi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEB
// SIG // BQAEggEAVBLPgF9ztUR7wWo6RGvPH2dGeO+MPHLxv7DK
// SIG // 4hosiGUbfpk9YKgZeHQpP3hmHP92sdwSloLr3eOzR9LJ
// SIG // yCsCn8dDAcDpJngqbgjQecYFbxXxULbLm4dY3yMNJgho
// SIG // 1D4roYO24qLFaWx9uJMCgpq/Sh7ntns/OVMDIFpDEof4
// SIG // M5bd+6w5PAXar8EHzgFbjiFd68Ex7BcNzWrXlZe6haub
// SIG // 72RQf9MuHS0KUCNzd+zqwl0T5RNQrm7kVC3DPJgFM6Bb
// SIG // mPj0H8iFxCe55UEJgeSyA6eaYV7ZDjg1x2mo5mLbs8O+
// SIG // Yjsqb8dBeLnTO76D7cdumL9aTPvqpmIv4J6vHKS4k6GC
// SIG // FywwghcoBgorBgEEAYI3AwMBMYIXGDCCFxQGCSqGSIb3
// SIG // DQEHAqCCFwUwghcBAgEDMQ8wDQYJYIZIAWUDBAIBBQAw
// SIG // ggFZBgsqhkiG9w0BCRABBKCCAUgEggFEMIIBQAIBAQYK
// SIG // KwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCCao9GZ
// SIG // PBWSOfhLZ6gUcue4Ra9eoHYrxHfQ3+JWJE+PYQIGY2Pe
// SIG // fFXrGBMyMDIyMTEwNDE3MjMzOS41MzNaMASAAgH0oIHY
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
// SIG // IgQgliQtla9QCxACbANvsFaLHUGJAdZmLpg7OI8+b0oB
// SIG // q4kwgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCAo
// SIG // 69Y4oHA7Q4pS+Y1NsBfrpIYTeWsPeGTami0X0PD7HzCB
// SIG // mDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
// SIG // YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
// SIG // VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNV
// SIG // BAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEw
// SIG // AhMzAAABuAjUwbh54FFJAAEAAAG4MCIEIJDBW67MRKy5
// SIG // 6CRRhSvuyzsbZ09Q6WTDPYgV7mzHGwVWMA0GCSqGSIb3
// SIG // DQEBCwUABIICAG0GpR+pbuOB1NVz7w+1HUIFpcpND6Ni
// SIG // PoJo1uaEHB6scR50BCVKdXvpo2IxI4muuj4VPI7ufXST
// SIG // 4fMX6xEHPmuxqt82F6RWp6G4cBaAluYbsNOV8WCGRBfs
// SIG // PjJ75/tjFnZaYcARvUNe1r2o1LjS7RoUxk34dD2xh2Xj
// SIG // SOKbH8QvScys46CobPXX8YraXMD++WffLwfSa4xOLjeS
// SIG // m4DXlRHTF9axr706p9QkYwNDmEysAlkWyluWK9kSCmEy
// SIG // gQDJzJodqiaoMGhYhazkm1r5HTaTvOFoxL3hZT+ZKts1
// SIG // 2NerNXJJfECAGAFHwNXqvgX61Xphygzf06YB5HLkck88
// SIG // 84OWWX4ZzeQPO6gUzkhwKrIsbcxJrrjbmoICqh1jlV1L
// SIG // sjlCwd6rWM+VL5vW+JGP84ezZF6fDffTuq5TXWkpuzwY
// SIG // xUbJu4jiDtpfOCk+lul9LulzZ+/vNYEm+cp8hheNbeRN
// SIG // LqSYw33oBu5DsxaJcUylXBIzy2g21zgquA2v4rLv94m0
// SIG // WRR5xKhmLMNdJHeIKvZ7EX+fNMrhkgK6YKI61ec/cu9i
// SIG // kT9g5Y2Me6/KwB6g+0Dabn1kuzC+PRORYxSRauHcy3Ys
// SIG // xfNZVHdYR2+O14ZWnSG73LqYLXwX2tJGN9Iiv1H3D4+V
// SIG // io/xU/JmNXGfUOrnviGE1ZOEIh8BAZYSKC8N
// SIG // End signature block
