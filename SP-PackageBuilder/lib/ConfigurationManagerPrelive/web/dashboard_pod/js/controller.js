(function () {

	"use strict";
	var dashboard = angular.module("dashboard", []);

	dashboard.controller("dashboardController", function ($scope) {

		$scope.targetCompliance = 0;
		$scope.successCriteriaFormatter = '';
		
		adminUI.initializeController($scope, async function () { 
			await LoadDataAsync();
			$scope.strings = await callJsonParseMethodAsync("GetStrings", null);
			$scope.PODMetadata = await callJsonParseMethodAsync("GetPODMetadata", null);
			$scope.SuccessCriteriaData = await callJsonParseMethodAsync("GetPODSuccessCriteriaData", null);
			$scope.PhasesChartData = await callJsonParseMethodAsync("GetPhaseData", null);
			$scope.selectedPhase = $scope.PhasesChartData[0];
			$scope.PODType = await $scope.convertSoftwareType();
			$scope.phaseChanged();
			
			if ($scope.brightness < 125) {
				$scope.PhasesChartData.forEach(function (phase) {
					SetColorToAllTextInChart('#phase' + phase.PhaseID, $scope.theme.ForeGroundColor);
				});
                SetColorToAllTextInChart("#successCriteria", $scope.theme.ForeGroundColor);
            }
            $scope.$apply();
		});
		
		async function LoadDataAsync() {
            //Load Data
            await callMethodAsync("LoadData", null, null);
        };
		
		$scope.convertSoftwareType = async function () {
			if ($scope.PODMetadata.SoftwareType == 0) {
				return $scope.strings.taskSequence;
			}
			else if ($scope.PODMetadata.SoftwareType == 1) {
				return $scope.strings.softwareUpdate;
			}
			else {
				return $scope.strings.application;
			}
		};

		$scope.getCurrentState = function (phase) {
			if (phase.DeploymentID == 0) {
				return $scope.strings.waiting;
			}
			else if (phase.ExecutionState == 1) {
				return $scope.strings.suspended;
			}
			else {
				return $scope.strings.deploymentCreated;
			}
		};

		$scope.phaseChanged = function () {
			// Try to get success criteria information for next phase
			var nextSuccessCriteria = null;
			var compliance = 0;
			var maxValue = 0;

			// Get the successCriteria values for the next phase
			$scope.SuccessCriteriaData.forEach(function (successCriteria) {
				if (successCriteria.PhaseID == Number($scope.selectedPhase.PhaseID) + 1) {
					nextSuccessCriteria = successCriteria;
				}
			});

			// The last phase is selected
			if (nextSuccessCriteria == null) {
                $scope.targetCompliance = 0;
                maxValue = 100;
			}
			else {
				$scope.targetCompliance = nextSuccessCriteria.CriteriaValue;

				if (nextSuccessCriteria.CriteriaType == 'Compliance') {
					if ($scope.selectedPhase.NumberTotal > 0) {
						compliance = $scope.selectedPhase.NumberSuccess / $scope.selectedPhase.NumberTotal * 100;
						$scope.successCriteriaFormatter = '%';
                    }
                    maxValue = 100;
				}
				else if (nextSuccessCriteria.CriteriaType == 'Number') {
					if ($scope.selectedPhase.NumberTotal > 0) {
						compliance = $scope.selectedPhase.NumberSuccess;
						maxValue = nextSuccessCriteria.CriteriaValue;
						$scope.successCriteriaFormatter = '';
					}
				}
			}
			
			$scope.createGaugeChart(compliance, maxValue);
			angular.element(document).ready(function () {
					$scope.createBarChart($scope.selectedPhase.PhaseID, $scope.selectedPhase);	
			});	
		};
			

		$scope.createBarChart = function (idToBindTo, phase) {
			var chartData = {};
			chartData['NumberSuccess'] = phase.NumberSuccess;
			chartData['NumberErrors'] = phase.NumberErrors;
			chartData['NumberInProgress'] = phase.NumberInProgress;
			chartData['NumberUnknown'] = phase.NumberUnknown;

			var columns = convertObjectToArrayOfArrays(chartData, ['NumberSuccess', 'NumberErrors', 'NumberInProgress', 'NumberUnknown']);
			idToBindTo = '#phase' + idToBindTo;

			c3.generate({
				bindto: idToBindTo,
				data: {
					columns: columns,
					groups: [['NumberSuccess', 'NumberErrors', 'NumberInProgress', 'NumberUnknown']],
					type: 'bar',
					names: {
						NumberSuccess: $scope.strings.success,
						NumberErrors: $scope.strings.failed,
						NumberInProgress: $scope.strings.inProgress,
						NumberUnknown: $scope.strings.unknown
					},
					colors: {
						NumberSuccess: '#2CA02C',
						NumberErrors: '#D62728',
						NumberInProgress: '#FFD63F',
						NumberUnknown: '#808080'
					}
				},
				axis: {
					rotated: true,
					x: { show: false },
					y: { show: false }
				},
				legend: {
					show: false
				},
				size: {
					width: 150,
					height: 40
				}
			});
		};

		$scope.createGaugeChart = function (actual, maxValue) {
			c3.generate({
				bindto: '#successCriteria',
				legend: {
					hide: true
				},
				data: {
					columns: [
						['SuccessData', actual]
					],
					type: 'gauge',
					names: {
						'SuccessData': $scope.strings.successCriteria
					},
					colors: {
						'SuccessData': '#2CA02C'
					}
				},
				size: {
					height: 180
				},
				gauge: {
					max: maxValue,
				}
			});
		};
	});
}());

// SIG // Begin signature block
// SIG // MIIomwYJKoZIhvcNAQcCoIIojDCCKIgCAQExDzANBglg
// SIG // hkgBZQMEAgEFADB3BgorBgEEAYI3AgEEoGkwZzAyBgor
// SIG // BgEEAYI3AgEeMCQCAQEEEBDgyQbOONQRoqMAEEvTUJAC
// SIG // AQACAQACAQACAQACAQAwMTANBglghkgBZQMEAgEFAAQg
// SIG // /lsvYGSOfxYNu3EbPnm1DHVQ2iyST45pDfwQOq8aWK+g
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
// SIG // ghpuMIIaagIBATCBlTB+MQswCQYDVQQGEwJVUzETMBEG
// SIG // A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
// SIG // ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
// SIG // MSgwJgYDVQQDEx9NaWNyb3NvZnQgQ29kZSBTaWduaW5n
// SIG // IFBDQSAyMDExAhMzAAAEhJjiEuB4ozFdAAAAAASEMA0G
// SIG // CWCGSAFlAwQCAQUAoIH3MBkGCSqGSIb3DQEJAzEMBgor
// SIG // BgEEAYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEE
// SIG // AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCBfpgken8T2puut
// SIG // Hc8Xx3FiXjgCpShm4xrkgg/uGKz6gDCBigYKKwYBBAGC
// SIG // NwIBDDF8MHqgXIBaAE0AaQBjAHIAbwBzAG8AZgB0AC4A
// SIG // VABvAG8AbABrAGkAdAAuAFcAcABmAC4AVQBJAC4AQwBv
// SIG // AG4AdAByAG8AbABzAC4AVwBlAGIAVgBpAGUAdwAuAGQA
// SIG // bABsoRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
// SIG // BgkqhkiG9w0BAQEFAASCAQBvYQGpFpafWu5RbMCvGC/Z
// SIG // XY8KLZj2aYolNsl8q5J1SI+9EeMs+PUlXEoa5knjIIkA
// SIG // ct3OYS3E94NULDQqJJKev8irHK+JTKAt+uHsZZNKFQqM
// SIG // IQ+ofin56aVVyrugHdzi5AYss4du8RCdjrloCB/wNllH
// SIG // rljydHJ1N0ldK59+QobWpcLPxCAHUOpyWmvEv9gfcxj7
// SIG // DSBV0hn4eCRmaNLtnHycG3S67plU4njDkTisGt4rxhjW
// SIG // 78QnPZMO+euTKaP72dyNm4f2KeJRjuNEgiDUgkcU+Kdy
// SIG // A96aN2dx+jP/pKYuAQPW8+RP58IgmxM+MNftN4tG5MX+
// SIG // Nzpr2IcuvkTOoYIXrzCCF6sGCisGAQQBgjcDAwExgheb
// SIG // MIIXlwYJKoZIhvcNAQcCoIIXiDCCF4QCAQMxDzANBglg
// SIG // hkgBZQMEAgEFADCCAVoGCyqGSIb3DQEJEAEEoIIBSQSC
// SIG // AUUwggFBAgEBBgorBgEEAYRZCgMBMDEwDQYJYIZIAWUD
// SIG // BAIBBQAEIBozVIpX4TTubGF9NhQAkEMxOEwJSeBH91nE
// SIG // MIabmin4AgZo8n1NKO4YEzIwMjUxMDIzMDI0NzI1LjQ2
// SIG // OFowBIACAfSggdmkgdYwgdMxCzAJBgNVBAYTAlVTMRMw
// SIG // EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
// SIG // b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
// SIG // b24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9w
// SIG // ZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNoaWVs
// SIG // ZCBUU1MgRVNOOjU1MUEtMDVFMC1EOTQ3MSUwIwYDVQQD
// SIG // ExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloIIR
// SIG // /TCCBygwggUQoAMCAQICEzMAAAIb0LK4Amf3cs8AAQAA
// SIG // AhswDQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMx
// SIG // EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
// SIG // ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
// SIG // dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3Rh
// SIG // bXAgUENBIDIwMTAwHhcNMjUwODE0MTg0ODMwWhcNMjYx
// SIG // MTEzMTg0ODMwWjCB0zELMAkGA1UEBhMCVVMxEzARBgNV
// SIG // BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
// SIG // HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEt
// SIG // MCsGA1UECxMkTWljcm9zb2Z0IElyZWxhbmQgT3BlcmF0
// SIG // aW9ucyBMaW1pdGVkMScwJQYDVQQLEx5uU2hpZWxkIFRT
// SIG // UyBFU046NTUxQS0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1p
// SIG // Y3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0G
// SIG // CSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCOxZ3nZlmT
// SIG // MHld7mD+XYaw6MDPfSyDqNXF8UlX7DjEgNXJojcs7xsi
// SIG // mbNi6XcBkeDnRQhDw+tJFkalCoWRE276jdgoniDa4ZgF
// SIG // GSwecdhHS5VIJCDnxOGRjJ6mUZfegC8ZFW48ilC0CJOx
// SIG // HvoD+B2hTscPARtvvdsnBPKtsoeFH5ZozL0NAcjiTlCj
// SIG // j5tkOzSSPvpu+Em90ZT5LzPFAGntQCGMmcWorEi6xIhM
// SIG // TvMIJHjbYQuGSFVU4WorbDqHUwC8gt7vqHFEhw+PRIEv
// SIG // avw723HmeNTj62DasB1TXnembKGprN2lRxxgET3ANEVR
// SIG // 3970KhbHtN2dSJwH4xqLtFPqqx7t7loapfUHtueP9ke+
// SIG // ut8X4EkQiVL2INcBSB6S9dn4VmaO8vA/5037T9yuH76v
// SIG // h7wWScXsRfogl+eY14M3/rxnn2RtonV/4/macph/J0J5
// SIG // mbGsalLS1paQOTfoPeM9Vl+W/Gtz7WuEIiUzm/1qAsQU
// SIG // jXZCIFN+k4E4GvcAYI+T54fT6Vq2NBqO6D7b8EPXapvz
// SIG // bnTQtDK1RZPai1r8didGBK/WO9nT92aXUWzFZjM6cKuN
// SIG // 90H/s3qk3JK3i+f48Y3p0UuKbuTGiz4H1Z9A97MmLd+4
// SIG // rLIMAH3NIc+PVm7ydl95xkn26bjOPsMWC8ldMNOcbmqU
// SIG // bhl1sVFr+ut/OQIDAQABo4IBSTCCAUUwHQYDVR0OBBYE
// SIG // FLa+n3f+XEumk0rw6Rq4nYC82YhQMB8GA1UdIwQYMBaA
// SIG // FJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYw
// SIG // VKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9w
// SIG // a2lvcHMvY3JsL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAl
// SIG // MjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRg
// SIG // MF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9z
// SIG // b2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIw
// SIG // VGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwG
// SIG // A1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUH
// SIG // AwgwDgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUA
// SIG // A4ICAQBmRTVfFAPg5MzcZOG3fZNdKEh88Ggx9KwWwFCo
// SIG // U5mosk7HIk6WUgEWmam860Y0+QLlnyV0bxoKm+AU2j+M
// SIG // NZ5PkWJbnd0CP0qdnGmxDc9/l9HNIYdFzEQw51chXMMn
// SIG // BxlRfRyN/GdrvJ02/x5cH9eTobpLKtHY4fpLUscxbXWb
// SIG // dS8oX54uMg+XjmvGKa4MKgR35p3SU4BcDn+9k4o3mf94
// SIG // 9h4/QtFyFlfRDofyf9mZI8yVuWLcw7znVDT1GZP9kYdr
// SIG // 78V3L5YsOvBxjKRX2ZTL/hNvArDoW11Hpk8fEx0iLWmT
// SIG // xjaYL8bMKrQsKwfS5MV5DpDs1zcxGYRH/eYtZSFtpYeB
// SIG // fUVthyG9HbZv4G6n5g9HlD/QGFpoA3oAgF9waz67+cmg
// SIG // gHLJkoDxxPIKadQj/i9boPi/LCDdcEV/h/YPAUfL96+w
// SIG // L7nwoyX6TbBrTlfaQrRP9sI8uFqi/1lfKhtrB804tgaJ
// SIG // q4pPYVa9vBnMcgUJPGMHDDo+3m5G8IT+OdRx//GGU4Yy
// SIG // fqIo71e3j29lMTZJ8gGT/fiItNEEnoftoY9NNCfNrc59
// SIG // a7X91HJwLpaXmiezc+OcZdNIpLFeWUk+aDpH+6Uaic/9
// SIG // QJignqY34ReN/IMs9cuqyv3X5VMbWtjNEKM/AEUAe/gQ
// SIG // jBoTRqMKt/vl5QYjf6hdTRQ/quWhnzCCB3EwggVZoAMC
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
// SIG // BRDBcQZqELQdVTNYs6FwZvKhggNYMIICQAIBATCCAQGh
// SIG // gdmkgdYwgdMxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
// SIG // YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
// SIG // VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNV
// SIG // BAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMg
// SIG // TGltaXRlZDEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNO
// SIG // OjU1MUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3Nv
// SIG // ZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4D
// SIG // AhoDFQCGhXqvj0zgYF3jUrVFgHVnR/jO4KCBgzCBgKR+
// SIG // MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5n
// SIG // dG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
// SIG // aWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1p
// SIG // Y3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqG
// SIG // SIb3DQEBCwUAAgUA7KOSxjAiGA8yMDI1MTAyMjE3Mjgz
// SIG // OFoYDzIwMjUxMDIzMTcyODM4WjB2MDwGCisGAQQBhFkK
// SIG // BAExLjAsMAoCBQDso5LGAgEAMAkCAQACAW0CAf8wBwIB
// SIG // AAICEtgwCgIFAOyk5EYCAQAwNgYKKwYBBAGEWQoEAjEo
// SIG // MCYwDAYKKwYBBAGEWQoDAqAKMAgCAQACAwehIKEKMAgC
// SIG // AQACAwGGoDANBgkqhkiG9w0BAQsFAAOCAQEAGho0RcM/
// SIG // BoGqYD/t3w9biTFIwXGX0td2Sgins2CQZdiOlynitKzJ
// SIG // 5ZTd5XhArwKasBkWi9EbX0qkTqTtMyI9DLmYRDucLmNg
// SIG // d/giEuSOet/eKP2Wqcpbc96SUGZIPyynQVRKVA+yyirW
// SIG // kduXpzwSHpmIvvEgzPVqzU9seONBkoYYaA4pHGLt+c9P
// SIG // SX9gsEod0LA0kyzMSSo2MIO+KL/op2s/ONd2pqQsdY9O
// SIG // nwhf0oKOdR1cYiWr9hal6zl6xkFlyhbWzuCZATRW95h+
// SIG // wQ1pDJg/h7nQErDnany7CJPgjEx9WX1ABhEmx+iNznyw
// SIG // TFw+o2cUUEGV0Qst15PYvO8BozGCBA0wggQJAgEBMIGT
// SIG // MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5n
// SIG // dG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
// SIG // aWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1p
// SIG // Y3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAAC
// SIG // G9CyuAJn93LPAAEAAAIbMA0GCWCGSAFlAwQCAQUAoIIB
// SIG // SjAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJ
// SIG // KoZIhvcNAQkEMSIEIBviTjbdIToXpqOlrMBF8eEQ/rA/
// SIG // +jhgtdGbCzBt4BDZMIH6BgsqhkiG9w0BCRACLzGB6jCB
// SIG // 5zCB5DCBvQQgMCUUlbg9o5jHEAhV3S7iQMA6VFTWem3O
// SIG // nXyVPN0Ni4AwgZgwgYCkfjB8MQswCQYDVQQGEwJVUzET
// SIG // MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
// SIG // bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
// SIG // aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFt
// SIG // cCBQQ0EgMjAxMAITMwAAAhvQsrgCZ/dyzwABAAACGzAi
// SIG // BCBUkprOMBrPIL/n0T1L4HR/JCuzc2g/raQ1CN3ZBcWB
// SIG // AzANBgkqhkiG9w0BAQsFAASCAgBQ/SnAQKC0wZx2t4Ws
// SIG // 6VpqRgs0ZUycpd29RoZTM6XRmlDLabGn7FkjAZvv9rVM
// SIG // s37OpAentKv3d0vzyQqMi98WUNZfoLs7Qsv1UF9Lv7md
// SIG // TOesm/lpCWDLkgtkLWr/M0b49XhccwOM9+JAUKmE6ARx
// SIG // Y3UDMOjuGFHBpd9fjkvC5g64KOhhiq2VrRyrQiUPoG/m
// SIG // K/3qHOPSmV/7rfJqjD/zGfYV4evv2vDMOVkNRDWZEXd1
// SIG // TF34LQT7/AgOEmM9Q1DwiK5YJKD+F63SDLV7ROdzeYnz
// SIG // NSKfkodexp2cWkDtke6S689U55ni0iTrO6hwdlUxDta3
// SIG // 4dE0ngPA7pbdkiFd8p2kpEUFv5G6N1XmOisKfreaTcXL
// SIG // +tYxM/pIbgVEywxprpxwT3k25UEnWEZGJnyugJh2zfed
// SIG // dAWv+eMAzgt3s6WqjiTl8qX93jpi/a2npIUeWrmhyk8j
// SIG // KOu6odaKmJhIqlAw5VPINXIcaMWnzQyBEMcHmeioRCjq
// SIG // 9EJVm6SXGbukJ7yuxzbcxBApYDszMibTEGyZ/5NVh504
// SIG // vJoewAD+mBhhPUPaSSmxxD1EbW/n2it9FIn6C4feud5N
// SIG // VedBI2FPRw/H9lrySuYnzeYI2OQl5TQd9MwAsyQ54Qhl
// SIG // dtOZHTJu8FFbXLyXvtbnp5NaXAw/6eEhXOHFXNa1qjWx
// SIG // 6IwCKg==
// SIG // End signature block
