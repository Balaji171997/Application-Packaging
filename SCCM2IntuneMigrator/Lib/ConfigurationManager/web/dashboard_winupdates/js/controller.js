-/// <dictionary target='parameter'>sce</dictionary>
/// <dictionary target='member'>bindto</dictionary>
/// <dictionary>bindto,sce</dictionary>

(function () {
    "use strict";

    var dashboard = angular.module("dashboard", []);

    dashboard.controller("dashboardController", function ($scope, $sce) {
        $scope.updateAge = "15";
		$scope.categoryString = "init";
		$scope.showForm = true;
        $scope.sliderValue = "15";
        $scope.olderDaysInterval = "30";
        $scope.all = "All";
        $scope.strings;
        // selected categories
        $scope.selection = [];
        
		adminUI.initializeController($scope, async function () { 
            await LoadDataAsync();
            
			if ($scope.brightness < 125) {
				
				SetColorToAllTextInChart('#updatesComplianceDonut', $scope.theme.ForeGroundColor);
				SetColorToAllTextInChart('#topMissingUpdatesChart', $scope.theme.ForeGroundColor);
                SetColorToAllTextInChart("#missingUpdatesByCategoryChart", $scope.theme.ForeGroundColor);
            }
			$scope.$apply();
		});

        async function LoadDataAsync() {
            //Load Data
            var updateAge = "15";
            var categoryString = "init";
            await callMethodAsync("InitData");
            await callMethodAsync("LoadData");

            $scope.getString = function (stringName) {
                return $scope.strings[stringName];
            };

            $scope.categories = await callJsonParseMethodAsync("GetCategories");
            $scope.updatesComplianceData = await callJsonParseMethodAsync("GetUpdatesComplianceData", JSON.stringify([updateAge, categoryString]));
            $scope.topMissingUpdatesData = await callJsonParseMethodAsync("GetTopMissingUpdatesData");
            $scope.missingUpdatesByCategoryData = await callJsonParseMethodAsync("GetMissingUpdatesByCategory");
            $scope.tiles = await callJsonParseMethodAsync("GetNumericTiles");
            $scope.colors = await callJsonParseMethodAsync("GetColorInfo");
            $scope.initColor = await callMethodAsync("GetColorFromCategory", JSON.stringify(["", "0"]));
            $scope.updateNames = await callJsonParseMethodAsync("GetUpdateNames");
            
            // watch categories for changes
            $scope.$watch('categories|filter:{selected:true}', function (nv) {
                $scope.selection = nv.map(function (cat) {
                    return cat.name;
                });
            }, true);

            $scope.createDonutChart("#updatesComplianceDonut", $scope.updatesComplianceData);
            $scope.createBarChart("#topMissingUpdatesChart", $scope.topMissingUpdatesData);
            $scope.createPieChart("#missingUpdatesByCategoryChart", $scope.missingUpdatesByCategoryData);

            $scope.$apply();
        };

        $scope.getColors = function (value) {
            if (value) {
                return $scope.colors[value];
            }
            return $scope.initColor;
        };

        $scope.getUpdateName = function (category, value) {
            try {
                if ($scope.updateNames[category]) {
                    return $scope.updateNames[category][value].LocalizedDisplayName;
                }
                if ($scope.updateNames[$scope.all][value]) {
                    return $scope.updateNames[$scope.all][value].LocalizedDisplayName;
                }
                return;
            }
            catch(err) {
                console.log(err)
                return;
            }
        };


        // helper method to get selected categories
        $scope.selectedCats = function selectedCats() {
            return filterFilter($scope.categories, { selected: true });
        };

        // Checks if value is null, 0, undefinded, "" or []
        function isEmpty(value) {
            return (value == 0 || value == null || value.length === 0 || isNaN(value));
        }

        function noDataInColumns(columns) {
            var noData = true;
            for (var i = 0; i < columns.length; i++) {
                if (!isEmpty(columns[i][1])) {
                    noData = false;
                    break;
                }
            }

            return noData
        }
        $scope.queryCompleted = async function (id) {
            return await callJsonParseMethodAsync("IsQueryDataCompleted", id);
        }

        $scope.toggle = function (value) {
            $scope[value] = !$scope[value];
        };

        $scope.alertClick = async function () {
            await callMethodAsync("OnCriticalAlertClick");
        }

        $scope.getTileImage = function (tileType) {
            return tileType.toLowerCase() + ".svg";
        };

        $scope.refreshDonutData = async function () {
            $scope.donutChart.load({ columns: await callJsonParseMethodAsync("GetUpdatesComplianceData", JSON.stringify([$scope.updateAge, $scope.categoryString])) });

            $scope.$apply();
        }

        $scope.refreshUpdatesByCatCharts = async function () {
            $scope.pieChart.load({ columns: await callJsonParseMethodAsync("GetMissingUpdatesByCategory") });
            $scope.barChart.load({ columns: await callJsonParseMethodAsync("GetTopMissingUpdatesData", null) });
            $scope.categories = await callJsonParseMethodAsync("GetCategories");

            $scope.$apply();
        }

        $scope.applyFilters = async function () {
            var filteredData = await callJsonParseMethodAsync("GetUpdatesComplianceData", JSON.stringify([String($scope.sliderValue), String($scope.selection)]));
            $scope.donutChart.load({ columns: filteredData });
        }

        $scope.handleSliderChange = function () {
            //slider handling
            var sliderVal = document.getElementById('older-than-label-slider').value;
            $scope.sliderValue = sliderVal;
            var newSliderValue = $scope.sliderValue;
            var sliderLabelElement = document.getElementById('slider-value-label');
            sliderLabelElement.textContent = newSliderValue;
        };

        $scope.createDonutChart = function (idToBindTo, columns) {
            var enable = true;
            var noData = noDataInColumns(columns);
            var pattern = ["#00BDF3", "#FE0101"];

            if (noData) {
                enable = false;
                pattern = ["#a9a9a9"];
                columns = [['', 1]];
            }

            $scope.donutChart = c3.generate({
                bindto: idToBindTo,
                data: {
                    columns: columns,
                    type: "donut"
                },
                interaction: {
                    enabled: enable
                },
                legend: {
                    position: "bottom",
                    show: enable,
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
                        },
                    },
                    expand: enable,

                },
            });

            //draw initial slider label with initial values.
            var newSliderValue = $scope.sliderValue;
            var sliderLabelElement = document.getElementById('slider-value-label');
            sliderLabelElement.textContent = newSliderValue;
            document.getElementById('older-than-label-slider').max = $scope.olderDaysInterval;
            document.getElementById('older-than-label-slider').AriaValueMax = $scope.olderDaysInterval;
        };

        $scope.createBarChart = async function (idToBindTo, columns) {
            $scope.barChart = c3.generate({
                bindto: idToBindTo,
                bar: {
                    width: {
                        ratio: 0.5
                    }

                },
                data: {
                    x: columns[0][0],
                    columns: columns,
                    type: 'bar',
                    color: function (color, d) {
                        return $scope.getColors($scope.selectedCat);
                    },
                    labels: true,
                    onclick: async function (d) { await callMethodAsync("OnUpdateClick", JSON.stringify([$scope.selectedCat, d.x])); }
                },
                axis: {
                    x: {
                        type: 'category',
                    },
                },
                legend: {
                    show: false
                },
                tooltip: {
                    grouped: false,
                    contents: function (d, defaultTitleFormat, defaultValueFormat, color) {
                        var $$ = this, config = $$.config,
						    titleFormat = config.tooltip_format_title || defaultTitleFormat,
						    nameFormat = config.tooltip_format_name || function (value) { return value; },
						    valueFormat = config.tooltip_format_value || function (d, id) {
                                var updateFullName = $scope.getUpdateName($scope.selectedCat, d.x);
                                return updateFullName;
						    },
						    text, i, title, value, name, bgcolor;
                        for (i = 0; i < d.length; i++) {
                            if (!(d[i] && (d[i].value || d[i].value === 0))) { continue; }

                            if (!text) {
                                title = titleFormat ? titleFormat(d[i].x) : d[i].x;
                                text = "<table class='" + $$.CLASS.tooltip + "'>" + (title || title === 0 ? "<tr><th colspan='2'>" + title + "</th></tr>" : "");
                            }

                            name = nameFormat(d[i].value);
                            value = valueFormat(d[i], d[i].id);
                            bgcolor = $$.levelColor ? $$.levelColor(d[i].value) : color(d[i].id);

                            text += "<tr class='" + $$.CLASS.tooltipName + "-" + d[i].id + "'>";
                            text += "<td class='name'><span style='background-color:" + bgcolor + "'></span>" + name + "</td>";
                            text += "<td class='value'>" + value + "</td>";
                            text += "</tr>";
                        }
                        return text + "</table>";
                    }
                },
                size: {

                    width: 875,
                    height: 245
                }
            });
        };

        $scope.selectedCat = "";
        $scope.createPieChart = async function (idToBindTo, columns) {
            var enable = true;
            var noData = noDataInColumns(columns);
            var pattern = ["#0072C6", "#00188F", "#05DBCF", "#6DC2E9"];

            if (noData) {
                enable = false;
                pattern = ["#a9a9a9"];
                columns = [['', 1]];
            }

            $scope.pieChart = c3.generate({
                bindto: idToBindTo,
                data: {
                    columns: columns,
                    type: "pie",
                    onclick: async function (d) {
                        if ($scope.selectedCat == d.name) {
                            $scope.selectedCat = "";
                        }
                        else {
                            $scope.selectedCat = d.name;
                        }
                        var filteredData = await callJsonParseMethodAsync("GetTopMissingUpdatesData", $scope.selectedCat);
                        $scope.updateNames = await callJsonParseMethodAsync("GetUpdateNames");
                        $scope.barChart.load({ columns: filteredData });
                    },
                    selection: {
                        enabled: enable,
                        multiple: false
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
                pie: {
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
        
    });
}());
// SIG // Begin signature block
// SIG // MIInywYJKoZIhvcNAQcCoIInvDCCJ7gCAQExDzANBglg
// SIG // hkgBZQMEAgEFADB3BgorBgEEAYI3AgEEoGkwZzAyBgor
// SIG // BgEEAYI3AgEeMCQCAQEEEBDgyQbOONQRoqMAEEvTUJAC
// SIG // AQACAQACAQACAQACAQAwMTANBglghkgBZQMEAgEFAAQg
// SIG // 8rUkJjdUsMuxD+Ixhid5fkDZ3aSP05yTi5kD8L5+m3yg
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
// SIG // ARUwLwYJKoZIhvcNAQkEMSIEIO2+rUBk4wgtBfYW/Tu8
// SIG // KGseXLoNP0NXGrVLQj3XzTHkMEIGCisGAQQBgjcCAQwx
// SIG // NDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRw
// SIG // Oi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEB
// SIG // BQAEggEANOsljs4cmEPEGflNAUzq1uUV5QD+zrTLv/N8
// SIG // iwds6dI36GaUsUtbioCSd3eS0V+ppxCDzdo1QX+0+/gG
// SIG // YGdnFIffPJBZyucMP5Uwaf6ilqS9m/6gPJRDU8MXyVEF
// SIG // dtPKCr7Z1f1aGDd4UirF13AhjCiLRiG8aZUDtEynhpq7
// SIG // bI/Z7me2Obt52iuS75g6HaQOJ/tUI/B+ndnXlFQ4QHPx
// SIG // +jC34iIB23v9fR7Oc25orlFEPdAdkRyNu2FI8nO9+mh3
// SIG // p2RLscVpPqgJ3Vpo5h8pAZ0dXUNk8+i2yDamUUflf9Rf
// SIG // IHSY/vJdC3TE3vkwVYFHt+eBH4QxnwyiXlnTfyGc7aGC
// SIG // FywwghcoBgorBgEEAYI3AwMBMYIXGDCCFxQGCSqGSIb3
// SIG // DQEHAqCCFwUwghcBAgEDMQ8wDQYJYIZIAWUDBAIBBQAw
// SIG // ggFZBgsqhkiG9w0BCRABBKCCAUgEggFEMIIBQAIBAQYK
// SIG // KwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCCJEctF
// SIG // A8vvQZwtBFXBtDcXLiNs0uk49HdgBVsx3LIOtQIGY2Pf
// SIG // aYHVGBMyMDIyMTEwNDE3MjM0MC4zNjdaMASAAgH0oIHY
// SIG // pIHVMIHSMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
// SIG // aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
// SIG // ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQL
// SIG // EyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExp
// SIG // bWl0ZWQxJjAkBgNVBAsTHVRoYWxlcyBUU1MgRVNOOkZD
// SIG // NDEtNEJENC1EMjIwMSUwIwYDVQQDExxNaWNyb3NvZnQg
// SIG // VGltZS1TdGFtcCBTZXJ2aWNloIIRezCCBycwggUPoAMC
// SIG // AQICEzMAAAG59gANZVRPvAMAAQAAAbkwDQYJKoZIhvcN
// SIG // AQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
// SIG // c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
// SIG // BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UE
// SIG // AxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAw
// SIG // HhcNMjIwOTIwMjAyMjE3WhcNMjMxMjE0MjAyMjE3WjCB
// SIG // 0jELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
// SIG // b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
// SIG // Y3Jvc29mdCBDb3Jwb3JhdGlvbjEtMCsGA1UECxMkTWlj
// SIG // cm9zb2Z0IElyZWxhbmQgT3BlcmF0aW9ucyBMaW1pdGVk
// SIG // MSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVTTjpGQzQxLTRC
// SIG // RDQtRDIyMDElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUt
// SIG // U3RhbXAgU2VydmljZTCCAiIwDQYJKoZIhvcNAQEBBQAD
// SIG // ggIPADCCAgoCggIBAONJPslh9RbHyQECbUIINxMF5uQk
// SIG // yN07VIShITXubLpWnANgBCLvCcJl7o/2HHORnsRcmSIN
// SIG // J/qclAmLIrOjnYnrbocAnixiMEXC+a1sZ84qxYWtEVY7
// SIG // VYw0LCczY+86U/8shgxqsaezKpWriPOcpV1Sh8SsOxf3
// SIG // 0yO7jvld/IBA3T6lHM2pT/HRjWk/r9uyx0Q4atx0mkLV
// SIG // YS9y55/oTlKLE00h792S+maadAdy3VgTweiwoEOXD785
// SIG // wv3h+fwH/wTQtC9lhAxhMO4p+OP9888Wxkbl6BqRWXud
// SIG // 54RTzqp2Vr+yen1Q1A6umyMB7Xq0snIYG5B1Acc4UgJl
// SIG // PQ/ZiMkqgxQNFCWQvz0G9oLgSPD8Ky0AkX22PcDOboPu
// SIG // NT4RceWPX0UVZUsX9IUgs7QF41HiQSwEeOOHGyrfQdmS
// SIG // slATrbmH/18M5QrsTM5JINjct9G42xqN8VF9Z8WOiGMj
// SIG // NbvlpcEmmysYl5QyhrEDoFnQTU7bFrD3JX0fIfu1sbLW
// SIG // eBqXwbp4Z8yACTtphK2VbzOvi4vc0RCmRNzvYQQ2PjZ7
// SIG // NaTXE4Gu3vggAJ+rtzUTAfJotvOSqcMgNwLZa1Y+ET/l
// SIG // b0VyjrYwFuHtg0QWyQjP5350LTpv086pyVUh4A3w/Os5
// SIG // hTGFZgFe5bCyMnpY09M0yPdHaQ/56oYUsSIcyKyVAgMB
// SIG // AAGjggFJMIIBRTAdBgNVHQ4EFgQUt7A4cdtYQ5oJjE1Z
// SIG // qrSonp41RFIwHwYDVR0jBBgwFoAUn6cVXQBeYl2D9OXS
// SIG // ZacbUzUZ6XIwXwYDVR0fBFgwVjBUoFKgUIZOaHR0cDov
// SIG // L3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jcmwvTWlj
// SIG // cm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAo
// SIG // MSkuY3JsMGwGCCsGAQUFBwEBBGAwXjBcBggrBgEFBQcw
// SIG // AoZQaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9w
// SIG // cy9jZXJ0cy9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIw
// SIG // UENBJTIwMjAxMCgxKS5jcnQwDAYDVR0TAQH/BAIwADAW
// SIG // BgNVHSUBAf8EDDAKBggrBgEFBQcDCDAOBgNVHQ8BAf8E
// SIG // BAMCB4AwDQYJKoZIhvcNAQELBQADggIBAM3cZ7NFUHRM
// SIG // sLKzjl7rJPIkv7oJ+s9kkut0hZif9WSt60SzYGULp1zm
// SIG // dPqc+w8eHTkhqX0GKCp2TTqSzBXBhwHOm8+p6hUxNlDe
// SIG // wGMZUos952aTXblAT3OKBnfVBLQyUavrSjuJGZAW30cN
// SIG // Y3rjVDUlGD+VygQHySaDaviJQbK6/6fQvUUFoqIk3ldG
// SIG // fjnAtnebsVlqh6WWamVc5AZdpWR1jSzN/oxKYqc1BG4S
// SIG // xxlPtcfrAdBz/cU4bxVXqAAf02NZscvJNpRnOALf5kVo
// SIG // 2HupJXCsk9TzP5PNW2sTS3TmwhIQmPxr0E0UqOojUrBJ
// SIG // UOhbITAxcnSa/IMluL1HXRtLQZI+xs2eRtuPOUsKUW71
// SIG // /1YeqsYCLHLvu82ceDVQQvP7GHEEkp2kEjiofbjYErBo
// SIG // 2iCEaxxeX4Z9HvAgA4MsQkbn6e4EFQf13sP+Kn3XgMIv
// SIG // JbqLJeFcQja+SUeOXu5cfkxe0GzTNojdyIwzaHlhOflV
// SIG // RZNrxee3B+yZwd3JHDIvv71uSI/SIzzt9cU2GyHQVqxB
// SIG // SrRtKW6W8Vw7zpVvoVsIv3ljxg+7NiGSlXX1s7zbBNDM
// SIG // Uj9OnzOlHK/3mrOU8YEuRf6RwakW5UCeGamy5MiKu2Yu
// SIG // yKiGBCv4OGhPstNe7ALkEOh8BX12t4ntuYu+gw9L6yCP
// SIG // Y0jWYaQtzAP9MIIHcTCCBVmgAwIBAgITMwAAABXF52ue
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
// SIG // VQQLEx1UaGFsZXMgVFNTIEVTTjpGQzQxLTRCRDQtRDIy
// SIG // MDElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAg
// SIG // U2VydmljZaIjCgEBMAcGBSsOAwIaAxUAx2IeGHhk58MQ
// SIG // kzzSWknGcLjfgTqggYMwgYCkfjB8MQswCQYDVQQGEwJV
// SIG // UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMH
// SIG // UmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
// SIG // cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1T
// SIG // dGFtcCBQQ0EgMjAxMDANBgkqhkiG9w0BAQUFAAIFAOcP
// SIG // r1kwIhgPMjAyMjExMDQyMzMzNDVaGA8yMDIyMTEwNTIz
// SIG // MzM0NVowdzA9BgorBgEEAYRZCgQBMS8wLTAKAgUA5w+v
// SIG // WQIBADAKAgEAAgIiQwIB/zAHAgEAAgIRhDAKAgUA5xEA
// SIG // 2QIBADA2BgorBgEEAYRZCgQCMSgwJjAMBgorBgEEAYRZ
// SIG // CgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqG
// SIG // SIb3DQEBBQUAA4GBALUhW0rAJUav0fSn2rVzws1tNm/+
// SIG // ilf/XXNQ+IM/ZgYf57j+qAYupAszZAPn6YGMXHLI4YJs
// SIG // HIlQhz0PgEOjih2uuLS+pb6y/O4U7iTcW+dqm8qulKhP
// SIG // x2SVseCOop0i023QcrJW1UOe6gkyPaA2PJtCW04hC98q
// SIG // 0yD8oTK6UFwtMYIEDTCCBAkCAQEwgZMwfDELMAkGA1UE
// SIG // BhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNV
// SIG // BAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
// SIG // b3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRp
// SIG // bWUtU3RhbXAgUENBIDIwMTACEzMAAAG59gANZVRPvAMA
// SIG // AQAAAbkwDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3
// SIG // DQEJAzENBgsqhkiG9w0BCRABBDAvBgkqhkiG9w0BCQQx
// SIG // IgQgtvOcFLnmVG3aEHRzO5lNFzeTHhcD6H6hHpiSBiFu
// SIG // V1wwgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCBk
// SIG // 60bO8W85uTAfJVEO3vX2aLaQFcgcGpdwsOoi+foP9DCB
// SIG // mDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
// SIG // YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
// SIG // VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNV
// SIG // BAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEw
// SIG // AhMzAAABufYADWVUT7wDAAEAAAG5MCIEIEpB3xr7eyxp
// SIG // TDMMf8hGiLLzDeIEhxmj1CIruH9UfJ8sMA0GCSqGSIb3
// SIG // DQEBCwUABIICAJ6FmUO1d1Z4ksYvkp1G5NXwCkMZcE1n
// SIG // +iXoOb8rH4+nPtyshWYkbBuHgzdxg/ooh8e5ztq13Xqf
// SIG // WXfffQfjnEgREkuRSaKRuzJuAVp4sPhg3YNsL6sayRjD
// SIG // bDwBJD6pi3npJk1uIwKvoUTkLBxtbQwTmoc1EPv7A+1F
// SIG // iw8GP5kAfmOGcGf1lJ7p4RP7HGJYIte4EB74Obta43cq
// SIG // 5mJjfgHKzu2SEDcsdsPOhLdXoD5/BSZNqJ9M6w9bcmMs
// SIG // vYk/Sy5m6Ix3NEa/owkzTHYcQGWVZ2oajqE69Hzt2mzN
// SIG // h8pwLUMYtN5rTvqfLTzTm7XYehC1P1rgCKlrf2H4/ofr
// SIG // +AiJjUMYY4cGyeA7MbWY2Hcuk8bbNfM8DhFY223RniBz
// SIG // PWPaoyrwyP7T0WXlrN4E3UwDvSxxOVJB1/A8aWWRrX7e
// SIG // UwSSiTDqaVfGn42PSWBJQ90ai5kTFfwwZT0tZ1OqEVmg
// SIG // UF4h5+j9cdli+E0CWJKHSWOoYPCkxQUtXYhhHj7QjYt3
// SIG // 1ldKLmshzwRAuiX/kuypbzAwMKR+ONP95FHFcssMhUpO
// SIG // 7T38W3mA7neDCz0QPVBuGBSpgl9x6AIjPDAcyZLwdpU7
// SIG // TmgaCJufV1Y2kOQM1ISCZAHYaP8t2Fl0iBalokQxYl7Q
// SIG // cdNXk870PdIwo59whFnJ5iIJcpVWjhzffnZR
// SIG // End signature block
