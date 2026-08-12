(function () {
    "use strict";
    var dashboard = angular.module("dashboard", []);
    dashboard.controller("dashboardController", ['$scope', function ($scope) {
        $scope.ChartState = ChartState; // for use in ng-expressions in html
        $scope.CollectionsData = ChartState.Loading;
        $scope.EdgeDevicesData = ChartState.Loading;
        $scope.InstalledBrowsersData = ChartState.Loading;
        $scope.DefaultBrowsersData = ChartState.Loading;
        $scope.VersionsData = ChartState.Loading;
        $scope.UsageData = ChartState.Loading;

        adminUI.initializeController($scope, function () {
            //Load static data to be used in controller
            $scope.setupAria();

            // *** DATA QUERIES AND PREPARATION ***
            //gets collections data to load the Collections dropdown filter
            adminUI.wmiQuery("SELECT CollectionID, Name, MemberCount FROM SMS_Collection Where CollectionType=2 ORDER BY LocalMemberCount DESC",
                SMS_DeviceCollectionsReceived);
        });

        $scope.getString = function (stringName) {
            return $scope.strings[stringName];
        };

        // *** VARIABLE DECLARATIONS
        var COLL_DISP_LIMIT = 5; // determines the amount of collections displayed in the dropdown filter
        $scope.SMS_DeviceCollections = {}; //temp storage for collections data
        var GetChartInfo = "GetChartInfo"; // C# Method Name
        var versionID = '#EdgeVersion';


        function SMS_DeviceCollectionsReceived(res) {
            res = JSON.parse(res);

            if (res.length == 0) {
                logger.err("SMS_Collection returned no results");
                $scope.CollectionsData = ChartState.NoDataFound;
                $scope.$apply();
                return;
            }

            // store first n number of results n = COLL_DISP_LIMIT and set default selected to first(largest) collection
            $scope.SMS_DeviceCollections.All = res.slice(0, COLL_DISP_LIMIT);
            $scope.SMS_DeviceCollections.Selected = res[0];

            for (var i = 0; i < $scope.SMS_DeviceCollections.All.length; ++i) {
                callMethod("GetCollectionAliasName", $scope.SMS_DeviceCollections.All[i].Name, function callback(response, returnCode) {
                    $scope.SMS_DeviceCollections.All[i].Name = JSON.parse(response);
                });
            }

            $scope.CollectionsData = ChartState.DataReady;
            $scope.SMS_DeviceCollectionChanged();

            $scope.$apply();
        };

        //*** DOM CHANGE HANDLERS
        // handle collection dropdown selection
        $scope.SMS_DeviceCollectionChanged = function () {
            $scope.EdgeDevicesData = ChartState.Loading;
            $scope.VersionsData = ChartState.Loading;
            $scope.InstalledBrowsersData = ChartState.Loading;
            $scope.DefaultBrowsersData = ChartState.Loading;
            $scope.UsageData = ChartState.Loading;
            // Load Chart Data
            getEdgeData($scope.SMS_DeviceCollections.Selected);
        };

        //*** CHART METHODS
        // launch wizard to pick a collection
        $scope.LaunchWizardCollectionPicker = async function () {
            try {
                // Collection is a string
                var collection = await callMethodAsync("LaunchWizardCollectionPicker", null);

                //get get collection object
                adminUI.wmiQuery("SELECT CollectionID, Name, MemberCount FROM SMS_Collection Where CollectionType=2 and CollectionID='" + collection + "'", function (res) {
                    res = JSON.parse(res);
                    if (res.length === 0) {
                        console.log("SMS_Collection returned no results");
                        return;
                    }

                    //Check if the item already exist in the dropdown
                    var selectedIndex = 0;
                    var listContainsCollection = $scope.SMS_DeviceCollections.All.some(function (item, index) {
                        if (item.CollectionID === collection) {
                            selectedIndex = index;
                            return true;
                        }
                        return false;
                    });

                    //If the item does not exists in the list, add it to the top and pop one from the buttom
                    if (!listContainsCollection) {
                        //Add the selected collection as the first item in the dropdown
                        $scope.SMS_DeviceCollections.All.unshift(res[0]);
                        //Localize the name
                        callMethod("GetCollectionAliasName", $scope.SMS_DeviceCollections.All[0].Name, function callback(response, returnCode) {
                            $scope.SMS_DeviceCollections.All[0].Name = JSON.parse(response);
                        });
                        // Only COLL_DISP_LIMIT items at a time should show in the drop down
                        if ($scope.SMS_DeviceCollections.All.length > COLL_DISP_LIMIT) {
                            $scope.SMS_DeviceCollections.All.pop();
                        }
                    }
                    // Update the selected item in the dropdown 
                    $scope.SMS_DeviceCollections.Selected = $scope.SMS_DeviceCollections.All[selectedIndex];
                    $scope.CollectionsData = ChartState.DataReady;
                    $scope.SMS_DeviceCollectionChanged();
                    $scope.$apply();
                });

            } catch (err) {
                console.log("launch Collection Picker wizard failed.");
            }
        };

        async function getEdgeData(collection) {
            var collID = collection.CollectionID;
            var collName = collection.Name;

            var edgeDevicesData = await callJsonParseMethodAsync(GetChartInfo, JSON.stringify([collID, "EdgeDevices"]));
            var versionsData = await callJsonParseMethodAsync(GetChartInfo, JSON.stringify([collID, "EdgeVersion"]));
            var installedBrowsersData = await callJsonParseMethodAsync(GetChartInfo, JSON.stringify([collID, "InstalledBrowsers"]));
            var defaultBrowsersData = await callJsonParseMethodAsync(GetChartInfo, JSON.stringify([collID, "DefaultBrowsers"]));
            var usageData = await callJsonParseMethodAsync(GetChartInfo, JSON.stringify([collID, "EdgeUsage"]));

            $scope.EdgeDevicesData = checkChartState(edgeDevicesData);
            $scope.VersionsData = checkChartState(versionsData);
            $scope.InstalledBrowsersData = checkChartState(installedBrowsersData);
            $scope.DefaultBrowsersData = checkChartState(defaultBrowsersData);
            $scope.UsageData = checkChartState(usageData);

            // Edge Device Counts
            var deviceCount = 0; // Total number devices in the collection
            var edgeCount = 0;

            edgeDevicesData.forEach(function (el) {
                deviceCount = el.DeviceCount;
                edgeCount = el.EdgeCount;
            })
            createGaugeChart(edgeCount, deviceCount, '#EdgeDevices');

            // Version objects
            var versions, versionCounts;
            versions = [];
            versionCounts = [];
            versionCounts.push($scope.getString("NumberOfDevices"));
            var pattern = ["#2F81DA", "#CF2321", "#F67F01", "#41A022", "#C9C9C9", "#3ECFAE"];

            // Version Counts
            var countDeviceVersion = 0;
            versionsData.forEach(function (el) {
                versions.push([el.ProductVersion00, Number(el.VersionCount)]);
                versionCounts.push(Number(el.VersionCount));
                countDeviceVersion += Number(el.VersionCount);
            })
            var edgeDiff = Number(edgeCount) - Number(countDeviceVersion);
            if (edgeDiff > 0) { // Place remaining version counts in Other
                versions.push([$scope.getString("Other"), edgeDiff]);
                versionCounts.push(edgeDiff);
            }
            createPieChart(versions, versionCounts, 0, versionID, pattern, $scope.getString("EdgeVersions"));
            
            // Installed Browser variables
            var browsersCounts, browsers;
            browsers = [];
            browsersCounts = [];
            browsersCounts.push($scope.getString("NumberOfDevices"));

            // Installed Browser Counts
            installedBrowsersData.forEach(function (el) {
                browsers.push(el.Browser);
                browsersCounts.push(Number(el.BrowserCount));
            })
            createBarChart(browsers, browsersCounts, '#InstalledBrowsers', '#0E549C', $scope.getString("InstalledBrowsers"));

            //Default Brpwser
            var defaults, defaultCounts;
            defaults = [];
            defaultCounts = [];
            defaultCounts.push($scope.getString("NumberOfDevices"));

            // Default Counts
            var countDeviceDefault = 0;
            var totCount = 0;
            defaultBrowsersData.forEach(function (el) {
                if (el.DefaultBrowser.trim() == "Total")
                    totCount = Number(el.BrowserCount);
                else {
                    if (el.DefaultBrowser.trim() != "No default")
                        defaults.push(el.DefaultBrowser);
                    else
                        defaults.push($scope.getString("NoDefault"));

                    defaultCounts.push(Number(el.BrowserCount));
                    countDeviceDefault += Number(el.BrowserCount);
                }
            })
            var countDiff = Number(totCount) - Number(countDeviceDefault)
            if (countDiff > 0) { // Place remaining default counts in Other
                defaults.push($scope.getString("Other"));
                defaultCounts.push(countDiff);
            }
            createBarChart(defaults, defaultCounts, '#DefaultBrowsers', '#06AC21', $scope.getString("DefaultBrowser"));

            //Preferred Browser
            var browserNames, percentages;
            browserNames = [];
            percentages = [];
            var pattern = ["#4472C4", "#7030A0", "#2CA02C", "#0E549C", "#C9C9C9", "#3ECFAE"];

            // Browser Usage
            var countPercentages = 0;
            usageData.forEach(function (el) {
                countPercentages += Number(el.UsagePercentage);
                percentages.push([el.Browser, Number(el.UsagePercentage)]);
                browserNames.push(el.Browser);
            })
            createPieChart(percentages, browserNames, countPercentages, '#EdgeUsage', pattern, $scope.getString("PreferredBrowsers"));

            if ($scope.brightness < 125) {
                SetColorToAllTextInChart(versionID, $scope.theme.ForeGroundColor);
                SetColorToAllTextInChart("#EdgeDevices", $scope.theme.ForeGroundColor);
                SetColorToAllTextInChart("#InstalledBrowsers", $scope.theme.ForeGroundColor);
                SetColorToAllTextInChart("#DefaultBrowsers", $scope.theme.ForeGroundColor);
                SetColorToAllTextInChart("#EdgeUsage", $scope.theme.ForeGroundColor);
            }

            $scope.$apply();
        };

        function checkChartState(data) {

            if (data == null) {
                console.log("chart returned no results");
                return ChartState.NoDataFound;
            }
            return ChartState.DataReady;
        }

        //***** CHART GENERATORS ****
        // Devices with Edge
        function createGaugeChart(actual, maxValue, domNode) {
            var chart = document.querySelectorAll(domNode);
            var chartEl = angular.element(chart);
            var tileEl = chartEl.parent();
            tileEl.attr('tabindex', '1');

            var str = [];
            var num = Number(actual / maxValue) * 100;
            var dec = roundToDecimalPlaces(num, 1);
            str.push(dec + "%");
            var chartTitle = $scope.getString("DevicesWithEdge");
            var summaryText = chartTitle + ", " + str.join("");

            tileEl.attr('aria-label', summaryText);
            chartEl.attr('aria-label', summaryText);

            c3.generate({
                bindto: domNode,
                legend: {
                    hide: true
                },
                data: {
                    columns: [
                        [$scope.strings['Devices'], actual]
                    ],
                    type: 'gauge',
                },
                gauge: {
                    label: {
                        format: function (value) {
                            return d3.format("0.1%")(value / maxValue);
                        }
                    },

                    max: maxValue
                },
                color: {
                    pattern: ['#198919']
                },
                size: {
                    height: 180
                }
            });
        }

        // Bar Chart
        function createBarChart(data, counts, domNode, color, chartTitle) {
            var chart = document.querySelectorAll(domNode);
            var chartEl = angular.element(chart);
            var tileEl = chartEl.parent();
            tileEl.attr('tabindex', '1');

            var tickCount = 0;
            var max = 0;
            var x;

            // Graph Size
            var height = 250;
            var width = 300;

            // Set aria-label for accessibility
            var str = [];
            for (x = 0; x < data.length; x++) {
                if (x == data.length - 1)
                    str.push(data[x] + ": " + counts[x + 1]);
                else
                    str.push(data[x] + ": " + counts[x + 1] + ",  ");
            }
            var summaryText = chartTitle + ". " + str.join("");

            tileEl.attr('aria-label', summaryText);
            chartEl.attr('aria-label', summaryText);

            for (x = 1; x < counts.length; x++) { // Traverse indices
                if (counts[x] > max)
                    max = counts[x];
            }

            // Check which chart to generate
            if (max <= 10) // For small numbers, the tickCount ratio is malformed so we need to generate a more accurate one
                createSmallNumBarChart(data, counts, domNode, color, height, width);
            else {
                if (counts.length < 5)
                    tickCount = counts.length;
                else
                    tickCount = 5;

                c3.generate({
                    bindto: domNode,
                    legend: {
                        hide: true
                    },
                    bar: {
                        width: {
                            ratio: 0.5
                        }
                    },
                    data: {
                        columns: [counts],
                        type: 'bar'
                    },
                    color: {
                        pattern: [color]
                    },
                    axis: {
                        rotated: true,
                        x: {
                            type: 'category',
                            categories: data
                        },
                        y: {
                            label: $scope.strings['NumberOfDevices'],
                            tick: {
                                format: function (x) {
                                    return Math.floor(x);
                                },
                                count: tickCount
                            }
                        }
                    },
                    size: {
                        height: height,
                        width: width
                    }
                });
            }
        };

        // Small Num Bar Chart
        function createSmallNumBarChart(data, counts, domNode, color, height, width) {

            c3.generate({
                bindto: domNode,
                legend: {
                    hide: true
                },
                bar: {
                    width: {
                        ratio: 0.5
                    }
                },
                data: {
                    columns: [counts],
                    type: 'bar'
                },
                color: {
                    pattern: [color]
                },
                axis: {
                    rotated: true,
                    x: {
                        type: 'category',
                        categories: data
                    },
                    y: {
                        label: $scope.strings['NumberOfDevices'],
                        tick: {
                            format: function (x) {
                                if (x % 1 > 0) {
                                    return '';
                                }
                                return Math.floor(x);
                            }
                        }
                    }
                },
                size: {
                    height: height,
                    width: width
                }
            });
        };

        // Pie Chart
        function createPieChart(data, browsers, total, domNode, pattern, chartTitle) {
            var chart = document.querySelectorAll(domNode);
            var chartEl = angular.element(chart);
            var tileEl = chartEl.parent();
            tileEl.attr('tabindex', '1');

            // Set aria-label for accessibility
            var str = [];
            if (domNode == versionID)
                data.forEach(function (k, v) { str.push(k[0] + ": " + k[1] + ",  "); });
            else
                data.forEach(function (k, v) { str.push(k[0] + ": " + Math.round(k[1] / total * 100) + "%,  "); });
            var summaryText = chartTitle + ". " + str.join("");

            tileEl.attr('aria-label', summaryText);
            chartEl.attr('aria-label', summaryText);

            c3.generate({
                bindto: domNode,
                data: {
                    columns: data,
                    type: 'pie',
                    groups: [browsers]
                },
                legend: {
                    position: 'right'
                },
                color: {
                    pattern: pattern
                },
                pie: {
                    label: {
                        format: function (value, ratio) {
                            if (domNode == versionID)
                                return value
                            else
                                return d3.format(".0%")(value / total);
                        }
                    },
                    expand: true
                },
                tooltip: {
                    format: {
                        value: function (value, ratio, id) {
                            if (domNode == versionID)
                                return value
                            else
                                return d3.format(".0%")(value / total);
                        }
                    }
                },
                padding: {
                    bottom: 50
                },
                size: {
                    height: 280,
                    width: 400
                }
            });
        };

        // For accessibiltiy of body pane
        $scope.setupAria = function () {
            var EdgeClientsDashboardBodyArea = document.getElementById("EdgeClientsDashboardBody");
            EdgeClientsDashboardBodyArea.setAttribute("aria-label", $scope.strings._EdgeUpdatesDashboardTitle);

            var EdgeClientsDashboardBodyDivArea = document.getElementById("EdgeClientsDashboardBodyDiv");
            EdgeClientsDashboardBodyDivArea.setAttribute("aria-label", $scope.strings._EdgeUpdatesDashboardTitle);
        };
    }])
    
}());
// SIG // Begin signature block
// SIG // MIInywYJKoZIhvcNAQcCoIInvDCCJ7gCAQExDzANBglg
// SIG // hkgBZQMEAgEFADB3BgorBgEEAYI3AgEEoGkwZzAyBgor
// SIG // BgEEAYI3AgEeMCQCAQEEEBDgyQbOONQRoqMAEEvTUJAC
// SIG // AQACAQACAQACAQACAQAwMTANBglghkgBZQMEAgEFAAQg
// SIG // PXCJlCUaZho2q15C4ghXGtniHZM9VE5oeGyE+Bzjn7ig
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
// SIG // ARUwLwYJKoZIhvcNAQkEMSIEIDYlQgahlfFw9JX415mZ
// SIG // l9j0FTjHepOXJnIO2HmmcRUlMEIGCisGAQQBgjcCAQwx
// SIG // NDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRw
// SIG // Oi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEB
// SIG // BQAEggEASAr89+csBojbArjr28S65ND3OjF47rtdbXDm
// SIG // rIpSwKvChY+WnNIacv/K/HHEJOcy7jD5VsfmDvvzkIGF
// SIG // JOIrX7HocY0heJ2hKanPpj/is0f/gE2BAMtt5c2T57+x
// SIG // jE+HYX9dSjkkvqL0sQPE3QnRnJWACk2fp8rtc4Szo8ch
// SIG // jcAOFA+RaKthxwq9+Szm1ZrKN/HR1CVhHu2qj+f+3uuG
// SIG // Ulfs2dgYc9dKU8ahRctbqCydwxMKQS56ht+Ch4f7YK9n
// SIG // Vzf6xaGveqY+4BvRQYvdNY9LdlE3s8Ox+/ejMElqF092
// SIG // WwjhCLxVUzZAKVHIMZREZ8zOCB7FDrgd5XqmX+bCKqGC
// SIG // FywwghcoBgorBgEEAYI3AwMBMYIXGDCCFxQGCSqGSIb3
// SIG // DQEHAqCCFwUwghcBAgEDMQ8wDQYJYIZIAWUDBAIBBQAw
// SIG // ggFZBgsqhkiG9w0BCRABBKCCAUgEggFEMIIBQAIBAQYK
// SIG // KwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCB/Js+L
// SIG // RDLSt6aKJPA7nrVMBdExx/xlyvmFXxkPirVcDAIGY2LW
// SIG // uFa2GBMyMDIyMTEwNDE3MjM0MC40MzhaMASAAgH0oIHY
// SIG // pIHVMIHSMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
// SIG // aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
// SIG // ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQL
// SIG // EyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExp
// SIG // bWl0ZWQxJjAkBgNVBAsTHVRoYWxlcyBUU1MgRVNOOjE3
// SIG // OUUtNEJCMC04MjQ2MSUwIwYDVQQDExxNaWNyb3NvZnQg
// SIG // VGltZS1TdGFtcCBTZXJ2aWNloIIRezCCBycwggUPoAMC
// SIG // AQICEzMAAAG1rRrf14VwbRMAAQAAAbUwDQYJKoZIhvcN
// SIG // AQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
// SIG // c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
// SIG // BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UE
// SIG // AxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAw
// SIG // HhcNMjIwOTIwMjAyMjExWhcNMjMxMjE0MjAyMjExWjCB
// SIG // 0jELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
// SIG // b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
// SIG // Y3Jvc29mdCBDb3Jwb3JhdGlvbjEtMCsGA1UECxMkTWlj
// SIG // cm9zb2Z0IElyZWxhbmQgT3BlcmF0aW9ucyBMaW1pdGVk
// SIG // MSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVTTjoxNzlFLTRC
// SIG // QjAtODI0NjElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUt
// SIG // U3RhbXAgU2VydmljZTCCAiIwDQYJKoZIhvcNAQEBBQAD
// SIG // ggIPADCCAgoCggIBAJcLCrhlXoLCjYmFxcFPgkh57dmu
// SIG // z31sNsj8IlvmEZRCbB94mxSIj35P8m5TKfCRmp7bvuw4
// SIG // v/t3ucFjf52yVCDFIxFiZ3PCTI6D5hwlrDLSTrkf9Ubu
// SIG // GmtUa8ULSHpatPfEwZeJOzbBBPO5e6ihZsvIsBjUI5MK
// SIG // 9GzLuAScMuwVF4lx3oDklPfdq30OMTWaMc57+Nky0LHP
// SIG // TZnAauVrJZKlQE3HPD0n4ASxKXRtQ6dsKjcOCayRcCTQ
// SIG // NW3800nGAAXObJkWQYLD+CYiv/Ala5aHIXhMkKJ45t6x
// SIG // bba6IwK3klJ4sQC7vaQ67ASOA1Dxht+KCG4niNaKhZf8
// SIG // ZOwPu7jPJOKPInzFVjU2nM2z5XQ2LZ+oQa3u69uURA+L
// SIG // nnAsT/A8ct+GD1BJVpZTz9ywF6eXDMEY8fhFs4xLSCxC
// SIG // l7gHH8a1wk8MmIZuVzcwgmWIeP4BdlNsv22H3pCqWqBW
// SIG // MJKGXk+mcaEG1+Sn7YI/rWZBVdtVL2SJCem9+Gv+OHba
// SIG // 7CunYk5lZzUzPSej+hIZZNrH3FMGxyBi/JmKnSjosneE
// SIG // cTgpkr3BTZGRIK5OePJhwmw208jvcUszdRJFsW6fJ/yx
// SIG // 1Z2fX6eYSCxp7ZDM2g+Wl0QkMh0iIbD7Ue0P6yqB8oxa
// SIG // oLRjvX7Z8WL8cza2ynjAs8JnKsDK1+h3MXtEnimfAgMB
// SIG // AAGjggFJMIIBRTAdBgNVHQ4EFgQUbFCG2YKGVV1V1VkF
// SIG // 9DpNVTtmx1MwHwYDVR0jBBgwFoAUn6cVXQBeYl2D9OXS
// SIG // ZacbUzUZ6XIwXwYDVR0fBFgwVjBUoFKgUIZOaHR0cDov
// SIG // L3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jcmwvTWlj
// SIG // cm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAo
// SIG // MSkuY3JsMGwGCCsGAQUFBwEBBGAwXjBcBggrBgEFBQcw
// SIG // AoZQaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9w
// SIG // cy9jZXJ0cy9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIw
// SIG // UENBJTIwMjAxMCgxKS5jcnQwDAYDVR0TAQH/BAIwADAW
// SIG // BgNVHSUBAf8EDDAKBggrBgEFBQcDCDAOBgNVHQ8BAf8E
// SIG // BAMCB4AwDQYJKoZIhvcNAQELBQADggIBAJBRjqcoyldr
// SIG // NrAPsE6g8A3YadJhaz7YlOKzdzqJ01qm/OTOlh9fXPz+
// SIG // de8boywoofx5ZT+cSlpl5wCEVdfzUA5CQS0nS02/zULX
// SIG // E9RVhkOwjE565/bS2caiBbSlcpb0Dcod9Qv6pAvEJjac
// SIG // s2pDtBt/LjhoDpCfRKuJwPu0MFX6Gw5YIFrhKc3RZ0Xc
// SIG // ly99oDqkr6y4xSqb+ChFamgU4msQlmQ5SIRt2IFM2u3J
// SIG // xuWdkgP33jKvyIldOgM1GnWcOl4HE66l5hJhNLTJnZeO
// SIG // DDBQt8BlPQFXhQlinQ/Vjp2ANsx4Plxdi0FbaNFWLRS3
// SIG // enOg0BXJgd/BrzwilWEp/K9dBKF7kTfoEO4S3IptdnrD
// SIG // p1uBeGxwph1k1VngBoD4kiLRx0XxiixFGZqLVTnRT0fM
// SIG // IrgA0/3x0lwZJHaS9drb4BBhC3k858xbpWdem/zb+nbW
// SIG // 4EkWa3nrCQTSqU43WI7vxqp5QJKX5S+idMMZPee/1FWJ
// SIG // 5o40WOtY1/dEBkJgc5vb7P/tm49Nl8f2118vL6ue45jV
// SIG // 0NrnzmiZt5wHA9qjmkslxDo/ZqoTLeLXbzIx4YjT5XX4
// SIG // 9EOyqtR4HUQaylpMwkDYuLbPB0SQYqTWlaVn1OwXEZ/A
// SIG // XmM3S6CM8ESw7Wrc+mgYaN6A/21x62WoMaazOTLDAf61
// SIG // X2+V59WEu/7hMIIHcTCCBVmgAwIBAgITMwAAABXF52ue
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
// SIG // VQQLEx1UaGFsZXMgVFNTIEVTTjoxNzlFLTRCQjAtODI0
// SIG // NjElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAg
// SIG // U2VydmljZaIjCgEBMAcGBSsOAwIaAxUAjTCfa9dUWY9D
// SIG // 1rt7pPmkBxdyLFWggYMwgYCkfjB8MQswCQYDVQQGEwJV
// SIG // UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMH
// SIG // UmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
// SIG // cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1T
// SIG // dGFtcCBQQ0EgMjAxMDANBgkqhkiG9w0BAQUFAAIFAOcP
// SIG // T1IwIhgPMjAyMjExMDQxNjQ0MDJaGA8yMDIyMTEwNTE2
// SIG // NDQwMlowdzA9BgorBgEEAYRZCgQBMS8wLTAKAgUA5w9P
// SIG // UgIBADAKAgEAAgIFNgIB/zAHAgEAAgIR6jAKAgUA5xCg
// SIG // 0gIBADA2BgorBgEEAYRZCgQCMSgwJjAMBgorBgEEAYRZ
// SIG // CgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqG
// SIG // SIb3DQEBBQUAA4GBACldai7xbisBNuUi/lBiAvnvJz/X
// SIG // cTmdA6PDeTY01H+oheSyG9ZZJ5VkODl/A44S6tJHgJL4
// SIG // xmSw2wS90kDubEZmlP7KMejAdrBlSjtEl5Wt0Dihbziw
// SIG // vqFViU7xaKZMK05HhuecbXUZ9diL5mTSWJvrh1abRzuq
// SIG // 9R2vcORIfbd/MYIEDTCCBAkCAQEwgZMwfDELMAkGA1UE
// SIG // BhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNV
// SIG // BAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
// SIG // b3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRp
// SIG // bWUtU3RhbXAgUENBIDIwMTACEzMAAAG1rRrf14VwbRMA
// SIG // AQAAAbUwDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3
// SIG // DQEJAzENBgsqhkiG9w0BCRABBDAvBgkqhkiG9w0BCQQx
// SIG // IgQgCszJiEfSFoAaH9PnIbFJAwlrPXgO6hWzJHeDknAf
// SIG // j1UwgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCAn
// SIG // yg01LWhnFon2HNzlZyKae2JJ9EvCXJVc65QIBfHIgzCB
// SIG // mDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
// SIG // YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
// SIG // VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNV
// SIG // BAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEw
// SIG // AhMzAAABta0a39eFcG0TAAEAAAG1MCIEIOQu58DB2hEx
// SIG // kJEZeZ7UPG0XmfNFM4ufFwkGtV1b7rhPMA0GCSqGSIb3
// SIG // DQEBCwUABIICAIanocs7wHuhkj19qcPw5k3/akXlrl5I
// SIG // v3ElnsyDNegCXgu/qWtWqUhiP/KNrWrq484KM4nD8ucC
// SIG // H+04sHKRDHjdwL1Mq/ck+iVHvs3DfPDvizY50pty/QCu
// SIG // dgSED0RrnGk/Bn84K2ocO7TmgA1KUjzl5lZdJxBTkKiY
// SIG // kiQsArDFFY3BSpNmtQ1CZuWMcwpmU6rIhT/yxOsCcLdf
// SIG // Vo3UGCPmgqsJ1UXIB2v1q3yL6SP2ALqMcGN7GbiramQM
// SIG // wjuaFhA32ylKv/PnqaMZw4lJtTPJr72X0oMVLSmUgXtp
// SIG // UeCVc4etumt36BWpm/3RAwuYfTc4qiYKnwSefnAS4DsQ
// SIG // csCgiOIMpLVazHJNlJTYHZNMBw9r27uY4Yjos15AmKL9
// SIG // lxZE+Y/wfxw/aYc4yjDg3f3RuzqxpvwJCINaaUNx3AdP
// SIG // Am1825jRV038q3KlxfxsSJtWOMDCOHmQ7py1BmqPknLO
// SIG // NBMVegsosmxEwNPZcuaQk7ijbSyIxI0VuDhegbx0W/8+
// SIG // Bu8cwUxK0hAz+/WDt4TJMSXOE8Y1LSlKkslO3fwZ0PKA
// SIG // n0PyxicyZBeCh6U0gjY3CCmquGtDtbMQHr30gU4AWUsg
// SIG // IEBlX38A6VEWG6o7KGyOdzK0R7fUjacKVxPvcrxP7CTv
// SIG // K4R4WE9kzvEigWx0xxvPqprYynjmfVYXyS6w
// SIG // End signature block
