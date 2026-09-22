(function (angular) {
    'use strict';
    angular.module('ngApp', [])
        .controller('controller', function ($scope, $sce) {

            $scope.milestone = window.external.Milestone;
            $scope.releases = JSON.parse(window.external.ReleasesJSON);
            $scope.barData = null;

            if (null != $scope.releases) {
                var i = $scope.releases.length;
                var total = 0;

                $scope.barData = [];
                while (i--) {
                    $scope.barData.push({
                        Completed: 0,
                        CompletedWidth: 0,
                        Incomplete: 0,
                        IncompleteWidth: 0,
                        Visible: false
                    });
                }

                i = 0;
                angular.forEach($scope.releases, function (release, key) {
                    if (null != release.Features) {
                        angular.forEach(release.Features, function (feature, key) {
                            if (null != feature.Scenarios) {
                                $scope.barData[i].Visible |= (0 < feature.Scenarios.length);
                                angular.forEach(feature.Scenarios, function (scenario, key) {
                                    if (scenario.Completed) {
                                        $scope.barData[i].Completed++;
                                    }
                                    else {
                                        $scope.barData[i].Incomplete++;
                                    }
                                });
                            }
                        });
                    }

                    total = $scope.barData[i].Completed + $scope.barData[i].Incomplete;
                    $scope.barData[i].CompletedWidth = Math.round(100.0 * $scope.barData[i].Completed / total);
                    $scope.barData[i].IncompleteWidth = 100 - $scope.barData[i].CompletedWidth;
                    i++;
                });
            }

            $scope.toggle = function ($event) {
                var link = angular.element($event.currentTarget);
                link.parent().toggleClass('on');
                link.next().toggleClass('hidden');
            };

        });
})(window.angular);

// SIG // Begin signature block
// SIG // MIIomAYJKoZIhvcNAQcCoIIoiTCCKIUCAQExDzANBglg
// SIG // hkgBZQMEAgEFADB3BgorBgEEAYI3AgEEoGkwZzAyBgor
// SIG // BgEEAYI3AgEeMCQCAQEEEBDgyQbOONQRoqMAEEvTUJAC
// SIG // AQACAQACAQACAQACAQAwMTANBglghkgBZQMEAgEFAAQg
// SIG // yOsW21/d0BLuoCE1H3WxGEvLg6jRO1PzHEOp/903ZmKg
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
// SIG // AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCCOzN6WvELsYdOz
// SIG // LSpq2IHID3Xmz+A5XNbb/yeYodKakTCBigYKKwYBBAGC
// SIG // NwIBDDF8MHqgXIBaAE0AaQBjAHIAbwBzAG8AZgB0AC4A
// SIG // VABvAG8AbABrAGkAdAAuAFcAcABmAC4AVQBJAC4AQwBv
// SIG // AG4AdAByAG8AbABzAC4AVwBlAGIAVgBpAGUAdwAuAGQA
// SIG // bABsoRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
// SIG // BgkqhkiG9w0BAQEFAASCAQCjOuDRpWyOZTKjiY+kobu1
// SIG // UwDoFvDfx4OhhyHwzOCRXb+V6frlHq47VsPA3HZnIeMQ
// SIG // EMSDbssknQukiHa/RKlGZXyvY0WRp2/O+2GjV+MYxCdQ
// SIG // wzNzFVsR+pDyvtJ3U046TYvGurD95jaN2UeDgszaL3RX
// SIG // BUCjcTuPUGRMgaA/MHmDfSanP8ICrsYgFPHvQep7Oyhd
// SIG // n8gHiDqN83IwHkO/1Zdu0DUTJDM5DLPQIahfsDUvo/Zn
// SIG // h/VK+t2mgfM0BwlgftB/Q4IIyse2YR+Z7D8j4qrPT/x9
// SIG // qVs/fpXz9+X5umCeqc53Z9mEeMIPeOaL4YQSuSgIWbQb
// SIG // vZne2Maa5hW5oYIXrDCCF6gGCisGAQQBgjcDAwExgheY
// SIG // MIIXlAYJKoZIhvcNAQcCoIIXhTCCF4ECAQMxDzANBglg
// SIG // hkgBZQMEAgEFADCCAVkGCyqGSIb3DQEJEAEEoIIBSASC
// SIG // AUQwggFAAgEBBgorBgEEAYRZCgMBMDEwDQYJYIZIAWUD
// SIG // BAIBBQAEIP10QWTR5xe3j9cQcCzZWvNOeHd7TlKCDoAY
// SIG // TUUPVYLoAgZo8jMcbWMYEjIwMjUxMDIzMDI0NzI4Ljgz
// SIG // WjAEgAIB9KCB2aSB1jCB0zELMAkGA1UEBhMCVVMxEzAR
// SIG // BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
// SIG // bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
// SIG // bjEtMCsGA1UECxMkTWljcm9zb2Z0IElyZWxhbmQgT3Bl
// SIG // cmF0aW9ucyBMaW1pdGVkMScwJQYDVQQLEx5uU2hpZWxk
// SIG // IFRTUyBFU046NTkxQS0wNUUwLUQ5NDcxJTAjBgNVBAMT
// SIG // HE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2WgghH7
// SIG // MIIHKDCCBRCgAwIBAgITMwAAAhSNzSNE7gbfcgABAAAC
// SIG // FDANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzET
// SIG // MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
// SIG // bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
// SIG // aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFt
// SIG // cCBQQ0EgMjAxMDAeFw0yNTA4MTQxODQ4MThaFw0yNjEx
// SIG // MTMxODQ4MThaMIHTMQswCQYDVQQGEwJVUzETMBEGA1UE
// SIG // CBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEe
// SIG // MBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0w
// SIG // KwYDVQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRp
// SIG // b25zIExpbWl0ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNT
// SIG // IEVTTjo1OTFBLTA1RTAtRDk0NzElMCMGA1UEAxMcTWlj
// SIG // cm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZTCCAiIwDQYJ
// SIG // KoZIhvcNAQEBBQADggIPADCCAgoCggIBAMlPp1oAlMr3
// SIG // 8hj9c0xZC5HYDrrV3FbXj/9Anl36xf+unISpePzGQwkO
// SIG // hPFK+JKoAsUL3n+y4NYH7KNRFlihur4sdVcbbztZDxiu
// SIG // D2SpjnqHi+vBevjMNhET8uAS9rySn+i6OWe19MZEY7XL
// SIG // 3zPU9Bw4Hx1Fus9Qm4EIqqxMbNjR9u61qVJMk2KzBuk1
// SIG // 8t/fhnTDk4F8lA4kRlRwMtxKmDcN80lrrJ9M3nZemv9Q
// SIG // 251yHL5/RWh83f/ehDzQTgndrzqUtApO5IJI1ccDqbbF
// SIG // mvCPpvgwON3MJRKz2iHfOBm3Rs6N1aDu2IQpkCKEWm9H
// SIG // fKK+T5soPlTJfI3qDfUnlMVWaQSP3EOE11ypSw5H2880
// SIG // kK4lYkBiRiS7Sktw01TbgaqY1y3btqdmKvTgz6mQqIjQ
// SIG // YeAgel9oi2FEjvLZm1FSzDBHoG7x0i10EfPEDSAoxaAQ
// SIG // Qwg8naE6Pf0zZKvNJju+8AzNOLT3b2zJsU9NRk6HetCS
// SIG // cVBpjE4LHoIXQRo5Dfg+hrFKWO7Wu4T/T8y67PgJcbuO
// SIG // l09te2wZ+hMCbAGAHPQtvJikVHKCGVkEW/jHKGWkrthH
// SIG // Es7iJQGjSEDbRpc9jxd36EnhpnP1e4AhrPAB5IisF8yU
// SIG // j37Z7B/Dv0d6ScNg/9oRxNyc8R9kqy19RXSOw68NeOT5
// SIG // C9IWxS+jFQgpAgMBAAGjggFJMIIBRTAdBgNVHQ4EFgQU
// SIG // 21/27NXEqck2J2Ln/zLfQjzYcBswHwYDVR0jBBgwFoAU
// SIG // n6cVXQBeYl2D9OXSZacbUzUZ6XIwXwYDVR0fBFgwVjBU
// SIG // oFKgUIZOaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3Br
// SIG // aW9wcy9jcmwvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUy
// SIG // MFBDQSUyMDIwMTAoMSkuY3JsMGwGCCsGAQUFBwEBBGAw
// SIG // XjBcBggrBgEFBQcwAoZQaHR0cDovL3d3dy5taWNyb3Nv
// SIG // ZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNyb3NvZnQlMjBU
// SIG // aW1lLVN0YW1wJTIwUENBJTIwMjAxMCgxKS5jcnQwDAYD
// SIG // VR0TAQH/BAIwADAWBgNVHSUBAf8EDDAKBggrBgEFBQcD
// SIG // CDAOBgNVHQ8BAf8EBAMCB4AwDQYJKoZIhvcNAQELBQAD
// SIG // ggIBAD98afQ+BrtEh/QftSR9IbMBariDWk0/kY6XxK/F
// SIG // JlDng5eFOblfotvP3kmFzMYHpt8gWcsGA8r3+KjF1L2w
// SIG // 3JZTakci9kb/I0rvMHJbf1UtfnOXFQiXzPlh75FK/nQn
// SIG // 1JTsvZ+HsQj19S+rlsBR+XqBX6jxKdxcN9IqzDdkqJxw
// SIG // St5gfLw49w/NKCSqntrWrTt/MjE4kRHQthw+3lSFFi+3
// SIG // eeFLaGMc8JCTdbe4BBBqLIAaXZsClWGAztVElkjZmRC4
// SIG // JWAOC6FaBg7lmze5g/FaM2AbH5GWqzsqyWJRf1Ag2Swf
// SIG // F2i36zHzMmUzAjrhLjw+M4/I8vybeNHJayFtOHLy4ZIZ
// SIG // MnQc3K5gth8XhN+oCbIfo85or0vWL8oj4S5KJtRT9AyB
// SIG // a+FZaslxymoK7Z6khfEMhKarUEu8Eu2c2RdHmXtH7GA9
// SIG // CdUWq21bg8ZlrKuOZ9b40XaJ7bhlHZqxtjhninfALYjY
// SIG // IX52m1QW4KWIHMf3i8lv5+NHk2yiJbJtHLHsrlr2Bcjq
// SIG // kF46FrS+P7FB8ZViLK45zWqza/jzpC/AtYxgQibr5tFG
// SIG // II4SGi/lwV2r62zrV/Zq2d8vBkA8Vl595oajNtWXBpPN
// SIG // 8UkagfXnHxmDURuoOub+t+YEs1JgSmVlnAzc8AKMbIBI
// SIG // 0xV8+moX8qwS6rIa4yVzynzvvQK/MIIHcTCCBVmgAwIB
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
// SIG // NTkxQS0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29m
// SIG // dCBUaW1lLVN0YW1wIFNlcnZpY2WiIwoBATAHBgUrDgMC
// SIG // GgMVANkcrF9fekVy08APz/ERVnVE6VLGoIGDMIGApH4w
// SIG // fDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
// SIG // b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
// SIG // Y3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWlj
// SIG // cm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwDQYJKoZI
// SIG // hvcNAQELBQACBQDso/FOMCIYDzIwMjUxMDIzMDAxMTU4
// SIG // WhgPMjAyNTEwMjQwMDExNThaMHQwOgYKKwYBBAGEWQoE
// SIG // ATEsMCowCgIFAOyj8U4CAQAwBwIBAAICHv0wBwIBAAIC
// SIG // EvYwCgIFAOylQs4CAQAwNgYKKwYBBAGEWQoEAjEoMCYw
// SIG // DAYKKwYBBAGEWQoDAqAKMAgCAQACAwehIKEKMAgCAQAC
// SIG // AwGGoDANBgkqhkiG9w0BAQsFAAOCAQEAcOfE1duvz4Q0
// SIG // tDoVIWX37CROEqsPgRpBHANi1iIT3gA2xWn1SVLlw9RC
// SIG // CILEOhc25XE3IK9Bc+PczWcZn9eeR5sGlxOMePwLDxLU
// SIG // ex0Tq5FTTgRKQVYpalufMNGLTEsQ2rRP6KX/WiTTigpt
// SIG // KQRaEpx+4tB67f2eMFFsTDtSGAHDGoca0f91SrVwKlmZ
// SIG // oNef2HNLdaTre1miWCVCCgrhrKejWWevOJYAzy2WvYJw
// SIG // AXE8tpAEUE03rFNtBaBf4NSMr8YYylSQrLV3tTcvoftu
// SIG // 4/LBBwUqPsuGIRGFTczyj4PofMM88fa+sFn+oM65Kj5E
// SIG // Qf9thCBlxS9gcnXqJy+9ATGCBA0wggQJAgEBMIGTMHwx
// SIG // CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
// SIG // MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
// SIG // b3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jv
// SIG // c29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAACFI3N
// SIG // I0TuBt9yAAEAAAIUMA0GCWCGSAFlAwQCAQUAoIIBSjAa
// SIG // BgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZI
// SIG // hvcNAQkEMSIEIJstolhZzYt7Sy+vK/56pITL4NehRkyQ
// SIG // CPCznsYwXlhVMIH6BgsqhkiG9w0BCRACLzGB6jCB5zCB
// SIG // 5DCBvQQgNnir71seW3KIuN20Tt/hLbUFAr8ng9nW18v+
// SIG // vtMSvscwgZgwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEG
// SIG // A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
// SIG // ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
// SIG // MSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQ
// SIG // Q0EgMjAxMAITMwAAAhSNzSNE7gbfcgABAAACFDAiBCC/
// SIG // HMLkwW2qOPzRMMCXdANvok4RiY3mzopop3kdB4YydzAN
// SIG // BgkqhkiG9w0BAQsFAASCAgANZhuFbs4aDsFNRmorUvg3
// SIG // k3Hb4bSv8M7RMcW2RcAsB/RMXMTu/gEWWVLUGB1DAmMY
// SIG // 4lXXXzNgUhA1XIJrdonBG2htyka3DpR1PCRCSkN836Ic
// SIG // A8yQCjQtFbGg/rz1qWLhcHbhYYxegxnHu2toSN73Fmov
// SIG // pPnYXNo7XHgdlOHmVSuhlXJT7yRGqKaUmGf1bUjEvTfo
// SIG // +CL9l/71LQBuaz7bUmtZ+ehQ+hJjL2DnLmnw6f7i3eNa
// SIG // ZpTwxY6hhMfCVqaUMKgQqp33n6ImT4I9Wdu7EBHHIi0S
// SIG // icGT+OhXsP097Ddwfr0u3G1gxvaECF1Wr0Smoynl41Lc
// SIG // 2ERKjx8hDDaCuNesXPrMSR+SXKkjga59X1JxFMGrBx8R
// SIG // GYbNU6QwgjaNzceOJXNE+5pr1XvNZ+cXoMOw1Xr16TiV
// SIG // iY0YhDyNfmmY8E8IMih+/wjYii2swiFmrjsG8DPNd/Yr
// SIG // lyYrnxwZk6H80folrQxtyMVxsJraGLb7muH5s82mISIa
// SIG // UBLSC64v9iHZcI12vvGDOqhnYhm43Ly5NxdC0UFFA9a2
// SIG // LccBegR+90wdc9tudDw2ae5YejDZ2Z5L1cVr1gkmQ3hk
// SIG // HOs0akOEB7hEyc3LDzpiQVEiKaXRjpFylOjfLvj/MSDL
// SIG // yhHkutIV5EKV3zM7w415cxruIooMfHnyD5mzcxcCAjqt6Q==
// SIG // End signature block
