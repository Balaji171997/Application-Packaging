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
// SIG // MIIomQYJKoZIhvcNAQcCoIIoijCCKIYCAQExDzANBglg
// SIG // hkgBZQMEAgEFADB3BgorBgEEAYI3AgEEoGkwZzAyBgor
// SIG // BgEEAYI3AgEeMCQCAQEEEBDgyQbOONQRoqMAEEvTUJAC
// SIG // AQACAQACAQACAQACAQAwMTANBglghkgBZQMEAgEFAAQg
// SIG // HzDJMGLiNfXtYXT6sWiDcxSLQ4ACkiag+vEADJYWqSyg
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
// SIG // AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCCPZmq8myzzRNAk
// SIG // R8JuWovuBR/slWgZXTw0Z7C1+LXVHjCBigYKKwYBBAGC
// SIG // NwIBDDF8MHqgXIBaAE0AaQBjAHIAbwBzAG8AZgB0AC4A
// SIG // VABvAG8AbABrAGkAdAAuAFcAcABmAC4AVQBJAC4AQwBv
// SIG // AG4AdAByAG8AbABzAC4AVwBlAGIAVgBpAGUAdwAuAGQA
// SIG // bABsoRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
// SIG // BgkqhkiG9w0BAQEFAASCAQAaatEjhprWycgEzr10zS0/
// SIG // AzdlIw2NKUpwmKZmpSB7L7wdy5VH+OdXdAFVf9ckSfFH
// SIG // tLgiZqubLIaUc+7/GuoIoSAc3cIimYxKKjKsLGaB542N
// SIG // 8jIshXnzGHX5Kq1MYq1s2q/F0gBuqw9n57QuZEk+vBaN
// SIG // Da3hUtM4p0/dUihVXOT/irIYmxxFOR5V9+zBB8zIlAwh
// SIG // AR45pm9G5sIYqRmijq/egKBUVKwh+pK8kymyg3Led16D
// SIG // KCccCcFEuC2oA65kZyqU7bkTHFMZ6ISVYiONjXhUC5ko
// SIG // xAZVBhyseyHtjJ1c/VSKER+4LZijOK1CcBuxl3UrCnL2
// SIG // lIsIFgxjulU2oYIXrTCCF6kGCisGAQQBgjcDAwExgheZ
// SIG // MIIXlQYJKoZIhvcNAQcCoIIXhjCCF4ICAQMxDzANBglg
// SIG // hkgBZQMEAgEFADCCAVoGCyqGSIb3DQEJEAEEoIIBSQSC
// SIG // AUUwggFBAgEBBgorBgEEAYRZCgMBMDEwDQYJYIZIAWUD
// SIG // BAIBBQAEIK6nhhf3jyWRZPA6to82JEGv4nKOneBToKUi
// SIG // AXDS8sJbAgZo8b4V8EUYEzIwMjUxMDIzMDI0NzM1LjQz
// SIG // NFowBIACAfSggdmkgdYwgdMxCzAJBgNVBAYTAlVTMRMw
// SIG // EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
// SIG // b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
// SIG // b24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9w
// SIG // ZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNoaWVs
// SIG // ZCBUU1MgRVNOOjJEMUEtMDVFMC1EOTQ3MSUwIwYDVQQD
// SIG // ExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloIIR
// SIG // +zCCBygwggUQoAMCAQICEzMAAAIS0QgGPMoYT6oAAQAA
// SIG // AhIwDQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMx
// SIG // EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
// SIG // ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
// SIG // dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3Rh
// SIG // bXAgUENBIDIwMTAwHhcNMjUwODE0MTg0ODE1WhcNMjYx
// SIG // MTEzMTg0ODE1WjCB0zELMAkGA1UEBhMCVVMxEzARBgNV
// SIG // BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
// SIG // HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEt
// SIG // MCsGA1UECxMkTWljcm9zb2Z0IElyZWxhbmQgT3BlcmF0
// SIG // aW9ucyBMaW1pdGVkMScwJQYDVQQLEx5uU2hpZWxkIFRT
// SIG // UyBFU046MkQxQS0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1p
// SIG // Y3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0G
// SIG // CSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCvTNOgOSlZ
// SIG // C2xl6RLRxXSq4N0pJMaSi+8FpkfQ4AgSLQ7cJw7vsmJf
// SIG // xzgSmr26JsdVlnVb8ui58TXva+RFc75Bg21ZaisQInYB
// SIG // xlDXRukCW2SFk2JeVUnwvdDOEqCteuYySbYn7+DzVTbc
// SIG // k9w7jBccR+2idPfCl3//3fquObDEybs2RuzKBsl/7gBU
// SIG // Ew2vhow9CEF3vqh3QowHpau/IQY45TTz3c4W59LkQN7L
// SIG // ifjhaBrEkTRWe/f846+47DkqnUo+qONgn4v3LAu4Ey1w
// SIG // N8uk1A7+HV4USgytuIQzrtM582Vd/FsPPgyWxi8uKjGB
// SIG // 3ZfN7LVDGtXX6L4nJUMkyJJ72Ao67OmJBAUTX0NQ+CyJ
// SIG // 3KMtPNcSFJUsGVGivR4JV/uALpF+Tw1jes7ayCA4vv29
// SIG // TkW4MpOH+wg61xQd4cLjaMEYH6190oLUo4FH5SU31o7O
// SIG // DyalQ0jYWCpC+KtU/2mlt4xR++nbAD2+jJOJFa8ODMLG
// SIG // jzGUnWexxhMchCuaQX2P8JrQgOa3x+86frieeUk4ZRhl
// SIG // gcwLWXTG2CRhMTURJSqqRrAqTuKpvF2cvLJxL51H7NrE
// SIG // +50wMutAXPyWB/L2huTQPwcLZ3OFalg2fmF2Sg8TOAKp
// SIG // BQ6ny/dCP+x3hqfK6l7kqgKSMAE4/fKFJDhb1n4OsmeE
// SIG // z+tuxcLuhO/bpwIDAQABo4IBSTCCAUUwHQYDVR0OBBYE
// SIG // FFIFuVLFvlxgpg7C939V+hc5+7feMB8GA1UdIwQYMBaA
// SIG // FJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYw
// SIG // VKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9w
// SIG // a2lvcHMvY3JsL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAl
// SIG // MjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRg
// SIG // MF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9z
// SIG // b2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIw
// SIG // VGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwG
// SIG // A1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUH
// SIG // AwgwDgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUA
// SIG // A4ICAQBedICSZfv1FzuXFLXA6jNcntXSi7kOe1Vw4mmU
// SIG // iQOO8Q3wEhCmHhT6BI4tm5VF4//P1h1SJSRw/AvU8zbj
// SIG // n+QRfUR6CnE1zwcMDqEoIeDQAs0Ry7GcY6WAouiRd9R6
// SIG // vUPmGJbw8AEz1H6d6K15OA9ppGUkW8ZNi+i1zS6oaIRL
// SIG // mExCEvxE0WGlL1FwhYe2dAYSet05S8ICGzgV5WJrByYt
// SIG // Mq/7XzvRz8x5MeLRAN15H7v9aDiqGQnaTWIQcl2Zh/ys
// SIG // hXQ1EFlx1FNN0d57flJc/md40J8CSMMi5nJxG53qPM8s
// SIG // I0uI1jMZcGzDMnKCPgR5I5FPvAy9oW4p5EBehcLfDBi+
// SIG // AiwjXOfcMZjrblj7JlKLxQ1I0e6uLfpm/1r5Di8nAOlg
// SIG // rfpLRMHal/vEuKIffaeTtgrvdGD3xbp9nYg27NjNnsaG
// SIG // C999+SPgRReDUTQR99jWkSqRukNM/uH8MGq3Og9ezLDY
// SIG // xSH7vK9ZyrYEZlK5xroJjpfiKgy5zk9amya846WLsBE0
// SIG // DsBvyQp0JzaA0MtpyCWzB5kRz39VAHqGWz9voqTfaeTC
// SIG // 4cTEqVp6hJWsoHlT3GWnX5zwn/sYmPhHDsCJDy1yn5aZ
// SIG // /IPwrFfZCUpsOLhJSOeCW/jrXtHz5r9wNYnJoy3zbv1a
// SIG // ft/bIx503uR8YhDlJmPrpF2F2Vk6rzCCB3EwggVZoAMC
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
// SIG // OjJEMUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3Nv
// SIG // ZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4D
// SIG // AhoDFQDlUcGviHTQQ3uNR1DfdIT6puT/wKCBgzCBgKR+
// SIG // MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5n
// SIG // dG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
// SIG // aWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1p
// SIG // Y3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqG
// SIG // SIb3DQEBCwUAAgUA7KN8PDAiGA8yMDI1MTAyMjE1NTIy
// SIG // OFoYDzIwMjUxMDIzMTU1MjI4WjB0MDoGCisGAQQBhFkK
// SIG // BAExLDAqMAoCBQDso3w8AgEAMAcCAQACAgKSMAcCAQAC
// SIG // AhJxMAoCBQDspM28AgEAMDYGCisGAQQBhFkKBAIxKDAm
// SIG // MAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAIAgEA
// SIG // AgMBhqAwDQYJKoZIhvcNAQELBQADggEBAGEn00gZ78Qn
// SIG // FGh662LfH+kUt0wXu9RZMYgOTJ2V6Xq2KxWnRpz/yMNv
// SIG // gsbqrcCLI9RnENAX3G6k47c4BkiYwh7EDhvlLWG30w0n
// SIG // ytT0CRjhOPD8wrs7yjjeVTKvwuHeUEwHGWAT8Yg6iu0p
// SIG // 7mPQm9Zx7XFcTcFd7lBPFDDkn3bFxQsu2bL/5AFxOYp2
// SIG // KHuUpsyp7f4BPOYfR+gfyAC8hnH9e4K3BDm4nRYVr+07
// SIG // lMHk6dVzjQnzYdUVR+wLT99Thsm35T0+MBDPX9snwrKU
// SIG // 1pPfjeax5wuVJQpoDdjMPDWrmlWPxmjpWQlPRBSNRq+c
// SIG // +H3xbZiJ+iTa+OIULQoPZO0xggQNMIIECQIBATCBkzB8
// SIG // MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
// SIG // bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
// SIG // cm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNy
// SIG // b3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAhLR
// SIG // CAY8yhhPqgABAAACEjANBglghkgBZQMEAgEFAKCCAUow
// SIG // GgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqG
// SIG // SIb3DQEJBDEiBCB1h8Lo/6TehD4KU+gmJd1P7io/k6uk
// SIG // GFaTU9vn87yCITCB+gYLKoZIhvcNAQkQAi8xgeowgecw
// SIG // geQwgb0EIHP5fka87taeCScfgFl5hT4HMEvUnLmgnzBW
// SIG // VM0jF9iDMIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzAR
// SIG // BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
// SIG // bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
// SIG // bjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAg
// SIG // UENBIDIwMTACEzMAAAIS0QgGPMoYT6oAAQAAAhIwIgQg
// SIG // ODxA25k0JnF5dOm3LPDRbfOaiQ8Ae/di+3APnjAsRvIw
// SIG // DQYJKoZIhvcNAQELBQAEggIAYF436+P1et/tyNUN6U2P
// SIG // 7vq4ktyAsVfSCxSV7IxFKKbE7C2PxbX8gX7cB+hEuEhi
// SIG // n0anzhBgHHz6uylXPT6De4xBZr3DS/7piDRmKzpzlrRl
// SIG // THeWjY7T440P3pewMgAC5MH88Z5RQrgC9FA8+qug2rC7
// SIG // iV5V5sOYt23G2OlcfOQS5KhyhbR4suiW0K3wgiwyl7aQ
// SIG // LqqWLLY4jAWJBbTFlsB9xhhfaZOeOPDIuO/GBNOWjb1h
// SIG // nJvpCwnGKM0XwuVU23pfbBM2Kx/5wZxy0+U907C9ypNM
// SIG // eXvaBYgxz0XqS+IXr7nsJ0EzWQ5bN857tOi2vaxud8TP
// SIG // 1qcvCMMx1F1OIsDsF7cv6DQJxTInc3xiF9Kev3XbN33j
// SIG // WX81+VGQCJeC7BeiZVcOm6x5GHq+KMQkXL9iDIoAjZwK
// SIG // KVT9bdM2zMX9KccGjWvsyDrJCuL6OiYEcps5kREDu8Bk
// SIG // OCjhvSgptSptF9j+MWJDaW/z8ObHO2ONtjBQqKSlvoW8
// SIG // qzAK8vTfA1P9EhHW4Mh3kmERW6xURg1QqciwflpRCZVX
// SIG // lgiPqJqghbQiKHGRSpYYLnFJU1N1A7ggRfwwgxcBYFXB
// SIG // LqcT9c7/GeLlq3remsoLxzbRaHNUFIeybItmj+qX44jS
// SIG // XxNlgquSuF2Nk9GQ51ZGgbiQWaFMRUX19MztdrnZ17myl80=
// SIG // End signature block
