(function () {

    "use strict"
    var dashboard = angular.module("dashboard", []);

    dashboard.controller("dashboardController", function ($scope, $sce) {
        $scope.serviceEnabled = false;
        $scope.strings = JSON.parse(window.external.GetStrings());
        $scope.M365ConnectionData = JSON.parse(window.external.GetM365ConnectionData());
        //parse the xml style string into text
        var dom = new DOMParser();
        var tenant = dom.parseFromString($scope.M365ConnectionData.TenantName, "text/html");
        var collection = dom.parseFromString($scope.M365ConnectionData.CollectionName, "text/html");
        var lastSyncTime = new Date($scope.M365ConnectionData.LastSyncTime);
        var serviceLastUpdated = new Date($scope.M365ConnectionData.ServiceLastUpdated);
        $scope.M365ConnectionData.TenantName = tenant.documentElement.textContent
        $scope.M365ConnectionData.CollectionName = collection.documentElement.textContent
        $scope.localizedCollectionName = JSON.parse(window.external.GetLocalizedConnectionName($scope.M365ConnectionData.CollectionName));
        $scope.M365ConnectionData.LastSyncTime = (lastSyncTime.toLocaleString() === "Invalid Date"? $scope.strings.noData: lastSyncTime.toLocaleString());
        $scope.M365ConnectionData.ServiceLastUpdated = (serviceLastUpdated.toLocaleString() === "Invalid Date" ? $scope.strings.noData: serviceLastUpdated.toLocaleString());
        //$scope.M365ConnectedDevicesData = JSON.parse(window.external.GetM365ConnectedDevicesData());
        $scope.M365ConnectionHealthData = JSON.parse(window.external.GetM365ConnectionHealthData());
        $scope.M365TopConfigErrors = JSON.parse(window.external.GetM365TopConfigErrors()); 
        $scope.DevicesWithErrors = ($scope.M365ConnectionHealthData.NumUnableEnroll === null ? 0 : parseInt($scope.M365ConnectionHealthData.NumUnableEnroll)) + ($scope.M365ConnectionHealthData.NumConfigurationAlert === null ? 0 : parseInt($scope.M365ConnectionHealthData.NumConfigurationAlert));

        // check if micro service connection exists
        $scope.microserviceConnectionExists = function () {
            var serviceEnabled = JSON.parse(window.external.MicroserviceConnectionExists());
            $scope.serviceState = serviceEnabled;
            return serviceEnabled;
        };

        // function to launch Azure services wizard
        $scope.launchAzureServicesWizard = function () {
            try {
                $scope.m365CollectionsCreated = JSON.parse(window.external.launchAzureServicesWizard());
            } catch (err) {
                console.log("launch Azure Services wizard failed");
            }

            // if we have successfully created M365 collection(s), it means the microservice connection exists
            // and so reload the page so that overlay will no longer display
            if ($scope.m365CollectionsCreated) {
                window.location.reload();
            }
        }

        // Property name for the donut chart, for narrator accessibility
        $scope.strings.ConnectionHealthChartAccessibilityString = $scope.strings.connectionHealthChartTitle + " donut chart " + 
                    $scope.M365ConnectionHealthData.NumUnableEnroll + " devices " + $scope.strings.unableEnroll + ", " +
                    $scope.M365ConnectionHealthData.NumProperlyEnroll  + " devices " + $scope.strings.healthyConnection + ", " +
                    $scope.M365ConnectionHealthData.NumWaitingForEnrollment + " devices " + $scope.strings.waitingForEnrollment + ", " +
                    $scope.M365ConnectionHealthData.NumMissingData + " devices " + $scope.strings.missingPrereqs + ", " + 
                    $scope.M365ConnectionHealthData.NumConfigurationAlert + "devices" + $scope.strings.configAlert + ", " + 
                    $scope.M365ConnectionHealthData.NumStatusPending + " devices " + $scope.strings.dataUnavailable;

        /*
        // function to create generic gauge chart
        $scope.createGaugeChart = function (id, data) {
            var showGaugeLabel = parseInt(data[0][2]) > 0;

            if (!JSON.parse(window.external.MicroserviceConnectionExists())) {
                data = [["", 0, 0]]
            }

            c3.generate({
                bindto: id,
                data: {
                    columns: [
                        [data[0][0], data[0][1]]
                    ],
                    type: 'gauge'
                },
                gauge: {
                    label: {
                        format: function (value, ratio) {
                            if (data[0][1] == 0) {
                                return value;
                            }
                            else {
                                var r = Number(ratio * 100).toFixed(1);
                                return r + '%';
                            }
                        },
                        show: showGaugeLabel,
                    },
                    max: data[0][2],
                },
                color: {
                    pattern: ['#0072C6'],
                },
                size: {
                    height: 150
                }
            });
        }

        // function to load gauage chart for connected devices
        function LoadConnectedDevicesChart() {
            var numConnectedDevices = $scope.M365ConnectedDevicesData.NumConnectedDevices;
            var numTotalDevices = $scope.M365ConnectedDevicesData.NumTotalDevices;
            var gaugeData = [["Connected Devices", numConnectedDevices, numTotalDevices]];

            $scope.createGaugeChart("#ConnectedDevicesChart", gaugeData);
        }
        */

        // function to create generic donut chart
        $scope.createDonutChart = function (id, data, drillthroughEnabled) {

            if (!JSON.parse(window.external.MicroserviceConnectionExists())) {
                data = [["", 0], ["", 0], ["", 0], ["", 0], ["", 0], ["", 0]]
            }

            c3.generate({
                bindto: id,
                data: {
                    columns: data,
                    type: 'donut',
                    onclick: function (d) {
                        if (id == "#ConnectionHealthChart") {
                            window.external.DrillThroughEnrollmentStatusChart(d.name);
                        }
                    }
                },
                legend: {
                    position: 'right'
                },
                color: {
                    pattern: ["#7FBA00", "#FF7F00", "#FFCD19", "#76797B", "#00FFFF", "#E81123"]
                },
                size: {
                    height: 200
                },
                donut: {
                    label: {
                        format: function (value, ratio) {
                            return value;
                        },
                    }
                },
                tooltip: {
                    show: false
                },
            });
        }

        // function to load donut chart for connection health
        function LoadConnectionHealthChart() {
                     
            var numUnableEnroll = $scope.M365ConnectionHealthData.NumUnableEnroll;
            var numProperlyEnroll = $scope.M365ConnectionHealthData.NumProperlyEnroll;
            var numWaitingForEnrollment = $scope.M365ConnectionHealthData.NumWaitingForEnrollment;
            var numMissingData = $scope.M365ConnectionHealthData.NumMissingData;
            var numConfigurationAlert = $scope.M365ConnectionHealthData.NumConfigurationAlert;
            var numStatusPending = $scope.M365ConnectionHealthData.NumStatusPending;;

            var donutData = [
                             [$scope.strings.healthyConnection, numProperlyEnroll],                             
                             [$scope.strings.unableEnroll, numUnableEnroll],
                             [$scope.strings.configAlert, numConfigurationAlert],
                             [$scope.strings.waitingForEnrollment, numWaitingForEnrollment],                             
                             [$scope.strings.missingPrereqs, numStatusPending],
                             [$scope.strings.dataUnavailable, numMissingData]];
            $scope.createDonutChart("#ConnectionHealthChart", donutData, true);
        }

        // handle Enter key press event
        $scope.keyPressToggle = function (event, id) {
            if (event.keyCode == 13) {   // This is the Enter keypress
                switch (id) {
                    case 'ConnectionHealthChart':
                        window.external.DrillThroughEnrollmentStatusChart("All states");
                        break;
                }
            }
        };


        $scope.createBarChart = function (id, strings, data) {
            if (!JSON.parse(window.external.MicroserviceConnectionExists())) {
                strings = ['x', 'Windows 8 device missing KB934510', 'Unsupported OS', 'Appraiser not run for 24 hrs', 'Windows 7 device missing KB398413', 'Telemetry not configured correctly'];
                data = [$scope.strings.deviceCount, 0, 0, 0, 0, 0];
            }

            c3.generate({
                bindto: id,
                data: {
                    x: 'x',
                    columns: [strings, data],
                    type: 'bar',
                    colors: {
                        'Devices': '#FFCD19'
                    },
                    labels: true
                },
                legend: {
                    show: false
                },
                bar: {
                    width: {
                        ratio: 0.5 // this makes bar width 50% of length between ticks
                    }
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
        
        $scope.desktopAnalyticsLearnMorelUrl = 'https://go.microsoft.com/fwlink/?linkid=2092081';
        $scope.desktopAnalyticsTroubleShootingUrl = 'https://go.microsoft.com/fwlink/?linkid=2033126';

        $scope.OpenTroubleShootingGuide = function () {
            try {
                window.external.OpenTroubleShootingGuide();
                console.log("Open Desktop Analytics troubleshooting guide");
            }
            catch (err) {
                console.log("Failed to open Desktop Analytics troubleshooting guide");
            }
        }

        $scope.OpenDenominatorDCRLearnMore = function () {
            try {
                window.external.OpenDenominatorDCRLearnMore();
                console.log("Open Desktop Analytics Denominator DCR learn more");
            }
            catch (err) {
                console.log("Failed to open Desktop Analytics Denominator DCR learn more");
            }
        }

        function LoadTopConnectionIssuesChart() {
            var firstErrorCount = ($scope.M365TopConfigErrors.FirstErrorCount > 0) ? $scope.M365TopConfigErrors.FirstErrorCount : null;
            var firstErrorName = (firstErrorCount > 0) ? $scope.M365TopConfigErrors.FirstErrorName : " ";
            var secondErrorCount = ($scope.M365TopConfigErrors.SecondErrorCount > 0) ? $scope.M365TopConfigErrors.SecondErrorCount : null;
            var secondErrorName = (secondErrorCount > 0) ? $scope.M365TopConfigErrors.SecondErrorName : " ";
            var thirdErrorCount = ($scope.M365TopConfigErrors.ThirdErrorCount > 0) ? $scope.M365TopConfigErrors.ThirdErrorCount : null;
            var thirdErrorName = (thirdErrorCount > 0) ? $scope.M365TopConfigErrors.ThirdErrorName : " ";
            var fourthErrorCount = ($scope.M365TopConfigErrors.FourthErrorCount > 0) ? $scope.M365TopConfigErrors.FourthErrorCount : null;
            var fourthErrorName = (fourthErrorCount > 0) ? $scope.M365TopConfigErrors.FourthErrorName : " ";
            var fifthErrorCount = ($scope.M365TopConfigErrors.FifthErrorCount > 0) ? $scope.M365TopConfigErrors.FifthErrorCount : null;
            var fifthErrorName = (fifthErrorCount > 0) ? $scope.M365TopConfigErrors.FifthErrorName : " ";

            var barStrings = ['x', firstErrorName, secondErrorName, thirdErrorName, fourthErrorName, fifthErrorName];
            var barData = [$scope.strings.deviceCount, firstErrorCount, secondErrorCount, thirdErrorCount, fourthErrorCount, fifthErrorCount];
            $scope.createBarChart("#TopConnectionIssuesChart", barStrings, barData);

            // Accessible name for the horizontal bar chart
            $scope.strings.HorizontalBarChartAriaLabel = "Horizontal bar chart of most frequent enrollment blockers and configuration alerts";

            // Property name for the horizontal bar chart, for accessibility
            $scope.strings.LoadTopConnectionIssuesChartAriaLabel = 
                       firstErrorName + " " + firstErrorCount + ", " +
                       secondErrorName + " " + secondErrorCount + ", " +
                       thirdErrorName + " " + thirdErrorCount + ", " +
                       fourthErrorName + " " + fourthErrorCount + ", " +
                       fifthErrorName + " " + fifthErrorCount;

        };

        // call to all functions
        $scope.microserviceConnectionExists();
        //LoadConnectedDevicesChart();
        LoadConnectionHealthChart();
        LoadTopConnectionIssuesChart();

    });
}());

// SIG // Begin signature block
// SIG // MIIonAYJKoZIhvcNAQcCoIIojTCCKIkCAQExDzANBglg
// SIG // hkgBZQMEAgEFADB3BgorBgEEAYI3AgEEoGkwZzAyBgor
// SIG // BgEEAYI3AgEeMCQCAQEEEBDgyQbOONQRoqMAEEvTUJAC
// SIG // AQACAQACAQACAQACAQAwMTANBglghkgBZQMEAgEFAAQg
// SIG // 76yNIe8FMzvl1G1+EPKJxRV+As3nSyMAhW1+XqXArSag
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
// SIG // AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCCmkz5Ve6m+1nTZ
// SIG // hu4OApqgYw0bEUm5eiroFx3TZ+dvRzCBigYKKwYBBAGC
// SIG // NwIBDDF8MHqgXIBaAE0AaQBjAHIAbwBzAG8AZgB0AC4A
// SIG // VABvAG8AbABrAGkAdAAuAFcAcABmAC4AVQBJAC4AQwBv
// SIG // AG4AdAByAG8AbABzAC4AVwBlAGIAVgBpAGUAdwAuAGQA
// SIG // bABsoRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
// SIG // BgkqhkiG9w0BAQEFAASCAQAFpxYk+0boe8Q5roeagTtP
// SIG // yKFv+KF4CvxwDowtHXWkomHzSzP/ljOzgtXyUxImv07r
// SIG // vCoWBSZHqFG5OG5qCBGI33dZWNMolJAU0vrLdGw+L9HE
// SIG // DEGcLAX44ksSDs4JrEN6HChKAC4cPf2PqDvY+eopfyFe
// SIG // Vgye/cNtriC66yA3/2JDWfgOgcWB3uNCwdgJRRwIoLJx
// SIG // 0J/Afp81lfJLa1yreEUXBaqpnD0HnN9RH2/5mtBO3dVF
// SIG // sCpj4XOkUZPg9EfTOSqWxxN90RJokLNgLnf7IrykiMQY
// SIG // veN2ulwuLmfmQOKzDtKiibbAUCCLC/oDBjyLuzAIs8AV
// SIG // yWf6shC+ohl4oYIXsDCCF6wGCisGAQQBgjcDAwExghec
// SIG // MIIXmAYJKoZIhvcNAQcCoIIXiTCCF4UCAQMxDzANBglg
// SIG // hkgBZQMEAgEFADCCAVoGCyqGSIb3DQEJEAEEoIIBSQSC
// SIG // AUUwggFBAgEBBgorBgEEAYRZCgMBMDEwDQYJYIZIAWUD
// SIG // BAIBBQAEILSViIf1T9gWFEUrEPwM5C+EO6uC39YVfq8C
// SIG // wttd+nBRAgZo8mFi1ZEYEzIwMjUxMDIzMDI0NjAwLjM3
// SIG // OVowBIACAfSggdmkgdYwgdMxCzAJBgNVBAYTAlVTMRMw
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
// SIG // CSqGSIb3DQEJBDEiBCDXl3VRt3/DrgnncqIax+5gGYjj
// SIG // RuYT1xmSHc8tdWIGijCB+gYLKoZIhvcNAQkQAi8xgeow
// SIG // gecwgeQwgb0EIJ2k3tS4UnhpyyyUV9alJljeg6cR3gzv
// SIG // kYWJhZ0LBiIPMIGYMIGApH4wfDELMAkGA1UEBhMCVVMx
// SIG // EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
// SIG // ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
// SIG // dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3Rh
// SIG // bXAgUENBIDIwMTACEzMAAAIW1pPO+5Mf7eEAAQAAAhYw
// SIG // IgQg0/sAfFXBXgfjkKEnXcLm6xk4XBVosMA2enKDYXfn
// SIG // 23AwDQYJKoZIhvcNAQELBQAEggIAPJWREV6hhhHR89wi
// SIG // iY8ExxY4zKjwfmGSbKwe2V89oFHUHUbXgeoElcTycHXH
// SIG // 9AVJSYj4ZvPLfHG2yKegZ2WOmyp2L24rB2b4AMTqlfCC
// SIG // m5GfdzOOcESJXIxbT+rQq3Nr7X1rVuuH1w9G9qurrt+2
// SIG // jz+726fye3brVq6n4OR0jtFGT/L6gYme6vfkjL+g6V9H
// SIG // elDFU2K6v0HT6Ve85IaIzJKOGuTrfku0WmAeBcXMdkD2
// SIG // lTiSuGiq/XAq6PiIYY8jQ5cflWLxBNN6jeTGwfcA1jxe
// SIG // 4gjx1XR18i3UqahEzXSWPCJYK7Nn74PVW/DinB6amFif
// SIG // yUnYsh9aFW6WKVXi+/kj9OQjCJs/3BvdlwG6vWVlISNa
// SIG // sm/EALMYoGSh9mOCxqlAz25GWpUu8hTM8p9yFM8OjQdG
// SIG // ddScBonShF/wiSEJ0FuurFCWTKLvEeD7z7Ft8LJObwHx
// SIG // JzDs7hqBQd9FTiqA2676EjAgIJIXiKUM4ECrInoPGlWR
// SIG // 8k3Ap0jSbXroLjsDhd8KMpN1D2hQGGV4348XLA/X90W9
// SIG // pJ/5QMIIuCw7o9GvWnM7gdst6EQJqXp4SbVpX/lLip7c
// SIG // g3X8Cq5MRZ5q+U2WJt3qiu2qZ1bO2RxcxbLuZsPDbDFk
// SIG // PLr9tCgq/EUNBUuRzMM3SvJm/wPO1v94+veIkZGXgdVN
// SIG // BE4zTVk=
// SIG // End signature block
