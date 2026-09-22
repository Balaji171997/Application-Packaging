/// <dictionary target='parameter'>sce</dictionary>
/// <dictionary target='member'>bindto</dictionary>
/// <dictionary>bindto,sce</dictionary>

(function () {
    "use strict";

    var dashboard = angular.module("dashboard", []);

    dashboard.controller("dashboardController", function ($scope, $sce) {
        $scope.strings = JSON.parse(window.external.GetStrings());
        $scope.overallComplianceData = JSON.parse(window.external.GetOverallDeviceCompliance());


        $scope.getString = function (stringName) {
            return $scope.strings[stringName];
        };


        // Checks if value is null, 0, undefinded, "" or []
        function isEmpty(value) {
            return (value == 0 || value == null || value.length === 0 || isNaN(value));
        }

        $scope.createDonutChart = function (idToBindTo, columns) {
            var enable = true;
            var noData = true;
            var pattern = ["#FE0101", "#00BDF3", "#FF8C00", "#000000", "#88BB00", "#A9A9A9"];

            for (var i = 0; i < columns.length; i++) {
                if (!isEmpty(columns[i][1]))
                    noData = false;
            }

            if (noData) {
                enable = false;
                pattern = ["#a9a9a9"];
                columns = [['', 1]];
            }

            var donut = c3.generate({
                bindto: idToBindTo,
                data: {
                    columns: columns,
                    type: "donut",
                    onclick: function (d) { window.external.OnOveralComplianceChartClick(d.name); }
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
        $scope.createDonutChart("#OverallComplianceDonut", $scope.overallComplianceData);
    });
}());

// SIG // Begin signature block
// SIG // MIIomAYJKoZIhvcNAQcCoIIoiTCCKIUCAQExDzANBglg
// SIG // hkgBZQMEAgEFADB3BgorBgEEAYI3AgEEoGkwZzAyBgor
// SIG // BgEEAYI3AgEeMCQCAQEEEBDgyQbOONQRoqMAEEvTUJAC
// SIG // AQACAQACAQACAQACAQAwMTANBglghkgBZQMEAgEFAAQg
// SIG // KVaoqFDtA5wHGa/ewnensdF6hAxPpone3hc83IuX5a6g
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
// SIG // ghprMIIaZwIBATCBlTB+MQswCQYDVQQGEwJVUzETMBEG
// SIG // A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
// SIG // ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
// SIG // MSgwJgYDVQQDEx9NaWNyb3NvZnQgQ29kZSBTaWduaW5n
// SIG // IFBDQSAyMDExAhMzAAAEhJjiEuB4ozFdAAAAAASEMA0G
// SIG // CWCGSAFlAwQCAQUAoIH3MBkGCSqGSIb3DQEJAzEMBgor
// SIG // BgEEAYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEE
// SIG // AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCAgDBP8/UcfQBQ4
// SIG // Te9UXR/XnB5MfSwD2VYPGt+il1+oFTCBigYKKwYBBAGC
// SIG // NwIBDDF8MHqgXIBaAE0AaQBjAHIAbwBzAG8AZgB0AC4A
// SIG // VABvAG8AbABrAGkAdAAuAFcAcABmAC4AVQBJAC4AQwBv
// SIG // AG4AdAByAG8AbABzAC4AVwBlAGIAVgBpAGUAdwAuAGQA
// SIG // bABsoRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
// SIG // BgkqhkiG9w0BAQEFAASCAQDcJQe1A1uEGqoCnfYgd2yt
// SIG // jpS/r95X5UPFj58qRV2HdIjAMl/ov4eDe1QT2ozVIL3x
// SIG // KYlJcyl9E1Qxt/OJOhIbcowgAgxv+S2ROQjzwE3knEzo
// SIG // x6JVQFUkOGnQY3RnZOviuyfGWucZ1anLLuxZU7kac4Jf
// SIG // Kql5CFF+/Hw+xNz92cOZcORrIxn98TeZWesxou5PESd2
// SIG // 55Nbq0kETCf9l+ZHhfvrE1wyxMJsQBBcguipVAg6WWJ2
// SIG // YIMG12MlR87W4oPhz9QOY3k87Vuo+u1LZMTIj9qV192p
// SIG // GxX1AYSkMHX7AfaQ7pOika34ftgG1n/CqTIiOk2Ll+BW
// SIG // 1SgHodRQa+g9oYIXrDCCF6gGCisGAQQBgjcDAwExgheY
// SIG // MIIXlAYJKoZIhvcNAQcCoIIXhTCCF4ECAQMxDzANBglg
// SIG // hkgBZQMEAgEFADCCAVkGCyqGSIb3DQEJEAEEoIIBSASC
// SIG // AUQwggFAAgEBBgorBgEEAYRZCgMBMDEwDQYJYIZIAWUD
// SIG // BAIBBQAEIAmleTTbooYJX1s3rtozRIZecFgqmts3J2Yx
// SIG // BNKGLIojAgZo8ZFFiv0YEjIwMjUxMDIzMDI0NjE5Ljc5
// SIG // WjAEgAIB9KCB2aSB1jCB0zELMAkGA1UEBhMCVVMxEzAR
// SIG // BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
// SIG // bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
// SIG // bjEtMCsGA1UECxMkTWljcm9zb2Z0IElyZWxhbmQgT3Bl
// SIG // cmF0aW9ucyBMaW1pdGVkMScwJQYDVQQLEx5uU2hpZWxk
// SIG // IFRTUyBFU046MzYwNS0wNUUwLUQ5NDcxJTAjBgNVBAMT
// SIG // HE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2WgghH7
// SIG // MIIHKDCCBRCgAwIBAgITMwAAAhOwQzVmz6+V6AABAAAC
// SIG // EzANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzET
// SIG // MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
// SIG // bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
// SIG // aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFt
// SIG // cCBQQ0EgMjAxMDAeFw0yNTA4MTQxODQ4MTdaFw0yNjEx
// SIG // MTMxODQ4MTdaMIHTMQswCQYDVQQGEwJVUzETMBEGA1UE
// SIG // CBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEe
// SIG // MBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0w
// SIG // KwYDVQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRp
// SIG // b25zIExpbWl0ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNT
// SIG // IEVTTjozNjA1LTA1RTAtRDk0NzElMCMGA1UEAxMcTWlj
// SIG // cm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZTCCAiIwDQYJ
// SIG // KoZIhvcNAQEBBQADggIPADCCAgoCggIBAPSZeuC6GcQy
// SIG // DUhYM/vSkuTs7+ZuePHj1c3PUV1nuE+PzKZX4GuHqtdk
// SIG // RnaeXFb543Xub8X6tmsf457u71FuK2TeJjlJub4fpHGL
// SIG // EJWEOdxcICAd5xI3EB6Jqxt5mXv6M4xUgK+iW4JSrSHg
// SIG // Mkj8wHBc8gHq+ZSzVBwRL0DDPATozMmqQr4dMbIOMShX
// SIG // FRCUCyhHwhgX3zGSP2prrRxW9wlE2e2laRtihxBVDZWd
// SIG // b8DCr8V0z0Q528Dxs8sqiSc537CzR0OL17drbUtT3gqB
// SIG // iNITdT3qvMhrCFzPaKHMAtOgxjUjP+CwMdrir8JlJ+jc
// SIG // C3NPrZr58usNvK2S3o7JEX51VqHxL9ZlmNIx1Jx68Ehg
// SIG // UvIFT/YHAbOj+YNDqSTzH8XVJB10ZHDDz1tISD/DW1vF
// SIG // uUrqfB7sJ0im46cgJRgVHTP1ea2W9LGZpJ+9eK+lCxiv
// SIG // nCywDekdxYV+jdJ4+uBduy0ytgW0tKSWWl46NHgzc9UH
// SIG // MXiBS1IBfkQbC2A5/BPHApHsSvDZbdxovcyX+ecOlH02
// SIG // fpMEzMTKhcYe/k38e/mgTm2fp8fetQLYqgMu81VevaPy
// SIG // 1kXSj2Xb2Z/REshm05z345AREb9tqa0pRE5UcMz+m5hF
// SIG // Tili1lcMbsIe21FlLlG9XI/d877bUGBkGreRPQCyyTZp
// SIG // byygrJAe62i7AgMBAAGjggFJMIIBRTAdBgNVHQ4EFgQU
// SIG // E54QSsfha8qYUFjEYqR+PbDBQDowHwYDVR0jBBgwFoAU
// SIG // n6cVXQBeYl2D9OXSZacbUzUZ6XIwXwYDVR0fBFgwVjBU
// SIG // oFKgUIZOaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3Br
// SIG // aW9wcy9jcmwvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUy
// SIG // MFBDQSUyMDIwMTAoMSkuY3JsMGwGCCsGAQUFBwEBBGAw
// SIG // XjBcBggrBgEFBQcwAoZQaHR0cDovL3d3dy5taWNyb3Nv
// SIG // ZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNyb3NvZnQlMjBU
// SIG // aW1lLVN0YW1wJTIwUENBJTIwMjAxMCgxKS5jcnQwDAYD
// SIG // VR0TAQH/BAIwADAWBgNVHSUBAf8EDDAKBggrBgEFBQcD
// SIG // CDAOBgNVHQ8BAf8EBAMCB4AwDQYJKoZIhvcNAQELBQAD
// SIG // ggIBAIJsWiaxqkNg+lCYWekJdkmRTmjbhm1ty8wfhEvp
// SIG // dgQdTCbQUUhXYv4VWN9zacbCUIUOUy1adA12DpCKD0HN
// SIG // e6x/iFYXpjvIwrflOiNUyMOnEe3PrRKPyY6ehKhFNXOP
// SIG // 5q2jI4B4UPq2gvzlAJvfANa+GyDx7bAZi0ThpnhOVyyB
// SIG // WgSGVh74dgjlyEyjm11XecBrSdXWWXcGhwAlxedOo7Wv
// SIG // rqFHcswHrjZUzy062fJ8ocRsJPVYenog0OwkDFkkmvAy
// SIG // UvT1F43qIvb03Uu2TF6rvrb+kM98baARefmBSuLhPpoh
// SIG // rPdBcZtFStpVq5hYY5EZec8qBzncBu7KTWJA6JgjzViL
// SIG // nVEJkGCqbfx7LKX3G/saZ1iA0HTM4BPKY9b6cC4FhJx+
// SIG // y7U+HWQnqA6PTyuNEcQQ/JCie+vZ4JBMH8Ag9hF/zEJO
// SIG // /XiLzoaZx9dhrlQcr2imZOV2b6rTzjTcK/Kv6gN/O+yL
// SIG // lsFoJ2nl/qa6cNHWf0C7Wxhla4D/k0UI7ftnXGQOT91+
// SIG // C8ADYYj7MtDpeFwnY+zsQSxbzs7Ajwz2lZ5KfnXwxRvj
// SIG // TgYq+2qkyevOttqcpoNVfuoHP9Ub8Qv8IL2MhtN93nCa
// SIG // r9Dp9GUTWK/ovzpMIANxz9Wiw9Gh6xKcOpbdNut4kZAr
// SIG // 63HXDlvMN4wvEybmhlsgtkvYxI84MIIHcTCCBVmgAwIB
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
// SIG // EMFxBmoQtB1VM1izoXBm8qGCA1YwggI+AgEBMIIBAaGB
// SIG // 2aSB1jCB0zELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
// SIG // c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
// SIG // BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEtMCsGA1UE
// SIG // CxMkTWljcm9zb2Z0IElyZWxhbmQgT3BlcmF0aW9ucyBM
// SIG // aW1pdGVkMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046
// SIG // MzYwNS0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29m
// SIG // dCBUaW1lLVN0YW1wIFNlcnZpY2WiIwoBATAHBgUrDgMC
// SIG // GgMVAJgRPEgo8YI2nJsvP1RHZOzcaUemoIGDMIGApH4w
// SIG // fDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
// SIG // b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
// SIG // Y3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWlj
// SIG // cm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwDQYJKoZI
// SIG // hvcNAQELBQACBQDso/goMCIYDzIwMjUxMDIzMDA0MTEy
// SIG // WhgPMjAyNTEwMjQwMDQxMTJaMHQwOgYKKwYBBAGEWQoE
// SIG // ATEsMCowCgIFAOyj+CgCAQAwBwIBAAICM1EwBwIBAAIC
// SIG // Ek8wCgIFAOylSagCAQAwNgYKKwYBBAGEWQoEAjEoMCYw
// SIG // DAYKKwYBBAGEWQoDAqAKMAgCAQACAwehIKEKMAgCAQAC
// SIG // AwGGoDANBgkqhkiG9w0BAQsFAAOCAQEAj78QNxgco/ZE
// SIG // 51DfsDtSlJd3dFr5+a0Uhlfy/crlr+i8kzBpFnNdaAFK
// SIG // cpdxaQdB55YuUVTORZFiOhMjdMEksUvhL1t8iAnbgoYr
// SIG // xD3yW9aBsV16wdmeDm5uBsXQv7mBY7NqG7ExTFZ7MhBG
// SIG // O5IpUvC0PQ8iuuZ1y0KWVhAJjalcZZakTDbT9D79tUE/
// SIG // P6xq+20VLHmqYe6489LGkHbLnzBO5pVFoOD/0PPtpw80
// SIG // DRWghRKr1bRe1R8REMhAcohhGGamMNOlz3cqSf4qwzeQ
// SIG // 062/jfL8CYdRuZeTIVYMqw4jWbFQOCrVywTy+SjuhqWR
// SIG // yTv9VCE44neKRHq6kCY6+zGCBA0wggQJAgEBMIGTMHwx
// SIG // CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
// SIG // MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
// SIG // b3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jv
// SIG // c29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAACE7BD
// SIG // NWbPr5XoAAEAAAITMA0GCWCGSAFlAwQCAQUAoIIBSjAa
// SIG // BgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZI
// SIG // hvcNAQkEMSIEIOv4KL2/0T/DyzGiVVcY0fmLbxZwY9z+
// SIG // xbZje4ZWT/DxMIH6BgsqhkiG9w0BCRACLzGB6jCB5zCB
// SIG // 5DCBvQQgzOEJbRSFM/CeA4wMz+J1aHWb0MWBpXlCH6fO
// SIG // jmucWGgwgZgwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEG
// SIG // A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
// SIG // ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
// SIG // MSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQ
// SIG // Q0EgMjAxMAITMwAAAhOwQzVmz6+V6AABAAACEzAiBCCd
// SIG // +9nkXr1irrpOWAzlT+6NexVkeB958Q6FcbHIrMQidDAN
// SIG // BgkqhkiG9w0BAQsFAASCAgBslOnQW/uz7k7rGl+bo7eZ
// SIG // 1oWdngWCk82RfvTVMiJgqjfVsdRQ5CFzxv6YHcaAcPaB
// SIG // bR8wndWr2gx+CCaCpn7lPKpn1TxXBbDIWiLI5Dfh98JV
// SIG // HxObBWzexJASmv9BR0n0L8NCd1fhvuo0+tbd0rPoHz8n
// SIG // qurUuHC/d1shGBD//v9tNp/EeKAqOPsIUGJiS38PiLd/
// SIG // 64zo/iXltsgwrAsR4IKAUj5wE6TqMsz9oFR8BhJ05KRu
// SIG // FutN19VwQyDWYZYMX/ZphxhPikZ1Ga8AmfTzKNovYSOt
// SIG // QIa8E8l4rLx+hhDdqPDqXiZj5x2+zjMgavQWiSVFUlTC
// SIG // YDpQeFgH6BZSghgorE5yHUGOI67cu/vaQo07hhGRD1td
// SIG // icMaChuLaVvketqDUj6wCFZmH9OH/OMaY8/L0KW17BM4
// SIG // enataUBrd5UvcFkPPOsspjbMBlHVGhyZ0lgEJasW+j6O
// SIG // j/SURljdpqzykeCr/AeCjIUijhULFkx1OR0RwG47eDu9
// SIG // EYJ+daudwUhGAmjdkv+6nfvH7fDulBV3yRCcjEgGesV6
// SIG // 3EgenCv5s5iRXyoHpHbpbiF0B95CyYw080v99HHxiwWo
// SIG // w07a/raaS0X2+LkGGrR9bGpGy56zjIjq1ZRK1NH29VYd
// SIG // Y5hto8QVk8egVOIjbtJT65iFjluL7FjhwO1GEqgzKuk0Kg==
// SIG // End signature block
