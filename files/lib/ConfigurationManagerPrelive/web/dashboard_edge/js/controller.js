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


        async function SMS_DeviceCollectionsReceived(res) {
            let parsedRes;
            try {
                parsedRes = JSON.parse(res);
            } catch (error) {
                logger.err("Failed to parse SMS_Collection response as JSON");
                $scope.CollectionsData = ChartState.NoDataFound;
                $scope.$apply();
                return;
            }

            if (parsedRes.length === 0) {
                logger.err("SMS_Collection returned no results");
                $scope.CollectionsData = ChartState.NoDataFound;
                $scope.$apply();
                return;
            }

            const locCollections = parsedRes.slice(0, COLL_DISP_LIMIT);
            const localizedPromises = locCollections.map((item) => {
                return new Promise((resolve, reject) => {
                    callMethod("GetCollectionAliasName", item.Name, function (response, returnCode) {
                        if (returnCode !== 0) {
                            logger.error("Error retrieving alias name for collection:", item.Name);
                            reject(new Error("Failed to retrieve alias name"));
                        } else {
                            item.Name = (typeof response === 'string' && response.startsWith('"'))
                                ? JSON.parse(response)
                                : response;
                            resolve();
                        }
                    });
                });
            });

            try {
                await Promise.all(localizedPromises);
            } catch (error) {
                console.error("One or more alias retrievals failed:", error);
            }

            $scope.SMS_DeviceCollections.All = locCollections;
            $scope.SMS_DeviceCollections.Selected = locCollections[0];

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
// SIG // MIIonAYJKoZIhvcNAQcCoIIojTCCKIkCAQExDzANBglg
// SIG // hkgBZQMEAgEFADB3BgorBgEEAYI3AgEEoGkwZzAyBgor
// SIG // BgEEAYI3AgEeMCQCAQEEEBDgyQbOONQRoqMAEEvTUJAC
// SIG // AQACAQACAQACAQACAQAwMTANBglghkgBZQMEAgEFAAQg
// SIG // DE4rvF/L73ZAhPmxul9TcuxSA+dZcbzpwcLFi8JBx1+g
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
// SIG // ghpvMIIaawIBATCBlTB+MQswCQYDVQQGEwJVUzETMBEG
// SIG // A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
// SIG // ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
// SIG // MSgwJgYDVQQDEx9NaWNyb3NvZnQgQ29kZSBTaWduaW5n
// SIG // IFBDQSAyMDExAhMzAAAEhJjiEuB4ozFdAAAAAASEMA0G
// SIG // CWCGSAFlAwQCAQUAoIH3MBkGCSqGSIb3DQEJAzEMBgor
// SIG // BgEEAYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEE
// SIG // AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCASYlr3svzC1nPk
// SIG // PaS2NbnehcESpUhC9M1c/0nEJ2scbTCBigYKKwYBBAGC
// SIG // NwIBDDF8MHqgXIBaAE0AaQBjAHIAbwBzAG8AZgB0AC4A
// SIG // VABvAG8AbABrAGkAdAAuAFcAcABmAC4AVQBJAC4AQwBv
// SIG // AG4AdAByAG8AbABzAC4AVwBlAGIAVgBpAGUAdwAuAGQA
// SIG // bABsoRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
// SIG // BgkqhkiG9w0BAQEFAASCAQAJpRTIh6O/Oan0oPlvtg6l
// SIG // +LUZGP2tAXcAzok1gr0aLeFdi9frrfFtyBkd9ndHDs5p
// SIG // +ufb26xRBTZTTGfP3jGpuJlEc+1mhXr5OzqneSxeKdn8
// SIG // G39vR3Wdpj89tulSRBAVXrZNeMUYgQqOmCWg+7qdZbXn
// SIG // LjRvBcbnz3cZxVisecaODitoSR5ccdvQF6+kFQfs11+j
// SIG // cGjfwGC7w2Th1C3c2rPBx1/DbEKQvDm9U/2PTiIpM+Qv
// SIG // fAeEMKokTgXdcIZfahfkNRhoJWXuTafKHxNWJ3CRosUh
// SIG // FImLANIHpJZRfaGyA3+gcQJeUF5rGLbowN3E6OVxFgYg
// SIG // RaiQw0fdp3aFoYIXsDCCF6wGCisGAQQBgjcDAwExghec
// SIG // MIIXmAYJKoZIhvcNAQcCoIIXiTCCF4UCAQMxDzANBglg
// SIG // hkgBZQMEAgEFADCCAVoGCyqGSIb3DQEJEAEEoIIBSQSC
// SIG // AUUwggFBAgEBBgorBgEEAYRZCgMBMDEwDQYJYIZIAWUD
// SIG // BAIBBQAEIA/Ss4LAct1i61L3rcm8E+HegT0UuPOcwZ1v
// SIG // G+JK4sxSAgZo8e4BPqYYEzIwMjUxMDIzMDI0NzM2LjIy
// SIG // OFowBIACAfSggdmkgdYwgdMxCzAJBgNVBAYTAlVTMRMw
// SIG // EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
// SIG // b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
// SIG // b24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9w
// SIG // ZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNoaWVs
// SIG // ZCBUU1MgRVNOOjQwMUEtMDVFMC1EOTQ3MSUwIwYDVQQD
// SIG // ExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloIIR
// SIG // /jCCBygwggUQoAMCAQICEzMAAAIZXrLYVHX0sY0AAQAA
// SIG // AhkwDQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMx
// SIG // EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
// SIG // ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
// SIG // dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3Rh
// SIG // bXAgUENBIDIwMTAwHhcNMjUwODE0MTg0ODI2WhcNMjYx
// SIG // MTEzMTg0ODI2WjCB0zELMAkGA1UEBhMCVVMxEzARBgNV
// SIG // BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
// SIG // HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEt
// SIG // MCsGA1UECxMkTWljcm9zb2Z0IElyZWxhbmQgT3BlcmF0
// SIG // aW9ucyBMaW1pdGVkMScwJQYDVQQLEx5uU2hpZWxkIFRT
// SIG // UyBFU046NDAxQS0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1p
// SIG // Y3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0G
// SIG // CSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCmoUjJSTMj
// SIG // LGkvdDTdaYu7Lgb1ghRJzOeEqv5wc5P7+7s9qvEj3qDH
// SIG // FvVata4DEHyqMYt+xsibHxXei4rWdRx/5H+eyddqzn+J
// SIG // OBX9OXdBNEZPQN65cE1ukepz7ALU2JPIDvqAueKu9IES
// SIG // gHOWuk1AUSe7B1s8sIulNLcpZIK7knTZv5EVZH+RwXNX
// SIG // GeGgTeAhp5RG2sYoYFkYosFe+qCCQMQ20qS+29FPfbEu
// SIG // 8C8v9GlF67nPXxmiMKzvZlKhrvgPLxhtpawObc5k6klF
// SIG // nFmw8oIdnrE2qAUp/TE0ePS32/RDdb7bPmABVpqwkkK9
// SIG // HnZKXRcnYA5/eXQtJ61eBQDmAPkhDVG8SyVOY2dKi5Os
// SIG // YgPcPWeNjuYG7Sm6Ih08raMr/VZ55/b5hHhxClZCR4Fm
// SIG // ZeJ2H0C5Z2XDEpAvXksnorZ3DzL+388GGYvK3pAB/QJ6
// SIG // lZF2BmczK1UBS5YfCVlFX0ktjtpfwPnl4v35w4ulfdsY
// SIG // 06Y3bhSkhbyq1lqpdp6wW8g5bbck0uFppBW85uvV67sY
// SIG // T/kyfjd778Nu11iX9ss/YhDXFgQl1JtxSQMV9bcqVkSH
// SIG // 6cEoO1pGc1GRuAiDEhsp1Pfw4pDBn9oDi5KyICDqcQ+J
// SIG // YEca7K0ijnBTvkzlV2OESqpMd9di7wEmLoZPO9ZP716R
// SIG // 8xd7OoKSSzFobwIDAQABo4IBSTCCAUUwHQYDVR0OBBYE
// SIG // FIBo6jkdZq03OpmfUgXV9wPqevchMB8GA1UdIwQYMBaA
// SIG // FJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYw
// SIG // VKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9w
// SIG // a2lvcHMvY3JsL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAl
// SIG // MjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRg
// SIG // MF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9z
// SIG // b2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIw
// SIG // VGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwG
// SIG // A1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUH
// SIG // AwgwDgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUA
// SIG // A4ICAQBfHNVkstcEV+gIIJOJjswdd1vtyK8lJN+sdgkL
// SIG // k6TY03vk2nNMxP1XZNwhCN9DcAVRuHU0EBi0xS7DELoP
// SIG // hx4RcbmVcCdu+QL1iN4tUNHIiZdhiZ+3vP5CmX23cL/x
// SIG // rS2Kqc7PxR7z8Ngu0xOC9Yyeyos2MgsNoiY5+ccjfpMs
// SIG // KMYV7xFgtcZ0JR04uV8B0wZ4/FJMDdMAA5z4ZBuY9aOu
// SIG // C4tZvG+eXc1WNG+sFlWTEUyhVkfR/uobAM5KGOme/mdi
// SIG // dDjy58vS4HPnZFs8Z1fgW/35QY6sGmuZwfOYi60W0l5z
// SIG // ZjiS6M21MrbAEaBaxwQ5WEWJpV2N7xUsnsxU0oTlOay4
// SIG // YzeNMuvWe5HkAUazdQqQ/uDdxAPhwcrtd0uJObt7rTpA
// SIG // n5ap5CwANgT129T3AhRsj0OXhRwgSsXD4UdpZJOuR8nh
// SIG // K8uaEqeXmSGGknWwXfPp7UHF6lSWJcerNEuIdaKFYhYR
// SIG // IXwgcSUXc87Fs/hUmocGJi9pcxXRLJGDCgPrNd11tSdf
// SIG // 1ZHokvYGWoCOMfEg3B6Wyn9WHEBZOHO4wDnwvG8T9UDO
// SIG // N8UXhabtrVkAuYlXDegv+z+7GjU6ni1xP6F9n243WG0L
// SIG // Uk3gO5GoV8u22O6gCZRChs7nNQVHO8KfwKT+GI75vNHX
// SIG // myqSOXEszIyOmRz95/hJRSKQPjry9TCCB3EwggVZoAMC
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
// SIG // BRDBcQZqELQdVTNYs6FwZvKhggNZMIICQQIBATCCAQGh
// SIG // gdmkgdYwgdMxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
// SIG // YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
// SIG // VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNV
// SIG // BAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMg
// SIG // TGltaXRlZDEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNO
// SIG // OjQwMUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3Nv
// SIG // ZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4D
// SIG // AhoDFQAxdin9aqp3JvR6eKCst/GXQicDPqCBgzCBgKR+
// SIG // MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5n
// SIG // dG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
// SIG // aWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1p
// SIG // Y3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqG
// SIG // SIb3DQEBCwUAAgUA7KOsKzAiGA8yMDI1MTAyMjE5MTY1
// SIG // OVoYDzIwMjUxMDIzMTkxNjU5WjB3MD0GCisGAQQBhFkK
// SIG // BAExLzAtMAoCBQDso6wrAgEAMAoCAQACAgcYAgH/MAcC
// SIG // AQACAhJQMAoCBQDspP2rAgEAMDYGCisGAQQBhFkKBAIx
// SIG // KDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAI
// SIG // AgEAAgMBhqAwDQYJKoZIhvcNAQELBQADggEBAERj8WHZ
// SIG // 1/TlYM4Ptc08Z668cw80qY+Zx+pBex8mTuvvmBi5M/GM
// SIG // rz/G3p2J7KBj/hG92ddCu4JLLcjexvDYfLJvWkLVexa4
// SIG // nKeuz5SKKMwuo1Yxwu6ovJ0gmW8pfnSU7z1JVApuzIWP
// SIG // 0lxygfN3Pndckh4VSVQr2BA6QHYgBL/3rFiPXcj1kGNe
// SIG // crpec5Zo/uli3KSqeW4IcwavzHGbwRsMlRL0l/iHRuMw
// SIG // VWXnkoA6xgnCF4uSfjnsQtfuhpd3gndc/4I5BS6e+i7i
// SIG // aimhkJ0J6wyB49zMWRPMIXwVazXyxjNFUqB2Afbx1QRy
// SIG // 2lnMIaOw1HYWO3n7UvZfafG3Rc0xggQNMIIECQIBATCB
// SIG // kzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
// SIG // Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
// SIG // TWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1N
// SIG // aWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAA
// SIG // AhlesthUdfSxjQABAAACGTANBglghkgBZQMEAgEFAKCC
// SIG // AUowGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8G
// SIG // CSqGSIb3DQEJBDEiBCBt9wNuDuSvj8zeY8CMZpN5OtNn
// SIG // 7E5atLARUmA4BZ3GfzCB+gYLKoZIhvcNAQkQAi8xgeow
// SIG // gecwgeQwgb0EINyRfrfcTXLUQXfZXXzNByuyCPMj37ct
// SIG // 7uaW+TY55u2GMIGYMIGApH4wfDELMAkGA1UEBhMCVVMx
// SIG // EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
// SIG // ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
// SIG // dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3Rh
// SIG // bXAgUENBIDIwMTACEzMAAAIZXrLYVHX0sY0AAQAAAhkw
// SIG // IgQgOyStiHS4g1F0q4lrwCt903H7NO0Iw7r1tIrJxX/l
// SIG // XJowDQYJKoZIhvcNAQELBQAEggIAHXlNsCE+49GogXdA
// SIG // 61CmPmZJQlENYzx0uZiziY20V/jHnuxrVW9uhwugq4tU
// SIG // S6MIkfWrY1W9tY04R96NKHoCYdMMiW2Bp8B7GIyAHDD/
// SIG // VnLyn6RM1o7tJOs2gFXwxRWeHPuQRl3LC7vaG1CLEwPC
// SIG // s9gRhq8RvcxlEkhz6sdvAg0XbOTgzcYRfrDjmwveTkXM
// SIG // 7fOwBt6Xymy0qhws2fW1nOhDmldAFQ9c4n3cfweN9EYu
// SIG // iuv6cFERoYbkGvOghOlB+WfgR48IDgKq+pJTPVN/BgyY
// SIG // Qeir/+cSnR5grQb9IG4MXL6e+N1GaduzsewUYLJEqcp7
// SIG // UsQ0VPgottqLSr7DNBs90Wk+KjqFXk1UuH6ixSxknn26
// SIG // M6ALeYvuqEvB27e0gLOV7/jUUfmbHHruTT+bBL/u7KY2
// SIG // SX0aNltN8bdXt3ImBj2UMApgN6sCp0DudNEldJEAjr1H
// SIG // KC3uL+pc9/H1h1Gb/4HP6Xh5diSwL+2SAQZ3WCPOVuSd
// SIG // 87qhqRuUv+gJI3G4jwiLgdvxFSC6pqm4JQiDzp2475IZ
// SIG // ztlD3T655OTaksH7ztKE7vyk5Y4yURyZKpJYbe/kjr4J
// SIG // znRkunPpwKcqbsfn5FeEEHfrEU+2uftFRFB0PAvzINMn
// SIG // Kns9AVXuR++oNfZN7YQqlytGEZMB3QtC9vRrFpQ0B/vm
// SIG // ILmUiEo=
// SIG // End signature block
