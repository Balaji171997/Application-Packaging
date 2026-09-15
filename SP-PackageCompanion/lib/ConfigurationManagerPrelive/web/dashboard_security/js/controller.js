/// <dictionary target='parameter'>sce</dictionary>
/// <dictionary target='member'>bindto</dictionary>
/// <dictionary>bindto,sce</dictionary>

(function () {
    "use strict";

    var dashboard = angular.module("dashboard", []);

    dashboard.controller("dashboardController", function ($scope, $sce) {
        $scope.strings = JSON.parse(window.external.GetStrings());
        $scope.protectionHealthData = JSON.parse(window.external.GetDonutProtectionHealthStatusData());
        $scope.HASComplianceData = JSON.parse(window.external.GetHASComplianceData());
        $scope.updatesComplianceData = JSON.parse(window.external.GetUpdatesComplianceData());

        // If All Desktop and Server clients not in the collections, grey out the tile
        $scope.epTileEnabled = JSON.parse(window.external.IsEPTileEnabled());

        $scope.getString = function (stringName) {
            return $scope.strings[stringName];
        };

        $scope.navigateToNode = function (nodeName) {
            window.external.OnTileClick(nodeName);
        };

        $scope.hasPermissions = function (chart) {
            var value = window.external.HasPermissions(chart);

            if (value == "false")
                return false;
            else
                return true;
        }

        $scope.keyPressToggle = function (event, nodeName) {
            // "Enter" key
            if (event.keyCode == 13) {
                window.external.OnTileClick(nodeName);
            }
        };

        // Checks if value is null, 0, undefinded, "" or []
        function isEmpty(value) {
            return (value == 0 || value == null || value.length === 0 || isNaN(value));
        }

        $scope.createDonutChart = function (idToBindTo, chartTitle, columns, pattern, clickhandler) {
            var enable = true;
            var noData = true;

            var chart = document.querySelectorAll(idToBindTo);
            var chartEl = angular.element(chart);
            var tileEl = chartEl.parent()

            for (var i = 0; i < columns.length; i++) {
                if (!isEmpty(columns[i][1]))
                    noData = false;
            }

            if (noData) {
                enable = false;
                pattern = ["#a9a9a9"];
                columns = [['', 1]];
                var summaryText = chartTitle + " " + $scope.getString("noData");
            } else {
                var str = [];
                columns.forEach(function (k, v) { str.push(k[0] + " " + k[1] + ".  "); });
                var summaryText = chartTitle + ": " + str.join("");
            }

            tileEl.attr('aria-label', summaryText);

            var legendPos = "bottom";
            if (idToBindTo == "#DeviceThreatDonut") {
                legendPos = "right";
            }

            var donut = c3.generate({
                bindto: idToBindTo,
                data: {
                    columns: columns,
                    type: "donut",
                    onclick: clickhandler
                },
                interaction: {
                    enabled: enable
                },
                legend: {
                    position: legendPos,
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

            if (idToBindTo == "#updatesComplianceDonut") {
                // Adjust size because of long title
                donut.resize({ height: 230, width: 230 });
            }
        };

        var defaultColorPattern = ["#00BDF3", "#FE0101", "#FF8C00", "#A9A9A9"];

        var emptyFunc = function () { };

        $scope.createDonutChart("#HASComplianceDonut", $scope.strings["HASComplianceDonutTitle"], $scope.HASComplianceData, defaultColorPattern, emptyFunc);
        $scope.createDonutChart("#EPStatusDonut", $scope.strings["protectionHealthDonutTitle"], $scope.protectionHealthData, defaultColorPattern, emptyFunc);
        $scope.createDonutChart("#updatesComplianceDonut", $scope.strings["winUpdatesDonutTitle"], $scope.updatesComplianceData, defaultColorPattern, emptyFunc);
    });
}());

// SIG // Begin signature block
// SIG // MIIomgYJKoZIhvcNAQcCoIIoizCCKIcCAQExDzANBglg
// SIG // hkgBZQMEAgEFADB3BgorBgEEAYI3AgEEoGkwZzAyBgor
// SIG // BgEEAYI3AgEeMCQCAQEEEBDgyQbOONQRoqMAEEvTUJAC
// SIG // AQACAQACAQACAQACAQAwMTANBglghkgBZQMEAgEFAAQg
// SIG // JUcUa80AWpwTLyjVdS3MFsvIZ6lTJ937kAJ2Vn+C5f2g
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
// SIG // ghptMIIaaQIBATCBlTB+MQswCQYDVQQGEwJVUzETMBEG
// SIG // A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
// SIG // ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
// SIG // MSgwJgYDVQQDEx9NaWNyb3NvZnQgQ29kZSBTaWduaW5n
// SIG // IFBDQSAyMDExAhMzAAAEhJjiEuB4ozFdAAAAAASEMA0G
// SIG // CWCGSAFlAwQCAQUAoIH3MBkGCSqGSIb3DQEJAzEMBgor
// SIG // BgEEAYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEE
// SIG // AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCC10jsCKILTtRvG
// SIG // 0SJby/0keBOYRy6+bxoKsmq+jxKCbjCBigYKKwYBBAGC
// SIG // NwIBDDF8MHqgXIBaAE0AaQBjAHIAbwBzAG8AZgB0AC4A
// SIG // VABvAG8AbABrAGkAdAAuAFcAcABmAC4AVQBJAC4AQwBv
// SIG // AG4AdAByAG8AbABzAC4AVwBlAGIAVgBpAGUAdwAuAGQA
// SIG // bABsoRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
// SIG // BgkqhkiG9w0BAQEFAASCAQDiqbcVhPZcMD/wPY/aDn7A
// SIG // EgRz/LVtijkvxwbOxSZmXtucTkbLjzdm9Oa7TZIIw/FF
// SIG // t9MgTPCQ0DJctNRBFekLpoXOPY7MKjWBnng1cJVF7mHF
// SIG // vhK8BEQHljS17KtO0ezN7lNTrqFtVDhmo9ks7Gvs4C6X
// SIG // 1/LelNLn2wMr0nFPpvt3yV9Ften1rGXW5jQtpzWnLV7Z
// SIG // M5LVrV0r0vKFP1e6IWkBAuqAOsHPAq9ZL8c18pfnq9/z
// SIG // N3QpFUuYFUOf1OB7XseCduG1PTs7SPbIqCsxuAVRa5mC
// SIG // 2QrQmlmzmoSfoJ0FRiAp/vfkUtRDDC1tc5reeyRPAztU
// SIG // Q07iBZBHRyWMoYIXrjCCF6oGCisGAQQBgjcDAwExghea
// SIG // MIIXlgYJKoZIhvcNAQcCoIIXhzCCF4MCAQMxDzANBglg
// SIG // hkgBZQMEAgEFADCCAVkGCyqGSIb3DQEJEAEEoIIBSASC
// SIG // AUQwggFAAgEBBgorBgEEAYRZCgMBMDEwDQYJYIZIAWUD
// SIG // BAIBBQAEIMPtbdm6g8SzUPQ7kg/e1RF7jsTyHlK0PN/H
// SIG // SRZdVkY7AgZo8n1NKCIYEjIwMjUxMDIzMDI0NzE4LjY4
// SIG // WjAEgAIB9KCB2aSB1jCB0zELMAkGA1UEBhMCVVMxEzAR
// SIG // BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
// SIG // bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
// SIG // bjEtMCsGA1UECxMkTWljcm9zb2Z0IElyZWxhbmQgT3Bl
// SIG // cmF0aW9ucyBMaW1pdGVkMScwJQYDVQQLEx5uU2hpZWxk
// SIG // IFRTUyBFU046NTUxQS0wNUUwLUQ5NDcxJTAjBgNVBAMT
// SIG // HE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2WgghH9
// SIG // MIIHKDCCBRCgAwIBAgITMwAAAhvQsrgCZ/dyzwABAAAC
// SIG // GzANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzET
// SIG // MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
// SIG // bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
// SIG // aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFt
// SIG // cCBQQ0EgMjAxMDAeFw0yNTA4MTQxODQ4MzBaFw0yNjEx
// SIG // MTMxODQ4MzBaMIHTMQswCQYDVQQGEwJVUzETMBEGA1UE
// SIG // CBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEe
// SIG // MBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0w
// SIG // KwYDVQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRp
// SIG // b25zIExpbWl0ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNT
// SIG // IEVTTjo1NTFBLTA1RTAtRDk0NzElMCMGA1UEAxMcTWlj
// SIG // cm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZTCCAiIwDQYJ
// SIG // KoZIhvcNAQEBBQADggIPADCCAgoCggIBAI7FnedmWZMw
// SIG // eV3uYP5dhrDowM99LIOo1cXxSVfsOMSA1cmiNyzvGyKZ
// SIG // s2LpdwGR4OdFCEPD60kWRqUKhZETbvqN2CieINrhmAUZ
// SIG // LB5x2EdLlUgkIOfE4ZGMnqZRl96ALxkVbjyKULQIk7Ee
// SIG // +gP4HaFOxw8BG2+92ycE8q2yh4UflmjMvQ0ByOJOUKOP
// SIG // m2Q7NJI++m74Sb3RlPkvM8UAae1AIYyZxaisSLrEiExO
// SIG // 8wgkeNthC4ZIVVThaitsOodTALyC3u+ocUSHD49EgS9q
// SIG // /DvbceZ41OPrYNqwHVNed6Zsoams3aVHHGARPcA0RVHf
// SIG // 3vQqFse03Z1InAfjGou0U+qrHu3uWhql9Qe254/2R766
// SIG // 3xfgSRCJUvYg1wFIHpL12fhWZo7y8D/nTftP3K4fvq+H
// SIG // vBZJxexF+iCX55jXgzf+vGefZG2idX/j+ZpymH8nQnmZ
// SIG // saxqUtLWlpA5N+g94z1WX5b8a3Pta4QiJTOb/WoCxBSN
// SIG // dkIgU36TgTga9wBgj5Pnh9PpWrY0Go7oPtvwQ9dqm/Nu
// SIG // dNC0MrVFk9qLWvx2J0YEr9Y72dP3ZpdRbMVmMzpwq433
// SIG // Qf+zeqTckreL5/jxjenRS4pu5MaLPgfVn0D3syYt37is
// SIG // sgwAfc0hz49WbvJ2X3nGSfbpuM4+wxYLyV0w05xuapRu
// SIG // GXWxUWv66385AgMBAAGjggFJMIIBRTAdBgNVHQ4EFgQU
// SIG // tr6fd/5cS6aTSvDpGridgLzZiFAwHwYDVR0jBBgwFoAU
// SIG // n6cVXQBeYl2D9OXSZacbUzUZ6XIwXwYDVR0fBFgwVjBU
// SIG // oFKgUIZOaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3Br
// SIG // aW9wcy9jcmwvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUy
// SIG // MFBDQSUyMDIwMTAoMSkuY3JsMGwGCCsGAQUFBwEBBGAw
// SIG // XjBcBggrBgEFBQcwAoZQaHR0cDovL3d3dy5taWNyb3Nv
// SIG // ZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNyb3NvZnQlMjBU
// SIG // aW1lLVN0YW1wJTIwUENBJTIwMjAxMCgxKS5jcnQwDAYD
// SIG // VR0TAQH/BAIwADAWBgNVHSUBAf8EDDAKBggrBgEFBQcD
// SIG // CDAOBgNVHQ8BAf8EBAMCB4AwDQYJKoZIhvcNAQELBQAD
// SIG // ggIBAGZFNV8UA+DkzNxk4bd9k10oSHzwaDH0rBbAUKhT
// SIG // maiyTsciTpZSARaZqbzrRjT5AuWfJXRvGgqb4BTaP4w1
// SIG // nk+RYlud3QI/Sp2cabENz3+X0c0hh0XMRDDnVyFcwycH
// SIG // GVF9HI38Z2u8nTb/Hlwf15Ohuksq0djh+ktSxzFtdZt1
// SIG // Lyhfni4yD5eOa8YprgwqBHfmndJTgFwOf72TijeZ/3j2
// SIG // Hj9C0XIWV9EOh/J/2ZkjzJW5YtzDvOdUNPUZk/2Rh2vv
// SIG // xXcvliw68HGMpFfZlMv+E28CsOhbXUemTx8THSItaZPG
// SIG // NpgvxswqtCwrB9LkxXkOkOzXNzEZhEf95i1lIW2lh4F9
// SIG // RW2HIb0dtm/gbqfmD0eUP9AYWmgDegCAX3BrPrv5yaCA
// SIG // csmSgPHE8gpp1CP+L1ug+L8sIN1wRX+H9g8BR8v3r7Av
// SIG // ufCjJfpNsGtOV9pCtE/2wjy4WqL/WV8qG2sHzTi2Bomr
// SIG // ik9hVr28GcxyBQk8YwcMOj7ebkbwhP451HH/8YZThjJ+
// SIG // oijvV7ePb2UxNknyAZP9+Ii00QSeh+2hj000J82tzn1r
// SIG // tf3UcnAulpeaJ7Nz45xl00iksV5ZST5oOkf7pRqJz/1A
// SIG // mKCepjfhF438gyz1y6rK/dflUxta2M0Qoz8ARQB7+BCM
// SIG // GhNGowq3++XlBiN/qF1NFD+q5aGfMIIHcTCCBVmgAwIB
// SIG // AgITMwAAABXF52ueAptJmQAAAAAAFTANBgkqhkiG9w0B
// SIG // AQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
// SIG // c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
// SIG // BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UE
// SIG // AxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0
// SIG // aG9yaXR5IDIwMTAwHhcNMjEwOTMwMTgyMjI1WhcNMzAw
// SIG // OTMwMTgzMjI1WjB8MQswCQYDVQQGEwJVUzETMBEGA1UE
// SIG // CBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEe
// SIG // MBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYw
// SIG // JAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
// SIG // MjAxMDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoC
// SIG // ggIBAOThpkzntHIhC3miy9ckeb0O1YLT/e6cBwfSqWxO
// SIG // dcjKNVf2AX9sSuDivbk+F2Az/1xPx2b3lVNxWuJ+Slr+
// SIG // uDZnhUYjDLWNE893MsAQGOhgfWpSg0S3po5GawcU88V2
// SIG // 9YZQ3MFEyHFcUTE3oAo4bo3t1w/YJlN8OWECesSq/XJp
// SIG // rx2rrPY2vjUmZNqYO7oaezOtgFt+jBAcnVL+tuhiJdxq
// SIG // D89d9P6OU8/W7IVWTe/dvI2k45GPsjksUZzpcGkNyjYt
// SIG // cI4xyDUoveO0hyTD4MmPfrVUj9z6BVWYbWg7mka97aSu
// SIG // eik3rMvrg0XnRm7KMtXAhjBcTyziYrLNueKNiOSWrAFK
// SIG // u75xqRdbZ2De+JKRHh09/SDPc31BmkZ1zcRfNN0Sidb9
// SIG // pSB9fvzZnkXftnIv231fgLrbqn427DZM9ituqBJR6L8F
// SIG // A6PRc6ZNN3SUHDSCD/AQ8rdHGO2n6Jl8P0zbr17C89XY
// SIG // cz1DTsEzOUyOArxCaC4Q6oRRRuLRvWoYWmEBc8pnol7X
// SIG // KHYC4jMYctenIPDC+hIK12NvDMk2ZItboKaDIV1fMHSR
// SIG // lJTYuVD5C4lh8zYGNRiER9vcG9H9stQcxWv2XFJRXRLb
// SIG // JbqvUAV6bMURHXLvjflSxIUXk8A8FdsaN8cIFRg/eKtF
// SIG // tvUeh17aj54WcmnGrnu3tz5q4i6tAgMBAAGjggHdMIIB
// SIG // 2TASBgkrBgEEAYI3FQEEBQIDAQABMCMGCSsGAQQBgjcV
// SIG // AgQWBBQqp1L+ZMSavoKRPEY1Kc8Q/y8E7jAdBgNVHQ4E
// SIG // FgQUn6cVXQBeYl2D9OXSZacbUzUZ6XIwXAYDVR0gBFUw
// SIG // UzBRBgwrBgEEAYI3TIN9AQEwQTA/BggrBgEFBQcCARYz
// SIG // aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9E
// SIG // b2NzL1JlcG9zaXRvcnkuaHRtMBMGA1UdJQQMMAoGCCsG
// SIG // AQUFBwMIMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBB
// SIG // MAsGA1UdDwQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB8G
// SIG // A1UdIwQYMBaAFNX2VsuP6KJcYmjRPZSQW9fOmhjEMFYG
// SIG // A1UdHwRPME0wS6BJoEeGRWh0dHA6Ly9jcmwubWljcm9z
// SIG // b2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1Jvb0Nl
// SIG // ckF1dF8yMDEwLTA2LTIzLmNybDBaBggrBgEFBQcBAQRO
// SIG // MEwwSgYIKwYBBQUHMAKGPmh0dHA6Ly93d3cubWljcm9z
// SIG // b2Z0LmNvbS9wa2kvY2VydHMvTWljUm9vQ2VyQXV0XzIw
// SIG // MTAtMDYtMjMuY3J0MA0GCSqGSIb3DQEBCwUAA4ICAQCd
// SIG // VX38Kq3hLB9nATEkW+Geckv8qW/qXBS2Pk5HZHixBpOX
// SIG // PTEztTnXwnE2P9pkbHzQdTltuw8x5MKP+2zRoZQYIu7p
// SIG // Zmc6U03dmLq2HnjYNi6cqYJWAAOwBb6J6Gngugnue99q
// SIG // b74py27YP0h1AdkY3m2CDPVtI1TkeFN1JFe53Z/zjj3G
// SIG // 82jfZfakVqr3lbYoVSfQJL1AoL8ZthISEV09J+BAljis
// SIG // 9/kpicO8F7BUhUKz/AyeixmJ5/ALaoHCgRlCGVJ1ijbC
// SIG // HcNhcy4sa3tuPywJeBTpkbKpW99Jo3QMvOyRgNI95ko+
// SIG // ZjtPu4b6MhrZlvSP9pEB9s7GdP32THJvEKt1MMU0sHrY
// SIG // UP4KWN1APMdUbZ1jdEgssU5HLcEUBHG/ZPkkvnNtyo4J
// SIG // vbMBV0lUZNlz138eW0QBjloZkWsNn6Qo3GcZKCS6OEua
// SIG // bvshVGtqRRFHqfG3rsjoiV5PndLQTHa1V1QJsWkBRH58
// SIG // oWFsc/4Ku+xBZj1p/cvBQUl+fpO+y/g75LcVv7TOPqUx
// SIG // UYS8vwLBgqJ7Fx0ViY1w/ue10CgaiQuPNtq6TPmb/wrp
// SIG // NPgkNWcr4A245oyZ1uEi6vAnQj0llOZ0dFtq0Z4+7X6g
// SIG // MTN9vMvpe784cETRkPHIqzqKOghif9lwY1NNje6CbaUF
// SIG // EMFxBmoQtB1VM1izoXBm8qGCA1gwggJAAgEBMIIBAaGB
// SIG // 2aSB1jCB0zELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
// SIG // c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
// SIG // BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEtMCsGA1UE
// SIG // CxMkTWljcm9zb2Z0IElyZWxhbmQgT3BlcmF0aW9ucyBM
// SIG // aW1pdGVkMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046
// SIG // NTUxQS0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29m
// SIG // dCBUaW1lLVN0YW1wIFNlcnZpY2WiIwoBATAHBgUrDgMC
// SIG // GgMVAIaFeq+PTOBgXeNStUWAdWdH+M7goIGDMIGApH4w
// SIG // fDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
// SIG // b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
// SIG // Y3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWlj
// SIG // cm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwDQYJKoZI
// SIG // hvcNAQELBQACBQDso5LGMCIYDzIwMjUxMDIyMTcyODM4
// SIG // WhgPMjAyNTEwMjMxNzI4MzhaMHYwPAYKKwYBBAGEWQoE
// SIG // ATEuMCwwCgIFAOyjksYCAQAwCQIBAAIBbQIB/zAHAgEA
// SIG // AgIS2DAKAgUA7KTkRgIBADA2BgorBgEEAYRZCgQCMSgw
// SIG // JjAMBgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIB
// SIG // AAIDAYagMA0GCSqGSIb3DQEBCwUAA4IBAQAaGjRFwz8G
// SIG // gapgP+3fD1uJMUjBcZfS13ZKCKezYJBl2I6XKeK0rMnl
// SIG // lN3leECvApqwGRaL0RtfSqROpO0zIj0MuZhEO5wuY2B3
// SIG // +CIS5I56394o/Zapyltz3pJQZkg/LKdBVEpUD7LKKtaR
// SIG // 25enPBIemYi+8SDM9WrNT2x440GShhhoDikcYu35z09J
// SIG // f2CwSh3QsDSTLMxJKjYwg74ov+inaz8413ampCx1j06f
// SIG // CF/Sgo51HVxiJav2FqXrOXrGQWXKFtbO4JkBNFb3mH7B
// SIG // DWkMmD+HudASsOdqfLsIk+CMTH1ZfUAGESbH6I3OfLBM
// SIG // XD6jZxRQQZXRCy3Xk9i87wGjMYIEDTCCBAkCAQEwgZMw
// SIG // fDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
// SIG // b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
// SIG // Y3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWlj
// SIG // cm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAIb
// SIG // 0LK4Amf3cs8AAQAAAhswDQYJYIZIAWUDBAIBBQCgggFK
// SIG // MBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAvBgkq
// SIG // hkiG9w0BCQQxIgQglBkrL5Uj+d4SZztaqwu+JrbWnBnZ
// SIG // trT2TvCnVUxKRGswgfoGCyqGSIb3DQEJEAIvMYHqMIHn
// SIG // MIHkMIG9BCAwJRSVuD2jmMcQCFXdLuJAwDpUVNZ6bc6d
// SIG // fJU83Q2LgDCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMw
// SIG // EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
// SIG // b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
// SIG // b24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1w
// SIG // IFBDQSAyMDEwAhMzAAACG9CyuAJn93LPAAEAAAIbMCIE
// SIG // IFSSms4wGs8gv+fRPUvgdH8kK7NzaD+tpDUI3dkFxYED
// SIG // MA0GCSqGSIb3DQEBCwUABIICAFhgp98DxPNvm+wpzjEH
// SIG // 0N72CHozOO8y01pow72pr6xEQNdhjyup98vU13mMdt1m
// SIG // 3TlrxwOALtaqTZ47n6TGPQWl4BTJaKS7dsvXopu9mW/1
// SIG // nAcJ5hxWtfcOiLEOmQAANoRxsYOtPWONMATMSmWA5bQ6
// SIG // Csu6mPOaP3lur6S5ltAG4u8oaYKqg5lQ8BhwnrGUxwt1
// SIG // l4fCB3e3je8Icbv+xIHcewPR1ZK3Nf5IbzL9ANOf0MMF
// SIG // TuRwDYElSo7nitfzRcK5XRwG73DL8xyE9NDOVOKoy8Ut
// SIG // OtVmRe2WbVqewx6Hnk1NS84SraEJ3AuTLCIwDpmQ53IJ
// SIG // sVMo4LnDydNQqnwnnM4ZH4goyBB19uOiDhNxjRXwP48a
// SIG // 5x7PP7a6P6nHeBvtNnFOOlVpIP0Gk5BhdWiKcCaGlS3a
// SIG // QSuTtHEMvCgRTKa14IUHEwMYUp95luiF0Nw5IduYffqt
// SIG // 40GPjqM37p332XvgXshDNpv/VSZG7IdXcFIgjqCRD9Rh
// SIG // 9GfeTNi1w0ldeTkS7xQpLyTLFz5CecaCpCHlYHImOO+U
// SIG // gGsfPgyNSN/a5rE0AsYo8qBsnv0twtbCCT1URH6l3o78
// SIG // bzkKYQKHtZVe3zAIvHiPoyt7nv1UtfEjq8LabsThszub
// SIG // Y/FtSNBLpk8qYY4LgrrAq//UjiAJDIQQG3G2kL36Ao0Z
// SIG // leUy
// SIG // End signature block
