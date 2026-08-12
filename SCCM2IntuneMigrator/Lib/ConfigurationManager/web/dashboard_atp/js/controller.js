/// <dictionary target='parameter'>sce</dictionary>
/// <dictionary target='member'>bindto</dictionary>
/// <dictionary>bindto,sce</dictionary>

(function () {
    "use strict";

    var dashboard = angular.module("dashboard", []);
    //dashboard.run(initChartTemplate);
    //dashboard.directive('dashboardChart', defineChartDirective);

    dashboard.controller("dashboardController", function ($scope) {
        $scope.ATPAgentHealthChartState = ChartState.Loading;
        $scope.strings = getStrings(["DeploymentStatusChartTitle", "DeploymentStatusChartHoverText", "AgentHealthChartTitle", "NotOnboardedAgent", "HealthyAgent", "InactiveAgent", "WindowsService"]);

        $scope.getString = function (stringName) {
            return $scope.strings[stringName];
        };

        function fetchDataForHealthChart() {
            getData("select * from SMS_G_System_AdvancedThreatProtectionHealthStatus", "GetATPHealthCounts", function (data) {

                if (data == null) {
                    logger.err("SMS_G_System_AdvancedThreatProtectionHealthStatus returned no results");
                    $scope.ATPAgentHealthChartState = ChartState.NoDataFound;
                    return;
                }

                $scope.ATPAgentHealthChartState = ChartState.DataReady;

                var chartData = convertObjectToArrayOfArrays(data, ["HealthyCount", "InactiveCount", "WindowsServiceCount", "NotOnboardedCount"])

                var deployedClients = (data.HealthyCount + data.WindowsServiceCount + data.InactiveCount);
                var totalClients = deployedClients + data.NotOnboardedCount;

                if (totalClients == 0) {
                    $scope.ATPAgentHealthChartState = ChartState.NoDataFound;
                    $scope.$apply();
                    return;
                }

                var c3ChartObject = createDonutChart("#agent-health", chartData, getString('AgentHealthChartTitle'))

                angular.merge(c3ChartObject, {
                    size: {
                        height: 250,
                        width: 450
                    },
                    data: {
                        names: {
                            NotOnboardedCount: $scope.strings["NotOnboardedAgent"],
                            HealthyCount: $scope.strings["HealthyAgent"],
                            WindowsServiceCount: $scope.strings["WindowsService"],
                            InactiveCount: $scope.strings["InactiveAgent"]
                        },
                        colors: {
                            HealthyCount: '#2E9F00',
                            InactiveCount: '#FF5C00',
                            WindowsServiceCount: '#D83B01',
                            NotOnboardedCount: '#5B616B '
                        },
                        order: null
                    },
                    legend: {
                        position: "right",
                    },
                    donut: {
                        label: {
                            format: undefined //this removes the default in createDonutChart() that shows that value instead of the ratio
                        },
                        width: 65
                    }
                });

                c3.generate(c3ChartObject);

                // deployment status chart
                var chartData = [["DeployedClients", deployedClients]];

                var c3ChartObject = createDonutChart("#deployment-status", chartData, getString('DeploymentStatusChartTitle'))

                angular.merge(c3ChartObject, {
                    data: {
                        type: 'gauge',
                        names: {
                            DeployedClients: $scope.strings["DeploymentStatusChartHoverText"]
                        },
                        columns: chartData
                    },
                    color: {
                        pattern: ['#2E9F00'],
                    },
                    gauge: {
                        max: totalClients,
                        width: 65
                    }
                });

                c3.generate(c3ChartObject)

                $scope.$apply();
            }, "GetATPHealthCounts")
        }

        fetchDataForHealthChart();
    });
}());

//Helper function to skip keyboard focus from hitting either the html or body tags
//when navigating into the WebBrowser.  This is due to many focus issues with the WebBrowser control
function skipFocus(e) {
    if (e.currentTarget == window) {
        if (window.external.IsShiftDown()) {
            document.querySelector("[data-last]").focus();
        }
        else {
            document.querySelector("[data-first]").focus();
        }
    }
}
// SIG // Begin signature block
// SIG // MIInyQYJKoZIhvcNAQcCoIInujCCJ7YCAQExDzANBglg
// SIG // hkgBZQMEAgEFADB3BgorBgEEAYI3AgEEoGkwZzAyBgor
// SIG // BgEEAYI3AgEeMCQCAQEEEBDgyQbOONQRoqMAEEvTUJAC
// SIG // AQACAQACAQACAQACAQAwMTANBglghkgBZQMEAgEFAAQg
// SIG // weq2PgxVSiP+pA0OhVMF+x2ScPfP4RQAov66r7H2cZGg
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
// SIG // SEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCGaAw
// SIG // ghmcAgEBMIGVMH4xCzAJBgNVBAYTAlVTMRMwEQYDVQQI
// SIG // EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
// SIG // HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAm
// SIG // BgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENB
// SIG // IDIwMTECEzMAAALMjrWWpr3RyU4AAAAAAswwDQYJYIZI
// SIG // AWUDBAIBBQCgga4wGQYJKoZIhvcNAQkDMQwGCisGAQQB
// SIG // gjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcC
// SIG // ARUwLwYJKoZIhvcNAQkEMSIEIIYL4OQOP4ABYoQkv+lL
// SIG // M+fGXWL0/1hszSP+OfBee8tiMEIGCisGAQQBgjcCAQwx
// SIG // NDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRw
// SIG // Oi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEB
// SIG // BQAEggEAjuu/DTwtumjbIrCyxQYPuIetHdXJZmS4BUAv
// SIG // NvHMBko4/2WW/Bwrq3oD+9HJ6t9UlN5nK+ZmQF0fhlTx
// SIG // tP8yIxyv5nHLqXAhRLcdT0/ebiAVm/HGJVPygD5J9aGP
// SIG // lb9YsBIcqXrGatYCb+tYqzt6wLFtl8dHnr3nPzg8u7J5
// SIG // /337//YgBthiWlWLKO1acNxjanrPInEnKcIncfX1/5Fc
// SIG // /Db/vmwttHNYRr1jeeqvRcXIijUqiN0v4jwFfd2+UqUt
// SIG // LEZdV3LATtxg2OKBxJvgXMOPV3VxKICT/+gFH5GJ4Xpd
// SIG // Kfcm5IWxLqJ1UgWAW+hdWTjM4M+MDFd/1VRPQ6QlLqGC
// SIG // FyowghcmBgorBgEEAYI3AwMBMYIXFjCCFxIGCSqGSIb3
// SIG // DQEHAqCCFwMwghb/AgEDMQ8wDQYJYIZIAWUDBAIBBQAw
// SIG // ggFXBgsqhkiG9w0BCRABBKCCAUYEggFCMIIBPgIBAQYK
// SIG // KwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCCOcVQN
// SIG // 8amF4vudKTienPpmZjtRavsSRSaABO73tKf5MgIGY2Pf
// SIG // aYG8GBEyMDIyMTEwNDE3MjMzOS4xWjAEgAIB9KCB2KSB
// SIG // 1TCB0jELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hp
// SIG // bmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoT
// SIG // FU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEtMCsGA1UECxMk
// SIG // TWljcm9zb2Z0IElyZWxhbmQgT3BlcmF0aW9ucyBMaW1p
// SIG // dGVkMSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVTTjpGQzQx
// SIG // LTRCRDQtRDIyMDElMCMGA1UEAxMcTWljcm9zb2Z0IFRp
// SIG // bWUtU3RhbXAgU2VydmljZaCCEXswggcnMIIFD6ADAgEC
// SIG // AhMzAAABufYADWVUT7wDAAEAAAG5MA0GCSqGSIb3DQEB
// SIG // CwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
// SIG // aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
// SIG // ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMT
// SIG // HU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMB4X
// SIG // DTIyMDkyMDIwMjIxN1oXDTIzMTIxNDIwMjIxN1owgdIx
// SIG // CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
// SIG // MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
// SIG // b3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1pY3Jv
// SIG // c29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEm
// SIG // MCQGA1UECxMdVGhhbGVzIFRTUyBFU046RkM0MS00QkQ0
// SIG // LUQyMjAxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0
// SIG // YW1wIFNlcnZpY2UwggIiMA0GCSqGSIb3DQEBAQUAA4IC
// SIG // DwAwggIKAoICAQDjST7JYfUWx8kBAm1CCDcTBebkJMjd
// SIG // O1SEoSE17my6VpwDYAQi7wnCZe6P9hxzkZ7EXJkiDSf6
// SIG // nJQJiyKzo52J626HAJ4sYjBFwvmtbGfOKsWFrRFWO1WM
// SIG // NCwnM2PvOlP/LIYMarGnsyqVq4jznKVdUofErDsX99Mj
// SIG // u475XfyAQN0+pRzNqU/x0Y1pP6/bssdEOGrcdJpC1WEv
// SIG // cuef6E5SixNNIe/dkvpmmnQHct1YE8HosKBDlw+/OcL9
// SIG // 4fn8B/8E0LQvZYQMYTDuKfjj/fPPFsZG5egakVl7neeE
// SIG // U86qdla/snp9UNQOrpsjAe16tLJyGBuQdQHHOFICZT0P
// SIG // 2YjJKoMUDRQlkL89BvaC4Ejw/CstAJF9tj3Azm6D7jU+
// SIG // EXHlj19FFWVLF/SFILO0BeNR4kEsBHjjhxsq30HZkrJQ
// SIG // E625h/9fDOUK7EzOSSDY3LfRuNsajfFRfWfFjohjIzW7
// SIG // 5aXBJpsrGJeUMoaxA6BZ0E1O2xaw9yV9HyH7tbGy1nga
// SIG // l8G6eGfMgAk7aYStlW8zr4uL3NEQpkTc72EENj42ezWk
// SIG // 1xOBrt74IACfq7c1EwHyaLbzkqnDIDcC2WtWPhE/5W9F
// SIG // co62MBbh7YNEFskIz+d+dC06b9POqclVIeAN8PzrOYUx
// SIG // hWYBXuWwsjJ6WNPTNMj3R2kP+eqGFLEiHMislQIDAQAB
// SIG // o4IBSTCCAUUwHQYDVR0OBBYEFLewOHHbWEOaCYxNWaq0
// SIG // qJ6eNURSMB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWn
// SIG // G1M1GelyMF8GA1UdHwRYMFYwVKBSoFCGTmh0dHA6Ly93
// SIG // d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jv
// SIG // c29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEp
// SIG // LmNybDBsBggrBgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKG
// SIG // UGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMv
// SIG // Y2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBD
// SIG // QSUyMDIwMTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwFgYD
// SIG // VR0lAQH/BAwwCgYIKwYBBQUHAwgwDgYDVR0PAQH/BAQD
// SIG // AgeAMA0GCSqGSIb3DQEBCwUAA4ICAQDN3GezRVB0TLCy
// SIG // s45e6yTyJL+6CfrPZJLrdIWYn/VkretEs2BlC6dc5nT6
// SIG // nPsPHh05Ial9Bigqdk06kswVwYcBzpvPqeoVMTZQ3sBj
// SIG // GVKLPedmk125QE9zigZ31QS0MlGr60o7iRmQFt9HDWN6
// SIG // 41Q1JRg/lcoEB8kmg2r4iUGyuv+n0L1FBaKiJN5XRn45
// SIG // wLZ3m7FZaoellmplXOQGXaVkdY0szf6MSmKnNQRuEscZ
// SIG // T7XH6wHQc/3FOG8VV6gAH9NjWbHLyTaUZzgC3+ZFaNh7
// SIG // qSVwrJPU8z+TzVtrE0t05sISEJj8a9BNFKjqI1KwSVDo
// SIG // WyEwMXJ0mvyDJbi9R10bS0GSPsbNnkbbjzlLClFu9f9W
// SIG // HqrGAixy77vNnHg1UELz+xhxBJKdpBI4qH242BKwaNog
// SIG // hGscXl+GfR7wIAODLEJG5+nuBBUH9d7D/ip914DCLyW6
// SIG // iyXhXEI2vklHjl7uXH5MXtBs0zaI3ciMM2h5YTn5VUWT
// SIG // a8XntwfsmcHdyRwyL7+9bkiP0iM87fXFNhsh0FasQUq0
// SIG // bSlulvFcO86Vb6FbCL95Y8YPuzYhkpV19bO82wTQzFI/
// SIG // Tp8zpRyv95qzlPGBLkX+kcGpFuVAnhmpsuTIirtmLsio
// SIG // hgQr+DhoT7LTXuwC5BDofAV9dreJ7bmLvoMPS+sgj2NI
// SIG // 1mGkLcwD/TCCB3EwggVZoAMCAQICEzMAAAAVxedrngKb
// SIG // SZkAAAAAABUwDQYJKoZIhvcNAQELBQAwgYgxCzAJBgNV
// SIG // BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYD
// SIG // VQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
// SIG // Q29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBS
// SIG // b290IENlcnRpZmljYXRlIEF1dGhvcml0eSAyMDEwMB4X
// SIG // DTIxMDkzMDE4MjIyNVoXDTMwMDkzMDE4MzIyNVowfDEL
// SIG // MAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
// SIG // EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jv
// SIG // c29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9z
// SIG // b2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwggIiMA0GCSqG
// SIG // SIb3DQEBAQUAA4ICDwAwggIKAoICAQDk4aZM57RyIQt5
// SIG // osvXJHm9DtWC0/3unAcH0qlsTnXIyjVX9gF/bErg4r25
// SIG // PhdgM/9cT8dm95VTcVrifkpa/rg2Z4VGIwy1jRPPdzLA
// SIG // EBjoYH1qUoNEt6aORmsHFPPFdvWGUNzBRMhxXFExN6AK
// SIG // OG6N7dcP2CZTfDlhAnrEqv1yaa8dq6z2Nr41JmTamDu6
// SIG // GnszrYBbfowQHJ1S/rboYiXcag/PXfT+jlPP1uyFVk3v
// SIG // 3byNpOORj7I5LFGc6XBpDco2LXCOMcg1KL3jtIckw+DJ
// SIG // j361VI/c+gVVmG1oO5pGve2krnopN6zL64NF50ZuyjLV
// SIG // wIYwXE8s4mKyzbnijYjklqwBSru+cakXW2dg3viSkR4d
// SIG // Pf0gz3N9QZpGdc3EXzTdEonW/aUgfX782Z5F37ZyL9t9
// SIG // X4C626p+Nuw2TPYrbqgSUei/BQOj0XOmTTd0lBw0gg/w
// SIG // EPK3Rxjtp+iZfD9M269ewvPV2HM9Q07BMzlMjgK8Qmgu
// SIG // EOqEUUbi0b1qGFphAXPKZ6Je1yh2AuIzGHLXpyDwwvoS
// SIG // CtdjbwzJNmSLW6CmgyFdXzB0kZSU2LlQ+QuJYfM2BjUY
// SIG // hEfb3BvR/bLUHMVr9lxSUV0S2yW6r1AFemzFER1y7435
// SIG // UsSFF5PAPBXbGjfHCBUYP3irRbb1Hode2o+eFnJpxq57
// SIG // t7c+auIurQIDAQABo4IB3TCCAdkwEgYJKwYBBAGCNxUB
// SIG // BAUCAwEAATAjBgkrBgEEAYI3FQIEFgQUKqdS/mTEmr6C
// SIG // kTxGNSnPEP8vBO4wHQYDVR0OBBYEFJ+nFV0AXmJdg/Tl
// SIG // 0mWnG1M1GelyMFwGA1UdIARVMFMwUQYMKwYBBAGCN0yD
// SIG // fQEBMEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93d3cubWlj
// SIG // cm9zb2Z0LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5
// SIG // Lmh0bTATBgNVHSUEDDAKBggrBgEFBQcDCDAZBgkrBgEE
// SIG // AYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYw
// SIG // DwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBTV9lbL
// SIG // j+iiXGJo0T2UkFvXzpoYxDBWBgNVHR8ETzBNMEugSaBH
// SIG // hkVodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2Ny
// SIG // bC9wcm9kdWN0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0y
// SIG // My5jcmwwWgYIKwYBBQUHAQEETjBMMEoGCCsGAQUFBzAC
// SIG // hj5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2Nl
// SIG // cnRzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNydDAN
// SIG // BgkqhkiG9w0BAQsFAAOCAgEAnVV9/Cqt4SwfZwExJFvh
// SIG // nnJL/Klv6lwUtj5OR2R4sQaTlz0xM7U518JxNj/aZGx8
// SIG // 0HU5bbsPMeTCj/ts0aGUGCLu6WZnOlNN3Zi6th542DYu
// SIG // nKmCVgADsAW+iehp4LoJ7nvfam++Kctu2D9IdQHZGN5t
// SIG // ggz1bSNU5HhTdSRXud2f8449xvNo32X2pFaq95W2KFUn
// SIG // 0CS9QKC/GbYSEhFdPSfgQJY4rPf5KYnDvBewVIVCs/wM
// SIG // nosZiefwC2qBwoEZQhlSdYo2wh3DYXMuLGt7bj8sCXgU
// SIG // 6ZGyqVvfSaN0DLzskYDSPeZKPmY7T7uG+jIa2Zb0j/aR
// SIG // AfbOxnT99kxybxCrdTDFNLB62FD+CljdQDzHVG2dY3RI
// SIG // LLFORy3BFARxv2T5JL5zbcqOCb2zAVdJVGTZc9d/HltE
// SIG // AY5aGZFrDZ+kKNxnGSgkujhLmm77IVRrakURR6nxt67I
// SIG // 6IleT53S0Ex2tVdUCbFpAUR+fKFhbHP+CrvsQWY9af3L
// SIG // wUFJfn6Tvsv4O+S3Fb+0zj6lMVGEvL8CwYKiexcdFYmN
// SIG // cP7ntdAoGokLjzbaukz5m/8K6TT4JDVnK+ANuOaMmdbh
// SIG // IurwJ0I9JZTmdHRbatGePu1+oDEzfbzL6Xu/OHBE0ZDx
// SIG // yKs6ijoIYn/ZcGNTTY3ugm2lBRDBcQZqELQdVTNYs6Fw
// SIG // ZvKhggLXMIICQAIBATCCAQChgdikgdUwgdIxCzAJBgNV
// SIG // BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYD
// SIG // VQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
// SIG // Q29ycG9yYXRpb24xLTArBgNVBAsTJE1pY3Jvc29mdCBJ
// SIG // cmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEmMCQGA1UE
// SIG // CxMdVGhhbGVzIFRTUyBFU046RkM0MS00QkQ0LUQyMjAx
// SIG // JTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNl
// SIG // cnZpY2WiIwoBATAHBgUrDgMCGgMVAMdiHhh4ZOfDEJM8
// SIG // 0lpJxnC434E6oIGDMIGApH4wfDELMAkGA1UEBhMCVVMx
// SIG // EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
// SIG // ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
// SIG // dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3Rh
// SIG // bXAgUENBIDIwMTAwDQYJKoZIhvcNAQEFBQACBQDnD69Z
// SIG // MCIYDzIwMjIxMTA0MjMzMzQ1WhgPMjAyMjExMDUyMzMz
// SIG // NDVaMHcwPQYKKwYBBAGEWQoEATEvMC0wCgIFAOcPr1kC
// SIG // AQAwCgIBAAICIkMCAf8wBwIBAAICEYQwCgIFAOcRANkC
// SIG // AQAwNgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYBBAGEWQoD
// SIG // AqAKMAgCAQACAwehIKEKMAgCAQACAwGGoDANBgkqhkiG
// SIG // 9w0BAQUFAAOBgQC1IVtKwCVGr9H0p9q1c8LNbTZv/opX
// SIG // /11zUPiDP2YGH+e4/qgGLqQLM2QD5+mBjFxyyOGCbByJ
// SIG // UIc9D4BDo4odrri0vqW+svzuFO4k3FvnapvKrpSoT8dk
// SIG // lbHgjqKdItNt0HKyVtVDnuoJMj2gNjybQltOIQvfKtMg
// SIG // /KEyulBcLTGCBA0wggQJAgEBMIGTMHwxCzAJBgNVBAYT
// SIG // AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
// SIG // EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
// SIG // cG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1l
// SIG // LVN0YW1wIFBDQSAyMDEwAhMzAAABufYADWVUT7wDAAEA
// SIG // AAG5MA0GCWCGSAFlAwQCAQUAoIIBSjAaBgkqhkiG9w0B
// SIG // CQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcNAQkEMSIE
// SIG // IJKm2lT0KA5ms68g+53Z+GHpKmxW1v3+pYLTM9/6Z2Wm
// SIG // MIH6BgsqhkiG9w0BCRACLzGB6jCB5zCB5DCBvQQgZOtG
// SIG // zvFvObkwHyVRDt719mi2kBXIHBqXcLDqIvn6D/QwgZgw
// SIG // gYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
// SIG // aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
// SIG // ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQD
// SIG // Ex1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAIT
// SIG // MwAAAbn2AA1lVE+8AwABAAABuTAiBCBKQd8a+3ssaUwz
// SIG // DH/IRoiy8w3iBIcZo9QiK7h/VHyfLDANBgkqhkiG9w0B
// SIG // AQsFAASCAgC77gdJzjMXPqNQQbppR7mo7UBA6mr9Kq2v
// SIG // ay9+k1r/mrXPROwRCLEZdkkFQg1+RaewjSrF2AhueuKy
// SIG // 9FRz9EWpcJz2p66fKIVRIqLALlja2OG7ubte1Hf2NFOB
// SIG // Gz+4319RNDJcMMXCpF7HaWeDItnT2EQOSD2mhli9qdGs
// SIG // ZL7bwM+Hi6bPQ4J7Dr/kbTZwIjNCYOYvNoX2y/ac0yBh
// SIG // hdw7NTstEUxvQ6J8sPCx7tzpSF05FFuOPX1jPs8xZv98
// SIG // n2X6zfi2+C9YI65btKXtlVpXx5NDGKJ7Z9WvGZ1cvrIi
// SIG // D7XSW4ULxq+ABSQTNFBQxcx4UpR44NHwcN0+h+wmL3sA
// SIG // 80YHN/oyUAtP2uHjOzyFtENrby9HxG3k6IIjiS4ulVzv
// SIG // D+Hn/TaFpzTSOVs7RJsHKjoL6rrieYQaofwf4J/ATdut
// SIG // IYgEP9nw3ElxCKZLhpX6U7uyKHqyfEais8DfTWY79x5B
// SIG // f2RFyKezecf7U8SKKGP4VK5CUXILL0gCGsa/hHEKYrrU
// SIG // jCnf9a18We5/k5Ty2kv5KILPNiwedFADJac7T+Ke54X6
// SIG // 1Fc/7TZTeMzCTuD6nVoq8SKt4kWmPkyfTqH0mb+tTpbe
// SIG // WLq/ofzErht4xQlt5yI2zakq5LHCL+AEbBcAUN6BBdnP
// SIG // ASDRje/4pogCbm5v4Ha3p1k6ik9xrbjIxA==
// SIG // End signature block
