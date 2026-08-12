//-----------------------------------------------------------------------------
// <copyright file="controller.js" company="Microsoft">
//    Copyright (c) 2016 Microsoft Corporation.  All rights reserved.
// </copyright>
// <purpose>
// </purpose>
// <notes>
// </notes>
//-----------------------------------------------------------------------------

"use strict"

var dashboard = angular.module("dashboard", []);

dashboard.controller("dashboardController", function ($scope) 
{
    $scope.strings = getStrings([
        "FailedRequestsPerSecond",
        "SuccessfulRequestsPerSecond",
        "MessagesAccepted",
        "MessagesRejected",
        "SuccessfulRequests",
        "FailedRequests",
        "SuccessfulReports",
        "RejectedReports",
        "FailedReports"
    ]);

    // CPU data
    $scope.CPUData = JSON.parse(window.external.CPU);

    // Memory usage data
    $scope.memoryData = parseInt(JSON.parse(window.external.Memory).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ","));

    // Management points
    $scope.managementPoints = JSON.parse(window.external.GetManagementPointData());

    $scope.MPList;
    $scope.MPListFirst;

    /// <summary>Gets a string calling getString in utility to display on the dashboard</summary>
    /// <param name="stringName">The name of the string in our resource file</param>
    /// <returns>The string that will be displayed on the dashboard</returns>
    $scope.getString = function (stringName) 
    {
        return getString(stringName);
    };

    /// <summary>Fetches the image for the memory performance counter</summary>
    /// <returns>-</returns>
    function fetchImage() 
    {
        var img;
        if ($scope.memoryData < 0) 
        {
            // Don't display icon
            $scope.memoryData = "-";
        }
        else if ($scope.memoryData < 500) 
        {
            img = "error";
        } 
        else if ($scope.memoryData < 700) 
        {
            img = "warning";
        } 
        else 
        {
            img = "ok";
        }
        $scope.Img = img;
    }

    /// <summary>Gets all the management points connected to the site</summary>
    /// <returns>-</returns>
    function getManagementPoints() 
    {
        var res = [];
        for (var item in $scope.managementPoints) 
        {
            res[item] = { 
                SiteCode: $scope.managementPoints[item] + "" 
            };
        }

        $scope.MPList = res;
        $scope.MPListFirst = $scope.MPList[0];
    }

    /// <summary>Checks to see if there is data in the columns, if data exists</summary>
    /// <param name="columns">The columns of the data in the table that we will be putting into our charts</param>
    /// <returns>True if data exists in the columns, false otherwise</returns>
    function dataInColumns(columns) 
    {
        // Check if the columns exist
        if (columns === null || typeof (columns) === 'undefined') 
        {
            return false;
        }
        var data = false;  // By default let there be no data in the columns
        var zeroData = 0; // If all the data is 0 then assume there is no data
        // Check if there is data by iterating through all the elements in the columns
        for (var i = 0; i < columns.length; i++) 
        {
            // If the columns are not empty and there is at least one column there exists data
            if (columns[i][1] != null) 
            {
                data = true;
                // Used to check if all values are 0
                if (columns[i][1] != 0) 
                {
                    zeroData++;
                }
            } 
            else 
            {
                data = false;
            }
        }
        // Check if all values are 0
        if (zeroData == columns.length)
        {
            data = true;
        }
        else 
        {
            data = false;
        }
        return data;
    };

    /// <summary>Creates a gauge chart for all cpu and memory data</summary>
    /// <param name="idToBindTo">Id in our dashboard where we wish to bind the chart to</param>
    /// <param name="columns">The columns of the data in the table that we will be putting into our charts</param>
    /// <returns>-<returns>
    $scope.createGauge = function (idToBindTo, columns)
    {
        var label;
        if (idToBindTo == "#CPUPerformance") {
            label = "CPU Performance";
        }
        else
        {

            label = "";
        }
        if (columns === null || columns < 0)
        {
            columns = 0;
        }
        var pattern = ["#7FBA00", "#FF8C00", "#D83B01"]
        $scope.gaugeChart = c3.generate({
            bindto: idToBindTo,
            data: {
                columns: [
                    [label, parseInt(columns)]
                ],
                type: 'gauge'
            },
            color: {
                pattern: pattern,
                threshold: {
                    values: [30, 60, 90]
                }
            },
            size: {
                height: 100
            }
        });
    };

    /// <summary>Creates a donut chart for inventory data</summary>
    /// <param name="idToBindTo">Id in our dashboard where we wish to bind the chat to</param>
    /// <param name="columns">The columns of the data in the table that we will be putting into our charts</param>
    /// <returns>-<returns>
    $scope.createThreeDonutChart = function (idToBindTo, columns)
    {
        var labels = true;                                  // Boolean for whether or not we will have labels
        var data = dataInColumns(columns);                  // Boolean for whether or not the data exists
        var pattern = ["#7FBA00", "#FF8C00", "#D83B01"];    // Colour pattern for the data, Green, Yellow, Red
        // Checks to see if data exists, if not generate an empty chart
        if (data === false)
        {
            labels = false;                                 // If there is not data there will be no labels
            pattern = ["#a9a9a9"];                          // If there is no data the default graph colour will be grey
            columns = [['', 1]];                            // If there is no data there will only be one entry in the graph
        }
        // Generate the donut chart
        $scope.donutChart = c3.generate({
            bindto: idToBindTo,
            data: {
                columns: columns,
                type: "donut"
            },
            legend: {
                position: "bottom",
                show: labels
            },
            color: {
                pattern: pattern
            },
            size: {
                height: 250,
                width: 250
            },
            donut: {
                // If there is no data the label will state 0
                labels: {
                    format: function (value, ratio) {
                        if (labels)
                        {
                            return value;
                        }
                        else
                        {
                            return 0;
                        }
                    }
                },
                expand: labels,
            }
        });
    };

    /// <summary>Creates a donut chart for policy, registration and state message data</summary>
    /// <param name="idToBindTo">Id in our dashboard where we wish to bind the chat to</param>
    /// <param name="columns">The columns of the data in the table that we will be putting into our charts</param>
    /// <returns>-<returns>
    $scope.createTwoDonutChart = function (idToBindTo, columns)
    {
        var labels = true;                                  // Boolean for whether or not we will have labels
        var data = dataInColumns(columns);                  // Boolean for whether or not the data exists
        var pattern = ["#7FBA00", "#D83B01"];               // Colour pattern for the data, Green, Red
        // Checks to see if data exists, if not generate an empty chart
        if (data === false)
        {
            labels = false;                                 // If there is not data there will be no labels
            pattern = ["#a9a9a9"];                          // If there is no data the default graph colour will be grey
            columns = [['', 1]];                            // If there is no data there will only be one entry in the graph
        }
        // Generate the donut chart
        $scope.donutChart = c3.generate({
            bindto: idToBindTo,
            data: {
                columns: columns,
                type: "donut"
            },
            legend: {
                position: "bottom",
                show: labels
            },
            color: {
                pattern: pattern
            },
            size: {
                height: 250,
                width: 250
            },
            donut: {
                // If there is no data the label will state 0
                labels: {
                    format: function (value, ratio) {
                        if (labels)
                        {
                            return value;
                        }
                        else
                        {
                            return 0;
                        }
                    }
                },
                expand: labels,
            }
        });
    };

    // CPU data
    getManagementPoints();
    execute();

    function execute()
    {
        var roleid;

        $scope.createGauge("#CPUPeformance", $scope.CPUData);
        fetchImage();

        // Role id data
        getChartData($scope.MPListFirst.SiteCode, '87E93EDC-E857-47AA-A98E-66A2A16EEDD4', function (columns)
        {
            if (columns == null)
            {
                roleid = 0;
            }
            else if (columns.length != 0)
            {
                roleid = columns[0].ID;
            }
            else
            {
                roleid = 0;
            }
        });

        // Number of clients
        getChartData(roleid, '7191E5AB-F1CF-4D31-8048-F18F07517CAB', function (columns)
        {
            if (columns == null)
            {
                $scope.client = 0;
            }
            else if (columns.length != 0)
            {
                $scope.client = columns[0].Value.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
            }
            else
            {
                $scope.client = 0;
            }
        });

        // State Messages
        getChartData(roleid, '6A3ADFB9-0111-4084-A4D7-330AEE7C983E', function (columns)
        {
            var data;
            if (columns == null)
            {
                data = [
                    [$scope.strings["MessagesAccepted"], 0],
                    [$scope.strings["MessagesRejected"], 0],
                ];
            }
            else if (columns.length != 0)
            {
                data = [
                    [$scope.strings["MessagesAccepted"], columns[1].Value - columns[0].Value],
                    [$scope.strings["MessagesRejected"], columns[0].Value],
                ];
            }
            else
            {
                data = [
                    [$scope.strings["MessagesAccepted"], 0],
                    [$scope.strings["MessagesRejected"], 0],
                ];
            }
            $scope.createTwoDonutChart("#StateMessage", data);
        });

        // Get Policy
        getChartData(roleid, '1C9DCBE4-222D-431C-9D8F-0DFC36733B38', function (columns)
        {
            var data;
            if (columns == null)
            {
                data = [
                    [$scope.strings["SuccessfulRequests"], 0],
                    [$scope.strings["FailedRequests"], 0],
                ];
            }
            else if (columns.length != 0)
            {
                data = [
                    [$scope.strings["SuccessfulRequests"], columns[2].Value - columns[0].Value],
                    [$scope.strings["FailedRequests"], columns[0].Value],
                ];
            }
            else
            {
                data = [
                    [$scope.strings["SuccessfulRequests"], 0],
                    [$scope.strings["FailedRequests"], 0],
                ];
            }
            $scope.createTwoDonutChart("#GetPolicy", data);
        });

        // Registration
        getChartData(roleid, '33040E59-2B98-4A78-B847-9C92D7A97013', function (columns)
        {
            var data;
            if (columns == null)
            {
                data = [
                    [$scope.strings["SuccessfulRequests"], 0],
                    [$scope.strings["FailedRequests"], 0],
                ];
            }
            else if (columns.length != 0)
            {
                data = [
                    [$scope.strings["SuccessfulRequests"], columns[1].Value - columns[0].Value],
                    [$scope.strings["FailedRequests"], columns[0].Value],
                ];
            }
            else
            {
                data = [
                    [$scope.strings["SuccessfulRequests"], 0],
                    [$scope.strings["FailedRequests"], 0],
                ];
            }
            $scope.createTwoDonutChart("#Registration", data);
        });

        // Software Inventory
        getChartData(roleid, '18F4E0CA-7A99-46C8-BB4E-493C92B54666', function (columns)
        {
            var data;
            if (columns == null)
            {
                data = [
                    [$scope.strings["SuccessfulReports"], 0],
                    [$scope.strings["RejectedReports"], 0],
                    [$scope.strings["FailedReports"], 0],
                ];
            }
            else if (columns.length != 0)
            {
                data = [
                    [$scope.strings["SuccessfulReports"], columns[2].Value - columns[1].Value - columns[0].Value],
                    [$scope.strings["RejectedReports"], columns[1].Value],
                    [$scope.strings["FailedReports"], columns[0].Value],
                ];
            }
            else
            {
                data = [
                    [$scope.strings["SuccessfulReports"], 0],
                    [$scope.strings["RejectedReports"], 0],
                    [$scope.strings["FailedReports"], 0],
                ];
            }
            $scope.createThreeDonutChart("#softwareInventory", data);
        });

        // Hardware Inventory
        getChartData(roleid, '70D37C83-E436-4F13-B861-34B245784954', function (columns)
        {
            var data;
            if (columns == null)
            {
                data = [
                    [$scope.strings["SuccessfulReports"], 0],
                    [$scope.strings["RejectedReports"], 0],
                    [$scope.strings["FailedReports"], 0],
                ];
            }
            else if (columns.length != 0)
            {
                data = [
                    [$scope.strings["SuccessfulReports"], columns[2].Value - columns[1].Value - columns[0].Value],
                    [$scope.strings["RejectedReports"], columns[1].Value],
                    [$scope.strings["FailedReports"], columns[0].Value],
                ];
            }
            else
            {
                data = [
                    [$scope.strings["SuccessfulReports"], 0],
                    [$scope.strings["RejectedReports"], 0],
                    [$scope.strings["FailedReports"], 0],
                ];
            }
            $scope.createThreeDonutChart("#hardwareInventory", data);
        });

        // DDR Manager
        getChartData(roleid, '68DCD7A5-3CF5-4931-80D1-2E11079B72E3', function (columns)
        {
            var data;
            if (columns == null)
            {
                data = [
                    [$scope.strings["SuccessfulReports"], 0],
                    [$scope.strings["RejectedReports"], 0],
                    [$scope.strings["FailedReports"], 0],
                ];
            }
            else if (columns.length != 0)
            {
                data = [
                    [$scope.strings["SuccessfulReports"], columns[2].Value - columns[1].Value - columns[0].Value],
                    [$scope.strings["RejectedReports"], columns[1].Value],
                    [$scope.strings["FailedReports"], columns[0].Value],
                ];
            }
            else
            {
                data = [
                    [$scope.strings["SuccessfulReports"], 0],
                    [$scope.strings["Rejected Reports"], 0],
                    [$scope.strings["FailedReports"], 0],
                ];
            }
            $scope.createThreeDonutChart("#DDRManager", data);
        });
    }

    // On new MPs the dashboard refreshes
    $scope.refresh = function refresh()
    {
        // CPU data
        $scope.CPUData = JSON.parse(window.external.CPU);

        // Memory usage data
        $scope.memoryData = parseInt(JSON.parse(window.external.Memory)).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");

        // Display all the dashboards
        execute();
    };
});
// SIG // Begin signature block
// SIG // MIInywYJKoZIhvcNAQcCoIInvDCCJ7gCAQExDzANBglg
// SIG // hkgBZQMEAgEFADB3BgorBgEEAYI3AgEEoGkwZzAyBgor
// SIG // BgEEAYI3AgEeMCQCAQEEEBDgyQbOONQRoqMAEEvTUJAC
// SIG // AQACAQACAQACAQACAQAwMTANBglghkgBZQMEAgEFAAQg
// SIG // HzDJMGLiNfXtYXT6sWiDcxSLQ4ACkiag+vEADJYWqSyg
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
// SIG // ARUwLwYJKoZIhvcNAQkEMSIEII9marybLPNE0CRHwm5a
// SIG // i+4FH+yVaBldPDRnsLX4tdUeMEIGCisGAQQBgjcCAQwx
// SIG // NDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRw
// SIG // Oi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEB
// SIG // BQAEggEARdoasOjZmgh+dfG6Zjkp3VwZAUh/UeAUt1kX
// SIG // XZKbWM1UPA6IOk0GLU8T2WO2YaLO21AbsvPuD1SQAObz
// SIG // VBU+8Rk8G561xgYioAGN3MpQfeCOUzEtTNBSkUIyzMNJ
// SIG // UCFWseoM5ZNYPsqzueWYYKPo0NnLqA4wNRpSoar59Abg
// SIG // dchN3t0+vGjJy+3xIwJTAsMruTaxHpUkt2zAzgd4djPT
// SIG // TCxdulX00pLnykb2CNB1AMh8bFtkn3QExxxhOvSZ5HAv
// SIG // wSkIQYzx1FR65lB8UdKkV8cq/IGsG0ghMuGKRgxxKGcH
// SIG // N3W5nmYTiXbH1lncIrGp1m9eAUEN+9qHL896mslK2qGC
// SIG // FywwghcoBgorBgEEAYI3AwMBMYIXGDCCFxQGCSqGSIb3
// SIG // DQEHAqCCFwUwghcBAgEDMQ8wDQYJYIZIAWUDBAIBBQAw
// SIG // ggFZBgsqhkiG9w0BCRABBKCCAUgEggFEMIIBQAIBAQYK
// SIG // KwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCApGePs
// SIG // PgIJK6ykJRTF5TOW6ypAG0falCZtMk2zTFsZlQIGY2Pe
// SIG // fFXqGBMyMDIyMTEwNDE3MjMzOS40OTNaMASAAgH0oIHY
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
// SIG // IgQgwsHa4BVRUyrNMUX+1rZNOvK/kcO+RCODvTSWbVjl
// SIG // CB4wgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCAo
// SIG // 69Y4oHA7Q4pS+Y1NsBfrpIYTeWsPeGTami0X0PD7HzCB
// SIG // mDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
// SIG // YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
// SIG // VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNV
// SIG // BAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEw
// SIG // AhMzAAABuAjUwbh54FFJAAEAAAG4MCIEIJDBW67MRKy5
// SIG // 6CRRhSvuyzsbZ09Q6WTDPYgV7mzHGwVWMA0GCSqGSIb3
// SIG // DQEBCwUABIICAInqgoQU1VADzrj/0eEBTMzepfsxwZ14
// SIG // 6lLEsOKskLwqGp+Qoryvk3BXC46ckmOX133q24oiz5L5
// SIG // ufyNxAJqJ7EWZ9Jr/YM8OjeZwVnMl2ZE72Y8S5MWoUXh
// SIG // 5VQultHCPJqWqU6MYP7n8L6NInLWqHo5eXdkOueTLjuG
// SIG // 1g6JQD0s4GoW0ZuZJV04k2MVqroVt9MS3WLr/9AaBbnJ
// SIG // 9jLS7g/xa5O/1bbACUlZlCAZ4vs5YeDSXqL3Jjpw3dXN
// SIG // zsJ+ejL92ILMxCmicpphMFcthQ3WCwS5Jr5XZ1iItsau
// SIG // L/mazY/VGn9LgDSLx+TQ03RzIn/YnepD85i5H3x4FGc9
// SIG // ac5U+86eDk2efA1QnuObw4hlhrVCz0pQsD3PG9z7nlUF
// SIG // Z5fU+LNYTLmE2e7Lb5HWPRugUxlqpmiuiOC28RCKH8/I
// SIG // TwnYwU41PmBSEbbrlL48kZ26YyP79ffV6fViu6zx6njI
// SIG // P3m7kXyKn2eTP7UNsMLf812q1agpS8gSlNsKFTTnkwge
// SIG // ris6XXcBqW6AP1EL3m+PQ1eveuStxHcDaQ54duFrsT1M
// SIG // urPEvCvcxS9u37pDtFJjqk6jKUejBBa01sl3ncRIF9SP
// SIG // jQazzeMG9uUJB3gvoEi1eLM8Gysp/qHoJqCEOZYvef7S
// SIG // Os2r6jSnkm9f4LLQDpBLCI1xwy3sZo2WXOjS
// SIG // End signature block
