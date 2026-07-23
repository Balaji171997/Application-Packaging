(function () {
    "use strict";

    var dashboard = angular.module("dashboard", []);

    dashboard.controller("dashboardController", function ($scope, $sce) {

        adminUI.initializeController($scope, function ()
        {
            $scope.refreshPage();
        });

        $scope.formatString = function (format) {
            var args = Array.prototype.slice.call(arguments, 1);
            return format.replace(/{(\d+)}/g, function (match, number) {
                return typeof args[number] != 'undefined'
                    ? args[number]
                    : match
                    ;
            });
        }

        $scope.showLoading = function() {
            document.getElementById("errorMessageBlock").style.display = "none";
            document.getElementById("documentationContentBlock").style.display = "none";
            document.getElementById("loadingMessageBlock").style.display = "block";
        }

        $scope.showContent = function() {
            document.getElementById("loadingMessageBlock").style.display = "none";
            document.getElementById("errorMessageBlock").style.display = "none";
            document.getElementById("documentationContentBlock").style.display = "block";
        }

        $scope.showError = function() {
            document.getElementById("loadingMessageBlock").style.display = "none";
            document.getElementById("documentationContentBlock").style.display = "none";
            document.getElementById("errorMessageBlock").style.display = "block";
        }

        $scope.refreshPage = function() {
            $scope.showLoading();

            adminUI.sendNewRequest("InitiateDownload", null, $scope.downloadCallback);
        }

        $scope.downloadCallback = function (results, returnCode) {

            if (returnCode == 0) {

                results = JSON.parse(results);

                adminUI.sendNewRequest("RunAntiXSS", results.Content, function callback(xssResults, returnCode){

                    xssResults = JSON.parse(xssResults);

                    var converter = new showdown.Converter();

                    converter.setFlavor('github');

                    converter.setOption('metadata', true);

                    var convertedHtml = converter.makeHtml(results.Content);

                    var documentationContentBlock = document.getElementById("documentationContentBlock");

                    var documentationContentBlockHTML = new DOMParser().parseFromString(convertedHtml, 'text/html').body;
                    while (documentationContentBlockHTML.hasChildNodes()) {
                        documentationContentBlock.appendChild(documentationContentBlockHTML.firstChild);
                    }

                    var links = documentationContentBlock.querySelectorAll("a");
                    links.forEach(function (link) {
                        link.setAttribute("target", "_blank");
                    }),

                    $scope.showContent();
                });
                
            }
            else {
                var errorTextElement = document.getElementById("errorText");
                var errorText;

                if (results.FailureType == "HTTP") {

                    var formattedError = $scope.formatString($scope.strings["ErrorLoadingMessageHttpFormat"], results.StatusCode, results.ReasonPhrase);
                    errorText = formattedError;

                } else if (results.FailureType == "Exception") {

                    var formattedError = $scope.formatString($scope.strings["ErrorLoadingMessageExceptionFormat"], results.ExceptionType, results.ExceptionMessage);
                    errorText = formattedError;

                } else if (results.FailureType == "InvalidData") {

                    var formattedError = $scope.strings["ErrorLoadingMessageInvalidData"];
                    errorText = formattedError;

                } else if (results.FailureType == "ScriptingDetected") {

                    var formattedError = $scope.strings["ErrorLoadingMessageInvalidData"];
                    errorText = formattedError;

                } else {

                    errorText = $scope.strings["ErrorLoadingMessageGeneric"];
                }

                errorText = errorText.replace(/\\r/gi, "").replace(/\\n/gi, "<br />");

                var errorTextHTML = new DOMParser().parseFromString(errorText, 'text/html').body;
                while (errorTextHTML.hasChildNodes()) {
                    errorTextElement.appendChild(errorTextHTML.firstChild);
                }

                var languageCode = window.external.GetLanguageCode();
                var formattedLanguage = $scope.formatString($scope.strings["LanguageIdentifierFormat"], languageCode);
                var formattedTime = window.external.GetCurrentDateTime();
                var currentLanguageAndTimeParagraph = document.getElementById("currentLanguageAndTimeParagraph");
                while (currentLanguageAndTimeParagraph.hasChildNodes()) {
                    currentLanguageAndTimeParagraph.removeChild(currentLanguageAndTimeParagraph.firstChild);
                }
                currentLanguageAndTimeParagraph.appendChild(document.createTextNode(formattedLanguage));
                currentLanguageAndTimeParagraph.appendChild(document.createElement("BR"));
                currentLanguageAndTimeParagraph.appendChild(document.createTextNode(formattedTime));

                $scope.showError();
            }
        }
    });
}());
// SIG // Begin signature block
// SIG // MIIomQYJKoZIhvcNAQcCoIIoijCCKIYCAQExDzANBglg
// SIG // hkgBZQMEAgEFADB3BgorBgEEAYI3AgEEoGkwZzAyBgor
// SIG // BgEEAYI3AgEeMCQCAQEEEBDgyQbOONQRoqMAEEvTUJAC
// SIG // AQACAQACAQACAQACAQAwMTANBglghkgBZQMEAgEFAAQg
// SIG // kVbcm6CcLaEfG5d/1+XbBP3cVAUdNl8CE8Au1XL11/ig
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
// SIG // ghpsMIIaaAIBATCBlTB+MQswCQYDVQQGEwJVUzETMBEG
// SIG // A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
// SIG // ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
// SIG // MSgwJgYDVQQDEx9NaWNyb3NvZnQgQ29kZSBTaWduaW5n
// SIG // IFBDQSAyMDExAhMzAAAEhJjiEuB4ozFdAAAAAASEMA0G
// SIG // CWCGSAFlAwQCAQUAoIH3MBkGCSqGSIb3DQEJAzEMBgor
// SIG // BgEEAYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEE
// SIG // AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCDQR/JVNlge06x3
// SIG // QquoTCi2wJbXtX9IC4LVvbej5G8/NTCBigYKKwYBBAGC
// SIG // NwIBDDF8MHqgXIBaAE0AaQBjAHIAbwBzAG8AZgB0AC4A
// SIG // VABvAG8AbABrAGkAdAAuAFcAcABmAC4AVQBJAC4AQwBv
// SIG // AG4AdAByAG8AbABzAC4AVwBlAGIAVgBpAGUAdwAuAGQA
// SIG // bABsoRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
// SIG // BgkqhkiG9w0BAQEFAASCAQB7z6NxXOi+G+/ZIMw3HRdi
// SIG // RgShyaPMMmWvpPHrly8KkWGCxMwpuUocEYVhkk4m8S45
// SIG // w7taVmOB/xyfpy7RuJTeKsw+bDDBvw153NZlvoA+Uog3
// SIG // o4L9BA4GeS8xW5W+uzhMW5rKouSzEL1PojqFw9fRRs1o
// SIG // 0w5DQMT9CQpV099NulHTrGg4yxA9TZfgfJwR6lhRZZIa
// SIG // vk3lAGZ7xjzvGfY5qAkj0Oq52rK1PGVG4oubio9+Px3g
// SIG // d4zVs7wTdSMY8YTZi84nDHUJe1LnHVftAIiBA/qRZHV4
// SIG // PSQFTJj62gNEc5eiU5BWg8lKd2OhCp9YUJnDe3aN2e5b
// SIG // Z7s0D1AmDRxtoYIXrTCCF6kGCisGAQQBgjcDAwExgheZ
// SIG // MIIXlQYJKoZIhvcNAQcCoIIXhjCCF4ICAQMxDzANBglg
// SIG // hkgBZQMEAgEFADCCAVoGCyqGSIb3DQEJEAEEoIIBSQSC
// SIG // AUUwggFBAgEBBgorBgEEAYRZCgMBMDEwDQYJYIZIAWUD
// SIG // BAIBBQAEIIpfQ7W5YaRqZsiThhnzh/y1Uw2ubQdUGUP0
// SIG // sof6i81kAgZo8pGR+7oYEzIwMjUxMDIzMDI0NTU2Ljg1
// SIG // NlowBIACAfSggdmkgdYwgdMxCzAJBgNVBAYTAlVTMRMw
// SIG // EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
// SIG // b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
// SIG // b24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9w
// SIG // ZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNoaWVs
// SIG // ZCBUU1MgRVNOOjY1MUEtMDVFMC1EOTQ3MSUwIwYDVQQD
// SIG // ExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloIIR
// SIG // +zCCBygwggUQoAMCAQICEzMAAAIVGAPTgQcmfFMAAQAA
// SIG // AhUwDQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMx
// SIG // EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
// SIG // ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
// SIG // dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3Rh
// SIG // bXAgUENBIDIwMTAwHhcNMjUwODE0MTg0ODIwWhcNMjYx
// SIG // MTEzMTg0ODIwWjCB0zELMAkGA1UEBhMCVVMxEzARBgNV
// SIG // BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
// SIG // HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEt
// SIG // MCsGA1UECxMkTWljcm9zb2Z0IElyZWxhbmQgT3BlcmF0
// SIG // aW9ucyBMaW1pdGVkMScwJQYDVQQLEx5uU2hpZWxkIFRT
// SIG // UyBFU046NjUxQS0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1p
// SIG // Y3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0G
// SIG // CSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDDcdXeFXEv
// SIG // SURg9XTdd40pnnXtUhuB7GGUM92lfANLQFi3E/CLhdil
// SIG // lHWV3S7pyvZeO66B2DnQNTHlYcvRCFjZ32+QlKTTasT/
// SIG // vmFwq33WbYiHbztBHFEyYW7cEXrjrqTyqnm5e197q5yK
// SIG // rj1hpLyn53O/e5NqsPiFDxRPstr3mk4mJGrHF3So4YsQ
// SIG // K8csRc9eKg1LH2nKHOGbqW3t7MvEl4VVi3FKGRq8+hk3
// SIG // R04KJh6HgqCgqjJqDMy5KIsKIxRbhR7hCybrnwUk0ZM2
// SIG // HtXmpdhUDqTnGPDlZ5Z0o7PSL0DmMFxtj19U6j9wDyLV
// SIG // vK3NwNPFvedy1yXLz85h42y2Rpv8iyrcLF7W+r3p8gcT
// SIG // X5kaYmORrWyh3Co/JxWn/a1v4GO6U8vkPquBRdM8XzhT
// SIG // zZEsodXntsHx8dGmCeNxYFC5c+BV5JekRFaKa3Q0XaUI
// SIG // 4vOqCu9L+9ip17kuf1iUoqEBn/EMTRMsgivr4j/YlO1c
// SIG // /fid+NMQ1WowEhJZxqQjEDAZvdEHnIcLHKcgU1Utx8oC
// SIG // wR0LlTZ6bR8C+ZW/Syieqe/Xty5piLZ4ItaGgrUhzzkP
// SIG // Duz+WFxesGljif9GXmXfAfOzi84iG7zsMjLlBRoS6kSz
// SIG // JjQ1aqAjgFaXq/XCCx76XwNYV5Reh+FS4KBVO5Mc3cry
// SIG // J2gxufxDd51QgQIDAQABo4IBSTCCAUUwHQYDVR0OBBYE
// SIG // FIkhd/FyoDAWoaP2N3BC11Kpp2PXMB8GA1UdIwQYMBaA
// SIG // FJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYw
// SIG // VKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9w
// SIG // a2lvcHMvY3JsL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAl
// SIG // MjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRg
// SIG // MF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9z
// SIG // b2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIw
// SIG // VGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwG
// SIG // A1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUH
// SIG // AwgwDgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUA
// SIG // A4ICAQB3jYe1X6QZu/HMsFMLk7u+QIgE/L8HCmMLN4vn
// SIG // eECIQ55un5V02fCb0ZUJ9ircox+uPhS8pBNQBpLlmTB7
// SIG // WC9neWNJKcI7JLk7A2712mDfDD5BbZ45xIuTJUBYWsuf
// SIG // oiKDdML/NYy9WGpe10WEbYonWVJs3bbZyxjcTf8GsaW4
// SIG // CW8RP2CbFXLLE3Ln3/skXnMgZwmJvJ3Gz3gkvUG0+Bck
// SIG // 59nND7/eJNzp4O2ZpZPoMp2cmhynzCRcpY8iwER+QPqT
// SIG // VCK3C+3SYes5FqHvlKN5w4q3ihZrJUuQ9OGjXZ7SieAS
// SIG // DVyN7l/FJka2GsytYq8jhHscQLuTyZof148DdWIfQJVJ
// SIG // I559o9MYzMiEcKjmneMblIxzI7d4D24RphAkhMmUsbcH
// SIG // DAabKljsL/z+ePVI6GDHUeAnTLA4kv3F8/gA5xaYJ9uy
// SIG // qAZsJoLtYfmwg13N8xqvxXtg0WqRsIZQqFzwakjIT4wq
// SIG // fJWffeOy5oYCU1GDt1VFRKhgsnG9SzD0Y7DIGkHBsT2y
// SIG // o4ub4ew7TSgXbc8yKjtYVdwVNkCOne6OKEEB8utcgKAY
// SIG // 4c92RnTja7Utmo5yeWvdfO+Ax76Y8/Jqxbx/Su3MmPdX
// SIG // kT8QqLJCU/GP0x+rbH2GKaeVdYZkJU94QFE6s1sNgF9r
// SIG // NPIs0I5OxG2Sw5JXcUG0+elC0s3vnjCCB3EwggVZoAMC
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
// SIG // BRDBcQZqELQdVTNYs6FwZvKhggNWMIICPgIBATCCAQGh
// SIG // gdmkgdYwgdMxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
// SIG // YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
// SIG // VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNV
// SIG // BAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMg
// SIG // TGltaXRlZDEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNO
// SIG // OjY1MUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3Nv
// SIG // ZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4D
// SIG // AhoDFQCPp5N6Nu5gTUh+Nt+u3q1d68JRIKCBgzCBgKR+
// SIG // MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5n
// SIG // dG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
// SIG // aWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1p
// SIG // Y3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqG
// SIG // SIb3DQEBCwUAAgUA7KOnDTAiGA8yMDI1MTAyMjE4NTUw
// SIG // OVoYDzIwMjUxMDIzMTg1NTA5WjB0MDoGCisGAQQBhFkK
// SIG // BAExLDAqMAoCBQDso6cNAgEAMAcCAQACAi3VMAcCAQAC
// SIG // AhK7MAoCBQDspPiNAgEAMDYGCisGAQQBhFkKBAIxKDAm
// SIG // MAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAIAgEA
// SIG // AgMBhqAwDQYJKoZIhvcNAQELBQADggEBAKd4ICae7N3K
// SIG // 17sNWOKMsEWRCv5kRv1NqHxcYocfiI3uEx8vVARPKa1n
// SIG // N9/WEK5LcmvpigdJVxjxvEOMQnAz5Ga3/XE4WPi6zVWh
// SIG // xxyrjY7h+mZXpeIuSQJY4X3P1bfW0ClERx+erA8dR1uU
// SIG // 9xp/8zSYzYujNYRG7CnSPKkNSubzOmjms/RvxR7xxVic
// SIG // J3R+eGImmw+2yG3E8mut7IKS0CF6VG8Y1zZM1/rz8B8A
// SIG // z4iO9hPMXuRnaWGeRxbIhi88ra1DuorcIHe1JdTLhCxw
// SIG // lnxpZEQe01LJyma6PNmzWZOH9PoJzv+G5z6gHVyppBP6
// SIG // tfNtK8YVR+eH0CKEqz0uLkgxggQNMIIECQIBATCBkzB8
// SIG // MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
// SIG // bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
// SIG // cm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNy
// SIG // b3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAhUY
// SIG // A9OBByZ8UwABAAACFTANBglghkgBZQMEAgEFAKCCAUow
// SIG // GgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqG
// SIG // SIb3DQEJBDEiBCCvMC781MOqakPL8wj/Zkbaw4QiU4Bu
// SIG // bQGDXMsiD/JcQzCB+gYLKoZIhvcNAQkQAi8xgeowgecw
// SIG // geQwgb0EIHAQ9HY8OtMUtyu1CwqtSLujPkk1EIX8pEcy
// SIG // KFI17uyKMIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzAR
// SIG // BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
// SIG // bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
// SIG // bjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAg
// SIG // UENBIDIwMTACEzMAAAIVGAPTgQcmfFMAAQAAAhUwIgQg
// SIG // Ytcu8GXVUPo1dsbuL7yn44Iz71TJ1Ua5Qm6EXtGwDiQw
// SIG // DQYJKoZIhvcNAQELBQAEggIASP67KxNkkkvb0BV7I4sk
// SIG // 7rRqL0dVPoG4psIxtbeh+TdX8rodQDTBlrJ4n94mcskM
// SIG // qun+GOSsCXAtc6jgUzbz6DrYy0O28gaqR9RA4E3bS+VO
// SIG // hHrYEDdwndPy999X4s6JWaB4Z0ZvaXODmWXfOmqGqqa7
// SIG // xSAbyJ8Coaj+x5r/CLLws1/9+uAsqWfS86wXJ7G0TzcP
// SIG // ZizM1VLyU26Sbb1Mh47MAhZBnWPGmL8GuxqttN0iea0F
// SIG // Yqso/p2bH6IVEhxMSH+vT1Lw6ZDt3F7BxXVDx+G5u9C9
// SIG // DHlNZNJx77aVVgFaafZw2Y+byXjJ7QXSkNA4xiHQ1pNn
// SIG // IbNdeGdWVNwJyR9MyDAxppR3B1rhAABNq0n4vTPuD7DN
// SIG // c/+EkzBTi/WZUUEhLfa3ZJ7/isAepY8Ml4mGDlXEIu94
// SIG // Rk5XU13TpIW2KE9TRJFTY3JnLaC4M7rk1DigOuM6RYOG
// SIG // uAND1x6QRm0GbXQWKV/5oR/i2flCPoYke8GynI5pQXKE
// SIG // VgTUCwlB8wzihZZ/wNtICsLkpNy3DczAyBPekzSrXpxL
// SIG // 7AyTxSVxrC/tS0aofeSSG6MANNEdz/DK1rwrgXN56m17
// SIG // pHWNvB+ojcu5wPAM3p7ckztpdv24juJiY++PDyEuKBKJ
// SIG // fi68Ge/cGYu4b9gThZkJkYw0YiqjzcAv10qZ2xplgT6juLo=
// SIG // End signature block
