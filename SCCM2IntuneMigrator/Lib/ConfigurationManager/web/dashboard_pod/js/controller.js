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
			
			angular.element(document).ready(function () {
				$scope.PhasesChartData.forEach(function (phase) {
					$scope.createBarChart(phase.PhaseID, phase);
				});
				$scope.phaseChanged();
			});
			
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
// SIG // MIInyAYJKoZIhvcNAQcCoIInuTCCJ7UCAQExDzANBglg
// SIG // hkgBZQMEAgEFADB3BgorBgEEAYI3AgEEoGkwZzAyBgor
// SIG // BgEEAYI3AgEeMCQCAQEEEBDgyQbOONQRoqMAEEvTUJAC
// SIG // AQACAQACAQACAQACAQAwMTANBglghkgBZQMEAgEFAAQg
// SIG // 9sLFGDuopKehkuV3EWpgcMv2Gp0Krc6vy/uvm1g5GEGg
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
// SIG // SEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCGZ8w
// SIG // ghmbAgEBMIGVMH4xCzAJBgNVBAYTAlVTMRMwEQYDVQQI
// SIG // EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
// SIG // HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAm
// SIG // BgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENB
// SIG // IDIwMTECEzMAAALMjrWWpr3RyU4AAAAAAswwDQYJYIZI
// SIG // AWUDBAIBBQCgga4wGQYJKoZIhvcNAQkDMQwGCisGAQQB
// SIG // gjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcC
// SIG // ARUwLwYJKoZIhvcNAQkEMSIEIKqyVKeEMMWdQiJyoGGm
// SIG // 3LV6wygIkvf4vnKi5wT7zNQAMEIGCisGAQQBgjcCAQwx
// SIG // NDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRw
// SIG // Oi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEB
// SIG // BQAEggEAGDGirVwluxgvGaV3pSHYIfXqGMKvrmedg/IB
// SIG // 6iXWwjwIG3A6lc+pCOfTKNqYZcxcrL8a4TnXpllorclN
// SIG // ugoZ444Vdzy1jGwKDR2tos/tMgsj+ZnprMW/GUuiNf4A
// SIG // 4MnXTL0dT5CQFzfruO1GTOHpHi+j5s9AsTgGxAg657Rt
// SIG // M+d1ikRVoalmIa3AZYMefIqVOB7vO1sv3YxiQcBhlaDu
// SIG // Aqy1NU1Gu0WnShlJiC12T+XkKMPMZsuj5XEgGWv/Ng5a
// SIG // cdSyTjDxFXEg5KWkDG96gUTd+HvnlcGGPSDDpzB9lS8Q
// SIG // rbomIDrQjZW+BLKIUNu4e5CS6QdCCa2PHeQdwxm/RaGC
// SIG // FykwghclBgorBgEEAYI3AwMBMYIXFTCCFxEGCSqGSIb3
// SIG // DQEHAqCCFwIwghb+AgEDMQ8wDQYJYIZIAWUDBAIBBQAw
// SIG // ggFZBgsqhkiG9w0BCRABBKCCAUgEggFEMIIBQAIBAQYK
// SIG // KwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCA08bfM
// SIG // stl+Qk5kfPkyXZkWqHx2485Hm5PYO930CcDs6QIGY2Ph
// SIG // hC7KGBMyMDIyMTEwNDE3MjMzOS4xODdaMASAAgH0oIHY
// SIG // pIHVMIHSMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
// SIG // aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
// SIG // ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQL
// SIG // EyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExp
// SIG // bWl0ZWQxJjAkBgNVBAsTHVRoYWxlcyBUU1MgRVNOOkQw
// SIG // ODItNEJGRC1FRUJBMSUwIwYDVQQDExxNaWNyb3NvZnQg
// SIG // VGltZS1TdGFtcCBTZXJ2aWNloIIReDCCBycwggUPoAMC
// SIG // AQICEzMAAAG6Hz8Z98F1vXwAAQAAAbowDQYJKoZIhvcN
// SIG // AQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
// SIG // c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
// SIG // BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UE
// SIG // AxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAw
// SIG // HhcNMjIwOTIwMjAyMjE5WhcNMjMxMjE0MjAyMjE5WjCB
// SIG // 0jELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
// SIG // b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
// SIG // Y3Jvc29mdCBDb3Jwb3JhdGlvbjEtMCsGA1UECxMkTWlj
// SIG // cm9zb2Z0IElyZWxhbmQgT3BlcmF0aW9ucyBMaW1pdGVk
// SIG // MSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVTTjpEMDgyLTRC
// SIG // RkQtRUVCQTElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUt
// SIG // U3RhbXAgU2VydmljZTCCAiIwDQYJKoZIhvcNAQEBBQAD
// SIG // ggIPADCCAgoCggIBAIhOFYMzkjWAE9UVnXF9hRGv0xBR
// SIG // xc+I5Hu3hxVFXyK3u38xusEb0pLkwjgGtDsaLLbrlMxq
// SIG // X3tFb/3BgEPEC3L0wX76gD8zHt+wiBV5mq5BWop29qRr
// SIG // gMJKKCPcpQnSjs9B/4XMFFvrpdPicZDv43FLgz9fHqMq
// SIG // 0LJDw5JAHGDS30TCY9OF43P4d44Z9lE7CaVS2pJMF3L4
// SIG // 53MXB5yYK/KDbilhERP1jxn2yl+tGCRguIAsMG0oeOhX
// SIG // aw8uSGOhS6ACSHb+ebi0038MFHyoTNhKf+SYo4OpSY3x
// SIG // P4+swBBTKDoYP1wH+CfxG6h9fymBJQPQZaqfl0riiDLj
// SIG // mDunQtH1GD64Air5k9Jdwhq5wLmSWXjyFVL+IDfOpdix
// SIG // J6f5o+MhE6H4t31w+prygHmd2UHQ657UGx6FNuzwC+Sp
// SIG // AHmV76MZYac4uAhTgaP47P2eeS1ockvyhl9ya+9JzPfM
// SIG // kug3xevzFADWiLRMr066EMV7q3JSRAsnCS9GQ08C4FKP
// SIG // bSh8OPM33Lng0ffxANnHAAX/DE7cHcx7l9jaV3Acmkj7
// SIG // oqir4Eh2u5YxwiaTE37XaMumX2ES3PJ5NBaXq7YdLJwy
// SIG // SD+U9pk/tl4dQ1t/Eeo7uDTliOyQkD8I74xpVB0T31/6
// SIG // 7KHfkBkFVvy6wye21V+9IC8uSD++RgD3RwtN2kE/AgMB
// SIG // AAGjggFJMIIBRTAdBgNVHQ4EFgQUimLm8QMeJa25j9MW
// SIG // eabI2HSvZOUwHwYDVR0jBBgwFoAUn6cVXQBeYl2D9OXS
// SIG // ZacbUzUZ6XIwXwYDVR0fBFgwVjBUoFKgUIZOaHR0cDov
// SIG // L3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jcmwvTWlj
// SIG // cm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAo
// SIG // MSkuY3JsMGwGCCsGAQUFBwEBBGAwXjBcBggrBgEFBQcw
// SIG // AoZQaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9w
// SIG // cy9jZXJ0cy9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIw
// SIG // UENBJTIwMjAxMCgxKS5jcnQwDAYDVR0TAQH/BAIwADAW
// SIG // BgNVHSUBAf8EDDAKBggrBgEFBQcDCDAOBgNVHQ8BAf8E
// SIG // BAMCB4AwDQYJKoZIhvcNAQELBQADggIBAF/I8U6hbZhv
// SIG // Dcn96nZ6tkbSEjXPvKZ6wroaXcgstEhpgaeEwleLuPXH
// SIG // LzEWtuJuYz4eshmhXqFr49lbAcX5SN5/cEsP0xdFayb7
// SIG // U5P94JZd3HjFvpWRNoNBhF3SDM0A38sI2H+hjhB/VfX1
// SIG // XcZiei1ROPAyCHcBgHLyQrEu6mnb3HhbIdr8h0Ta7WFy
// SIG // lGhLSFW6wmzKusP6aOlmnGSac5NMfla6lRvTYHd28rbb
// SIG // CgfSm1RhTgoZj+W8DTKtiEMwubHJ3mIPKmo8xtJIWXPn
// SIG // Xq6XKgldrL5cynLMX/0WX65OuWbHV5GTELdfWvGV3DaZ
// SIG // rHPUQ/UP31Keqb2xjVCb30LVwgbjIvYS77N1dARkN8F/
// SIG // 9pJ1gO4IvZWMwyMlKKFGojO1f1wbjSWcA/57tsc+t2bl
// SIG // rMWgSNHgzDr01jbPSupRjy3Ht9ZZs4xN02eiX3eG297N
// SIG // rtC6l4c/gzn20eqoqWx/uHWxmTgB0F5osBuTHOe77DyE
// SIG // A0uhArGlgKP91jghgt/OVHoH65g0QqCtgZ+36mnCEg6I
// SIG // OhFoFrCc0fJFGVmb1+17gEe+HRMM7jBk4O06J+IooFrI
// SIG // 3e3PJjPrQano/MyE3h+zAuBWGMDRcUlNKCDU7dGnWvH3
// SIG // XWwLrCCIcz+3GwRUMsLsDdPW2OVv7v1eEJiMSIZ2P+M7
// SIG // L20Q8aznU4OAMIIHcTCCBVmgAwIBAgITMwAAABXF52ue
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
// SIG // oXBm8qGCAtQwggI9AgEBMIIBAKGB2KSB1TCB0jELMAkG
// SIG // A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAO
// SIG // BgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29m
// SIG // dCBDb3Jwb3JhdGlvbjEtMCsGA1UECxMkTWljcm9zb2Z0
// SIG // IElyZWxhbmQgT3BlcmF0aW9ucyBMaW1pdGVkMSYwJAYD
// SIG // VQQLEx1UaGFsZXMgVFNTIEVTTjpEMDgyLTRCRkQtRUVC
// SIG // QTElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAg
// SIG // U2VydmljZaIjCgEBMAcGBSsOAwIaAxUAdqNHe113gCJ8
// SIG // 7aZIGa5QBUqIwvKggYMwgYCkfjB8MQswCQYDVQQGEwJV
// SIG // UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMH
// SIG // UmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
// SIG // cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1T
// SIG // dGFtcCBQQ0EgMjAxMDANBgkqhkiG9w0BAQUFAAIFAOcP
// SIG // sXYwIhgPMjAyMjExMDQyMzQyNDZaGA8yMDIyMTEwNTIz
// SIG // NDI0NlowdDA6BgorBgEEAYRZCgQBMSwwKjAKAgUA5w+x
// SIG // dgIBADAHAgEAAgIDDDAHAgEAAgIRdTAKAgUA5xEC9gIB
// SIG // ADA2BgorBgEEAYRZCgQCMSgwJjAMBgorBgEEAYRZCgMC
// SIG // oAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3
// SIG // DQEBBQUAA4GBAF7P2VmK9E7u9eQPQl8zrH/2faSve+Ee
// SIG // 503loMwa+OCfGVZUczGM9r8dvRRzjI9DYot1Xscfwlf9
// SIG // LnGskclgnp8DFyRS+2GgOywOVJNdlvHyJ2JcG5av4S8V
// SIG // c2N01LjqHBurqdWUCb/YYqA60Gi/zeRDmRALuzpfYs3Z
// SIG // msOL23aYMYIEDTCCBAkCAQEwgZMwfDELMAkGA1UEBhMC
// SIG // VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcT
// SIG // B1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
// SIG // b3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUt
// SIG // U3RhbXAgUENBIDIwMTACEzMAAAG6Hz8Z98F1vXwAAQAA
// SIG // AbowDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJ
// SIG // AzENBgsqhkiG9w0BCRABBDAvBgkqhkiG9w0BCQQxIgQg
// SIG // +VcMQAU2VVWEa/KX5/CwujXvJ8dx6eR/b8n4aYY1LUgw
// SIG // gfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCApVb08
// SIG // M25w+tYGWsmlGtp1gy1nPcqWfqgMF3nlWYVzBTCBmDCB
// SIG // gKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
// SIG // aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
// SIG // ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMT
// SIG // HU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMz
// SIG // AAABuh8/GffBdb18AAEAAAG6MCIEILveL+81/fgI1uLT
// SIG // 9XPqAMVR3MPdwkQQqt8OF70GQ6BiMA0GCSqGSIb3DQEB
// SIG // CwUABIICAAEB6BnXT9eaVF9tzvaElsFhXdU9sSHi7wJC
// SIG // MKhJdML0eOGKZ5YohCeUn7TfL4DzgYFjqs7a/1I07NxH
// SIG // +fF/9/AiinTcI4V3hvazjkmC5ftMXkKcxX0Z5cBxjvca
// SIG // rhnzWgxwVOxOr1YCtQIuVcS7hdTR1xNoFSOEuar+JD8z
// SIG // aypkvUvbCWqMIxp1Ju5m+HNNku19m0ulNBXfn9U/O92c
// SIG // OiH2BBVXyPY0sv5jLAzFVRl0qek2jk9GY9fC/+CHFbPS
// SIG // CKlgYWNDpsnWL7EudKXFMdFQcQxItQUATF5Ku4C+Ib8T
// SIG // 7wT3Ubkg3BQ+PZfMUvNo6MjQKwqrk4iDqjefiDkBDEtb
// SIG // gBINBQ1II8p126U9dxzWnYJgZt/obCd1dT06XgcDI5tw
// SIG // gPvfSBv/tWIYNnVtUo5FJ2aFIGWHTx5A3X7Bt/kTCcn/
// SIG // LEubA6+nKumf01k2gbHulymhpWc90D8SICHmCGU6RPAw
// SIG // g2JcZ/xtUwWXEsiJBeUK16PYrINPbUhAgPJMbFGhxbj+
// SIG // Dr0JPojdysh+/HwrECPhvlIhOG/Yf8sMFCX1+HfHorr0
// SIG // 2D8DLml4zG9M5srZ+zoVTc20ftYk73FsY5UTyl1tZkI+
// SIG // f4GxSbfndyqfC8XVAfOn8S0jBMRNtQz9zN6gFVvJN1Os
// SIG // VqSsLncmhYAPxvuhl4Zr4JXXoQqO0ymC
// SIG // End signature block
