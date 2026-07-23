
(function () {
    "use strict";
    var dashboard = angular.module("dashboard", []);

    dashboard.controller("dashboardController", function ($scope, $sce) {
        $scope.Empty = true;
        $scope.totalCount = 0;
        $scope.totalSurface = 0;
        $scope.models = [];

        adminUI.initializeController($scope, async function () {
            await LoadDataAsync();

            if ($scope.brightness < 125) {
                SetColorToAllTextInChart('#Models', $scope.theme.ForeGroundColor);
                SetColorToAllTextInChart('#Versions', $scope.theme.ForeGroundColor);
                SetColorToAllTextInChart("#Gauge", $scope.theme.ForeGroundColor);
            }
            $scope.$apply();
        });

        async function LoadDataAsync() {
            $scope.modelCounts = await callJsonParseMethodAsync("GetModelType");
            var firmwareCounts = await callJsonParseMethodAsync("GetFirmwareVersion");

            // Chart for Firmware Version
            var firmwareY = [$scope.strings.ChartLabel];
            var firmwareX = ["version"];
            var countFirmware = 0;
            firmwareCounts.forEach(function (e1) {
                if (countFirmware < 5) {
                    firmwareX.push(e1.Version);
                    firmwareY.push(e1.Number);
                }
                countFirmware++;
            });

            $scope.surfaceExists = async function () {
                var enabled = await callJsonParseMethodAsync("IsSurface");
                $scope.Empty = enabled;
                return enabled;
            };

            $scope.getString = function (stringName) {
                return $scope.strings[stringName];
            };

            $scope.updateHTMLString = function (id, htmlStringName) {
                utilityUpdateHTMLString(id, $scope.strings[htmlStringName]);
            };

            // Chart for Model Type
            var curTot = 0;
            $scope.modelCounts.forEach(function (el) {
                $scope.models.push([el.Model, el.Number]);
                curTot += parseInt(el.Number);
                $scope.totalCount = el.TotalDevices;
            });
            $scope.totalSurface = curTot;

            $scope.createPieChart("#Models", $scope.models);
            $scope.createBarChart("#Versions", firmwareX, firmwareY);
            $scope.createGaugeChart("#Gauge", $scope.totalSurface);
        };

        $scope.createPieChart = function (bindID, columns) {
            var enable = true;
            var columns1 = columns;
            if (!$scope.Empty) {
                enable = false;
                columns1 = [["", 1]];
            }
            c3.generate({
                bindto: bindID,
                data: {
                    columns: columns1,
                    type: "donut",
                    onclick: async function (d) { await callMethodAsync("OnModelTypeClick", d.name); }
                },
                size: {
                    height: 250,
                    width: 330
                },
                interaction: {
                    enabled: enable
                },
                donut: {
                    label: {
                        format: function (value, ratio) {
                            if (!$scope.Empty) {
                                return 0;
                            }
                            return value;
                        }
                    },
                    width: 45
                },
                expand: enable
            });
            if (GetCurrentBackgroundColor() < 125) {
                SetColorToAllTextInChart(bindID, 'white');
            }

            GetSummaryText(bindID, $scope.strings.ChartModelTitle, columns1);
        };

        $scope.createBarChart = function (bindID, xData, yData) {
            var columns1 = [xData, yData];
            if (!$scope.Empty) {
                columns1 = [[""], [0]];
            }

            var summaryText = "";
            var chart = document.querySelectorAll(bindID);
            var chartEl = angular.element(chart);
            var str = [];

            for (var i = 1; i < xData.length; i++) {
                str.push(xData[0] + " " + xData[i] + ": " + yData[0] + " " + yData[i] + ",  ");
            }

            var chartTitle = $scope.strings.FirmwareVersionTitle;
            summaryText = chartTitle + ". " + str.join("");

            var ariaLbl = document.getElementById("FirmwareVersionTitle");
            ariaLbl.setAttribute("aria-label", chartTitle);
            chartEl.attr('aria-label', summaryText);

            c3.generate({
                bindto: bindID,
                bar: {
                    width: 20
                },
                data: {
                    x: "version",
                    columns: columns1,
                    type: "bar",
                    onclick: async function (d) { await callMethodAsync("OnFirmwareClick", columns1[0][d.index + 1]); }
                },
                axis: {
                    rotated: true,
                    x: {
                        type: "category"
                    }
                },
                tooltip: {
                    grouped: false
                }
            });

            if (GetCurrentBackgroundColor() < 125) {
                SetColorToAllTextInChart(bindID, 'white');
            }

            $scope.$apply();
        };

        // Chart for Percentage of Surface Devices 
        $scope.createGaugeChart = function (bindID, tot) {
            var columns1 = [[$scope.strings["ChartLabel"], tot]];

            if (!$scope.Empty) {
                columns1 = [[""], [0]];
            }
            c3.generate({
                bindto: bindID,
                data: {
                    columns: columns1,
                    type: "gauge",
                    onclick: async function (d) { await callMethodAsync("OnPercentageClick"); }
                },
                gauge: {
                    label: {
                        format: function (value, ratio) {
                            if ($scope.totalCount === 0) {
                                return value;
                            } else {
                                var r = Number(ratio * 100).toFixed(1);
                                return r + "%";
                            }
                        },
                    },
                    max: $scope.totalCount,
                },
                color: {
                    pattern: ["#70AD47"],
                },
                size: {
                    height: 180
                }
            });
            if (GetCurrentBackgroundColor() < 125) {
                SetColorToAllTextInChart(bindID, 'white');
            }

            GetSummaryText(bindID, $scope.strings.GaugeModelTitle, columns1);
        };

        // Sets aria-label for accessibility
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


    })
        .directive("dashboardChart", defineChartDirective);
}());


// SIG // Begin signature block
// SIG // MIIonAYJKoZIhvcNAQcCoIIojTCCKIkCAQExDzANBglg
// SIG // hkgBZQMEAgEFADB3BgorBgEEAYI3AgEEoGkwZzAyBgor
// SIG // BgEEAYI3AgEeMCQCAQEEEBDgyQbOONQRoqMAEEvTUJAC
// SIG // AQACAQACAQACAQACAQAwMTANBglghkgBZQMEAgEFAAQg
// SIG // u8xN0acnJtPsIoh5Fq3yTyEms88SWgyMdR/rs5UEM8ug
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
// SIG // AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCDemNVIfsHs6sKd
// SIG // 3/F7yeXwf4bV2amBWlSLKjmXbgLBLTCBigYKKwYBBAGC
// SIG // NwIBDDF8MHqgXIBaAE0AaQBjAHIAbwBzAG8AZgB0AC4A
// SIG // VABvAG8AbABrAGkAdAAuAFcAcABmAC4AVQBJAC4AQwBv
// SIG // AG4AdAByAG8AbABzAC4AVwBlAGIAVgBpAGUAdwAuAGQA
// SIG // bABsoRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
// SIG // BgkqhkiG9w0BAQEFAASCAQABPMiakb1KcJOstqpD4Sqo
// SIG // Bk8IaaKbEzNrvmn78LOc4yVB8tn6JqT7yV/QS9KamnXO
// SIG // bXIDzfTMOlOOQ6Nabds52AWYdrB+HuYZ3tmc2XPLfSOg
// SIG // YyGO4uuAvWDWuf1iXJboWiEQfAIba73wrh3PUMfuErm9
// SIG // qiOsyb4+Pxjw0KeOC2D01CuDxGQuE1rhTtKIIij4CSPV
// SIG // EIBI+vb9tdRJsbRvdqvaYoryefz9Bk1UqTfv1mVkc1nS
// SIG // Hk3gdRAGf9UjizmuuCNUaEGuPdFTFUEdQLUrEvdLP6rs
// SIG // goiogvWygz0UNed616M5P0csBef85I7sSthb1q5WsX0I
// SIG // 6JjIBBfNSLFtoYIXsDCCF6wGCisGAQQBgjcDAwExghec
// SIG // MIIXmAYJKoZIhvcNAQcCoIIXiTCCF4UCAQMxDzANBglg
// SIG // hkgBZQMEAgEFADCCAVoGCyqGSIb3DQEJEAEEoIIBSQSC
// SIG // AUUwggFBAgEBBgorBgEEAYRZCgMBMDEwDQYJYIZIAWUD
// SIG // BAIBBQAEIEwDYUxD2q58u1WvRJx3pALxk6ejfH2De7js
// SIG // HatjD+LCAgZo8qG4xtwYEzIwMjUxMDIzMDI0ODE3LjA2
// SIG // OFowBIACAfSggdmkgdYwgdMxCzAJBgNVBAYTAlVTMRMw
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
// SIG // CSqGSIb3DQEJBDEiBCAujbFCuvdODt8hm9vxy6SyIRYQ
// SIG // ebvYU0pAxP4s2hX4tDCB+gYLKoZIhvcNAQkQAi8xgeow
// SIG // gecwgeQwgb0EIKAgaSY2F2jv4oTt1aEj4TYK3HZEtahi
// SIG // +8mh0IhyIcdoMIGYMIGApH4wfDELMAkGA1UEBhMCVVMx
// SIG // EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
// SIG // ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
// SIG // dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3Rh
// SIG // bXAgUENBIDIwMTACEzMAAAIcCVUV18NZB9EAAQAAAhww
// SIG // IgQgxUNpuzqbgbMKgAtMn8Y9XFutNIGB7poEbD04uiId
// SIG // fVwwDQYJKoZIhvcNAQELBQAEggIAlRaryIvbelfWGM53
// SIG // iiJMoLnm0/fUPvErd2dH09rZ6AEh5PsrGhe6ihIK+Vf/
// SIG // AOgYtdu6PycKD4RJzakTxhFq8LComkvICALp43n0WvwM
// SIG // 4mmYr6vG8QaLCdHVVBuhVHeoqMCfnxlJTA+7NLvahnm6
// SIG // DI2popSHEt/Fysi0X/zC6Oo/M4QOw9jzJ1QQkJ2rIlxo
// SIG // DweK2oqCW8x5UnAdue7qamkyK850YT1YnTUee7InvNed
// SIG // 82e8aU5Ewjsoxz52vObaZHeNMuP+vXslCUNEec8jjQK5
// SIG // JuC8RFrQ4xLlMd51xf+59EcxpwVukbxhLY/XFssDJTK1
// SIG // MFSpS9305+s+r2JQ5+3/nGZqVZBMxi5sQf6kSyhoaP0W
// SIG // UdaTBwEij9cb2p5YP2HMKjqkW4VUwgcOf20g7pc6FYfr
// SIG // tPMUqgrZ4VALtk8t1+F4wSctSTTlS4ZjNNA32AexXNPL
// SIG // +loD9INIozD0DQeB9p9CPGbifGs40zvxKHtkf0OPZJPt
// SIG // Nlt6UMsI4E9eNBb5munTPZuWL689vmhp0pJFHe6gxF1L
// SIG // ZM2h54QCJ2VYcbxAnZuqA+bCBxOQrGhl6q0gPI9HoPvD
// SIG // O1uqOSKSkiMf6AC9SzDlnhxYIzAzllQhC8VyRilN0p7K
// SIG // D5DtgdqYt877Bnky6+we5CiZQh/K8HMdg88IYmjlkuTG
// SIG // qOc5+yk=
// SIG // End signature block
