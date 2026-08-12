/// <dictionary target='parameter'>sce</dictionary>
/// <dictionary target='member'>bindto</dictionary>
/// <dictionary>bindto,sce</dictionary>

(function () {
    "use strict";

    var dashboard = angular.module("dashboard", []);

    dashboard.controller("dashboardController", function ($scope, $sce) {
        $scope.strings = JSON.parse(window.external.GetStrings());
        $scope.HASComplianceData = JSON.parse(window.external.GetHASComplianceData());
        $scope.HAStopNCreasons = JSON.parse(window.external.GetTopNCReasons());
        $scope.HASUsageData = JSON.parse(window.external.GetHASUsageData());
        $scope.deviceInfoData = JSON.parse(window.external.GetClientTypeData());

        $scope.dhaEnabled = function () {

            var enabled = JSON.parse(window.external.IsDHAEnabled());

            // If not enabled, we want to check if there is already some data present in the dashboard
            if (!enabled) {
                // $scope.HASUsageData[0][2] corresponds to the number of devices
                return $scope.HASUsageData[0][2] > 0;
            }

            return enabled;
        };

        $scope.getString = function (stringName) {
            return $scope.strings[stringName];
        };

        $scope.getHTMLString = function (htmlStringName) {
            var htmlString = $scope.strings[htmlStringName];
            return $sce.trustAsHtml(htmlString);
        };

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
            var pattern = ["#00BBF1", "#2E75B6", "#E32636", "#A9A9A9"];     // Compliant, NonCompliant, Errors, Unknown

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
                    onclick: function (d) { window.external.OnHAComplianceStatusChartClick(d.name); }
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
            var pattern = ["#00BBF1", "#2E75B6", "#A6A6A6"];

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
                    onclick:
                        function (d) {
                            window.external.OnNonCompliantDevicesByCTClick(d.name);
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
                    onclick: function (d) { window.external.OnW10DevicesReportingHAClick(); }
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
                    onclick: function (d) { window.external.OnHAComplianceSettingsChartClick(columns[0][d.x + 1]); }
                },
                axis: {
                    rotated: true,
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

        $scope.createDonutChart("#HASComplianceDonut", $scope.HASComplianceData);
        $scope.createHorizBarChart("#ncSettingsBarChart", $scope.HAStopNCreasons);
        $scope.createGaugeChart("#HASUsageDonut", $scope.HASUsageData);
        $scope.createClientTypeChart("#deviceInfoTreeMap", $scope.deviceInfoData);
    });
}());

// SIG // Begin signature block
// SIG // MIInywYJKoZIhvcNAQcCoIInvDCCJ7gCAQExDzANBglg
// SIG // hkgBZQMEAgEFADB3BgorBgEEAYI3AgEEoGkwZzAyBgor
// SIG // BgEEAYI3AgEeMCQCAQEEEBDgyQbOONQRoqMAEEvTUJAC
// SIG // AQACAQACAQACAQACAQAwMTANBglghkgBZQMEAgEFAAQg
// SIG // 0YiMeN/w2Vvp1b0J56WMihDs3olZeqBm/i3/5ZkJxZOg
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
// SIG // ARUwLwYJKoZIhvcNAQkEMSIEIMeG8vKpH/uWwXkb5yih
// SIG // KBdF4PC45w7KTv9iqguCfFJhMEIGCisGAQQBgjcCAQwx
// SIG // NDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRw
// SIG // Oi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEB
// SIG // BQAEggEAOCsriGz+DXJpBCGfPxp3yvnBtVqrwPieF9MQ
// SIG // hwzlaJkE03xNOp2aj3NkUTGNwVupdELQ9W1J6itG60In
// SIG // HhCrZ7C3LZY3pfL01FBFXRvWXrzrzb4hFxt6r0oXCNaZ
// SIG // ALo0exVt7etF7Jv04k3R/8/NRknDpb54yCG4hoF2PM72
// SIG // XQpZIL1/hE82hfdHGSTHziOKbdzKSy7MkBZEkPx5iQxZ
// SIG // fUa0sBbb7RgL5H6AP82voiZeKIzPzi87vIU3z0JYuqLa
// SIG // Y7Y78UFeHft6gAf5aIY/NeBAYIYZEhPxEQk2CqEncKPY
// SIG // pshvlPOAocw/PCdGygeh7hxqqj0TwVYdU4gjKo1Q0KGC
// SIG // FywwghcoBgorBgEEAYI3AwMBMYIXGDCCFxQGCSqGSIb3
// SIG // DQEHAqCCFwUwghcBAgEDMQ8wDQYJYIZIAWUDBAIBBQAw
// SIG // ggFZBgsqhkiG9w0BCRABBKCCAUgEggFEMIIBQAIBAQYK
// SIG // KwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCDBRZZK
// SIG // 8pt1hpn4OfFhyQYaw9g24pRLXaZsAowo+cacVQIGY2Pe
// SIG // fFXuGBMyMDIyMTEwNDE3MjMzOS42MjVaMASAAgH0oIHY
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
// SIG // IgQgWDaDKfZvtBPqNpFHBxRI6q8f+OrjEJxBHZpsW6h7
// SIG // 7WEwgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCAo
// SIG // 69Y4oHA7Q4pS+Y1NsBfrpIYTeWsPeGTami0X0PD7HzCB
// SIG // mDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
// SIG // YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
// SIG // VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNV
// SIG // BAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEw
// SIG // AhMzAAABuAjUwbh54FFJAAEAAAG4MCIEIJDBW67MRKy5
// SIG // 6CRRhSvuyzsbZ09Q6WTDPYgV7mzHGwVWMA0GCSqGSIb3
// SIG // DQEBCwUABIICAIXGkS5dFwcyG+CSZCRJl9bbCQCaM2m2
// SIG // sOT66Jlpy4itUEuFY7srsjBCvfLITKQdGsFXvsKTUYrp
// SIG // UwwJRekw44MDGCw7w9CovDivWh/NnZaATK+4Is+8HaT6
// SIG // btD0rXEHivuw7Q6Lb2kgUs4CdgC5FC1YntI8AebiLGGd
// SIG // xhBaFBUqhnJLVCy7fd1uZ6OpLqPCZOVWO/Oic26edA4t
// SIG // okfRIvZhSUqotEkzxk48OUmQ8QFBFyXKU89cokcCqdmY
// SIG // WkzWNPaMxpV1s3s30wadCbHWvrby9kHbTNFSas5RoMiI
// SIG // 6otuGZLhSWQ5w6dkEZuo5V5RRXEwY6u4djmTSzwusKyg
// SIG // wBVDRXyGHmujht+/nE/7bzE31dL2HR1P463+18qOqmk7
// SIG // ArrVzKHnJMN8IE2fKVcDNmssPq/IPXSlwfVvHi1mEsJc
// SIG // AJi4bjVInT5JJMdO08bofX95qiaGMeUXn/O9rerdedUI
// SIG // 3CDkDSQOIrFf8d5VwtYSuvQRj2yq1xmSVIaO5SUCeJ5U
// SIG // pD+hppxzkY+GTgxpjT8Qhu+SaUwevpyk6ZL7XPLRvqTb
// SIG // hoHQC44WdPX999VjNuM8H8+NdhQDo2PcFIso0JWxGkqC
// SIG // QcRXzvljbhP41Z7HoslCZWCT9N0V1H9YiFXPa6t19EKV
// SIG // 2IJYH3hL8cBjEdxAWccCYV5YObVeKCKiZmDy
// SIG // End signature block
