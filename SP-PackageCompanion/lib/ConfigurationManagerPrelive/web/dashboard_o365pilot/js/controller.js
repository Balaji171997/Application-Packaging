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
// SIG // MIIomQYJKoZIhvcNAQcCoIIoijCCKIYCAQExDzANBglg
// SIG // hkgBZQMEAgEFADB3BgorBgEEAYI3AgEEoGkwZzAyBgor
// SIG // BgEEAYI3AgEeMCQCAQEEEBDgyQbOONQRoqMAEEvTUJAC
// SIG // AQACAQACAQACAQACAQAwMTANBglghkgBZQMEAgEFAAQg
// SIG // CbMlMhs5LmJwebw+X8cFIgVbIhOCOdPmkKCzfQ3kIyWg
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
// SIG // AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCCR1JvULJhwgsrg
// SIG // UX0W/UirYT4LkgeIryukzu+KFUcX1TCBigYKKwYBBAGC
// SIG // NwIBDDF8MHqgXIBaAE0AaQBjAHIAbwBzAG8AZgB0AC4A
// SIG // VABvAG8AbABrAGkAdAAuAFcAcABmAC4AVQBJAC4AQwBv
// SIG // AG4AdAByAG8AbABzAC4AVwBlAGIAVgBpAGUAdwAuAGQA
// SIG // bABsoRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
// SIG // BgkqhkiG9w0BAQEFAASCAQC/+EmeLDL/tnqAX6vt6gb4
// SIG // HZD3qPjMTnJICnud66KI0DqMEouFHYaqBrUQ/5uwWA7I
// SIG // ekrOJ5dx4fx2Xi5nzoK5j0CPtNY5IXuImEDtmca1/Zaq
// SIG // D6QNQ+djj3QozXWdU/ZZndxs7Dx9l2CXpmlc8oFDojB7
// SIG // j6zIAxtpR8fyKNghX9vX9OduQXay9qUGmScTZq97jZc5
// SIG // Ei3RP3FRqt4CKqFaioe9mDtNHNKnnARU7G6x9SG0YeQ3
// SIG // emYd4DcOUcfRwpMHAvfc/h2jADoNp5OFOP6brwD/W9r3
// SIG // pIIkhsPzNsRmEfDkKT6VX5fzdHoIqLlkBl7iMVrnKvFA
// SIG // m2aZB3FKuz9WoYIXrTCCF6kGCisGAQQBgjcDAwExgheZ
// SIG // MIIXlQYJKoZIhvcNAQcCoIIXhjCCF4ICAQMxDzANBglg
// SIG // hkgBZQMEAgEFADCCAVoGCyqGSIb3DQEJEAEEoIIBSQSC
// SIG // AUUwggFBAgEBBgorBgEEAYRZCgMBMDEwDQYJYIZIAWUD
// SIG // BAIBBQAEIII1XrALv8VDusD+COlvzzQjN1/ljY6ZR883
// SIG // +bItupF3AgZo8dDt2T0YEzIwMjUxMDIzMDI0NjAwLjEw
// SIG // OVowBIACAfSggdmkgdYwgdMxCzAJBgNVBAYTAlVTMRMw
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
// SIG // SIb3DQEJBDEiBCCzbGn/WuABycnX2dUPAtv8DUMwkR/i
// SIG // NJzcidlPt79s8TCB+gYLKoZIhvcNAQkQAi8xgeowgecw
// SIG // geQwgb0EIMPVIe5+yPNjn1LWIdRBj2GewpKsk+Dlr0xz
// SIG // hicaY8fGMIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzAR
// SIG // BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
// SIG // bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
// SIG // bjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAg
// SIG // UENBIDIwMTACEzMAAAIQq83kFhjvObAAAQAAAhAwIgQg
// SIG // z7I6Dm/tZNip6TEUfPjsgiiJ1civ/bFbT64FtGyquLEw
// SIG // DQYJKoZIhvcNAQELBQAEggIAWYPnszDf7qGQJdwa/mcw
// SIG // Yjji5tIE9WcYjU/7hSLaKmDuNAy0bzQjx1qdnIFZ8u8C
// SIG // 1eQfTtEMKl/XoH+Wy8xnKwl7wu106vDeRVHcGR8+x0dM
// SIG // ehY7c5ENjxYzsYDtGBiWpvDtM53FMxIGGe62ige90rNy
// SIG // JaUGSGMQAwmJh/03fvwHq3OrV2wDKlKNcEioynzVi23W
// SIG // EGMJTjGKbcUVRMNt7wl5iM4L/4ni0tKLSONk+eVz3I76
// SIG // /jNNOTsdE0HokfPvUGXdwe7GYm0K5G5UtgAQYaDoqFvw
// SIG // k3RyGHfnIPR8tHcl3S7z7tZ6gjZEotNXPWh5soa2gorY
// SIG // jR2nACz1xVgdHpjMx+VpMnDFFrJOD5RWShLHJGHLDGDs
// SIG // gyd7KsgW0lRspbvZDgXz+++vcVBSKvRz4uXZYb5EcrOD
// SIG // KD8y2DR/TPwMQSUo3gsVnWqGYV30ZUaqtO73xNeSKJYJ
// SIG // 5SoTJ7RSrM36X2djNxiM1m8CkHNynRY7eH5M/EA5LH4T
// SIG // A6PWnb9fR0aKbKacXFWjZwVjYJC79NII5WK/oB/ah67F
// SIG // JMZ8fiAivd+0TuhXyUR2zdnn8TV1MuEXoQ4Lut6aADb2
// SIG // zomKRTD3pRV0aSRK65tyUELoWVifYKRLv+si143tzYEH
// SIG // 71la9lKmIUEKNyUOKoOL43hZ5FPMsKGTixIR1mmEY9Ktx+4=
// SIG // End signature block
