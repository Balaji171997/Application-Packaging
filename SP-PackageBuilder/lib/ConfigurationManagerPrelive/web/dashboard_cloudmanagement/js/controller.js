//-----------------------------------------------------------------------------
// <copyright file="controller.js" company="Microsoft">
// Copyright (c) 2019 Microsoft Corporation. All rights reserved.
// </copyright>
// <purpose>
//   Controller logic for Cloud Management Dashboard.
// </purpose>
// <notes>
// </notes>
//-----------------------------------------------------------------------------
(function () {
    "use strict";
    var dashboard = angular.module("dashboard", []);

    dashboard.controller("dashboardController", function ($scope, $sce) {

        $scope.brightness = GetCurrentBackgroundColor();

        $scope.toggle = function ($event) {
            var link = angular.element($event.currentTarget);
            link.parent().toggleClass('on');
            link.next().toggleClass('hidden');
        };

        //handle Enter key press event
        $scope.keyPressToggle = function ($event) {
            if (event.keyCode == 13) {
                $scope.toggle($event);
            }
        };

       

        $scope.strings = JSON.parse(window.external.GetStrings());
        $scope.getString = function (stringName) {
            return $scope.strings[stringName];
        };

        // Create AAD approved clients Gauge chart
        $scope.aadApprovedClients = [];
        $scope.aadApprovedClientsData = JSON.parse(window.external.GetAADApprovedClientsData());
        if ($scope.aadApprovedClientsData.length == 2) {
            $scope.totalAadApprovedClients = $scope.aadApprovedClientsData[0].Value;
            $scope.aadApprovedClients.push([$scope.aadApprovedClientsData[1].Name, $scope.aadApprovedClientsData[1].Value]);
        }

        $scope.createAADRegisteredClientsGaugeChart = function (bindID, columns) {
            c3.generate({
                bindto: bindID,
                data: {
                    columns: columns,
                    type: "gauge",
                },
                gauge: {
                    label: {
                        format: function (value, ratio) {
                            if ($scope.totalAadApprovedClients === 0) {
                                return value;
                            } else {
                                var r = Number(ratio * 100).toFixed(1);
                                return r + "%";
                            }
                        },
                    },
                    max: $scope.totalAadApprovedClients,
                },
                color: {
                    pattern: ["#70AD47"],
                },
                size: {
                    height: 180
                }

            });
            if ($scope.brightness < 125) {
                SetColorToAllTextInChart(bindID, 'white');
            }
        };

        $scope.createAADRegisteredClientsGaugeChart("#AADRegisteredClientsGauge", $scope.aadApprovedClients);

        // Create AAD registered clients trend area chart
        $scope.devicesTrend = [];
        $scope.devicesTrendData = JSON.parse(window.external.GetApprovedAADDeviceTrendData());
        $scope.devicesTrendData.forEach(function (data) {
            $scope.row = [];
            data.forEach(function (data1) {
                $scope.row.push(data1.Value);
            });
            $scope.devicesTrend.push($scope.row);
        });

        $scope.devicesTrendTypes = JSON.parse(window.external.GetApprovedAADDeviceTrendLegend());
        $scope.createAADDevicesAreaChart = function (bindID, columns, types) {
            c3.generate({
                bindto: bindID,
                padding: {
                    top: 0,
                    right: 20,
                    bottom: 60,
                    left: 50,
                },
                data: {
                    x: 'x',
                    xFormat: '%Y-%m-%d %H',
                    columns: columns,
                    types: types
                },
                axis: {
                    x: {
                        type: 'timeseries',
                        tick: {
                            format: function (x) { return x.getMonth() + 1 + '/' + x.getDate() + ' ' + x.getHours() + ':00'; }
                        }
                    }
                },
                legend: {
                    show: true,
                    position: 'inset',
                    inset: {
                        anchor: 'top-left',
                        x: 0,
                        y: 0,
                        step: 5
                    }
                },
                point: {
                    show: false
                },
                zoom: {
                    enabled: true
                }
            });
            if ($scope.brightness < 125) {
                SetColorToAllTextInChart(bindID, 'white');
            }
        };

        $scope.createAADDevicesAreaChart("#AADRegisteredClientsArea", $scope.devicesTrend, $scope.devicesTrendTypes);


        // Create donut chart for AAD user discovery
        $scope.users = [];
        $scope.usersData = JSON.parse(window.external.GetUsersData());
        $scope.usersData.forEach(function (data) {
            $scope.users.push([data.Name, data.Value]);
        });

        $scope.createAADDiscoveredUsersDonutChart = function (bindID, columns) {
            c3.generate({
                bindto: bindID,
                data: {
                    columns: columns,
                    type: 'donut',
                    onclick: function (d, i) { console.log("onclick", d, i); },
                    onmouseover: function (d, i) { console.log("onmouseover", d, i); },
                    onmouseout: function (d, i) { console.log("onmouseout", d, i); },
                    empty: {
                        label: {
                            text: $scope.getString("NoResults")
                        }
                    }
                },
                donut: {
                    label: {
                        format: function (value, ratio) {
                            return value;
                        }
                    },
                    width: 45
                },
                size: {
                    height: 250,
                    width: 330
                }
            });
            if ($scope.brightness < 125) {
                SetColorToAllTextInChart(bindID, 'white');
            }
        };

        $scope.createAADDiscoveredUsersDonutChart("#AADDiscoveredUsersDonut", $scope.users);

        // Create AAD discovered users trend area chart
        $scope.usersTrend = [];
        $scope.usersTrendData = JSON.parse(window.external.GetUsersTrendData());
        $scope.usersTrendData.forEach(function (data) {
            $scope.row = [];
            data.forEach(function (data1) {
                $scope.row.push(data1.Value);
            });
            $scope.usersTrend.push($scope.row);
        });

        $scope.usersTrendTypes = JSON.parse(window.external.GetUsersTrendLegend());
        $scope.createAADDiscoveredUsersAreaChart = function (bindID, columns, types) {
            c3.generate({
                bindto: bindID,
                padding: {
                    top: 0,
                    right: 20,
                    bottom: 60,
                    left: 50,
                },
                data: {
                    x: 'x',
                    xFormat: '%Y-%m-%d %H',
                    columns: columns,
                    types: types
                },
                axis: {
                    x: {
                        type: 'timeseries',
                        tick: {
                            format: function (x) { return x.getMonth() + 1 + '/' + x.getDate() + ' ' + x.getHours() + ':00'; }
                        }
                    }
                },
                legend: {
                    show: true,
                    position: 'inset',
                    inset: {
                        anchor: 'top-left',
                        x: 0,
                        y: 0,
                        step: 5
                    }
                },
                point: {
                    show: false
                },
                zoom: {
                    enabled: true
                }
            });
            if ($scope.brightness < 125) {
                SetColorToAllTextInChart(bindID, 'white');
            }
        };

        $scope.createAADDiscoveredUsersAreaChart("#AADDiscoveredUsersArea", $scope.usersTrend, $scope.usersTrendTypes);

        // Create donut chart for AAD Discovered devices
        $scope.discoveredDevices = [];
        $scope.devicessData = JSON.parse(window.external.GetDevicesData());
        $scope.devicessData.forEach(function (data) {
            $scope.discoveredDevices.push([data.Name, data.Value]);
        });

        $scope.createAADDiscoveredDevicesDonutChart = function (bindID, columns) {
            c3.generate({
                bindto: bindID,
                data: {
                    columns: columns,
                    type: 'donut',
                    onclick: function (d, i) { console.log("onclick", d, i); },
                    onmouseover: function (d, i) { console.log("onmouseover", d, i); },
                    onmouseout: function (d, i) { console.log("onmouseout", d, i); },
                    empty: {
                        label: {
                            text: $scope.getString("NoResults")
                        }
                    }
                },
                donut: {
                    label: {
                        format: function (value, ratio) {
                            return value;
                        }
                    },
                    width: 45
                },
                size: {
                    height: 250,
                    width: 330
                }
            });
            if ($scope.brightness < 125) {
                SetColorToAllTextInChart(bindID, 'white');
            }
        };

        $scope.createAADDiscoveredDevicesDonutChart("#AADDiscoveredDevicesDonut", $scope.discoveredDevices);

        // Create AAD discovered devices trend area chart
        $scope.aadDevicesTrend = [];
        $scope.aadDevicesTrendData = JSON.parse(window.external.GetAADDevicesTrendData());
        $scope.aadDevicesTrendData.forEach(function (data) {
            $scope.row = [];
            data.forEach(function (data1) {
                $scope.row.push(data1.Value);
            });
            $scope.aadDevicesTrend.push($scope.row);
        });

        $scope.aadDevicesTrendTypes = JSON.parse(window.external.GetAADDevicesTrendLegend());
        $scope.createAADDiscoveredDevicesAreaChart = function (bindID, columns, types) {
            c3.generate({
                bindto: bindID,
                padding: {
                    top: 0,
                    right: 20,
                    bottom: 60,
                    left: 50,
                },
                data: {
                    x: 'x',
                    xFormat: '%Y-%m-%d %H',
                    columns: columns,
                    types: types
                },
                axis: {
                    x: {
                        type: 'timeseries',
                        tick: {
                            format: function (x) { return x.getMonth() + 1 + '/' + x.getDate() + ' ' + x.getHours() + ':00'; }
                        }
                    }
                },
                legend: {
                    show: true,
                    position: 'inset',
                    inset: {
                        anchor: 'top-left',
                        x: 0,
                        y: 0,
                        step: 5
                    }
                },
                point: {
                    show: false
                },
                zoom: {
                    enabled: true
                }
            });
            if ($scope.brightness < 125) {
                SetColorToAllTextInChart(bindID, 'white');
            }
        };

        $scope.createAADDiscoveredDevicesAreaChart("#AADDiscoveredDevicesArea", $scope.aadDevicesTrend, $scope.aadDevicesTrendTypes);

        // Create donut chart for CMG managed identities
        $scope.cmgClients = [];
        $scope.cmgClientsData = JSON.parse(window.external.GetCMGClientsData());
        $scope.cmgClientsData.forEach(function (data) {
            $scope.cmgClients.push([data.Name, data.Value]);
        });

        $scope.createCMGManagedIdentitiesDonutChart = function (bindID, columns) {
            c3.generate({
                bindto: bindID,
                data: {
                    columns: columns,
                    type: 'donut',
                    onclick: function (d, i) { console.log("onclick", d, i); },
                    onmouseover: function (d, i) { console.log("onmouseover", d, i); },
                    onmouseout: function (d, i) { console.log("onmouseout", d, i); },
                    empty: {
                        label: {
                            text: $scope.getString("NoResults")
                        }
                    }
                },
                donut: {
                    label: {
                        format: function (value, ratio) {
                            return value;
                        }
                    },
                    width: 45
                },
                size: {
                    height: 250,
                    width: 330
                }
            });
            if ($scope.brightness < 125) {
                SetColorToAllTextInChart(bindID, 'white');
            }
        };

        $scope.createCMGManagedIdentitiesDonutChart("#CMGManagedIdentitiesDonut", $scope.cmgClients);

        // Create CMG traffic trend area chart
        $scope.cmgTrafficTrend = [];
        $scope.cmgTrafficTrendData = JSON.parse(window.external.GetCMGTrafficTrendData());
        $scope.cmgTrafficTrendData.forEach(function (data) {
            $scope.row = [];
            data.forEach(function (data1) {
                $scope.row.push(data1.Value);
            });
            $scope.cmgTrafficTrend.push($scope.row);
        });

        $scope.cmgTrafficTrendTypes = JSON.parse(window.external.GetCMGTrafficTrendLegend());
        $scope.createCMGTrafficAreaChart = function (bindID, columns, types) {
            c3.generate({
                bindto: bindID,
                padding: {
                    top: 0,
                    right: 20,
                    bottom: 60,
                    left: 50,
                },
                data: {
                    x: 'x',
                    xFormat: '%Y-%m-%d %H',
                    columns: columns,
                    types: types
                },
                axis: {
                    x: {
                        type: 'timeseries',
                        tick: {
                            format: function (x) { return x.getMonth() + 1 + '/' + x.getDate() + ' ' + x.getHours() + ':00'; }
                        }
                    }
                },
                legend: {
                    show: true,
                    position: 'inset',
                    inset: {
                        anchor: 'top-left',
                        x: 0,
                        y: 0,
                        step: 5
                    }
                },
                point: {
                    show: false
                },
                zoom: {
                    enabled: true
                }
            });
            if ($scope.brightness < 125) {
                SetColorToAllTextInChart(bindID, 'white');
            }
        };

        $scope.createCMGTrafficAreaChart("#CMGTrafficArea", $scope.cmgTrafficTrend, $scope.cmgTrafficTrendTypes);

        // Create donut chart for CMG online clients
        $scope.bgblients = [];
        $scope.bgbClientsData = JSON.parse(window.external.GetBGBClientsData());
        $scope.bgbClientsData.forEach(function (data) {
            $scope.bgblients.push([data.Name, data.Value]);
        });

        $scope.createCMGOnlineClientsDonutChart = function (bindID, columns) {
            c3.generate({
                bindto: bindID,
                data: {
                    columns: columns,
                    type: 'donut',
                    onclick: function (d, i) { console.log("onclick", d, i); },
                    onmouseover: function (d, i) { console.log("onmouseover", d, i); },
                    onmouseout: function (d, i) { console.log("onmouseout", d, i); },
                    empty: {
                        label: {
                            text: $scope.getString("NoResults")
                        }
                    }
                },
                color: {
                    pattern: ['#1f77b4', '#ff7f0e', '#2ca02c']
                },
                donut: {
                    label: {
                        format: function (value, ratio) {
                            return value;
                        }
                    },
                    width: 45
                },
                size: {
                    height: 250,
                    width: 330
                }
            });
            if ($scope.brightness < 125) {
                SetColorToAllTextInChart(bindID, 'white');
            }
        };

        $scope.createCMGOnlineClientsDonutChart("#CMGOnlineClientsDonut", $scope.bgblients);

        // Create online clients trend area chart
        $scope.bgbClientsTrend = [];
        $scope.bgbClientsTrendData = JSON.parse(window.external.GetBGBClientsTrendData());
        $scope.bgbClientsTrendData.forEach(function (data) {
            $scope.row = [];
            data.forEach(function (data1) {
                $scope.row.push(data1.Value);
            });
            $scope.bgbClientsTrend.push($scope.row);
        });

        $scope.bgbClientsTrendTypes = JSON.parse(window.external.GetBGBClientsTrendLegend());
        $scope.createCMGOnlineClientsAreaChart = function (bindID, columns, types) {
            c3.generate({
                bindto: bindID,
                padding: {
                    top: 0,
                    right: 20,
                    bottom: 60,
                    left: 50,
                },
                data: {
                    x: 'x',
                    xFormat: '%Y-%m-%d %H',
                    columns: columns,
                    types: types
                },
                axis: {
                    x: {
                        type: 'timeseries',
                        tick: {
                            format: function (x) { return x.getMonth() + 1 + '/' + x.getDate() + ' ' + x.getHours() + ':00'; }
                        }
                    }
                },
                legend: {
                    show: true,
                    position: 'inset',
                    inset: {
                        anchor: 'top-left',
                        x: 0,
                        y: 0,
                        step: 5
                    }
                },
                point: {
                    show: false
                },
                zoom: {
                    enabled: true
                }
            });
            if ($scope.brightness < 125) {
                SetColorToAllTextInChart(bindID, 'white');
            }
        };

        $scope.createCMGOnlineClientsAreaChart("#CMGOnlineClientsArea", $scope.bgbClientsTrend, $scope.bgbClientsTrendTypes);

        /// <summary>Sets up all Aria strings for accessibility use</summary>
        /// <returns>Aria strings for narrator use</returns>
        $scope.setupAria = function () {
            console.log($scope.users);
            console.log($scope.discoveredDevices);
            console.log($scope.aadApprovedClients);
            console.log($scope.cmgClients);
            console.log($scope.bgblients);

            // Setup aria for Microsoft Entra ID users chart
            var azureActiveDirectoryUsersSummaryText = "";
            if ($scope.users.length !== 0) {
                for (var value in $scope.users) {
                    azureActiveDirectoryUsersSummaryText += $scope.users[value][0] + ", " + $scope.users[value][1] + ", ";
                }
            } else {
                azureActiveDirectoryUsersSummaryText = $scope.getString("NoResults");
            }
            var azureActiveDirectoryUsersAriaLabel = document.getElementById("azureActiveDirectoryUsersAria");
            azureActiveDirectoryUsersAriaLabel.setAttribute("aria-label", azureActiveDirectoryUsersSummaryText);

            // Setup aria for Microsoft Entra ID devices chart
            var azureActiveDirectoryDevicesSummaryText = "";
            if ($scope.discoveredDevices.length !== 0) {
                for (var value in $scope.discoveredDevices) {
                    azureActiveDirectoryDevicesSummaryText += $scope.discoveredDevices[value][0] + ", " + $scope.discoveredDevices[value][1] + ", ";
                }
            } else {
                azureActiveDirectoryDevicesSummaryText = $scope.getString("NoResults");
            }
            var azureActiveDirectoryDevicesAriaLabel = document.getElementById("azureActiveDirectoryDevicesAria");
            azureActiveDirectoryDevicesAriaLabel.setAttribute("aria-label", azureActiveDirectoryDevicesSummaryText);

            // Setup aria for Approved clients with Microsoft Entra ID identity chart
            var azureActiveDirectoryRegisteredClientsSummaryText = "";
            if ($scope.aadApprovedClients.length !== 0) {
                azureActiveDirectoryRegisteredClientsSummaryText = $scope.getString("ApprovedAzureADClientsChart") + " " + (100 * $scope.aadApprovedClients[0][1] / $scope.totalAadApprovedClients).toFixed(1) + "%";
            } else {
                azureActiveDirectoryRegisteredClientsSummaryText = $scope.getString("NoResults");
            }
            var azureActiveDirectoryRegisteredClientsAriaLabel = document.getElementById("azureActiveDirectoryRegisteredClientsAria");
            azureActiveDirectoryRegisteredClientsAriaLabel.setAttribute("aria-label", azureActiveDirectoryRegisteredClientsSummaryText);

            // Setup aria for Identities communicated with CMG (Last 14 days) chart
            var cloudManagementGatewayManagedIdentitiesSummaryText = "";
            if ($scope.cmgClients.length !== 0) {
                for (var value in $scope.cmgClients) {
                    cloudManagementGatewayManagedIdentitiesSummaryText += $scope.cmgClients[value][0] + ", " + $scope.cmgClients[value][1] + ", ";
                }
            } else {
                cloudManagementGatewayManagedIdentitiesSummaryText = $scope.getString("NoResults");
            }
            var cloudManagementGatewayManagedIdentitiesAriaLabel = document.getElementById("cloudManagementGatewayManagedIdentitiesAria");
            cloudManagementGatewayManagedIdentitiesAriaLabel.setAttribute("aria-label", cloudManagementGatewayManagedIdentitiesSummaryText);

            // Setup aria for Current online clients chart
            var cloudManagementGatewayOnlineClientsSummaryText = "";
            if ($scope.bgblients.length !== 0) {
                for (var value in $scope.bgblients) {
                    cloudManagementGatewayOnlineClientsSummaryText += $scope.bgblients[value][0] + ", " + $scope.bgblients[value][1] + ", ";
                }
            } else {
                cloudManagementGatewayOnlineClientsSummaryText = $scope.getString("NoResults");
            }
            var cloudManagementGatewayOnlineClientsAriaLabel = document.getElementById("cloudManagementGatewayOnlineClientsAria");
            cloudManagementGatewayOnlineClientsAriaLabel.setAttribute("aria-label", cloudManagementGatewayOnlineClientsSummaryText);

            // Setup aria for the trend charts

            // Users Trend
            var azureActiveDirectoryUsersTrendSummaryText = "";
            if ($scope.usersTrend.length !== 0) {
                // For accessibility limit it to 10 evenly spaced values
                var count = Math.ceil(($scope.usersTrend[0].length - 1) / 10);
                for (var j = 1; j < $scope.usersTrend.length; j++) {
                    azureActiveDirectoryUsersTrendSummaryText += $scope.usersTrend[j][0] + " ";
                    for (var i = 1; i < $scope.usersTrend[0].length; i += count) {
                        azureActiveDirectoryUsersTrendSummaryText += $scope.usersTrend[0][i] + ", " + $scope.usersTrend[j][i] + ", ";
                    }
                }
            } else {
                azureActiveDirectoryUsersTrendSummaryText = $scope.getString("NoResults");
            }

            var azureActiveDirectoryUsersTrendAriaLabel = document.getElementById("azureActiveDirectoryUsersTrendAria");
            azureActiveDirectoryUsersTrendAriaLabel.setAttribute("aria-label", azureActiveDirectoryUsersTrendSummaryText);

            // Devices Trend
            var azureActiveDirectoryDevicesTrendSummaryText = "";

            if ($scope.aadDevicesTrend.length !== 0) {
                // For accessibility limit it to 10 evenly spaced values
                var count = Math.ceil(($scope.aadDevicesTrend[0].length - 1) / 10);
                for (j = 1; j < $scope.aadDevicesTrend.length; j++) {
                    azureActiveDirectoryDevicesTrendSummaryText += $scope.aadDevicesTrend[j][0] + " ";
                    for (var i = 1; i < $scope.aadDevicesTrend[0].length; i += count) {
                        azureActiveDirectoryDevicesTrendSummaryText += $scope.aadDevicesTrend[0][i] + ", " + $scope.aadDevicesTrend[j][i] + ", ";
                    }
                }
            } else {
                azureActiveDirectoryDevicesTrendSummaryText = $scope.getString("NoResults");
            }

            var azureActiveDirectoryDevicesTrendAriaLabel = document.getElementById("azureActiveDirectoryDevicesTrendAria");
            azureActiveDirectoryDevicesTrendAriaLabel.setAttribute("aria-label", azureActiveDirectoryDevicesTrendSummaryText);

            // Registered Clients Trend
            var azureActiveDirectoryRegisteredClientsTrendSummaryText = "";

            if ($scope.devicesTrend.length !== 0) {
                // For accessibility limit it to 10 evenly spaced values
                var count = Math.ceil(($scope.devicesTrend[0].length - 1) / 10);
                for (j = 1; j < $scope.devicesTrend.length; j++) {
                    azureActiveDirectoryRegisteredClientsTrendSummaryText += $scope.devicesTrend[j][0] + " ";
                    for (var i = 1; i < $scope.devicesTrend[0].length; i += count) {
                        azureActiveDirectoryRegisteredClientsTrendSummaryText += $scope.devicesTrend[0][i] + ", " + $scope.devicesTrend[j][i] + ", ";
                    }
                }
            } else {
                azureActiveDirectoryRegisteredClientsTrendSummaryText = $scope.getString("NoResults");
            }

            var azureActiveDirectoryRegisteredClientsTrendAriaLabel = document.getElementById("azureActiveDirectoryRegisteredClientsTrendAria");
            azureActiveDirectoryRegisteredClientsTrendAriaLabel.setAttribute("aria-label", azureActiveDirectoryRegisteredClientsTrendSummaryText);

            // CMG Traffic
            var azureActiveDirectoryCMGTrafficTrendSummaryText = "";

            if ($scope.cmgTrafficTrend.length !== 0) {
                // For accessibility limit it to 10 evenly spaced values
                var count = Math.ceil(($scope.cmgTrafficTrend[0].length - 1) / 10);
                for (j = 1; j < $scope.cmgTrafficTrend.length; j++) {
                    azureActiveDirectoryCMGTrafficTrendSummaryText += $scope.cmgTrafficTrend[j][0] + " ";
                    for (var i = 1; i < $scope.cmgTrafficTrend[0].length; i += count) {
                        azureActiveDirectoryCMGTrafficTrendSummaryText += $scope.cmgTrafficTrend[0][i] + ", " + $scope.cmgTrafficTrend[j][i] + ", ";
                    }
                }
            } else {
                azureActiveDirectoryCMGTrafficTrendSummaryText = $scope.getString("NoResults");
            }

            var azureActiveDirectoryCMGTrafficTrendAriaLabel = document.getElementById("azureActiveDirectoryCMGTrafficTrendAria");
            azureActiveDirectoryCMGTrafficTrendAriaLabel.setAttribute("aria-label", azureActiveDirectoryCMGTrafficTrendSummaryText);

            // Online Clients Trend
            var azureActiveDirectoryOnlineClientsTrendSummaryText = "";

            if ($scope.bgbClientsTrend.length !== 0) {
                // For accessibility limit it to 10 evenly spaced values
                var count = Math.ceil(($scope.bgbClientsTrend[0].length - 1) / 10);

                for (var j = 1; j < $scope.bgbClientsTrend.length; j++) {
                    azureActiveDirectoryOnlineClientsTrendSummaryText += $scope.bgbClientsTrend[j][0] + " ";
                    for (var i = 1; i < $scope.bgbClientsTrend[0].length; i += count) {
                        azureActiveDirectoryOnlineClientsTrendSummaryText += $scope.bgbClientsTrend[0][i] + ", " + $scope.bgbClientsTrend[j][i] + ", ";
                    }
                }
            } else {
                azureActiveDirectoryOnlineClientsTrendSummaryText = $scope.getString("NoResults");
            }

            var azureActiveDirectoryOnlineClientsTrendAriaLabel = document.getElementById("azureActiveDirectoryOnlineClientsTrendAria");
            azureActiveDirectoryOnlineClientsTrendAriaLabel.setAttribute("aria-label", azureActiveDirectoryOnlineClientsTrendSummaryText);
        }

        $scope.setupAria();

        /* ----------------------------------- Cloud Cost estimator | TODO: move to a component ----------------------------------- */

        /*******************************/
        /** Cloud Cost Estimator Data **/
        /*******************************/
        $scope.showCostEstimatorMainForm = true;
        $scope.isCloudCostEstimatorInitialized = false;

        //Data that was queried
        $scope.queriedData;

        //Backend estimated values
        $scope.estimations = {
            clientCount  : 0,
            CMGInstances : 0,
            clientDataConsumption : 0,
            roamingClientsPercentage : 0
        }

        //Estimator Configurations
        $scope.dataConsumption = {
            includeContent: false
        }
        
        $scope.devicesIncluded = {
            laptops  : true,
            servers  : false,
            desktops : false
        };
        
        //Texts to show current estimation prices 
        $scope.monthlyCostEstimate     = "";
        $scope.perDeviceCostEstimation = "";
        
        //CMG estimations
        $scope.CMGInstances = {amount : 1};
        
        $scope.defaultRegion   = "West US";
        $scope.defaultCurrency = "USD";

        //Posible pricing regions
        $scope.selectedRegion   = "";
        $scope.availableRegions = [];
        
        //Possible pricing currencies
        $scope.selectedCurrency   = "";
        $scope.availableCurrecies = [];

        //Sliders
        //Feeding example data, this is overriden on theinitValues method
        $scope.devices = {
            count   : 23000,
            countMinValue : 30000,
            countMaxValue : 0,
            estimatedDevicesTooltipText : "",
            roamingClientsPercentage : 10
        };

        $scope.clientData = {
            consumption : 30,
            consumptionMinValue : 0,
            consumptionMaxValue : 1
        };

        //Buttons Texts
        //Default is Options
        $scope.customizeMenuText = getString('Options');

        //Max value for numbers
        $scope.inputsMaxValue = JSON.parse(window.external.getMaxValueSupported());

        //Feature Exposure
        $scope.isCloudCostEstimatorFeatureExposed = false;

        /************************************/
        /**  Cost Estimator Initialization **/
        /************************************/
        $scope.initCloudCostEstimatorValues = function () {
            $scope.updateFeatureExposureStatus( function() {
                //If it's not exposed, we dont load any data
                if ($scope.isCloudCostEstimatorFeatureExposed) {
                    
                    //Inits options menu with defaults
                    $scope.devicesIncluded.laptops  = true;
                    $scope.devicesIncluded.servers  = false;
                    $scope.devicesIncluded.desktops = false;
                    $scope.dataConsumption.includeContent = false;

                    //Inits selected devices tooltip text
                    $scope.updateDevicesText($scope.devicesIncluded)

                    //Inits percentaje of roaming clients
                    $scope.updateRoamingClientsPercentage(function() {

                        //Inits selected currency and region
                        //Note that the backend checks that the retrieved data makes sense
                        $scope.updateCurrentPricingConfiguration(function() {

                            //Inits regions
                            $scope.updateAvailableRegions(function() {
                                $scope.defaultRegion = $scope.selectedRegion;

                                //Inits currencies
                                $scope.updateAvailableCurrencies($scope.selectedRegion, function() {
                                    $scope.defaultCurrency = $scope.selectedCurrency;

                                    //Inits other defaults
                                    $scope.getInitCloudCostEstimatorValues(function (data) {
                                        
                                        //Inits the CMG instances recomended based on retrieved data
                                        $scope.updateCMGInstancesRecomendations(data.estimation.clientCount, $scope.devices.roamingClientsPercentage, function() {
                                            
                                            //TODO: Move deafults to c# when all code is migrated
                                            $scope.devices.countMinValue = data.devices.countMinValue;
                                            //We add 20% more devices to the slider for users to experiment with.
                                            $scope.devices.countMaxValue = data.devices.countMaxValue + Math.floor(data.devices.countMaxValue * 0.2);
                                            
                                            $scope.clientData.consumptionMinValue = data.clientData.consumptionMinValue;
                                            $scope.clientData.consumptionMaxValue = data.clientData.consumptionMaxValue;

                                            $scope.clientData.consumption = data.clientData.consumption;
                                            $scope.devices.count = data.devices.count;

                                            $scope.estimations.clientCount  = data.estimation.clientCount;
                                            $scope.estimations.clientDataConsumption = data.estimation.clientDataConsumption;
                                        
                                            $scope.updateEstimationCosts($scope.devices.count, $scope.clientData.consumption, $scope.CMGInstances.amount, $scope.devices.roamingClientsPercentage, function () {
                                                //Once everithing is initilized, we show the component
                                                $scope.isCloudCostEstimatorInitialized = true;
                                            });
                                        });
                                    });
                                });
                            });
                        });
                    });
                }
            });
        }

        $scope.getInitCloudCostEstimatorValues = function (callback) {
            //Calls the backend for DB data. Maps to CloudCostEstimationDataDTO
            var queriedData = JSON.parse(window.external.getCloudCostEstimatorData());

            var data = {
                estimation: {
                    CMGInstances: 1,
                    clientCount: 0,
                    clientDataConsumption: 0
                },
                devices: {
                        count: 0,
                        countMinValue: 0,
                        countMaxValue: 0
                },
                clientData: {
                        consumption: 0,
                        consumptionMinValue: 0,
                        consumptionMaxValue: 5000
                }
            };

            // Devices
            $scope.calculateDevicesEstimation($scope.devicesIncluded, queriedData, function(devicesEstimation) {
                data.devices.countMaxValue  = queriedData.clientCount;
                data.estimation.clientCount = data.devices.count = devicesEstimation

                //Data consumption
                $scope.calculateClientDataConsumption($scope.dataConsumption.includeContent, queriedData, function(estimatedConsumption) {
                    data.clientData.consumption = data.estimation.clientDataConsumption = estimatedConsumption;
                    $scope.queriedData = queriedData;

                    callback(data);
                })
            });
        }
        
        /************************/
        /** Estimation Updates **/
        /************************/
        $scope.updateEstimationCosts = function(clientCount, usagePerDevice, CMGInstances, roamingClientsPercentage, callback) {
            $scope.calculateNewCosts(clientCount, usagePerDevice, CMGInstances, roamingClientsPercentage, function(result) {
                $scope.monthlyCostEstimate     = result.monthlyCost;
                $scope.perDeviceCostEstimation = result.costPerDevice;

                callback();
            });
        }

        /*********************/
        /** Pricing Updates **/
        /*********************/
        $scope.updatePricing = function() {
            $scope.changePricing($scope.selectedRegion, $scope.selectedCurrency, function(response) {
                $scope.refreshCostsAndConfigurations(function(){});
            });
        }

        $scope.selectedRegionChanged = function(region) {
            $scope.updateAvailableCurrencies(region, function() {
                $scope.selectedCurrency = $scope.availableCurrecies[0];

                $scope.updatePricing()
            })
        }

        $scope.refreshCostsAndConfigurations = function(callback) {
            //Costs
            $scope.updateEstimationCosts($scope.devices.count, $scope.clientData.consumption, $scope.CMGInstances.amount, $scope.devices.roamingClientsPercentage,  function() {
                //Configurations
                $scope.updateCurrentPricingConfiguration(function() {
                    callback()
                });
            });
        }

        /******************************************************/
        /**     Estimation Updates + Input validation        **/
        /******************************************************/
        
        /*--------------*/
        /*-  Watchers  -*/
        /*--------------*/
        $scope.$watch('devices.count', function (newCount, oldCount) {
            if ($scope.isCloudCostEstimatorFeatureExposed) {
                var newCountInt = parseInt(newCount);

                if (newCount != "" && ($scope.containsNonDigitRegex.test(newCount) || !$scope.inRange(newCountInt, 0, $scope.inputsMaxValue))) {
                    //Contains a non digit, we go back to the previous value
                    $scope.devices.count = oldCount;
                } else {
                    if (newCount.length > 0) {
                        if (newCountInt != NaN) {
                            $scope.updateEstimationCosts($scope.devices.count, $scope.clientData.consumption, $scope.CMGInstances.amount, $scope.devices.roamingClientsPercentage, function () {});

                            //We Update the CMG instances after changing the amount of devices 
                            $scope.updateCMGInstancesRecomendations(newCountInt, $scope.devices.roamingClientsPercentage, function() {});
                        }
                    }
                }
            }
        }, true);

        $scope.$watch('clientData.consumption', function (newDataConsumption, oldDataconsumption) {
            if ($scope.isCloudCostEstimatorFeatureExposed) {
                var newDataConsumptionInt = parseInt(newDataConsumption);

                if (newDataConsumption != "" && ($scope.containsNonDigitRegex.test(newDataConsumption) || !$scope.inRange(newDataConsumptionInt, 0, $scope.inputsMaxValue))) {
                    //Contains a non digit, we go back to the previous value
                    $scope.clientData.consumption = oldDataconsumption;
                } else {
                    if (newDataConsumption.length > 0) {
                        if (newDataConsumptionInt != NaN) {
                            $scope.updateEstimationCosts($scope.devices.count, $scope.clientData.consumption, $scope.CMGInstances.amount, $scope.devices.roamingClientsPercentage, function() {});
                        }
                    }
                }
            }
        }, true);

        /*-----------------*/
        /*-  Blur events  -*/
        /*-----------------*/
        $scope.devicesCountOnBlur = function() {
            if ($scope.devices.count == "") {
                $scope.devices.count = $scope.estimations.clientCount;
                $scope.updateEstimationCosts($scope.devices.count, $scope.clientData.consumption, $scope.CMGInstances.amount, $scope.devices.roamingClientsPercentage, function() {});
            }
        }

        $scope.clientDataConsumptionOnBlur = function() {
            if ($scope.clientData.consumption == "") {
                $scope.clientData.consumption = $scope.estimations.clientDataConsumption;
                $scope.updateEstimationCosts($scope.devices.count, $scope.clientData.consumption, $scope.CMGInstances.amount, $scope.devices.roamingClientsPercentage, function() {});
            }
        }

        /****************************/
        /**  Options menu changes  **/
        /****************************/

        /*--------------*/
        /*-  Watchers  -*/
        /*--------------*/
        $scope.$watch('selectedCurrency', function (newCurrency, oldCurrency) {
            if ($scope.isCloudCostEstimatorFeatureExposed) {
                //If its not a valid region, we return to the previous one
                if ($scope.availableCurrecies.indexOf(newCurrency) == -1) {
                    $scope.selectedCurrency = oldCurrency;
                } else {
                    $scope.updatePricing()
                }
            }
        }, true);
        
        $scope.$watch("CMGInstances.amount", function(newCMGInstances, oldCMGInstances) {
            if ($scope.isCloudCostEstimatorFeatureExposed) {
                var newCMGInstancesInt = parseInt(newCMGInstances);

                if (newCMGInstances != "" && ($scope.containsNonDigitRegex.test(newCMGInstances) || !$scope.inRange(newCMGInstancesInt, 0, $scope.inputsMaxValue))) {
                    //Contains a non digit, we go back to the previous value
                    $scope.CMGInstances.amount = oldCMGInstances;
                } else {
                    if (newCMGInstances.length > 0) {
                        if (newCMGInstancesInt != NaN) {
                            $scope.updateEstimationCosts($scope.devices.count, $scope.clientData.consumption, newCMGInstancesInt, $scope.devices.roamingClientsPercentage, function(){});
                        }
                    }
                }
            }
        });

        $scope.$watch("devices.roamingClientsPercentage", function(newRoamingClientsPercentage, oldRoamingClientsPercentage) {
            if ($scope.isCloudCostEstimatorFeatureExposed) {
                var newRoamingClientsPercentageInt = parseInt(newRoamingClientsPercentage);

                if (newRoamingClientsPercentage != "" && ($scope.containsNonDigitRegex.test(newRoamingClientsPercentage) || !$scope.inRange(newRoamingClientsPercentageInt, 0, 101))) {
                    //Contains a non digit, we go back to the previous value
                    $scope.devices.roamingClientsPercentage = oldRoamingClientsPercentage;
                } else {
                    if (newRoamingClientsPercentage.length > 0) {
                        if (newRoamingClientsPercentageInt != NaN) {
                            $scope.updateEstimationCosts($scope.devices.count, $scope.clientData.consumption, $scope.CMGInstances.amount, $scope.devices.roamingClientsPercentage, function() {});
                            
                            //We Update the CMG instances after changing the amount of roaming devices
                            $scope.updateCMGInstancesRecomendations($scope.devices.count, $scope.devices.roamingClientsPercentage, function() {});
                        }
                    }
                }
            }
        }, true);

        /*------------------*/
        /*- Change events  -*/
        /*------------------*/
        $scope.regionChanged = function (newRegion, oldRegion) {
            if ($scope.isCloudCostEstimatorFeatureExposed && newRegion != oldRegion ) {
                //If its not a valid region, we return to the previous one
                if ($scope.availableRegions.indexOf(newRegion) == -1) {
                    $scope.selectedRegion = oldRegion;
                } else {
                    $scope.selectedRegion = newRegion;
                    $scope.selectedRegionChanged(newRegion);
                }
            }
        }

        /*-------------------*/
        /*- Spinner Events  -*/
        /*-------------------*/
        $scope.addCMGInstance = function () {
            var instances = parseInt($scope.CMGInstances.amount);
            
            if (instances < $scope.inputsMaxValue) {
                $scope.CMGInstances.amount = parseInt($scope.CMGInstances.amount) + 1;
                $scope.updateEstimationCosts($scope.devices.count, $scope.clientData.consumption, $scope.CMGInstances.amount, $scope.devices.roamingClientsPercentage,  function(){});
            }
        }

        $scope.removeCMGInstance = function () {
            var instances = parseInt($scope.CMGInstances.amount);

            if (instances > 0) {
                $scope.CMGInstances.amount--;
                $scope.updateEstimationCosts($scope.devices.count, $scope.clientData.consumption, $scope.CMGInstances.amount, $scope.devices.roamingClientsPercentage,  function() {});
            }
        }

        $scope.addRoamingClientsPercentage = function () {
            var clientsPercentage = parseInt($scope.devices.roamingClientsPercentage);
            
            if (clientsPercentage < 100) {
                $scope.devices.roamingClientsPercentage = clientsPercentage + 1;
                $scope.updateEstimationCosts($scope.devices.count, $scope.clientData.consumption, $scope.CMGInstances.amount, $scope.devices.roamingClientsPercentage, function() {});
            }
        }

        $scope.removeRoamingClientsPercentage = function () {
            var clientsPercentage = parseInt($scope.devices.roamingClientsPercentage);

            if (clientsPercentage > 0) {
                $scope.devices.roamingClientsPercentage = clientsPercentage - 1;
                $scope.updateEstimationCosts($scope.devices.count, $scope.clientData.consumption, $scope.CMGInstances.amount, $scope.devices.roamingClientsPercentage, function() {});
            }
        }

        /*----------------*/
        /*- Blur events  -*/
        /*----------------*/
        $scope.CMGInstancesOnBlur = function() {
            if ($scope.CMGInstances.amount == "" || $scope.CMGInstances.amount == null) {
                $scope.CMGInstances.amount = $scope.estimations.CMGInstances;
                $scope.updateEstimationCosts($scope.devices.count, $scope.clientData.consumption, $scope.CMGInstances.amount, $scope.devices.roamingClientsPercentage, function() {});
            }
        }

        $scope.roamingClientsPercentageOnBlur = function() {
            if ($scope.devices.roamingClientsPercentage == "" || $scope.devices.roamingClientsPercentage == null) {
                $scope.devices.roamingClientsPercentage = $scope.estimations.roamingClientsPercentage;
                $scope.updateEstimationCosts($scope.devices.count, $scope.clientData.consumption, $scope.CMGInstances.amount, $scope.devices.roamingClientsPercentage, function() {});
            }
        }

        /*------------------------*/
        /*- Data update Methods  -*/
        /*------------------------*/
        $scope.applyAdvancedOptionsDevicesChanges = function() {
            if ($scope.isCloudCostEstimatorFeatureExposed) {
                
                //Updates the estimation amount 
                $scope.calculateDevicesEstimation($scope.devicesIncluded, $scope.queriedData, function (newEstimation) {
                    $scope.estimations.clientCount = $scope.devices.count = newEstimation;

                    // Update price texts
                    $scope.updateEstimationCosts($scope.devices.count, $scope.clientData.consumption, $scope.CMGInstances.amount, $scope.devices.roamingClientsPercentage, function () {
                        $scope.updateDevicesText($scope.devicesIncluded);
                        $scope.updateCMGInstancesRecomendations($scope.devices.count, $scope.devices.roamingClientsPercentage, function() {});
                    });
                });
            
            }
        }

        $scope.applyAdvancedOptionsContentChanges = function () {
            if ($scope.isCloudCostEstimatorFeatureExposed) {
                
                // readjust selected value, current estimation and max value
                $scope.recalculateContentValues(function() {

                    // Update price texts
                    $scope.updateEstimationCosts($scope.devices.count, $scope.clientData.consumption, $scope.CMGInstances.amount, $scope.devices.roamingClientsPercentage,  function() {});
                });
            
            }
        }

        $scope.recalculateContentValues = function(callback) {
            $scope.calculateClientDataConsumption($scope.dataConsumption.includeContent, $scope.queriedData, function(estimatedConsumption) {
                //Update estimation
                $scope.estimations.clientDataConsumption = estimatedConsumption;

                //Update Selected Values
                if ($scope.dataConsumption.includeContent) {
                    $scope.clientData.consumptionMaxValue = parseInt($scope.clientData.consumptionMaxValue) + $scope.queriedData.averageCMBPerMonthPerClient;
                    $scope.clientData.consumption = parseInt($scope.clientData.consumption) + $scope.queriedData.averageCMBPerMonthPerClient;
                } else {

                    //Check boundaries for the max consumption
                    var newMaxConsumption = parseInt($scope.clientData.consumptionMaxValue) - $scope.queriedData.averageCMBPerMonthPerClient;
                    if (newMaxConsumption > 0) {
                        $scope.clientData.consumptionMaxValue = parseInt($scope.clientData.consumptionMaxValue) - $scope.queriedData.averageCMBPerMonthPerClient;
                    } else {
                        $scope.clientData.consumptionMaxValue = 0;
                    }

                    //Check boundaries for consumption
                    var newConsumption = parseInt($scope.clientData.consumption) - $scope.queriedData.averageCMBPerMonthPerClient;
                    if (newConsumption > 0) {
                        $scope.clientData.consumption = parseInt($scope.clientData.consumption) - $scope.queriedData.averageCMBPerMonthPerClient;
                    } else {
                        $scope.clientData.consumption = 0;
                    }
                }
                
                callback();
            });
        }

        $scope.calculateClientDataConsumption = function(contentIncluded, queriedData, callback) {
            var estimatedConsumption = queriedData.averageMPMBPerMonthPerClient;

            if (contentIncluded) {
                estimatedConsumption += queriedData.averageCMBPerMonthPerClient;
            }

            callback(estimatedConsumption);
        }

        $scope.calculateDevicesEstimation = function(selectedDevices, queriedData, callback) {
            var newAmount = 0;

            //Devices
            if (selectedDevices.laptops) {
                newAmount += queriedData.laptopCount;
            }

            if (selectedDevices.servers) {
                newAmount += queriedData.serverCount;
            };

            if (selectedDevices.desktops) {
                newAmount += queriedData.desktopCount;
            };
         
            callback(newAmount);
        }

        /******************/
        /** Reset button **/
        /******************/
        $scope.resetDefaults = function() { 
            $scope.changePricing($scope.defaultRegion, $scope.defaultCurrency, function(){
                $scope.refreshCostsAndConfigurations(function() {
                    $scope.initCloudCostEstimatorValues();
                });
            });
        }

        /***********************************************/
        /** Swap views between main and options frame **/
        /***********************************************/
        $scope.toggleAdvancedOptions = function (value) {
            if ($scope[value]) {
                $scope.customizeMenuText = getString('Hide');
            } else {
                $scope.customizeMenuText = getString('Options')
            }

            $scope[value] = !$scope[value];
        };


        /********************************/
        /** Devices selected info text **/
        /********************************/        
        $scope.updateDevicesText = function(devicesIncluded) {
            if ($scope.anyDeviceEnabledForEstimation(devicesIncluded)) {
                $scope.devices.estimatedDevicesTooltipText = $scope.getUpdatedIncludedDevicesText(devicesIncluded);
            } else {
                $scope.devices.estimatedDevicesTooltipText = $scope.getString("DevicesConfigurationHasNothingSelected");
            }
        }

        // NOTE: This strings should be dynamic as it has the form 'Based on: {0}'. As the parameter can have several devices, the translation can be inacurate.
        //        For simplicity we generate all the cases explicitly to ensure translation accuracy.
        $scope.getUpdatedIncludedDevicesText = function(devices) {
            var result = "BasedOn";

            if (devices.laptops) {
                result += "Laptops";
            }

            if (devices.desktops) {
                result += "Desktops";
            }

            if (devices.servers) {
                result += "Servers";
            }
                        
            return getString(result);
        }

        /*****************************************/
        /** Backend Retrievers (External calls) **/
        /*****************************************/

        /**
         * Callback parameter is represented by CloudCostsEstimationCurrentPricingConfigurationDTO.
        **/
        $scope.getCurrentPricingConfiguration = function(callback) {
            callback(
                JSON.parse(window.external.GetCurrentPricingConfiguration())
            );
        }

        $scope.getFeatureExposureStatus = function(callback) {
            callback(
                JSON.parse(window.external.GetCloudCostEstimatorFeatureExposureStatus())
            );
        }

        $scope.getCMGInstancesRecomendation = function(clientCount, callback) {
            callback(
                JSON.parse(window.external.CalculateCMGInstancesRecomendation(clientCount))
            );
        };

        $scope.getMaxValueSupported = function(callback) {
            callback(
                JSON.parse(window.external.GetMaxValueSupported())
            );
        };

        $scope.calculateNewCosts = function (clientCount, usagePerDevice, CMGInstances, roamingClientsPercentage, callback) {
            callback(
                JSON.parse(window.external.CalculateCloudUsageCost(usagePerDevice, clientCount, roamingClientsPercentage, CMGInstances))
            )
        }
        
        $scope.getCMGInstancesRecomendations = function(clientCount, roamingClientsPercentage, callback) {
            callback(
                JSON.parse(window.external.CalculateCMGInstancesRecomendation(clientCount, roamingClientsPercentage))
            );
        }

        $scope.getAvailableCurrencies = function(region, callback) {
            callback(
                JSON.parse(window.external.GetAvailableCurrencies(region))
            );
        }

        $scope.getAvailableRegions = function(callback) {
            callback(
                JSON.parse(window.external.GetAvailableRegions())
            );
        }

        // TODO: Check error handling when window.external call fails, how to handle this on the frontend?
        $scope.changePricing = function(region, currency, callback) {
            callback(
                JSON.parse(window.external.ChangePricing(region, currency))
            );
        }

        $scope.getDefaultRoamingClientsPercentage = function(callback) {
            callback(
                JSON.parse(window.external.GetDefaultRoamingClientsPercentage())
            );
        }

        /****************************************/
        /** Retrievers internal state updaters **/
        /****************************************/
        $scope.updateRoamingClientsPercentage = function(callback) {
            $scope.getDefaultRoamingClientsPercentage(function(roamingClientsPercentage) {
                $scope.devices.roamingClientsPercentage     = roamingClientsPercentage;
                $scope.estimations.roamingClientsPercentage = roamingClientsPercentage; 

                callback();
            })
        }

        $scope.updateCMGInstancesRecomendations = function(deviceCount, roamingClientsPercentage, callback) {
            $scope.getCMGInstancesRecomendations(deviceCount, roamingClientsPercentage, function(CMGInstancesRecomended){
                $scope.CMGInstances.amount      = CMGInstancesRecomended;
                $scope.estimations.CMGInstances = CMGInstancesRecomended;
                
                callback();
            });
        }

        $scope.updateAvailableCurrencies = function(region, callback) {
            $scope.getAvailableCurrencies(region, function(currencies) {
                 $scope.availableCurrecies = currencies;

                 callback();
            });
        }

        $scope.updateAvailableRegions = function(callback) {
            $scope.getAvailableRegions(function(regions) {
                $scope.availableRegions = regions;

                callback()
            })
        }

        $scope.updateCurrentPricingConfiguration = function(callback) {
            $scope.getCurrentPricingConfiguration(function(currentConfiguration){    
                $scope.selectedRegion   = currentConfiguration.region;
                $scope.selectedCurrency = currentConfiguration.currency;

                callback()
            });
        };

        $scope.updateFeatureExposureStatus = function(callback) {
            $scope.getFeatureExposureStatus( function(exposureStatus) {
                $scope.isCloudCostEstimatorFeatureExposed = exposureStatus;

                callback();
            });
        }

        /*************/
        /** Helpers **/
        /*************/
        $scope.containsNonDigitRegex = new RegExp("\\D", "g");

        $scope.inRange = function(number, min, max) {
            return !isNaN(number) && number >= min && number < max;
        }

        $scope.anyDeviceEnabledForEstimation = function(devicesIncluded) {
            var anyEnabled = false; 

            Object.keys(devicesIncluded).forEach( function(key) {
                anyEnabled |= devicesIncluded[key];
            });

            return anyEnabled;
        }

        $scope.dictionariesDiffer = function(dictA, dictB) {
            var differ = false;
            
            Object.keys(dictA).forEach( function(key) {
                differ |= dictA[key] != dictB[key];
            });

            return differ;
        }

        $scope.initCloudCostEstimatorValues();
    });

//  Theres a bug in angular where the min and max values of an input range are
//    processed after the actual value of the input, so that ends up in a weird slider
//    behaviour, this directive is a workaround. 
//  The bug was fixed on angular v1.6.0, if in the future the angular version
//    that we use is updated, this can be removed.
//  References:
//      StackOverflow post: https://stackoverflow.com/questions/26453634/how-to-initialize-the-value-of-an-inputrange-using-angularjs-when-value-is-ove
//      Angular repo fix commit: https://github.com/angular/angular.js/commit/a272a3c0bd88b6df354102dc059a0d14b5b22675

    dashboard.directive('slider', function () {
        return {
            restrict: 'E',
            template: '<input type="range">',
            replace: true,
            transclude: true,
            link: function($scope, elem, attr) {
                elem.attr('max', attr.max);
            }
        }
    });
}(window.angular));
// SIG // Begin signature block
// SIG // MIIomQYJKoZIhvcNAQcCoIIoijCCKIYCAQExDzANBglg
// SIG // hkgBZQMEAgEFADB3BgorBgEEAYI3AgEEoGkwZzAyBgor
// SIG // BgEEAYI3AgEeMCQCAQEEEBDgyQbOONQRoqMAEEvTUJAC
// SIG // AQACAQACAQACAQACAQAwMTANBglghkgBZQMEAgEFAAQg
// SIG // FinhkjMaNkhhCdAmjk2FNItxhpBLvtQFD3/p9PGbI6Sg
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
// SIG // AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCBE9Bx5J3IvvLvL
// SIG // Xm2LcX/4VWmwddLMV53vuLJq5DuP1zCBigYKKwYBBAGC
// SIG // NwIBDDF8MHqgXIBaAE0AaQBjAHIAbwBzAG8AZgB0AC4A
// SIG // VABvAG8AbABrAGkAdAAuAFcAcABmAC4AVQBJAC4AQwBv
// SIG // AG4AdAByAG8AbABzAC4AVwBlAGIAVgBpAGUAdwAuAGQA
// SIG // bABsoRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
// SIG // BgkqhkiG9w0BAQEFAASCAQCVAIubN1qU5dqsCrYjFpWu
// SIG // KgEss2yDMk91V+UYGeXbhMo/lwYQS0nLai9pe/GA42yp
// SIG // cAisLOfymmF9a1JaKK1Ja8MZ4H75m/2OPbbDB0kA3Ai2
// SIG // we5+XcLKd00ffnCB0jVr2KoahcgQGZLWJVdDxHWck9zY
// SIG // Go/oYX8laF3xgRgaSZDmbVAj04qQdp2zgFkMv66sCD87
// SIG // f5aM7FGbbqzn5f+BHbMP8NRQLOuuTfRhjuIkCdhe0YEt
// SIG // rSRhYpTLZkgPbGv9aeFGvT0++pmeirumgehZ7nFJF3Xx
// SIG // w7Kv7OyL4rdobw3EVvOx3unEAlic7m2aX0ocbeD061ZU
// SIG // FX9fwUqB16h3oYIXrTCCF6kGCisGAQQBgjcDAwExgheZ
// SIG // MIIXlQYJKoZIhvcNAQcCoIIXhjCCF4ICAQMxDzANBglg
// SIG // hkgBZQMEAgEFADCCAVoGCyqGSIb3DQEJEAEEoIIBSQSC
// SIG // AUUwggFBAgEBBgorBgEEAYRZCgMBMDEwDQYJYIZIAWUD
// SIG // BAIBBQAEIOhLKevEe1RabWYp3WAPL11mJzyY+S70A2c0
// SIG // qIay4d/HAgZo8jMcb3gYEzIwMjUxMDIzMDI0NzQ5Ljc0
// SIG // NlowBIACAfSggdmkgdYwgdMxCzAJBgNVBAYTAlVTMRMw
// SIG // EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
// SIG // b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
// SIG // b24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9w
// SIG // ZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNoaWVs
// SIG // ZCBUU1MgRVNOOjU5MUEtMDVFMC1EOTQ3MSUwIwYDVQQD
// SIG // ExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloIIR
// SIG // +zCCBygwggUQoAMCAQICEzMAAAIUjc0jRO4G33IAAQAA
// SIG // AhQwDQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMx
// SIG // EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
// SIG // ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
// SIG // dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3Rh
// SIG // bXAgUENBIDIwMTAwHhcNMjUwODE0MTg0ODE4WhcNMjYx
// SIG // MTEzMTg0ODE4WjCB0zELMAkGA1UEBhMCVVMxEzARBgNV
// SIG // BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
// SIG // HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEt
// SIG // MCsGA1UECxMkTWljcm9zb2Z0IElyZWxhbmQgT3BlcmF0
// SIG // aW9ucyBMaW1pdGVkMScwJQYDVQQLEx5uU2hpZWxkIFRT
// SIG // UyBFU046NTkxQS0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1p
// SIG // Y3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0G
// SIG // CSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDJT6daAJTK
// SIG // 9/IY/XNMWQuR2A661dxW14//QJ5d+sX/rpyEqXj8xkMJ
// SIG // DoTxSviSqALFC95/suDWB+yjURZYobq+LHVXG287WQ8Y
// SIG // rg9kqY56h4vrwXr4zDYRE/LgEva8kp/oujlntfTGRGO1
// SIG // y98z1PQcOB8dRbrPUJuBCKqsTGzY0fbutalSTJNiswbp
// SIG // NfLf34Z0w5OBfJQOJEZUcDLcSpg3DfNJa6yfTN52Xpr/
// SIG // UNudchy+f0VofN3/3oQ80E4J3a86lLQKTuSCSNXHA6m2
// SIG // xZrwj6b4MDjdzCUSs9oh3zgZt0bOjdWg7tiEKZAihFpv
// SIG // R3yivk+bKD5UyXyN6g31J5TFVmkEj9xDhNdcqUsOR9vP
// SIG // NJCuJWJAYkYku0pLcNNU24GqmNct27anZir04M+pkKiI
// SIG // 0GHgIHpfaIthRI7y2ZtRUswwR6Bu8dItdBHzxA0gKMWg
// SIG // EEMIPJ2hOj39M2SrzSY7vvAMzTi0929sybFPTUZOh3rQ
// SIG // knFQaYxOCx6CF0EaOQ34PoaxSlju1ruE/0/Muuz4CXG7
// SIG // jpdPbXtsGfoTAmwBgBz0LbyYpFRyghlZBFv4xyhlpK7Y
// SIG // RxLO4iUBo0hA20aXPY8Xd+hJ4aZz9XuAIazwAeSIrBfM
// SIG // lI9+2ewfw79HeknDYP/aEcTcnPEfZKstfUV0jsOvDXjk
// SIG // +QvSFsUvoxUIKQIDAQABo4IBSTCCAUUwHQYDVR0OBBYE
// SIG // FNtf9uzVxKnJNidi5/8y30I82HAbMB8GA1UdIwQYMBaA
// SIG // FJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYw
// SIG // VKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9w
// SIG // a2lvcHMvY3JsL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAl
// SIG // MjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRg
// SIG // MF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9z
// SIG // b2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIw
// SIG // VGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwG
// SIG // A1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUH
// SIG // AwgwDgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUA
// SIG // A4ICAQA/fGn0Pga7RIf0H7UkfSGzAWq4g1pNP5GOl8Sv
// SIG // xSZQ54OXhTm5X6Lbz95JhczGB6bfIFnLBgPK9/ioxdS9
// SIG // sNyWU2pHIvZG/yNK7zByW39VLX5zlxUIl8z5Ye+RSv50
// SIG // J9SU7L2fh7EI9fUvq5bAUfl6gV+o8SncXDfSKsw3ZKic
// SIG // cEreYHy8OPcPzSgkqp7a1q07fzIxOJER0LYcPt5UhRYv
// SIG // t3nhS2hjHPCQk3W3uAQQaiyAGl2bApVhgM7VRJZI2ZkQ
// SIG // uCVgDguhWgYO5Zs3uYPxWjNgGx+Rlqs7KsliUX9QINks
// SIG // Hxdot+sx8zJlMwI64S48PjOPyPL8m3jRyWshbThy8uGS
// SIG // GTJ0HNyuYLYfF4TfqAmyH6POaK9L1i/KI+EuSibUU/QM
// SIG // gWvhWWrJccpqCu2epIXxDISmq1BLvBLtnNkXR5l7R+xg
// SIG // PQnVFqttW4PGZayrjmfW+NF2ie24ZR2asbY4Z4p3wC2I
// SIG // 2CF+dptUFuCliBzH94vJb+fjR5NsoiWybRyx7K5a9gXI
// SIG // 6pBeOha0vj+xQfGVYiyuOc1qs2v486QvwLWMYEIm6+bR
// SIG // RiCOEhov5cFdq+ts61f2atnfLwZAPFZefeaGozbVlwaT
// SIG // zfFJGoH15x8Zg1EbqDrm/rfmBLNSYEplZZwM3PACjGyA
// SIG // SNMVfPpqF/KsEuqyGuMlc8p8770CvzCCB3EwggVZoAMC
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
// SIG // OjU5MUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3Nv
// SIG // ZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4D
// SIG // AhoDFQDZHKxfX3pFctPAD8/xEVZ1ROlSxqCBgzCBgKR+
// SIG // MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5n
// SIG // dG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
// SIG // aWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1p
// SIG // Y3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqG
// SIG // SIb3DQEBCwUAAgUA7KPxTjAiGA8yMDI1MTAyMzAwMTE1
// SIG // OFoYDzIwMjUxMDI0MDAxMTU4WjB0MDoGCisGAQQBhFkK
// SIG // BAExLDAqMAoCBQDso/FOAgEAMAcCAQACAh79MAcCAQAC
// SIG // AhL2MAoCBQDspULOAgEAMDYGCisGAQQBhFkKBAIxKDAm
// SIG // MAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAIAgEA
// SIG // AgMBhqAwDQYJKoZIhvcNAQELBQADggEBAHDnxNXbr8+E
// SIG // NLQ6FSFl9+wkThKrD4EaQRwDYtYiE94ANsVp9UlS5cPU
// SIG // QgiCxDoXNuVxNyCvQXPj3M1nGZ/XnkebBpcTjHj8Cw8S
// SIG // 1HsdE6uRU04ESkFWKWpbnzDRi0xLENq0T+il/1ok04oK
// SIG // bSkEWhKcfuLQeu39njBRbEw7UhgBwxqHGtH/dUq1cCpZ
// SIG // maDXn9hzS3Wk63tZolglQgoK4ayno1lnrziWAM8tlr2C
// SIG // cAFxPLaQBFBNN6xTbQWgX+DUjK/GGMpUkKy1d7U3L6H7
// SIG // buPywQcFKj7LhiERhU3M8o+D6HzDPPH2vrBZ/qDOuSo+
// SIG // REH/bYQgZcUvYHJ16icvvQExggQNMIIECQIBATCBkzB8
// SIG // MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
// SIG // bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
// SIG // cm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNy
// SIG // b3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAhSN
// SIG // zSNE7gbfcgABAAACFDANBglghkgBZQMEAgEFAKCCAUow
// SIG // GgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqG
// SIG // SIb3DQEJBDEiBCDUtwAQBKzYsf7/hTi4ydjN70eTLPnY
// SIG // eYJa3DsFZh1UezCB+gYLKoZIhvcNAQkQAi8xgeowgecw
// SIG // geQwgb0EIDZ4q+9bHltyiLjdtE7f4S21BQK/J4PZ1tfL
// SIG // /r7TEr7HMIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzAR
// SIG // BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
// SIG // bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
// SIG // bjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAg
// SIG // UENBIDIwMTACEzMAAAIUjc0jRO4G33IAAQAAAhQwIgQg
// SIG // vxzC5MFtqjj80TDAl3QDb6JOEYmN5s6KaKd5HQeGMncw
// SIG // DQYJKoZIhvcNAQELBQAEggIARajn4yxc1riY8ho0Aure
// SIG // YnVQn+/er4ddDtl5g8n7NPGlsljQ+aTC2jH3B5G0HsQz
// SIG // s81mZy2dvUXOXNSOrCT9wC6UixcN1QlianqkQSdqGeQ5
// SIG // 9r1678J1VxnP1q/LTpUN61cn03vso9voenXgGIKNWk+g
// SIG // SuJdbbdpQiW7agvfsYonGeY4hE/2AwVMYazR6iwtfR1b
// SIG // 33Gn82YSZcuyCpZFBDhOlx1GOlrclnsE3oPdEwvqH59L
// SIG // NvJMPV8zyVarLS1105GOWaltdPK1a5A0F4TGTQ/MocZy
// SIG // Or+STjQhH6hXQG5DUq7Q0nuqR4CtpxtjA4eRkMzbUNAC
// SIG // TZeaRAjX9V0ZvztAsbrfZNr3hiIfT9fJjHi1TsFPF9iT
// SIG // ti0qgibFwKIwSmH2X3jnocdHVtw3jX2fkT1p+8qi2/u+
// SIG // dRqQ4ZJcHLZ9fZmGXr3CJwpC1dqM30ElWgyEeF82jbk2
// SIG // YjQn6qt3+I+ZOPkuT6fVPb3x5IarAkrMVollnpQuCeC3
// SIG // 0Zp+bSm2MQxV2SaPxyLZDfksJJ/KZAVQVwDHSrOmOkqI
// SIG // eSPRAc8VQUo+1jySC0J7jATa8Pj+GD/EXGd6KKgsaYrY
// SIG // EyRykwpJcly7ilqF8ioxUgtKTyt7qJ+R5CmXYLellgRX
// SIG // fI5YdulslmwuApbXTMtcDVhBuZazUEkH+NoE8qLhuWTPO8M=
// SIG // End signature block
