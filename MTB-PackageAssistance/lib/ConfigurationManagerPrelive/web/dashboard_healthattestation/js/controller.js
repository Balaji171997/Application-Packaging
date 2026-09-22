/// <dictionary target='parameter'>sce</dictionary>
/// <dictionary target='member'>bindto</dictionary>
/// <dictionary>bindto,sce</dictionary>

(function () {
    "use strict";

    var dashboard = angular.module("dashboard", []);

    dashboard.controller("dashboardController", function ($scope, $sce) {
        adminUI.initializeController($scope, async function () {
            // to control the appearance of pop up and layover on HTML
            $scope.enabled = false;
            await LoadDataAsync();
            if ($scope.brightness < 125) {
                SetColorToAllTextInChart("#HASComplianceDonut", $scope.theme.ForeGroundColor);
                SetColorToAllTextInChart("#HASUsageDonut", $scope.theme.ForeGroundColor);
                SetColorToAllTextInChart("#deviceInfoTreeMap", $scope.theme.ForeGroundColor);
                SetColorToAllTextInChart("#ncSettingsBarChart", $scope.theme.ForeGroundColor);
            }
            $scope.$apply();
        });

        async function LoadDataAsync() {
            $scope.HASComplianceData = await callJsonParseMethodAsync("GetHASComplianceData");
            $scope.HAStopNCreasons = await callJsonParseMethodAsync("GetTopNCReasons");
            $scope.HASUsageData = await callJsonParseMethodAsync("GetHASUsageData");
            $scope.deviceInfoData = await callJsonParseMethodAsync("GetClientTypeData");

            $scope.dhaEnabled = async function () {
                $scope.enabled = await callJsonParseMethodAsync("IsDHAEnabled");
                // If not enabled, we want to check if there is already some data present in the dashboard
                if (!$scope.enabled) {
                    // $scope.HASUsageData[0][2] corresponds to the number of devices
                    $scope.enabled =  $scope.HASUsageData[0][2] > 0 ? true: false;
                }
                $scope.$apply();
            }

            $scope.dhaEnabled();

            $scope.getString = function (stringName) {
                return $scope.strings[stringName];
            };

            $scope.updateHTMLString = function (id, htmlStringName) {
                utilityUpdateHTMLString(id, $scope.strings[htmlStringName]);
            };

            execute();
        }

        // Checks if value is null, 0, undefinded, "" or []
        function isEmpty(columns) {
            var noData = true;
            for (var i = 0; i < columns.length; i++) {
                var value = columns[i][1];
                if (value == 0 || value == null || value.length === 0 || isNaN(value))
                    continue;
                else {
                    noData = false;
                    break;
                }
            }
            return noData;
        }

        $scope.createDonutChart = function (idToBindTo, columns) {
            var enable = true;
            var pattern = ["#253494", "#2E75B6", "#E32636", "#707070"];     // Compliant, NonCompliant, Errors, Unknown

            if (isEmpty(columns)) {
                enable = false;
                pattern = ["#a9a9a9"];
                columns = [['', 1]];
            }

            $scope.donut = c3.generate({
                bindto: idToBindTo,
                data: {
                    columns: columns,
                    type: "donut",
                    onclick: async function (d) {
                        await adminUI.sendNewRequestSync("OnHAComplianceStatusChartClick", d.name);
                    }
                },
                interaction: {
                    enabled: enable
                },
                legend: {
                    position: "bottom",
                    show: enable
                },
                color: {
                    pattern: pattern
                },
                donut: {
                    label: {
                        format: function (value, ratio) {
                            if (enable)
                                return value;
                            else
                                return 0;
                        }
                    },
                    expand: enable
                }
            });
        };

        $scope.createClientTypeChart = function (idToBindTo, columns) {
            var enable = true;
            var pattern = ["#253494", "#2E75B6", "#707070"];

            if (isEmpty(columns)) {
                enable = false;
                pattern = ["#a9a9a9"];
                columns = [['', 1]];
            }

            c3.generate({
                bindto: idToBindTo,
                data: {
                    columns: columns,
                    type: "donut",
                    onclick: async function (d) {
                        await adminUI.sendNewRequestSync("OnNonCompliantDevicesByCTClick", d.name);
                    }
                },
                interaction: {
                    enabled: enable
                },
                legend: {
                    position: "bottom",
                    show: enable
                },
                color: {
                    pattern: pattern
                },
                donut: {
                    label: {
                        format: function (value, ratio) {
                            if (enable)
                                return value;
                            else
                                return 0;
                        }
                    },
                    expand: enable
                },
            });
        };

        $scope.createGaugeChart = function (idToBindTo, columns) {
            var hasSupportedCount = columns[0][1];
            var totalCount = columns[0][2];
            var showGaugeLabel = parseInt(totalCount) > 0;

            c3.generate({
                bindto: idToBindTo,
                data: {
                    columns: [[columns[0][0], hasSupportedCount]],
                    type: 'gauge',
                    onclick: async function (d) {
                        await adminUI.sendNewRequestSync("OnW10DevicesReportingHAClick");
                    }
                },
                gauge: {
                    label: {
                        format: function (value, ratio) {
                            if (totalCount == 0) {
                                return value;
                            }
                            else {
                                var r = Number(ratio * 100).toFixed(1);
                                return r + '%';
                            }
                        },
                        show: showGaugeLabel,
                    },
                    max: totalCount,
                },
                color: {
                    pattern: ['#70AD47'],   // Green
                },
                size: {
                    height: 180
                }
            });
        };

        $scope.createHorizBarChart = function (idToBindTo, columns) {
            c3.generate({
                bindto: idToBindTo,
                bar: {
                    width: 20
                },
                data: {
                    x: columns[0][0],
                    columns: columns,
                    type: 'bar',
                    color: "#2E75B6",
                    onclick: async function (d) {
                        await adminUI.sendNewRequestSync("OnHAComplianceSettingsChartClick", columns[0][d.x + 1]);
                    }
                },
                axis: {
                    rotated: false,
                    x: {
                        type: 'category'
                    },
                    y: {
                        tick: {
                            format: function (x) {
                                return (x == Math.floor(x)) ? x : "";
                            }
                        }
                    }
                },
                tooltip: {
                    grouped: false
                }
            });
        };

        function execute() {
            $scope.createDonutChart("#HASComplianceDonut", $scope.HASComplianceData);
            $scope.createHorizBarChart("#ncSettingsBarChart", $scope.HAStopNCreasons);
            $scope.createGaugeChart("#HASUsageDonut", $scope.HASUsageData);
            $scope.createClientTypeChart("#deviceInfoTreeMap", $scope.deviceInfoData);
        }
    });
}());

// SIG // Begin signature block
// SIG // MIIonAYJKoZIhvcNAQcCoIIojTCCKIkCAQExDzANBglg
// SIG // hkgBZQMEAgEFADB3BgorBgEEAYI3AgEEoGkwZzAyBgor
// SIG // BgEEAYI3AgEeMCQCAQEEEBDgyQbOONQRoqMAEEvTUJAC
// SIG // AQACAQACAQACAQACAQAwMTANBglghkgBZQMEAgEFAAQg
// SIG // mjJt4pW0EYcNXpO7Lm04KGLnvjOSqEY6vz8qHTK4ZQGg
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
// SIG // AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCCgZO+EVXHQAfp2
// SIG // 5MbD3fC2Pomnh2OjmQaoVCIstQO7NDCBigYKKwYBBAGC
// SIG // NwIBDDF8MHqgXIBaAE0AaQBjAHIAbwBzAG8AZgB0AC4A
// SIG // VABvAG8AbABrAGkAdAAuAFcAcABmAC4AVQBJAC4AQwBv
// SIG // AG4AdAByAG8AbABzAC4AVwBlAGIAVgBpAGUAdwAuAGQA
// SIG // bABsoRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
// SIG // BgkqhkiG9w0BAQEFAASCAQCEkqWmLrYfmEQNdgpT78If
// SIG // oTJNMoYQ0k6VXrYY0igdaTAY1rGtdrl5rzCbvawTHVcG
// SIG // p9ygaaEAwC3BtKPYrJ0kT2D8HF5LrOijjont4CQOxX8B
// SIG // WoGU+KnpB5bkhuIbYyS693gkzCDxO2Ysd2I+JuPL3pwp
// SIG // 3eA4ZcXXte8OCgVE8Me04y1D1kFNe4MRnhfhzpervSSl
// SIG // awn+FTCi7hNQCqk+9Tq1NMQVztcMy+Y+AnvHFGtlsXoZ
// SIG // zQ2TQ4T6Ik0jUOE7ejH44aRRtdXBXYErClj+NSztiWRi
// SIG // A0Xvl4/pvekJQHUW+4C7fy5PgfynFb3gV8JmSh+FumQb
// SIG // WCdB16u8a81VoYIXsDCCF6wGCisGAQQBgjcDAwExghec
// SIG // MIIXmAYJKoZIhvcNAQcCoIIXiTCCF4UCAQMxDzANBglg
// SIG // hkgBZQMEAgEFADCCAVoGCyqGSIb3DQEJEAEEoIIBSQSC
// SIG // AUUwggFBAgEBBgorBgEEAYRZCgMBMDEwDQYJYIZIAWUD
// SIG // BAIBBQAEINRKu1+Qq+Ai3UnRuxUjNGq5B9kGHaPJBTJx
// SIG // oSGpzVPBAgZo8U/opuYYEzIwMjUxMDIzMDI0NzMxLjYy
// SIG // OVowBIACAfSggdmkgdYwgdMxCzAJBgNVBAYTAlVTMRMw
// SIG // EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
// SIG // b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
// SIG // b24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9w
// SIG // ZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNoaWVs
// SIG // ZCBUU1MgRVNOOjZCMDUtMDVFMC1EOTQ3MSUwIwYDVQQD
// SIG // ExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloIIR
// SIG // /jCCBygwggUQoAMCAQICEzMAAAIRRRg5m0PP/GwAAQAA
// SIG // AhEwDQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMx
// SIG // EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
// SIG // ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
// SIG // dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3Rh
// SIG // bXAgUENBIDIwMTAwHhcNMjUwODE0MTg0ODEzWhcNMjYx
// SIG // MTEzMTg0ODEzWjCB0zELMAkGA1UEBhMCVVMxEzARBgNV
// SIG // BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
// SIG // HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEt
// SIG // MCsGA1UECxMkTWljcm9zb2Z0IElyZWxhbmQgT3BlcmF0
// SIG // aW9ucyBMaW1pdGVkMScwJQYDVQQLEx5uU2hpZWxkIFRT
// SIG // UyBFU046NkIwNS0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1p
// SIG // Y3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0G
// SIG // CSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDPubszEB0v
// SIG // lVrKuTuOwyjcaeE3zmS0cJkS8RyPgEhxwcp380oLu4++
// SIG // lfl2E7rdbpUzmILGSUbypB5VWs9oq+Px1hgkLsM23g03
// SIG // deVV0L++i94m48+FMn+7tf6liZXap6FNU844HX+Gma3n
// SIG // VLODFlzMx2cWX5fZ7U+C61IDkICH39fPk1bQLGdhXPyD
// SIG // RWnGD4GrfZqaS1FevybcFISBSzyOBZE9XM8cRzOluGWg
// SIG // YYR8dpE6YeFUoio34mEzB4SNTY1czZbqGbfaP9Af8j8p
// SIG // ao019hyEdobTEmWNVNihQo+lxAO6Ef11AoSC8bGPZTn/
// SIG // cWrV6bh07oiHTibpH623GvpjyhEkf1mFnexyIUEi9mHs
// SIG // TZgVc6M/gwbJtLKVBM8MQUC0ceCmSyR4RSGw8NH1W9Za
// SIG // F6SFDHepdoAqH4CQubP+GkTd7TL5Ego7YBESNQskAqB/
// SIG // 5H1Cc2+ox4yTP08auOyKOpYbMHaTYk3JpRgqVuZDB45p
// SIG // uwKKiJjZ8luKaNXIUAaTkB5h11QXG8kaBFUIfsF4E8oC
// SIG // rsww6ZIJM4xnRLDrPI3HhSGHljS4nRk6hMqcHcp9039t
// SIG // r94ocV4SGLdaoB/NPGLLSsy+Gx+xdkrvOhyWppG9WXxD
// SIG // jwnXvj57KuLKlj0eFT6iGCJiLi5AYMNV1MN4oO2gL+EP
// SIG // YKf4BHPATWsV8QIDAQABo4IBSTCCAUUwHQYDVR0OBBYE
// SIG // FGJ9RQPA6eohy99vnf7JXQRmfs5wMB8GA1UdIwQYMBaA
// SIG // FJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYw
// SIG // VKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9w
// SIG // a2lvcHMvY3JsL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAl
// SIG // MjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRg
// SIG // MF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9z
// SIG // b2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIw
// SIG // VGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwG
// SIG // A1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUH
// SIG // AwgwDgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUA
// SIG // A4ICAQCkQp2cx4ghSJTo9q1n+puvCIPNhQwpFzMLgGn9
// SIG // djVL02Ycj7Zzd1ynAfZI6YN928giq3uZGuC8E9g68n0K
// SIG // 1lLl54iuw5sLRvSCApO/bCtOBYb6qS2o0USFB6Kl1RE0
// SIG // s3ry4cCbl53AHK13WTDLmvoH3eSXEOyV06ZVa3D+eCPu
// SIG // Sc3T2a4KbCvXsmewwVygg38fn2z7VFg3tWJ3j7uePwVy
// SIG // 9jL2ttk4yd0HOxOKiwXUz5owglfaTcRUVWy4Mvv9Hmmk
// SIG // j1ODt5ZA5Yoxkc92wDdmpbMO6EmpPOgVJBKGdl6cL7Gr
// SIG // /P0GEc8UVtS1+MCgboQM+NJAlheaiCNrw4RrX3HCeHfB
// SIG // W594/5yT7/SDE2LuD6Q7pZo6bTnYXiyIPzGLpS/vkvvv
// SIG // 3yUe89OFzEceyBeoxjn3Z3XBSh/e0v94NpDRSGdgJTzI
// SIG // aRTZcmdy042cEoC9REC9/aqIhYOPgulybTMDtW6h+4lH
// SIG // VOm7JzmnWNrnZs1kEFWoA7DIOECapawlcCNheeywL98m
// SIG // R57fXgWH4YjIyC8A9FJyCpFmpXXp1MFi+h77DWf/Baz/
// SIG // JJNSzEPDhP8AhNy7k8CwucJWkCsOsUtFMXK6354dSgbp
// SIG // Rhl+Pz9Gy5DjYg2x7Wlv9w+bsbaVwsm2QgpPzTG8HUuJ
// SIG // o289MFURyY1K8VQzTGtdldxhzFVeJjCCB3EwggVZoAMC
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
// SIG // OjZCMDUtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3Nv
// SIG // ZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4D
// SIG // AhoDFQArKnyrZV2ACrVUaTN3s9nBXrM1zaCBgzCBgKR+
// SIG // MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5n
// SIG // dG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
// SIG // aWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1p
// SIG // Y3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqG
// SIG // SIb3DQEBCwUAAgUA7KO2wzAiGA8yMDI1MTAyMjIwMDIx
// SIG // MVoYDzIwMjUxMDIzMjAwMjExWjB3MD0GCisGAQQBhFkK
// SIG // BAExLzAtMAoCBQDso7bDAgEAMAoCAQACAh1bAgH/MAcC
// SIG // AQACAhLkMAoCBQDspQhDAgEAMDYGCisGAQQBhFkKBAIx
// SIG // KDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAI
// SIG // AgEAAgMBhqAwDQYJKoZIhvcNAQELBQADggEBADpdlerc
// SIG // /RtXUZzkJnP46yLBHuTqG6XeWanZT0EZghl0QCdgLjNO
// SIG // bt54ofgUmYeUdmzgAOq0JLA7zxwA585U0/XQG8vCKMNS
// SIG // hOh31sIqkOlXdChlbGU8gpuZ9QDlWXIrkvhWb3YDZ/Kb
// SIG // JO8rVnNWi6nIyWOxVFXNZ4uj3KpVfELduQ7Nk/H3cajy
// SIG // cut0a0RZAIvsryLAyt8Opz0ZWNJGKxdSc5chauMnaCb5
// SIG // EaYXlIxPv239cDOuCNhi7eCQdgVc1PunVfSXgoffXB9d
// SIG // 5U7x+rt05VsF6h4md9mtzFU9+/Y7FCD2bpdfu6tsEsEx
// SIG // wI68aHwOBj8hYSoCjmAg8CwU7UcxggQNMIIECQIBATCB
// SIG // kzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
// SIG // Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
// SIG // TWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1N
// SIG // aWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAA
// SIG // AhFFGDmbQ8/8bAABAAACETANBglghkgBZQMEAgEFAKCC
// SIG // AUowGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8G
// SIG // CSqGSIb3DQEJBDEiBCDgofVirFcZn0dcDp6pa6Srdy40
// SIG // cI0R749TRR3/XJnFMTCB+gYLKoZIhvcNAQkQAi8xgeow
// SIG // gecwgeQwgb0EICytM6ma74dOrVpcXC+WGMXynadQI00I
// SIG // Rf85Ysc0Mya3MIGYMIGApH4wfDELMAkGA1UEBhMCVVMx
// SIG // EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
// SIG // ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
// SIG // dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3Rh
// SIG // bXAgUENBIDIwMTACEzMAAAIRRRg5m0PP/GwAAQAAAhEw
// SIG // IgQgLfvW1j2euwNJDexmo3iDS1ag4kaQd73F2iDbTAVj
// SIG // GTYwDQYJKoZIhvcNAQELBQAEggIAj/2j57wmMqJeXKM6
// SIG // +OuNtKBALCVi9qG3gQd33MVIDgNv2KNROhxWQ+lRRuRI
// SIG // TCridltIGsTzlj+NQ0YzGm7wLQQe8XcDqX4KXyUP92iN
// SIG // ih5MwnpfitsRTeycjz6XsTeK4+NKBSiT7jMB9odUJWO4
// SIG // /a6Qx8HJ/CNGkqVDmqCaGygO2PwA4wbJOqxFcfrnt0Rs
// SIG // zXPkT7uvQ16HSrIf+oz41KPmsJTUdebt1J0cn7+v7P54
// SIG // EnQruazgYx+ePl7u49a/NMsW2ihXYA3i1ky3MC7zPcV7
// SIG // mTKvJ+mRJPbEyGDVPs+ZVj1RHiKVPJG37IthY+IzAelT
// SIG // RBh7/Hyp+DzSSVq8vIaJMgf9jS3tD16+evmYaqt2We9a
// SIG // 32gTvRqadPGcFsmieuZSygcqxM1xhCSkNuDIhITrmvK6
// SIG // oh9amnV0ElYQzfCU0S9bCmHYu5JqL3jo/gu5R+1KIiXi
// SIG // 1d7bGvp6hjfr0qb19yaelVtjyS9xZ/FF7SUFIIjJwZ05
// SIG // aWRKbq+jbxS11diNa7m1wCvU+xNHM1+j9HruyNod85Ah
// SIG // jyNjLIvazi5ShfjFn7iL/tkO9yn5ioN/c9v0b6gp9yVO
// SIG // 3yum4D4mOEd+wPaUZiZDXoozH4bzwtyBPH6xsAFiIsZC
// SIG // n4wE1m6AUQn3seAowRJJ5Op+o53WyFDum/BJhCfSxynN
// SIG // h/ELxtw=
// SIG // End signature block
