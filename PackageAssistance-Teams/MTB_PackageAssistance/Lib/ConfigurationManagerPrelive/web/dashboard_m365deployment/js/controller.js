(function () {

    "use strict"
    var dashboard = angular.module("dashboard", []);

    dashboard.controller("dashboardController", function ($scope, $sce) {

        $scope.strings = JSON.parse(window.external.GetStrings());
        $scope.M365DeploymentPlanInfo = JSON.parse(window.external.M365DeploymentPlanInfo());
        $scope.DeploymentPlanState = JSON.parse(window.external.M365DeploymentPlanState());
        $scope.M365UpgradeDecisionData = JSON.parse(window.external.M365UpgradeDecisionData());
        $scope.M365PilotReadinessData = JSON.parse(window.external.M365PilotReadinessData());
        //$scope.M365PilotProgressData = JSON.parse(window.external.M365PilotProgressData());
        $scope.M365ProdReadinessData = JSON.parse(window.external.M365ProductionReadinessData());
        //$scope.M365ProdProgressData = JSON.parse(window.external.M365ProductionProgressData());

        $scope.DeployIsDisabled = (($scope.DeploymentPlanState == 0) ? true : false) && window.external.HasPermissionToDeploy();
        $scope.ShowOffice = ($scope.M365DeploymentPlanInfo.OfficeVersion == null) ? false : true;

        // generic function to create donut chart
        $scope.createDonutChart = function (id, data, color, drillThroughEnabled) {
            if (noDataInColumns(data)) {
                $scope.createEmptyDonutChart(id);
            }
            else {
                c3.generate({
                bindto: id,
                data: {
                    columns: data,
                    type: 'donut',
                },
                legend: {
                    position:'right'
                },
                color: {
                    pattern: color
                },
                donut: {
                    label: {
                        format: function (value, ratio) {
                            return value;
                        },
                    }
                },
                size: {
                    width: 500,
                    height: 250,
                }
            });
            }
        };

        // generic function to create bar chart
        $scope.createBarChart = function (id, data, drillThroughEnabled) {
            if (noDataInColumns(data)) {
                $scope.createEmptyBarChart(id);
            }
            else {
            c3.generate({
                bindto: id,
                data: {
                    columns: data,
                    type: 'bar',
                    labels: {
                        format: function (value, ratio) {
                            return value;
                        }
                    }
                },
                axis: {
                    rotated: false,
                    x: { show: false },
                    y: { show: false }
                },
                legend: {
                    position: 'right'
                },
                bar: {
                    width: { ratio: 0.6 }
                    //space: 0.2
                },
                color: {
					pattern: ['#0072C6', '#80EAFF', '#FFCD19', '#FF7F00', '#E81123', '#63cc43', '#BCBFC5']
                },
                tooltip: {
                    show: false
                }
            });
            }
        };
 
        $scope.createEmptyBarChart = function (idToBindTo) {
            c3.generate({
                bindto: idToBindTo,
                data: {
                    columns: [[' ', 5, 2, 3, 4, 1]],
                    type: 'bar',
                    label: {
                        format: function (value, ratio) {
                            return "No data";
                        },
                    }
                },
                axis: {
                    rotated: false,
                    x: { show: false },
                    y: { show: false }
                },
                legend: {
                    show: false
                },
                bar: {
                    width: { ratio: 0.6 }
                },
                color: {
                    pattern: ['#a9a9a9', '#a9a9a9', '#a9a9a9', '#a9a9a9', '#a9a9a9']
                },
                tooltip: {
                    show: false
                }
            });

            if (GetCurrentBackgroundColor() < 125) {
                SetColorToAllTextInChart(idToBindTo, 'white');
            }

            $scope.$apply();
        };


        $scope.createStackedBarChart = function (id, data) {
            c3.generate({
                bindto: id,
                data: {
                    columns: data,
                    type: 'bar',
                    labels: {
                        format: function (value, ratio) {
                            return value;
                        }
                    },
                    groups: [
                        ['Not started', 'In progress', 'Needs attention', 'Completed']
                    ]
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
                bar: {
                    width: 30
                },
                legend: {
                    position: 'inset',
                    inset: {
                        anchor: 'bottom-left',
                        x: 20,
                        y: 100,
                        step: 4
                    }
                },
                color: {
                    pattern: ['#BCBFC5', '#76797B', '#E81123', '#7FBA00']
                },
                tooltip: {
                    show: false
                }
            });
        }

        // generic function to create empty donut chart
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
                            return "No data";
                        },
                    }
                },
                size: {
                    height: 235,
                    width: 235
                }
            });

            if (GetCurrentBackgroundColor() < 125) {
                SetColorToAllTextInChart(idToBindTo, 'white');
            }

            $scope.$apply();
        }

        // function to chart out the over all upgrade decision status
        $scope.createUpgradeDecisionDonutChart = function () {
            var upgradeDecisionUptoDate = $scope.M365UpgradeDecisionData.NumUptoDate;
            var upgradeDecisionComplete = $scope.M365UpgradeDecisionData.NumUpgradeDecisionComplete;
            var upgradeDecisionNotReviewed = $scope.M365UpgradeDecisionData.NumNotReviewed;

            var donutData = [
                [$scope.strings['upgradeDecisionUptoDate'], upgradeDecisionUptoDate],
                [$scope.strings['upgradeDecisionComplete'], upgradeDecisionComplete],
                [$scope.strings['upgradeDecisionNotReviewed'], upgradeDecisionNotReviewed]
            ];
            var pattern = ['#7FBA00', '#66D7F7', '#BCBFC5'];

            $scope.createDonutChart("#recommendedPilot", donutData, pattern, false);
        }

        $scope.createStackedBarChartPilotDepProgress = function () {
            var data = [['Not started', 3],
            ['In progress', 11],
            ['Needs attention', 0],
            ['Completed', 8]];
            $scope.createStackedBarChart("#pilotDeploymentProgress", data);
        }

        $scope.createStackedBarChartProductionDepProgress = function () {
            var data = [['Not started', 24],
            ['In progress', 78],
            ['Needs attention', 5],
            ['Completed', 177]];
            $scope.createStackedBarChart("#prodDeploymentProgress", data);
        }

        $scope.createBarChartPilot = function () {
            var pilotReady = ($scope.M365PilotReadinessData.NumPilotReady == 0) ? null : $scope.M365PilotReadinessData.NumPilotReady;
            var pilotReadyRemediation = ($scope.M365PilotReadinessData.NumPilotReadyRemediation == 0) ? null : $scope.M365PilotReadinessData.NumPilotReadyRemediation;
            var pilotBlocked = ($scope.M365PilotReadinessData.NumPilotBlocked == 0) ? null : $scope.M365PilotReadinessData.NumPilotBlocked;
            var pilotReplacementRequired = ($scope.M365PilotReadinessData.NumPilotReplacementRequired == 0) ? null : $scope.M365PilotReadinessData.NumPilotReplacementRequired;
            var pilotReinstallRequired = ($scope.M365PilotReadinessData.NumPilotReinstallRequired == 0) ? null : $scope.M365PilotReadinessData.NumPilotReinstallRequired;
            var pilotUpToDate = ($scope.M365PilotReadinessData.NumPilotUptoDate == 0) ? null : $scope.M365PilotReadinessData.NumPilotUptoDate;
            var pilotNotReviewed = ($scope.M365PilotReadinessData.NumPilotNotReviewed == 0) ? null : $scope.M365PilotReadinessData.NumPilotNotReviewed;
            var data = [
                [$scope.strings['pilotReady'], pilotReady],
                [$scope.strings['pilotReadyRemediation'], pilotReadyRemediation],
                [$scope.strings['pilotBlocked'], pilotBlocked],
                [$scope.strings['pilotReplacementRequired'], pilotReplacementRequired],
                [$scope.strings['pilotReinstallRequired'], pilotReinstallRequired],
                [$scope.strings['pilotUptoDate'], pilotUpToDate],
                [$scope.strings['pilotNotReviewed'], pilotNotReviewed]
            ]
            $scope.createBarChart("#pilotReadinessDevices", data, false);
        };


        $scope.createBarChartProd = function () {
            var prodReady = ($scope.M365ProdReadinessData.NumProdReady == 0) ? null : $scope.M365ProdReadinessData.NumProdReady;
            var prodReadyRemediation = ($scope.M365ProdReadinessData.NumProdReadyRemediation == 0) ? null : $scope.M365ProdReadinessData.NumProdReadyRemediation;
            var prodBlocked = ($scope.M365ProdReadinessData.NumProdBlocked == 0) ? null : $scope.M365ProdReadinessData.NumProdBlocked;
            var prodReplacementRequired = ($scope.M365ProdReadinessData.NumProdReplacementRequired == 0) ? null : $scope.M365ProdReadinessData.NumProdReplacementRequired;
            var prodReinstallRequired = ($scope.M365ProdReadinessData.NumProdReinstallRequired == 0) ? null : $scope.M365ProdReadinessData.NumProdReinstallRequired;
            var prodUpToDate = ($scope.M365ProdReadinessData.NumProdUptoDate == 0) ? null : $scope.M365ProdReadinessData.NumProdUptoDate;
            var prodNotReviewed = ($scope.M365ProdReadinessData.NumProdNotReviewed == 0) ? null : $scope.M365ProdReadinessData.NumProdNotReviewed;
            var data = [
                [$scope.strings['productionReady'], prodReady],
                [$scope.strings['productionReadyRemediation'], prodReadyRemediation],
                [$scope.strings['productionBlocked'], prodBlocked],
                [$scope.strings['productionReplacementRequired'], prodReplacementRequired],
                [$scope.strings['productionReinstallRequired'], prodReinstallRequired],
                [$scope.strings['productionUptoDate'], prodUpToDate],
                [$scope.strings['productionNotReviewed'], prodNotReviewed]
            ]
            $scope.createBarChart("#productionReadinessDevices", data, false);
        }

        // launch wizard from deployment plan dashboard to create a new collection 
        $scope.CreateCollection = function () {
            try {
                window.external.CreateCollection();
                console.log("creation collection is called");
            } catch (err) {
                console.log("Create collection failed");
            }
        };

        // launch link to Desktop Analytics portal
        $scope.OpenDesktopAnalyticsPortal = function () {
            try {
                window.external.OpenDesktopAnalyticsPortal();
                console.log("Launch Desktop Analytics");
            }
            catch (err) {
                console.log("Failed to launch Desktop Analytics");
            }
        }

        // launch wizard from deployment plan dashboard to deploy app, sup or task sequence for pilot 
        // if Office options are not shown, disable Application wizard, so adjust index accordingly
        $scope.DeployToPilotCollection = function () {
            try {
                var e = document.getElementById("PilotReadinessSelector");
                var selectedIndex = e.options[e.selectedIndex].value;
                window.external.DeployToCollection(selectedIndex, "pilot");
                console.log("Deploy to pilot collection is called");
            } catch (err) {
                console.log("Deploy to pilot collection failed");
            }
        };

        // launch wizard from deployment plan dashboard to deploy app, sup or task sequence for production 
        // if Office options are not shown, disable Application wizard, so adjust index accordingly
        $scope.DeployToProdCollection = function () {
            try {
                var e = document.getElementById("ProdReadinessSelector");
                var selectedIndex = e.options[e.selectedIndex].value;
                window.external.DeployToCollection(selectedIndex, "production");
                console.log("Deploy to production collection is called");
            } catch (err) {
                console.log("Deploy to production collection failed");
            }
        };

        // calling all functions 
        angular.element(document).ready(function () {
            $scope.createUpgradeDecisionDonutChart();
            $scope.createBarChartProd();
            $scope.createBarChartPilot();
            $scope.createStackedBarChartPilotDepProgress();
            $scope.createStackedBarChartProductionDepProgress();
        });
    });
}());
// SIG // Begin signature block
// SIG // MIIonAYJKoZIhvcNAQcCoIIojTCCKIkCAQExDzANBglg
// SIG // hkgBZQMEAgEFADB3BgorBgEEAYI3AgEEoGkwZzAyBgor
// SIG // BgEEAYI3AgEeMCQCAQEEEBDgyQbOONQRoqMAEEvTUJAC
// SIG // AQACAQACAQACAQACAQAwMTANBglghkgBZQMEAgEFAAQg
// SIG // MIEJoXb4dq52pk6rExLb+WRuoahjANTGizGDTmPgSfWg
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
// SIG // AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCDZIZk6c06HuKoU
// SIG // 6nd0hgYIfC0TP2CqvvGmwVdGMw2R9jCBigYKKwYBBAGC
// SIG // NwIBDDF8MHqgXIBaAE0AaQBjAHIAbwBzAG8AZgB0AC4A
// SIG // VABvAG8AbABrAGkAdAAuAFcAcABmAC4AVQBJAC4AQwBv
// SIG // AG4AdAByAG8AbABzAC4AVwBlAGIAVgBpAGUAdwAuAGQA
// SIG // bABsoRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
// SIG // BgkqhkiG9w0BAQEFAASCAQAA5QLWGQ4wltncexrEeQ/C
// SIG // WIhYfHj1leQkLy5MLDzrL3vpWJmN38FvbhQ7lBUd42Sf
// SIG // QiFMN/ex1z5myE+EiOT0glssC6ML3uHdr7OEb8HVZ9uV
// SIG // qkdX9PCO4Zo4gXeKwYzFeC0zBH+vGkTFUlpMzYBMy4Zp
// SIG // tASCYC8dvrgogerqcHjDQvyYaBkYGAq9ZqussV13IiRG
// SIG // 4wF95ftsQu+dVU01sIS4czpy4gkzkK4Y9TCIvkFfQ5x0
// SIG // ev61YVmBQuO3JkcTUryNZZXMu/UN80b2B/qH0+aPbx2e
// SIG // Fy/UqbBbS4zjBu4vpAfC+h+LbwFUdt3M768XzEw9JNIO
// SIG // 8mZWnut1ackJoYIXsDCCF6wGCisGAQQBgjcDAwExghec
// SIG // MIIXmAYJKoZIhvcNAQcCoIIXiTCCF4UCAQMxDzANBglg
// SIG // hkgBZQMEAgEFADCCAVoGCyqGSIb3DQEJEAEEoIIBSQSC
// SIG // AUUwggFBAgEBBgorBgEEAYRZCgMBMDEwDQYJYIZIAWUD
// SIG // BAIBBQAEIF1NTpER0z7+Wa+5k5fT1agpIoUah6Yy+UTI
// SIG // tmM8MAj/AgZo8e4BO+wYEzIwMjUxMDIzMDI0NzE1LjAx
// SIG // OVowBIACAfSggdmkgdYwgdMxCzAJBgNVBAYTAlVTMRMw
// SIG // EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
// SIG // b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
// SIG // b24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9w
// SIG // ZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNoaWVs
// SIG // ZCBUU1MgRVNOOjQwMUEtMDVFMC1EOTQ3MSUwIwYDVQQD
// SIG // ExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloIIR
// SIG // /jCCBygwggUQoAMCAQICEzMAAAIZXrLYVHX0sY0AAQAA
// SIG // AhkwDQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMx
// SIG // EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
// SIG // ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
// SIG // dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3Rh
// SIG // bXAgUENBIDIwMTAwHhcNMjUwODE0MTg0ODI2WhcNMjYx
// SIG // MTEzMTg0ODI2WjCB0zELMAkGA1UEBhMCVVMxEzARBgNV
// SIG // BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
// SIG // HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEt
// SIG // MCsGA1UECxMkTWljcm9zb2Z0IElyZWxhbmQgT3BlcmF0
// SIG // aW9ucyBMaW1pdGVkMScwJQYDVQQLEx5uU2hpZWxkIFRT
// SIG // UyBFU046NDAxQS0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1p
// SIG // Y3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0G
// SIG // CSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCmoUjJSTMj
// SIG // LGkvdDTdaYu7Lgb1ghRJzOeEqv5wc5P7+7s9qvEj3qDH
// SIG // FvVata4DEHyqMYt+xsibHxXei4rWdRx/5H+eyddqzn+J
// SIG // OBX9OXdBNEZPQN65cE1ukepz7ALU2JPIDvqAueKu9IES
// SIG // gHOWuk1AUSe7B1s8sIulNLcpZIK7knTZv5EVZH+RwXNX
// SIG // GeGgTeAhp5RG2sYoYFkYosFe+qCCQMQ20qS+29FPfbEu
// SIG // 8C8v9GlF67nPXxmiMKzvZlKhrvgPLxhtpawObc5k6klF
// SIG // nFmw8oIdnrE2qAUp/TE0ePS32/RDdb7bPmABVpqwkkK9
// SIG // HnZKXRcnYA5/eXQtJ61eBQDmAPkhDVG8SyVOY2dKi5Os
// SIG // YgPcPWeNjuYG7Sm6Ih08raMr/VZ55/b5hHhxClZCR4Fm
// SIG // ZeJ2H0C5Z2XDEpAvXksnorZ3DzL+388GGYvK3pAB/QJ6
// SIG // lZF2BmczK1UBS5YfCVlFX0ktjtpfwPnl4v35w4ulfdsY
// SIG // 06Y3bhSkhbyq1lqpdp6wW8g5bbck0uFppBW85uvV67sY
// SIG // T/kyfjd778Nu11iX9ss/YhDXFgQl1JtxSQMV9bcqVkSH
// SIG // 6cEoO1pGc1GRuAiDEhsp1Pfw4pDBn9oDi5KyICDqcQ+J
// SIG // YEca7K0ijnBTvkzlV2OESqpMd9di7wEmLoZPO9ZP716R
// SIG // 8xd7OoKSSzFobwIDAQABo4IBSTCCAUUwHQYDVR0OBBYE
// SIG // FIBo6jkdZq03OpmfUgXV9wPqevchMB8GA1UdIwQYMBaA
// SIG // FJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYw
// SIG // VKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9w
// SIG // a2lvcHMvY3JsL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAl
// SIG // MjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRg
// SIG // MF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9z
// SIG // b2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIw
// SIG // VGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwG
// SIG // A1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUH
// SIG // AwgwDgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUA
// SIG // A4ICAQBfHNVkstcEV+gIIJOJjswdd1vtyK8lJN+sdgkL
// SIG // k6TY03vk2nNMxP1XZNwhCN9DcAVRuHU0EBi0xS7DELoP
// SIG // hx4RcbmVcCdu+QL1iN4tUNHIiZdhiZ+3vP5CmX23cL/x
// SIG // rS2Kqc7PxR7z8Ngu0xOC9Yyeyos2MgsNoiY5+ccjfpMs
// SIG // KMYV7xFgtcZ0JR04uV8B0wZ4/FJMDdMAA5z4ZBuY9aOu
// SIG // C4tZvG+eXc1WNG+sFlWTEUyhVkfR/uobAM5KGOme/mdi
// SIG // dDjy58vS4HPnZFs8Z1fgW/35QY6sGmuZwfOYi60W0l5z
// SIG // ZjiS6M21MrbAEaBaxwQ5WEWJpV2N7xUsnsxU0oTlOay4
// SIG // YzeNMuvWe5HkAUazdQqQ/uDdxAPhwcrtd0uJObt7rTpA
// SIG // n5ap5CwANgT129T3AhRsj0OXhRwgSsXD4UdpZJOuR8nh
// SIG // K8uaEqeXmSGGknWwXfPp7UHF6lSWJcerNEuIdaKFYhYR
// SIG // IXwgcSUXc87Fs/hUmocGJi9pcxXRLJGDCgPrNd11tSdf
// SIG // 1ZHokvYGWoCOMfEg3B6Wyn9WHEBZOHO4wDnwvG8T9UDO
// SIG // N8UXhabtrVkAuYlXDegv+z+7GjU6ni1xP6F9n243WG0L
// SIG // Uk3gO5GoV8u22O6gCZRChs7nNQVHO8KfwKT+GI75vNHX
// SIG // myqSOXEszIyOmRz95/hJRSKQPjry9TCCB3EwggVZoAMC
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
// SIG // OjQwMUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3Nv
// SIG // ZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4D
// SIG // AhoDFQAxdin9aqp3JvR6eKCst/GXQicDPqCBgzCBgKR+
// SIG // MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5n
// SIG // dG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
// SIG // aWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1p
// SIG // Y3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqG
// SIG // SIb3DQEBCwUAAgUA7KOsKzAiGA8yMDI1MTAyMjE5MTY1
// SIG // OVoYDzIwMjUxMDIzMTkxNjU5WjB3MD0GCisGAQQBhFkK
// SIG // BAExLzAtMAoCBQDso6wrAgEAMAoCAQACAgcYAgH/MAcC
// SIG // AQACAhJQMAoCBQDspP2rAgEAMDYGCisGAQQBhFkKBAIx
// SIG // KDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAI
// SIG // AgEAAgMBhqAwDQYJKoZIhvcNAQELBQADggEBAERj8WHZ
// SIG // 1/TlYM4Ptc08Z668cw80qY+Zx+pBex8mTuvvmBi5M/GM
// SIG // rz/G3p2J7KBj/hG92ddCu4JLLcjexvDYfLJvWkLVexa4
// SIG // nKeuz5SKKMwuo1Yxwu6ovJ0gmW8pfnSU7z1JVApuzIWP
// SIG // 0lxygfN3Pndckh4VSVQr2BA6QHYgBL/3rFiPXcj1kGNe
// SIG // crpec5Zo/uli3KSqeW4IcwavzHGbwRsMlRL0l/iHRuMw
// SIG // VWXnkoA6xgnCF4uSfjnsQtfuhpd3gndc/4I5BS6e+i7i
// SIG // aimhkJ0J6wyB49zMWRPMIXwVazXyxjNFUqB2Afbx1QRy
// SIG // 2lnMIaOw1HYWO3n7UvZfafG3Rc0xggQNMIIECQIBATCB
// SIG // kzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
// SIG // Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
// SIG // TWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1N
// SIG // aWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAA
// SIG // AhlesthUdfSxjQABAAACGTANBglghkgBZQMEAgEFAKCC
// SIG // AUowGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8G
// SIG // CSqGSIb3DQEJBDEiBCB5oAjxRZrTlkDSlPD//eRndNp/
// SIG // 47JfExkqMrXZZPii0zCB+gYLKoZIhvcNAQkQAi8xgeow
// SIG // gecwgeQwgb0EINyRfrfcTXLUQXfZXXzNByuyCPMj37ct
// SIG // 7uaW+TY55u2GMIGYMIGApH4wfDELMAkGA1UEBhMCVVMx
// SIG // EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
// SIG // ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
// SIG // dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3Rh
// SIG // bXAgUENBIDIwMTACEzMAAAIZXrLYVHX0sY0AAQAAAhkw
// SIG // IgQgOyStiHS4g1F0q4lrwCt903H7NO0Iw7r1tIrJxX/l
// SIG // XJowDQYJKoZIhvcNAQELBQAEggIAolsziCU25wq9n2aH
// SIG // C0ychw4X6H3vKsD0N8IkrByYI75Zekqcekm6AYvDHl0Z
// SIG // AvkJSzLSuNm0jYYydypWfk9hYMm+b2qMIXc5HS4kpHjC
// SIG // tQEL/t4M12ufq6bPDI/PJY0pAlXz65wTlwXuFoT3qtUl
// SIG // iijcle+7pyhZPBmJndWiur1idosQ1noaTJHPjrtrbWs0
// SIG // 0kdKz2+b9Pg7VLXBduvzd4KkSHItL4MHD/A1oHsSKV0r
// SIG // xZcPuba7d16apvBtHqBfGRnvrJazwxbBjWR+ovOahBuN
// SIG // Ksp+lT3VcnHfcJvqCCNGlK61KSdQIw9N5OGa43ER8xkB
// SIG // VTCa/TsNQiOp0mYNpDBdoa0A3Cs2F2LkzPmzFQd28CRb
// SIG // seNwrQ456d4fjzCR1MeqiODiNuCHHa+mZx5Ti6K/wemX
// SIG // XUxeFf+IRqVd2gSQlHY/mECWc2T8gDZaLvUKAu5nZOjf
// SIG // 9mei135na99D4V9+eLl2RNUKN9nk0TgwxO9BPzPt8MD4
// SIG // CbsoJZYrfgCiaE0vuqem3UIV1RWcDHJqPeqh1Y00dDnJ
// SIG // rgxMOFCOpwRafadWUxWoWScz080pkhM9VzQCnnEb0Dj7
// SIG // uv3qVhChhnwyVYAEZ/cV6aiHjHF4sS082zP8muUll1+q
// SIG // uRt7xGEriQ7IbTkiajl37ylBkRSxB6jD10Ozwv3Ko4wS
// SIG // grjH5gw=
// SIG // End signature block
