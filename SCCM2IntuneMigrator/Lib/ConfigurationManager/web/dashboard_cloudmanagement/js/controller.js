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

        $scope.renderHtml = function (html) {
            return $sce.trustAsHtml(html);
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

            // Setup aria for Azure AD users chart
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

            // Setup aria for Azure AD devices chart
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

            // Setup aria for Approved clients with Azure AD identity chart
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
// SIG // MIInywYJKoZIhvcNAQcCoIInvDCCJ7gCAQExDzANBglg
// SIG // hkgBZQMEAgEFADB3BgorBgEEAYI3AgEEoGkwZzAyBgor
// SIG // BgEEAYI3AgEeMCQCAQEEEBDgyQbOONQRoqMAEEvTUJAC
// SIG // AQACAQACAQACAQACAQAwMTANBglghkgBZQMEAgEFAAQg
// SIG // 2apN15h8YkULnBW72iFfpgHqPwEmhRajo6GtusaEpdqg
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
// SIG // ARUwLwYJKoZIhvcNAQkEMSIEIKZAobcie2Cl6z3gkmb0
// SIG // GbcbWlsxqDaI9vzOgZbwYbWwMEIGCisGAQQBgjcCAQwx
// SIG // NDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRw
// SIG // Oi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEB
// SIG // BQAEggEAPMNV/u3FUYO9y5qDaWhMgiTjCYshsB1Yy/tY
// SIG // +k7g+a6DaDxCSO1VqJbW0YSJx6LWIroAx6HexqqfFpea
// SIG // CEO6ncrzo4UQ+l5TDR2PYCsXTn3SxohXxYth56hFmUlN
// SIG // LNtB1GTdgpmGbLcLeYZ1/7nqBSYyE4+/otmDm6JaT1IL
// SIG // ESe2lNJhOQG9aGMNERpssUCFK1ol2ex0H/S0cRfFXzGg
// SIG // vFrkELGCrYsFoqJXnDB+8NpS00vsqvQvyTpKcfz0EfJa
// SIG // pMN3YuMpTJcKPfg3+U5nFxYDZ/xhU5blQFImnaxdNc+Q
// SIG // G1K5c1eJ9kYyMVL+QiI/Gh+nXdQSULiUhurzr2vKx6GC
// SIG // FywwghcoBgorBgEEAYI3AwMBMYIXGDCCFxQGCSqGSIb3
// SIG // DQEHAqCCFwUwghcBAgEDMQ8wDQYJYIZIAWUDBAIBBQAw
// SIG // ggFZBgsqhkiG9w0BCRABBKCCAUgEggFEMIIBQAIBAQYK
// SIG // KwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCBQuVWw
// SIG // u8vzkSTso21EooTi/KBr4oMA1OuqfiWd0/iTsAIGY2Pf
// SIG // aYHLGBMyMDIyMTEwNDE3MjMzOS44MzJaMASAAgH0oIHY
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
// SIG // IgQgtPrEGjADrYhRxFqTFQHG4KV3w3JU37jnM6gMuZ1D
// SIG // hOQwgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCBk
// SIG // 60bO8W85uTAfJVEO3vX2aLaQFcgcGpdwsOoi+foP9DCB
// SIG // mDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
// SIG // YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
// SIG // VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNV
// SIG // BAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEw
// SIG // AhMzAAABufYADWVUT7wDAAEAAAG5MCIEIEpB3xr7eyxp
// SIG // TDMMf8hGiLLzDeIEhxmj1CIruH9UfJ8sMA0GCSqGSIb3
// SIG // DQEBCwUABIICAB2zdoxlh3vzNUhh17Ec6TwTbxDH/egv
// SIG // iCOpVgODfOQ88ZF2wVOngXYtY2l6ixPAeMg4mJ2/yh25
// SIG // XfKs9xJlPcww4YNvDDKBd4/Rfpe2tvm2fzsis7+croMD
// SIG // 1PKribu5L7wnYRRUQWeYvKy1A0qTVq0Qi8L/ZmU19NvN
// SIG // T3mDvIwKACp0DnHY/qZiliHoBuVd6/oJkrfxtUceRnGQ
// SIG // z+yi2tyDXg3ffe9SjHTq1pPtalXYk6vf9H6nGsosA229
// SIG // HoOvh9xHdotgSxipjOGoNRQ/U66SKvz+RaM1H+DvR+YS
// SIG // ki5LNxBcyh4W1Jaxq4dvsWG/b8tquP832DJQHU0z3Anv
// SIG // qoltHQbWEIPB8Q75cjA5dCRJZJe13yIQeo5M4bTDq28Q
// SIG // UA7Vg5MJ52RkF8ygYGSBgOpUrBJeCrBJqevoG2UCMDs9
// SIG // 4rWlhMFSfJFWNupdU19qYcGZO9RuE9HoOqODK6JF5gg4
// SIG // Iqwgqzx4p2TibLOBbljCbtojD7AFb4D1k9fz9xyC0Gm7
// SIG // i2XblfQ1tYhxkpzJ6YazHjqF4JBf64ts47a0fWrbUY85
// SIG // jO9B1HcRxDXRaGe4NefMzZ3AEf7+aIbZAEjLVxJ1J9hK
// SIG // xckhchwTfpbrF94YQ2PcG/rqFpxowsRCY/DizVKcCJoF
// SIG // GgGfnrhSUJRkNPUgmWtXTU4obd9wsI1Ck1dD
// SIG // End signature block
