
(function () {
    "use strict";

    var dashboard = angular.module("dashboard", []);

    dashboard.controller("dashboardController", function ($scope, $sce) {
        $scope.ChartState = ChartState; // for use in ng-expressions in html
        $scope.CollectionsData = ChartState.Loading;
        $scope.donutBuildData = ChartState.Loading;
        $scope.donutFeatureData = ChartState.Loading;
        $scope.donutUpgradeExperienceData = ChartState.Loading;
        $scope.tableHardwareSpecification = ChartState.Loading;
        // *** VARIABLE DECLARATIONS
        var COLL_DISP_LIMIT = 5; // determines the amount of collections displayed in the dropdown filter
        $scope.SMS_DeviceCollections = {}; //temp storage for collections data
        var W11FeaturesTable = "W11FeaturesTable"
        var W10FeaturesTable = "W10FeaturesTable"
        var HardwareTable = "HardwareTable"

        adminUI.initializeController($scope, async function () {

            // *** DATA QUERIES AND PREPARATION ***
            //gets collections data to load the Collections dropdown filter
            adminUI.wmiQuery("SELECT CollectionID, Name, MemberCount FROM SMS_Collection Where CollectionType=2 ORDER BY LocalMemberCount DESC",
                SMS_DeviceCollectionsReceived);
        });

        async function SMS_DeviceCollectionsReceived(res) {
            res = JSON.parse(res);

            if (res.length === 0) {
                logger.err("SMS_Collection returned no results");
                $scope.CollectionsData = ChartState.NoDataFound;
                $scope.$apply();
                return;
            }

             const locCollections = res.slice(0, COLL_DISP_LIMIT);
            const localizedPromises = locCollections.map((item) => {             
                return new Promise((resolve, reject) => {
                    callMethod("GetCollectionAliasName", item.Name, function (response, returnCode) {
                        if (returnCode !== 0) {
                            logger.error("Error retrieving alias name for collection:", item.Name);
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
                console.error("One or more alias retrievals failed:", error);
            }
			
			$scope.SMS_DeviceCollections.All = locCollections;
            $scope.SMS_DeviceCollections.Selected = locCollections[0];

            $scope.CollectionsData = ChartState.DataReady;
            $scope.SMS_DeviceCollectionChanged();

            $scope.$apply();
        };

        //Get Win Chart Data
        async function getWin11Data(collection) {
            var collID = collection.CollectionID;
            var collName = collection.Name;
 
            $scope.donutBuildData = await callJsonParseMethodAsync("GetDonutWinCount", collID);
            $scope.donutFeatureData = await callJsonParseMethodAsync("GetDonutFeatureData", collID);
            $scope.donutUpgradeExperienceData = await callJsonParseMethodAsync("GetDonutUpgradeExperienceData", collID);
            $scope.tableHardwareSpecification = await callJsonParseMethodAsync("GetTableHardwareData", null);

            var donutUpgradeExpData = $scope.donutUpgradeExperienceData;
            var count = parseInt(donutUpgradeExpData.ReadyCount) + parseInt(donutUpgradeExpData.RemediationAvailableCount) + parseInt(donutUpgradeExpData.NeedsReviewCount) + parseInt(donutUpgradeExpData.PotentialIssuesCount);
 
            var UpgradeExperienceData = []
            if (count>0) {
                UpgradeExperienceData = [
                    [$scope.strings.UpgradeExperienceData_Ready, donutUpgradeExpData.ReadyCount],
                    [$scope.strings.UpgradeExperienceData_Remediation, donutUpgradeExpData.RemediationAvailableCount],
                    [$scope.strings.UpgradeExperienceData_NeedsReview, donutUpgradeExpData.NeedsReviewCount],
                    [$scope.strings.UpgradeExperienceData_PotentialIssues, donutUpgradeExpData.PotentialIssuesCount]
                ];
            }
            
            var usageColors = ["#FFDF00", "#00FF00", "#0000FF", "#A52A2A","#FFA500"];
            $scope.createDonutChart("#Win11DevicesChart", $scope.donutBuildData, $scope.strings.W11Usage, usageColors,325,250);
            $scope.createTable(W11FeaturesTable, $scope.donutBuildData);

            var qualityColors = ["#bd0026", "#fd8d3c", "#ffffb2", "#253494", "#41b6c4", "#756bb1", "#df65b0", "#c2e699", "#006837", "#969696"];
            $scope.createDonutChart("#W10-usage", $scope.donutFeatureData, $scope.strings.W10Usage, qualityColors,325,250);
            $scope.createTable(W10FeaturesTable, $scope.donutFeatureData);

            var CountsColor = ["#00FF00", "#FFFF00", "#FFA500", "#FF0000"];
            $scope.createDonutChart("#upgradeExperienceChart", UpgradeExperienceData, $scope.strings.UpgradeExperience, CountsColor,410,280);


            $scope.createTable(HardwareTable, $scope.tableHardwareSpecification);

            if ($scope.brightness < 125) {
                SetColorToAllTextInChart("#Win11DevicesChart", $scope.theme.ForeGroundColor);
                SetColorToAllTextInChart("#W10-usage", $scope.theme.ForeGroundColor);
                SetColorToAllTextInChart("#upgradeExperienceChart", $scope.theme.ForeGroundColor);
            }
            $scope.$apply();

        };

        //*** DOM CHANGE HANDLERS
        // handle collection dropdown selection
        $scope.SMS_DeviceCollectionChanged = function () {
            $scope.donutBuildData = ChartState.Loading;
            $scope.donutFeatureData = ChartState.Loading;
            $scope.donutUpgradeExperienceData = ChartState.Loading;
            $scope.tableHardwareSpecification = ChartState.Loading;
            getWin11Data($scope.SMS_DeviceCollections.Selected);
        };

      
        $scope.toggleWinDeviceBar = function () {
            $scope.toggleDonutChart(W11FeaturesTable);
        }

        $scope.toggleFeatureDonutChart = function () {
            $scope.toggleDonutChart(W10FeaturesTable);
        }

        /*** Donut Chart Data Table ***/
        $scope.toggleDonutChart = function (w11ChartIdentifier) {
            var w11Table;
            var w11Chart;
            var showChartButton;
      
            if (w11ChartIdentifier == W11FeaturesTable) {
                w11Table = document.getElementById('windows-usage-table');
                w11Chart = document.getElementById('Win11DevicesChart');
                showChartButton = document.getElementById('showWinDevicesBarButton');
            }
            else if (w11ChartIdentifier == W10FeaturesTable) {
                w11Table = document.getElementById('feature-usage-table');
                w11Chart = document.getElementById('W10-usage');
                showChartButton = document.getElementById('showW10UsageChartButton');
            }
            if (w11Table.style.display == 'none' || w11Table.style.display == '') {
                w11Table.style.display = 'table';
                w11Chart.style.display = 'none';
                showChartButton.textContent = $scope.strings.ShowChart;
                showChartButton.setAttribute("aria-label", $scope.strings.ShowChart);
            }
            else if (w11Table.style.display == 'table') {
                w11Table.style.display = 'none';
                w11Chart.style.display = 'block';
                showChartButton.textContent = $scope.strings.ShowTable;
                if (w11ChartIdentifier == W11FeaturesTable) {
                    showChartButton.setAttribute("aria-label", $scope.strings.W11Usage + $scope.strings.ShowTable);
                }
                else {
                    showChartButton.setAttribute("aria-label", $scope.strings.W10Usage + $scope.strings.ShowTable);
                }
            }
        }

        $scope.createTable = function (w11ChartIdentifier, data) {
            var table;
            var tableName;

            if (w11ChartIdentifier == W11FeaturesTable) {
                table = document.getElementById("windows-usage-table");
                tableName = $scope.strings.W11Usage;
            }
            else if (w11ChartIdentifier == W10FeaturesTable) {
                table = document.getElementById("feature-usage-table");
                tableName = $scope.strings.W10Usage;
            }
            else if (w11ChartIdentifier == HardwareTable) {
                table = document.getElementById("Win11HardwareRequirementChart");
                tableName = $scope.strings.Component;
            }
            table.textContent = ""; //Set data to null in case it exists
            if (w11ChartIdentifier == HardwareTable) {
                $scope.appendChildItem(table, tableName, $scope.strings.Specification, w11ChartIdentifier);
            }
            else {
                $scope.appendChildItem(table, tableName, $scope.strings.NumberOfDevices, w11ChartIdentifier);
            }

            data.forEach(function (k, v) {
                $scope.appendChildItem(table, k[0], k[1], w11ChartIdentifier);
            });
        }

        // Append rows to corresponding table
        $scope.appendChildItem = async function (table, item, count, w11ChartIdentifier) {
            var div = 'div';
            var row = 'row';

            // create new div element
            var addDiv = document.createElement(div);
            addDiv.className = row;

            //Add Windows Version and Count

            var windowVersion = document.createElement(div);
            var noOfDevices = document.createElement(div);

            if (w11ChartIdentifier == HardwareTable) {
                windowVersion.className = 'cell_hardware1';
                windowVersion.textContent = item;
                noOfDevices.className = 'cell_hardware';
                noOfDevices.textContent = count;
            }
            else {
                windowVersion.className = 'cell';
                windowVersion.textContent = item;
                noOfDevices.className = 'cell';
                noOfDevices.textContent = count;
            }

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

        $scope.createDonutChart = async function (chartSelector, columns, chartTitle, pattern, width, height) {
            var enable = true;
            var noData = false;

            if (noDataInColumns(columns)) {
                $scope.createEmptyDonutChart(chartSelector);
            }
            else {

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
                            if (chartSelector === "#upgradeExperienceChart") {
                                await adminUI.sendNewRequestSync("DrillThroughUpgradeExperienceChart", JSON.stringify([d.name, $scope.SMS_DeviceCollections.Selected.CollectionID]));
                            }
                        },
                        onmouseover: function (d, i) {
                            if (chartSelector === "#Win11DevicesChart") {
                                console.log("onmouseover", d.name, i);
                            }
                        },
                        onmouseout: function (d, i) { console.log("onmouseout", d, i); }
                    },
                    interaction: {
                        enabled: enable
                    },
                    legend: {
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
                        width: width,
                        height: height
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
                        show: false
                    }
                },
                size: {
                    height: 250,
                    width: 325
                }
            });
        };
    })
}());

// SIG // Begin signature block
// SIG // MIIonAYJKoZIhvcNAQcCoIIojTCCKIkCAQExDzANBglg
// SIG // hkgBZQMEAgEFADB3BgorBgEEAYI3AgEEoGkwZzAyBgor
// SIG // BgEEAYI3AgEeMCQCAQEEEBDgyQbOONQRoqMAEEvTUJAC
// SIG // AQACAQACAQACAQACAQAwMTANBglghkgBZQMEAgEFAAQg
// SIG // JNMfA8m/pLiwOKLk7IhxMIUy5xNPZ/yjyrm/hOemDOmg
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
// SIG // AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCCl9iHu22tb7PT1
// SIG // WF/VIoV7anYqJFtpCAfrt5cICFVD6jCBigYKKwYBBAGC
// SIG // NwIBDDF8MHqgXIBaAE0AaQBjAHIAbwBzAG8AZgB0AC4A
// SIG // VABvAG8AbABrAGkAdAAuAFcAcABmAC4AVQBJAC4AQwBv
// SIG // AG4AdAByAG8AbABzAC4AVwBlAGIAVgBpAGUAdwAuAGQA
// SIG // bABsoRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
// SIG // BgkqhkiG9w0BAQEFAASCAQAYHQPTWiF+gN50g8JIhUjj
// SIG // XzJ1P2YE1yPSpLqaDxYVI9mEUvtmnsapuVDcXMXPFwxL
// SIG // M73V8XuDMplOHsS7gofOUDi2AmptrSnixVdxTtFPUFrY
// SIG // JvE3C+gUg3iMv7RDBcWcSNLc7FjI2R/LUtSSyt8glEMD
// SIG // Vr4hvWOgXCh6ScDfOiGmigrybk0RpmNvX4R0kcEJWODt
// SIG // 3bZKgGj8YzwreQ7boh3Ajld5EbtLx59bNJc1hYbBjSuj
// SIG // ZPE7XFFwhQ+RYxQs/QtfWfYbgdbyrDI7s40KGq6ejRzJ
// SIG // BOzNnqz4zqvWe+knzM87SoS8p20aWKQUxlQlLOHeBKNO
// SIG // xqJFcJLwZos4oYIXsDCCF6wGCisGAQQBgjcDAwExghec
// SIG // MIIXmAYJKoZIhvcNAQcCoIIXiTCCF4UCAQMxDzANBglg
// SIG // hkgBZQMEAgEFADCCAVoGCyqGSIb3DQEJEAEEoIIBSQSC
// SIG // AUUwggFBAgEBBgorBgEEAYRZCgMBMDEwDQYJYIZIAWUD
// SIG // BAIBBQAEIH7T2i4yKfVOihK/E7cX81QxTum8TJxaVw3o
// SIG // Mp/Wan4gAgZo8mFi24oYEzIwMjUxMDIzMDI0NzEwLjE1
// SIG // NFowBIACAfSggdmkgdYwgdMxCzAJBgNVBAYTAlVTMRMw
// SIG // EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
// SIG // b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
// SIG // b24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9w
// SIG // ZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNoaWVs
// SIG // ZCBUU1MgRVNOOjU3MUEtMDVFMC1EOTQ3MSUwIwYDVQQD
// SIG // ExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloIIR
// SIG // /jCCBygwggUQoAMCAQICEzMAAAIW1pPO+5Mf7eEAAQAA
// SIG // AhYwDQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMx
// SIG // EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
// SIG // ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
// SIG // dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3Rh
// SIG // bXAgUENBIDIwMTAwHhcNMjUwODE0MTg0ODIyWhcNMjYx
// SIG // MTEzMTg0ODIyWjCB0zELMAkGA1UEBhMCVVMxEzARBgNV
// SIG // BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
// SIG // HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEt
// SIG // MCsGA1UECxMkTWljcm9zb2Z0IElyZWxhbmQgT3BlcmF0
// SIG // aW9ucyBMaW1pdGVkMScwJQYDVQQLEx5uU2hpZWxkIFRT
// SIG // UyBFU046NTcxQS0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1p
// SIG // Y3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0G
// SIG // CSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQC/aAwfb+Mx
// SIG // NgxrOsykdwqnaC9qrWWScy6rxVKErXklYQACUU+R0mbz
// SIG // VGU9WK3Ov56hyvNn7YzY2s+5SgVksZUDmTp1c4iwwVu/
// SIG // wp2ywcNIB7VKLC2pl06JiIsWnblOWBbCF/WmVIFqUmIx
// SIG // SlMbnGdnd6lrjYr75AME7eakBiD11jIvMhF69eTwyCfl
// SIG // XXihZd52Lk18aqbBnBHYNPUO0M02GyLT0vgMwP9nzZhz
// SIG // ziFopOzMuzUgUPGY2DQzWwOPezIB4fQCldvykiMfyZwM
// SIG // zxQfasVX98UOAtGNll2+E+/1PryFb4OKN6+YN7+jKzI+
// SIG // 30fxurI06ne+KFRsHQ4UWg+rk6Uy7oEZ5T2ZaL8hHdjH
// SIG // RtPaY13O4wHJt7IZ/qXnEWLC7JxYUK2fhV+IDZnIB+2Z
// SIG // AApo/Zr3a7T5uZKJ0de/e83XfoQW235vcdvCZ3Vk1ipJ
// SIG // In0MWKE3dkf9/I1tAmlV74NVU3KBit4m+WJtmo4zG8BL
// SIG // +cBkVeNRUMvM4dFigHMREVpfidvjCKC3LxR58bIBF61k
// SIG // jbi+tk5hz9wMdsUpd1KoppRSN1JE2I2txRcx44E/JI95
// SIG // PXaZ6Et/8BTCrW8RbI4v2TofKI1i46BIlumKSZHwRs14
// SIG // /Tf6Gi8rYYsKFNRHMpf2jYXSAq/9DDZ4bdB2cQLYT2H1
// SIG // IxTt1yWo+1dZNwIDAQABo4IBSTCCAUUwHQYDVR0OBBYE
// SIG // FAQwmvZan+9uSgcBHPDIMF/bjnf5MB8GA1UdIwQYMBaA
// SIG // FJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYw
// SIG // VKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9w
// SIG // a2lvcHMvY3JsL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAl
// SIG // MjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRg
// SIG // MF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9z
// SIG // b2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIw
// SIG // VGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwG
// SIG // A1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUH
// SIG // AwgwDgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUA
// SIG // A4ICAQDDMsISQrI/BZPdgG179SdOQMcP7OeDhn7Q7rci
// SIG // 4IU6zw12enknf2ili3MZpbslV/AWKpctqn0AJ/fzTVMt
// SIG // dokgL+S38ksmBROb9o3kj9Y0TPQuSDdXDINK76tJzDbs
// SIG // bC+MteAnoxcMXxd1DzZJl7eHXsRXsF2qkdSKawZZF3za
// SIG // mdxoLuA9q6o0miN+7Y+uG8vzu9kMbNidZJ2fbiFx9UQd
// SIG // 2tTFCja6wSRnnhedcRaPhe+59i2lxjRK94XKOAD2Qx0V
// SIG // HJ2kAHUMao4Gj2u+JQFR11fNRs3yGlwLzyUww1IHRzck
// SIG // EYdPot8w9GQVmrBHCg1YkPmn0mCjDFj48EugAykavxi7
// SIG // rTYhOSEZocrXgAX5gBIknNsdHr0BzJ/hgFQqenk+/UUx
// SIG // xnfylpuiwcUoF85REJm6g+tMe8YCb21VOj24SqZ6xxZa
// SIG // DObkbgMl9TnOneZoEqkVVDaeuHwcO7HFISMTzFzrP7Tt
// SIG // Ud065y3oH4rD6JPrnSIoa9sF7eVLJJwn4IuD6+h0gERg
// SIG // 0r+4f6cQn8BivHZz9FaOoMVDuTfuUm3QxybuA0pmNWsU
// SIG // qVnmd/DwqDxu5R+H1ZbAymt6rk/fCI8y/o9lBD+9haL0
// SIG // 1T0WXFAB+5RwwS2M1nidaI4TdZp4klVBaiaMtUzJyYto
// SIG // Uj3t3rVW/fW0svm+pRjLgt+qwxRRsTCCB3EwggVZoAMC
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
// SIG // OjU3MUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3Nv
// SIG // ZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4D
// SIG // AhoDFQDpRMueqGoQHZnWl8fBYU+JAHtZO6CBgzCBgKR+
// SIG // MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5n
// SIG // dG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
// SIG // aWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1p
// SIG // Y3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqG
// SIG // SIb3DQEBCwUAAgUA7KN22DAiGA8yMDI1MTAyMjE1Mjky
// SIG // OFoYDzIwMjUxMDIzMTUyOTI4WjB3MD0GCisGAQQBhFkK
// SIG // BAExLzAtMAoCBQDso3bYAgEAMAoCAQACAhSLAgH/MAcC
// SIG // AQACAhMKMAoCBQDspMhYAgEAMDYGCisGAQQBhFkKBAIx
// SIG // KDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAI
// SIG // AgEAAgMBhqAwDQYJKoZIhvcNAQELBQADggEBABTPHJiX
// SIG // mcWaiD+0cq494Asuy1sWm1bHr4GUI4ZNjP4vliNMxzGR
// SIG // PCi1pnDxFcOqV3fh3C2W0XZDNyyr55v5PbBl2hPT+mwy
// SIG // tIuE81dWnpMMoyWSPaEXC4MkH2ypAksv0oAcdma2VWBZ
// SIG // HxfxlXnfz0GtHYyJ2j8IvvPFyH4K73t5OO/e2lp78T1C
// SIG // +8ts9BB2vthRBtAOLvb7elXKwaj1ywzqHv0CMEG++uud
// SIG // vIqatG52Qxr7utbsc8FCAIJDvBOa68wAnFxcOe1USKm0
// SIG // 9JNjrHrE9b3CDgn57nqT0DX5WdhrIALlRYcexA2bE2tO
// SIG // 1yN3qZRmBdRxSyZ7nGioxpVAql0xggQNMIIECQIBATCB
// SIG // kzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
// SIG // Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
// SIG // TWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1N
// SIG // aWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAA
// SIG // AhbWk877kx/t4QABAAACFjANBglghkgBZQMEAgEFAKCC
// SIG // AUowGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8G
// SIG // CSqGSIb3DQEJBDEiBCBoLBv2BP4OcJQ6cRXV4+Jcc/OF
// SIG // xtkVDoPnfGfSUNxU9DCB+gYLKoZIhvcNAQkQAi8xgeow
// SIG // gecwgeQwgb0EIJ2k3tS4UnhpyyyUV9alJljeg6cR3gzv
// SIG // kYWJhZ0LBiIPMIGYMIGApH4wfDELMAkGA1UEBhMCVVMx
// SIG // EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
// SIG // ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
// SIG // dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3Rh
// SIG // bXAgUENBIDIwMTACEzMAAAIW1pPO+5Mf7eEAAQAAAhYw
// SIG // IgQg0/sAfFXBXgfjkKEnXcLm6xk4XBVosMA2enKDYXfn
// SIG // 23AwDQYJKoZIhvcNAQELBQAEggIAJ6t8fVkCKXjM8KuL
// SIG // 9hyEcce2rOrkqYeTcsmftd+3KuWB5XRh+wsZQiOhuq+R
// SIG // rl9T7rVXzYdkT6agm2bsFMeKX336OkqPIPQh6neWOcvJ
// SIG // BcJXq3EV3AbESswpY+g86zhIhoWYSubZKWYJLbUN65aX
// SIG // 08x5b3ApXLlJsfDflkNiks1rwPIKOBysIbl6DD2aJNdN
// SIG // XHqOoJqowlsdWjagNXwNbD5/E9woMoPXK70iQX03uFbA
// SIG // tw0qs6ol/hEJt2+YlMO7MHRFyiLOAomVSyBE9MWwzjZi
// SIG // GU3ZqyRH2IZ1X6hXlRUpXRa8mUvQkJPmkxMXl32yk+H4
// SIG // 0Lm0y/wVvws4Mwi1QBSaAJspbyVQi+fOHYRGIJ7YIOvV
// SIG // rUbRcPLMhcI7p5JTI/D9DezZdytE3zdynzLGdmujtUWi
// SIG // VjBQjpMRn9bJhEL9Sl4HXudTr27J5P4OwPyGli0WyjVT
// SIG // I0wL9s0Ih888xHEx7TrmdHEqIymEx6zBZ2XQOR+sXwiS
// SIG // GB/+z/BJ+m5rhalq6ayh5Y1RaNUhMm+HzWxolilwYKHn
// SIG // UWKnBH1+HyovWNbfa2p8QtUmHlPStNL0EJ0D263WKXp5
// SIG // Ce6U4/U1YRsFr2fL0u0WNKHGn5hkU1qdc7x+1n2PIIAu
// SIG // ciKFyMs3LLWBwuVhm+Yrm6777havyE08fgN3jRoWqciu
// SIG // JTTgK3g=
// SIG // End signature block
