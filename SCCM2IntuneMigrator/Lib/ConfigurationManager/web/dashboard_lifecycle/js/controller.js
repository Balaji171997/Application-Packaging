(function () {
    "use strict";

    var dashboard = angular.module("dashboard", []);

    dashboard.controller("dashboardController", function ($scope, $sce) {
        $scope.strings = getStrings([
            "AISPDisabledWarning",
            "All",
            "Category_All",
            "Category_ConfigMgr",
            "Category_Database",
            "Category_Office",
            "Category_WinClient",
            "Category_WinServer",
            "Client",
            "Database",
            "Days",
            "DaysFormat",
            "EOLProductsLabel",
            "Expand",
            "Expired",
            "Extended",
            "ExtendedSupport",
            "ExtendedSupportEndDate",
            "LearnMore",
            "LegalText",
            "LifecycleChartLabel",
            "LifecycleStartDate",
            "Mainstream",
            "MainstreamSupport",
            "MainstreamSupportEndDate",
            "NearEOLProductsLabel",
            "NextSteps",
            "NoDataFound",
            "None",
            "NoProductsFound",
            "NumberInEnvironment",
            "ProductCategory",
            "ProductInformation",
            "ProductName",
            "ReportFileLoadError",
            "RowXOfYFormat",
            "Server",
            "ShowChart",
            "ShowTable",
            "Support",
            "SupportTimeRemaining",
            "WarningIconAltText",
            "YearsFormat",
            "MonthsRemaining",
        ]);

        $scope.strings.LastUpdated = window.external.GetLastUpdated();

        $scope.DefaultDate = new Date(1970, 1, 2);

        $scope.IsValidDate = function (dateAsLocalDate) {
            return dateAsLocalDate >= $scope.DefaultDate;
        };

        $scope.GetSupportEndDate = function (lifecycleItem) {
            var endDate = lifecycleItem.ExtendedSupportEndDate;
            if ($scope.IsValidDate(endDate)) {
                return endDate;
            } else {
                return lifecycleItem.MainstreamSupportEndDate;
            }
        };

        $scope.dateOnlyISO8601Regex = /(\d\d\d\d)-(\d{1,2})-(\d{1,2})/;

        //Date.parse treats date-only ISO8601 strings as UTC instead of local
        //We parse the dates ourselves to get a local version
        $scope.dateOnlyISO8601StringToLocalDate = function (dateOnlyISO8601String) {
            var result = dateOnlyISO8601String.match($scope.dateOnlyISO8601Regex);
            if (result != null) {
                var year = parseInt(result[1], 10);
                var month = parseInt(result[2], 10);
                var day = parseInt(result[3], 10);
                return new Date(year, month - 1, day);
            } else {
                return $scope.DefaultDate;
            }
        };

        $scope.reportingEnabled = (window.external.GetReportingEnabled().trim().toUpperCase() == "TRUE");
        $scope.aispEnabled = (window.external.GetAISPEnabled().trim().toUpperCase() == "TRUE");
        $scope.isCAS = (window.external.GetIsCAS().trim().toUpperCase() == "TRUE");
        $scope.updateEnabled2103 = (window.external.GetUpdateEnabled2103().trim().toUpperCase() == "TRUE");

        $scope.lifecycleData = JSON.parse(window.external.GetLifecycleData());

        for (var i = 0, len = $scope.lifecycleData.length; i < len; i++) {
            $scope.lifecycleData[i].MainstreamSupportEndDate = $scope.dateOnlyISO8601StringToLocalDate($scope.lifecycleData[i].MainstreamSupportEndDateISO8601);
            $scope.lifecycleData[i].ExtendedSupportEndDate = $scope.dateOnlyISO8601StringToLocalDate($scope.lifecycleData[i].ExtendedSupportEndDateISO8601);
        }

        $scope.lifecycleData.sort(function (left, right) {
            var leftDate = $scope.GetSupportEndDate(left);
            var rightDate = $scope.GetSupportEndDate(right);

            if (leftDate < rightDate) {
                return -1;
            } else if (leftDate > rightDate) {
                return 1;
            } else {
                return left.GroupName.localeCompare(right.GroupName);
            }
        });

        $scope.createBarChartWithXAxisLabels = function (config) {
            var enable = true;
            var chartPattern = [config.BarColor] || ["#00BBF1", "#2E75B6", "#70AD47", "#A6A6A6"];
            var noData = (config.ChartData.length <= 1) || (config.ChartXAxisLabels.length <= 1);
            var summaryText = ""; /* This used to be config.ChartTitle + ". " but that causes a duplicate chart title because the H1 chart header is read as part of the aria group. */

            var columns;
            if (noData) {
                enable = false;
                chartPattern = ["#a9a9a9"];
                columns = [[config.ChartData[0], 0], [config.ChartXAxisLabels[0], $scope.strings.NoProductsFound]];
                summaryText = summaryText + $scope.strings.NoProductsFound + ".";
            } else {
                var str = [];
                columns = [config.ChartData, config.ChartXAxisLabels];
                for (var i = 1; i < config.ChartData.length; ++i) {
                    str.push(config.ChartXAxisLabels[0] + ", " + config.ChartXAxisLabels[i] + ", " + config.ChartData[0] + ", " + config.ChartData[i] + ".");
                }
                summaryText = summaryText + str.join(" ");
            }

            var chartConfig = {
                bindto: "#" + config.ChartID,
                padding: {
                    bottom: 100,
                    right: 6,
                },
                data: {
                    x: config.ChartXAxisLabels[0],
                    columns: columns,
                    type: 'bar',
                },
                axis: {
                    x: {
                        type: 'category',
                    },
                    y: {
                        label: {
                            text: config.ChartYAxisLabel,
                            position: 'outer-middle',
                        },
                        max: config.YMax,
                        min: config.YMin,

                        padding: {
                            top: 0,
                            bottom: 0,
                        },
                    },
                },
                interaction: {
                    enabled: enable,
                },
                legend: {
                    //position: "bottom",
                    //show: enable,
                    show: false,
                },
                color: {
                    pattern: chartPattern,
                },
                bar: {
                    label: {
                        format: function (value, ratio, id) {
                            if (enable)
                                return value;
                            else
                                return 0;
                        },
                    },
                    expand: enable,
                },
                grid: {
                    focus: {
                        /* This gets rid of the line that is drawn through the middle of a bar when the mouse is hovering over it */
                        show: false,
                    },
                },
            };

            //Special handling for an empty graph so that the y-axis intervals don't display decimal points
            if ((columns[0].length == 1) && !noData) {
                columns[0] = columns[0].slice(0);
                columns[0].push(10);

                columns[1] = columns[1].slice(0);
                columns[1].push("");

                //chartConfig.axis.y.padding = { top: 0, bottom: 0 };
            }

            //Generate the chart.
            var chartObject = c3.generate(chartConfig);

            //Setup ARIA. To make this work with Narrator without an unnecessary tab stop we give the owning
            //DIV an aria-label, set give the SVG both the img role and an attribute pointing to the div.
            //We also need to disable the SVG's internal tab stop since it is considered non-interactive
            //and only interactive elements should be tab stops according to MAS.
            var chartOwner = chartObject.element;

            chartOwner.setAttribute('aria-label', summaryText);

            for (var i = 0; i < chartOwner.childNodes.length; ++i) {
                var childNode = chartOwner.childNodes[i];

                $scope.hideChildrenFromAria(childNode);

                if (childNode.nodeName.toUpperCase() == 'SVG') {
                    childNode.setAttribute('role', 'img');
                    childNode.setAttribute('aria-labelledby', chartOwner.id);

                    childNode.setAttribute('focusable', 'false');
                    childNode.removeAttribute('tabindex');
                }
            }

            return chartObject;
        };

        $scope.hideChildrenFromAria = function (node) {
            var childNodes = node.childNodes;
            for (var i = 0; i < childNodes.length; ++i) {
                var childNode = childNodes[i];
                if (childNode instanceof Element || childNode instanceof HTMLDocument) {
                    childNode.setAttribute('aria-hidden', 'true');
                    childNode.setAttribute('focusable', 'false');
                    childNode.removeAttribute('tabindex');
                }

                $scope.hideChildrenFromAria(childNode);
            }
        }

        $scope.getTodaysDate = function () {
            var today = new Date();
            return new Date(today.getFullYear(), today.getMonth(), today.getDate(), 0, 0, 0, 0);
        }

        $scope.addDays = function (originalDate, days) {
            var newDate = new Date(originalDate.valueOf());
            newDate.setDate(newDate.getDate() + days);
            return newDate;
        }

        $scope.processLifecycleGridInformation = function (productInfo) {
            var _MS_PER_DAY = 86400000; /* 1000 * 60 * 60 * 24 */
            var today = $scope.getTodaysDate();
            var todayUTC = Date.UTC(today.getFullYear(), today.getMonth(), today.getDate());

            var products = [];

            productInfo.forEach(function (item) {
                var mainstreamSupportEndDate = item.MainstreamSupportEndDate;
                var extendedSupportEndDate = item.ExtendedSupportEndDate;
                var supportDaysRemaining;

                var mainstreamSupportEndDateUTC = Date.UTC(mainstreamSupportEndDate.getFullYear(), mainstreamSupportEndDate.getMonth(), mainstreamSupportEndDate.getDate());
                var extendedSupportEndDateUTC = Date.UTC(extendedSupportEndDate.getFullYear(), extendedSupportEndDate.getMonth(), extendedSupportEndDate.getDate());
                var furthestDateUTC = Math.max(mainstreamSupportEndDateUTC, extendedSupportEndDateUTC);
                if (furthestDateUTC >= todayUTC) {
                    supportDaysRemaining = Math.round((furthestDateUTC - todayUTC) / _MS_PER_DAY);
                } else {
                    supportDaysRemaining = 0;
                }

                products.push({
                    GroupName: item.GroupName,
                    MainstreamSupportEndDate: item.MainstreamSupportEndDate,
                    MainstreamSupportEndDateDisplay: item.MainstreamSupportEndDateDisplay,
                    ExtendedSupportEndDate: item.ExtendedSupportEndDate,
                    ExtendedSupportEndDateDisplay: item.ExtendedSupportEndDateDisplay,
                    SupportDaysRemaining: supportDaysRemaining,
                    InstallCount: parseInt(item.InstallCount),
                    MoreInformationLink: item.MoreInformationLink,
                    Category: item.Category,
                    LocalizedCategory: item.LocalizedCategory,
                });
            });

            products.sort(function (left, right) {
                if (left.SupportDaysRemaining < right.SupportDaysRemaining) {
                    return -1;
                } else if (left.SupportDaysRemaining > right.SupportDaysRemaining) {
                    return 1;
                }

                if (left.InstallCount < right.InstallCount) {
                    return 1;
                } else if (left.InstallCount > right.InstallCount) {
                    return -1;
                }

                var result = left.GroupName.localeCompare(right.GroupName);
                return left.GroupName.localeCompare(right.GroupName);
            });

            return products;
        };

        $scope.getProductsNearEndOfLife = function (lifecycleData) {
            var _MS_PER_DAY = 86400000; /* 1000 * 60 * 60 * 24 */
            var today = $scope.getTodaysDate();

            //multiplies number of months by average num of days in a month, rounded to nearest whole day.
            var daysToAdd = Math.round(document.getElementById('product-filter-slider').value * 30.44);
            var cutoff = $scope.addDays(today, daysToAdd);

            var todayUTC = Date.UTC(today.getFullYear(), today.getMonth(), today.getDate());
            var cutoffUTC = Date.UTC(cutoff.getFullYear(), cutoff.getMonth(), cutoff.getDate());
            var filteredProducts = [];

            lifecycleData.forEach(function (item) {
                var extendedSupportEndDate = $scope.GetSupportEndDate(item);
                var extendedSupportEndDateUTC = Date.UTC(extendedSupportEndDate.getFullYear(), extendedSupportEndDate.getMonth(), extendedSupportEndDate.getDate());

                if ((extendedSupportEndDateUTC >= todayUTC) && (extendedSupportEndDateUTC <= cutoffUTC)) {
                    filteredProducts.push(item);
                }
            });

            return filteredProducts;
        };

        $scope.getExpiredProducts = function (lifecycleData) {
            var _MS_PER_DAY = 86400000; /* 1000 * 60 * 60 * 24 */
            var today = $scope.getTodaysDate();
            var todayUTC = Date.UTC(today.getFullYear(), today.getMonth(), today.getDate());
            var filteredProducts = [];

            lifecycleData.forEach(function (item) {
                var extendedSupportEndDate = $scope.GetSupportEndDate(item);
                var extendedSupportEndDateUTC = Date.UTC(extendedSupportEndDate.getFullYear(), extendedSupportEndDate.getMonth(), extendedSupportEndDate.getDate());

                if (extendedSupportEndDateUTC < todayUTC) {
                    filteredProducts.push(item);
                }
            });

            return filteredProducts;
        };

        $scope.getNameAndInstallCountOnly = function (productArray) {
            var installCounts = [$scope.strings.NumberInEnvironment];
            var productNames = [$scope.strings.ProductName];
            productArray.forEach(function (item) {
                installCounts.push(item.InstallCount);
                productNames.push(item.GroupName);
            });
            return [installCounts, productNames];
        }

        $scope.createTextNode = function (text, classname) {
            var textNode = document.createTextNode(text);
            if (classname) {
                textNode.className += ' ' + classname;
            }
            return textNode;
        }

        $scope.addCellToTableRow = function (tr, non_td_cell_contents) {
            var td = tr.insertCell(-1);
            td.appendChild(non_td_cell_contents);
            return td;
        }

        $scope.addTextCellToTableRow = function (tr, text) {
            var textNode = $scope.createTextNode(text, 'text-align-left');
            return $scope.addCellToTableRow(tr, textNode);
        }

        $scope.formatDateForLifecycleTable = function (today, date, displayDate) {
            //if (date < today) return $scope.strings.Expired;
            if (date < today) return "-";
            return displayDate;
        }

        $scope.createLinkWithText = function (address, text) {
            var a = document.createElement('a');
            var textNode = $scope.createTextNode(text);
            a.appendChild(textNode);
            a.title = text;
            a.href = address;
            return a;
        }

        $scope.nbsp = '\xa0';

        $scope.spaceToNBSP = function (text) {
            return text = text.replace(' ', $scope.nbsp);
        }

        $scope.formatString = function (format) {
            var args = Array.prototype.slice.call(arguments, 1);
            return format.replace(/{(\d+)}/g, function (match, number) {
                return (typeof args[number] != 'undefined') ? args[number] : match;
            });
        }

        $scope.formatSupportTime = function (numDays) {
            if (numDays <= 0) {
                return $scope.strings.None;
            } else if (numDays <= 365) {
                return $scope.formatString($scope.strings.DaysFormat, numDays);
            } else {
                var years = window.external.JsNumberToString((numDays / 365.25), 1);
                return $scope.formatString($scope.strings.YearsFormat, years);
            }
        }

        $scope.appendLifecycleTableDataRow = function (tbody, item, today, rowNumber, numRows) {

            var summaryTextParts = [];

            summaryTextParts.push($scope.formatString($scope.strings.RowXOfYFormat, rowNumber, numRows));

            var tr = document.createElement('TR');

            /*
                Figure out which icon to display
            */

            var statusStyle;
            var iconPath;
            var iconText;
            if ($scope.IsValidDate(item.MainstreamSupportEndDate) && (today <= item.MainstreamSupportEndDate)) {
                /* mainstream support */
                statusStyle = '';
                iconPath = 'img/ok.svg';
                iconText = $scope.strings.Mainstream;
            } else {
                var extendedEnd = $scope.GetSupportEndDate(item);
                if (today > extendedEnd) {
                    /* totally expired */
                    statusStyle = 'lifecycle-table-error';
                    iconPath = 'img/error.svg';
                    iconText = $scope.strings.Expired;
                } else {
                    /* extended support */
                    statusStyle = 'lifecycle-table-warning';
                    iconPath = 'img/warning.svg';
                    iconText = $scope.strings.Extended;
                }
            }

            var td, img, text, textNode, p, li, ul, a;

            img = document.createElement('IMG');
            img.src = iconPath;
            img.alt = iconText;

            td = tr.insertCell(-1);
            td.className += ' lifecycle-table-icon nobr';
            td.appendChild(img);

            text = $scope.nbsp + $scope.spaceToNBSP(iconText);
            textNode = $scope.createTextNode(text, 'text-align-left');

            td.appendChild(textNode);

            summaryTextParts.push($scope.strings.Support + ": " + iconText);

            /*
                Add the product/group name
            */

            td = $scope.addTextCellToTableRow(tr, item.GroupName);
            td.className += ' lifecycle-table-product-name';

            summaryTextParts.push($scope.strings.ProductName + ": " + item.GroupName);

            /*
                Add support time remaining
            */

            var timeRemaining = $scope.formatSupportTime(item.SupportDaysRemaining);
            td = $scope.addTextCellToTableRow(tr, timeRemaining);
            td.className += ' lifecycle-table-number';

            summaryTextParts.push($scope.strings.SupportTimeRemaining + ": " + timeRemaining);

            /*
                Add the number of installs in the environment.

                Only create a link to the reports if reporting is enabled and we are not a CAS.

                The database on the CAS does have the full INSTALLED_SOFTWARE_DATA table which contains individual machine details, it only
                has the INSTALLED_SOFTWARE_DATA_Summary table.
            */

            //if ($scope.reportingEnabled && ($scope.isCAS == false)) {
            var formattedInstallCount = window.external.JsNumberToString(item.InstallCount, 0);

            if ($scope.updateEnabled2103 || $scope.reportingEnabled) {
                a = $scope.createLinkWithText("javascript:void(0)", formattedInstallCount);
                (function (a, productName) {
                    a.onclick = function () {
                        try {
                            if ($scope.updateEnabled2103) {
                                window.external.LaunchDevicesStickyNode(productName);
                            } else {
                                window.external.ViewReportForProduct(productName);
                            }
                        }
                        catch (err) {
                            window.alert($scope.strings.ReportFileLoadError);
                        }
                        return false;
                    }
                })(a, item.GroupName);
                td = $scope.addCellToTableRow(tr, a);
            } else {
                td = $scope.addTextCellToTableRow(tr, formattedInstallCount);
            }
            td.className += ' lifecycle-table-number';

            summaryTextParts.push($scope.strings.NumberInEnvironment + ": " + formattedInstallCount);

            /*
                Mainstream support end date
            */

            var formattedMainstreamEndData = $scope.formatDateForLifecycleTable(today, item.MainstreamSupportEndDate, item.MainstreamSupportEndDateDisplay);
            td = $scope.addTextCellToTableRow(tr, formattedMainstreamEndData);
            td.className += ' lifecycle-table-number nobr';

            summaryTextParts.push($scope.strings.MainstreamSupportEndDate + ": " + formattedMainstreamEndData);

            /*
                Extended support end date
            */

            var formattedExtendedEndData = $scope.formatDateForLifecycleTable(today, item.ExtendedSupportEndDate, item.ExtendedSupportEndDateDisplay);
            td = $scope.addTextCellToTableRow(tr, formattedExtendedEndData);
            td.className += ' lifecycle-table-number nobr';

            summaryTextParts.push($scope.strings.ExtendedSupportEndDate + ": " + formattedExtendedEndData);

            /*
                Link to additional information
            */

            text = $scope.strings.LearnMore;
            if (item.MoreInformationLink) {
                a = $scope.createLinkWithText(item.MoreInformationLink, text);
            } else {
                a = $scope.createLinkWithText("https://go.microsoft.com/fwlink/?linkid=2185961/?terms=" + encodeURIComponent(item.GroupName), text);
            }
            a.target = '_blank';
            td = $scope.addCellToTableRow(tr, a);
            td.classname += ' lifecycle-table-centered nobr';

            summaryTextParts.push($scope.strings.NextSteps + ": " + text);

            /*
                Add the row to the table body
            */

            tbody.appendChild(tr);

            return summaryTextParts.join(", ") + ".";
        }

        $scope.appendColumnHeaderToTR = function (tr, text) {
            var th = document.createElement('TH');
            tr.appendChild(th);

            th.setAttribute("scope", "col");

            var textNode = document.createTextNode(text);
            th.appendChild(textNode);
        }

        $scope.createLifecycleTable = function (tableParentID, tableData) {
            if (tableParentID[0] == '#') {
                tableParentID = tableParentID.substring(1);
            }

            var tableParent = document.getElementById(tableParentID);

            var oldTable = tableParent.getElementsByTagName('TABLE')[0];
            if (oldTable) {
                tableParent.removeChild(oldTable);
            }

            var newTable = document.createElement("TABLE");

            var thead = document.createElement('THEAD');

            var headerTR = document.createElement('TR');

            $scope.appendColumnHeaderToTR(headerTR, $scope.strings.Support);
            $scope.appendColumnHeaderToTR(headerTR, $scope.strings.ProductName);
            $scope.appendColumnHeaderToTR(headerTR, $scope.strings.SupportTimeRemaining);
            $scope.appendColumnHeaderToTR(headerTR, $scope.strings.NumberInEnvironment);
            $scope.appendColumnHeaderToTR(headerTR, $scope.strings.MainstreamSupportEndDate);
            $scope.appendColumnHeaderToTR(headerTR, $scope.strings.ExtendedSupportEndDate);
            $scope.appendColumnHeaderToTR(headerTR, $scope.strings.NextSteps);

            thead.appendChild(headerTR);
            newTable.appendChild(thead);

            var today = $scope.getTodaysDate();

            var tbody = document.createElement('TBODY');

            var rowSummaries = []

            for (var i = 0; i < tableData.length; ++i) {
                var item = tableData[i];
                var rowSummary = $scope.appendLifecycleTableDataRow(tbody, item, today, i + 1, tableData.length);
                rowSummaries.push(rowSummary);
            }

            newTable.appendChild(tbody);

            newTable.setAttribute("aria-colcount", 7);
            newTable.setAttribute("aria-rowcount", newTable.rows.length);

            tableParent.appendChild(newTable);

            /*
            This currently isn't working as expected so commenting out for the time being.
            Narrator seems to ignore aria-label when placed on tables. Our summary does a much
            better job of describing the table, so leaving the logic here in case we can get
            it to work later.

            var summaryText = rowSummaries.join(" ");
            tableParent.setAttribute("aria-label", summaryText);
            */
        }

        $scope.getTopXProductsByInstallCount = function (x, products) {
            var dupArray = products.slice(0);
            dupArray.sort(function (left, right) {
                if (left.InstallCount < right.InstallCount) {
                    return 1;
                } else if (left.InstallCount > right.InstallCount) {
                    return -1;
                } else {
                    /* If install counts are equal, sort by product name */
                    return left.GroupName.localeCompare(right.GroupName);
                }
            });
            if (dupArray.length > x) {
                return dupArray.slice(0, x);
            } else {
                return dupArray;
            }
        }

        $scope.filterProductsByCategory = function (lifecycleData, category) {
            /* category is the unlocalized value since the item values are stored that way.*/
            category = category.toUpperCase();

            if (category === "ALL") {
                /* Special case for All, just duplicate the array */
                return lifecycleData.slice(0);
            }

            var filteredProducts = [];

            lifecycleData.forEach(function (item) {
                if (category === item.Category.toUpperCase()) {
                    filteredProducts.push(item);
                }
            });
            return filteredProducts;
        }

        $scope.toggleChart = function (chartID, tableID, buttonID) {
            var chart = document.getElementById(chartID);
            var table = document.getElementById(tableID);
            var button = document.getElementById(buttonID);

            if (table.style.display == 'none' || table.style.display == '') {
                table.style.display = 'table';
                chart.style.display = 'none';
                button.innerHTML = $scope.strings["ShowChart"];
            }
            else if (table.style.display = 'table') {
                table.style.display = 'none';
                chart.style.display = 'block';
                button.innerHTML = $scope.strings["ShowTable"];
            }
        }

        $scope.toggleExpiredChart = function () {
            $scope.toggleChart('EOLBarchart', 'top-expired-table', 'showExpiredChartButton');
        }

        $scope.toggleNearEOLChart = function () {
            $scope.toggleChart('NearEOLBarchart', 'top-neareol-table', 'showNearEOLChartButton');
        }

        $scope.escapeHtml = function (str) {
            return str
                .replace(/&/g, "&amp;")
                .replace(/</g, "&lt;")
                .replace(/>/g, "&gt;")
                .replace(/"/g, "&quot;")
                .replace(/'/g, "&#039;");
        }

        $scope.createTable = function (tableID, productNames, installCounts) {
            var tableItemsContainerID = tableID + "-items";
            var tableItemsContainer = document.getElementById(tableItemsContainerID);

            while (tableItemsContainer.firstChild) {
                tableItemsContainer.removeChild(tableItemsContainer.firstChild);
            }

            var noData = (productNames.length <= 1);
            if (noData) {
                var addDiv = document.createElement('div');
                addDiv.className = 'tablerow';
                addDiv.innerHTML = '<div class="tablecell lefttext">' + $scope.escapeHtml($scope.strings.NoProductsFound) + '</div><div class="tablecell">' + 0 + '</div>';

                tableItemsContainer.appendChild(addDiv);
            }
            else {
                for (var i = 1; i < productNames.length; i += 1) {
                    var addDiv = document.createElement('div');
                    if (i & 1) {
                        addDiv.className = 'tablerow';
                    }
                    else {
                        addDiv.className = 'tablerow evenrow';
                    }
                    addDiv.innerHTML = '<div class="tablecell lefttext">' + $scope.escapeHtml(productNames[i]) + '</div><div class="tablecell">' + installCounts[i] + '</div>';

                    tableItemsContainer.appendChild(addDiv);
                }
            }
        }

        $scope.calculateYAxisMax = function (lifecycleDataNamesAndInstallCounts) {
            if (lifecycleDataNamesAndInstallCounts.length == 0) {
                return 10;
            }

            var installCounts = lifecycleDataNamesAndInstallCounts[0];

            var maxInstallCount = 0;
            var i;

            //The first item in the count array is a string used by the chart, so skip it
            for (i = 1; i < installCounts.length; i += 1) {
                var installCount = installCounts[i];
                maxInstallCount = Math.max(maxInstallCount, installCount);
            }

            if (maxInstallCount <= 10) {
                return 10;
            }

            var increment;
            if (maxInstallCount <= 100) {
                increment = 10;
            } else if (maxInstallCount <= 1000) {
                increment = 100;
            } else if (maxInstallCount <= 10000) {
                increment = 1000;
            } else if (maxInstallCount <= 100000) {
                increment = 10000;
            } else if (maxInstallCount <= 1000000) {
                increment = 100000;
            } else {
                increment = 1000000;
            }

            var mod = maxInstallCount % increment;
            if (mod == 0) {
                return maxInstallCount;
            } else {
                return maxInstallCount + increment - mod;
            }
        }

        $scope.updateChartsForCategory = function (selectedIndex) {

            //WARNING: Do not change the order of these values unless also adjusting the select with id="product-filter-selector" in dashboard.html
            var category;
            if (selectedIndex == 0) {
                category = "All";
            } else if (selectedIndex == 1) {
                category = "WinClient";
            } else if (selectedIndex == 2) {
                category = "WinServer";
            } else if (selectedIndex == 3) {
                category = "Database";
            } else if (selectedIndex == 4) {
                category = "ConfigMgr";
            } else if (selectedIndex == 5) {
                category = "Office";
            } else {
                category = "All";
            }

            console.log("Filtering on:" + category);

            var filteredLifecycleData = $scope.filterProductsByCategory($scope.lifecycleData, category);

            console.log("Filtering returned:" + filteredLifecycleData);

            var productsPastExpiration = $scope.getExpiredProducts(filteredLifecycleData);
            productsPastExpiration = $scope.getTopXProductsByInstallCount(5, productsPastExpiration);
            var productCountsAndNamesPastExpiration = $scope.getNameAndInstallCountOnly(productsPastExpiration);
            $scope.pastEOLBarchartConfig = {
                ChartType: "bar-chart-with-x-axis-and-empty-labels",
                ChartID: "EOLBarchart",
                ChartTitle: $scope.strings.EOLProductsLabel,
                ChartData: productCountsAndNamesPastExpiration[0],
                ChartXAxisLabels: productCountsAndNamesPastExpiration[1],
                ChartYAxisLabel: $scope.strings.NumberInEnvironment,
                BarColor: "#CC0000",
                NumItems: productCountsAndNamesPastExpiration[0].length - 1,
                DisplayedPageStartIndex: 0,
                ItemsPerPage: 4,
                YMax: $scope.calculateYAxisMax(productCountsAndNamesPastExpiration),
                YMin: 0,
            };
            $scope.createBarChartWithXAxisLabels($scope.pastEOLBarchartConfig);
            $scope.createTable('top-expired-table', productCountsAndNamesPastExpiration[1], productCountsAndNamesPastExpiration[0]);

            var productsNearingExpiration = $scope.getProductsNearEndOfLife(filteredLifecycleData);
            productsNearingExpiration = $scope.getTopXProductsByInstallCount(5, productsNearingExpiration);
            var productCountsAndNamesNearingExpiration = $scope.getNameAndInstallCountOnly(productsNearingExpiration);
            $scope.nearEOLBarchartConfig = {
                ChartType: "bar-chart-with-x-axis-and-empty-labels",
                ChartID: "NearEOLBarchart",
                ChartTitle: $scope.strings.NearEOLProductsLabel,
                ChartData: productCountsAndNamesNearingExpiration[0],
                ChartXAxisLabels: productCountsAndNamesNearingExpiration[1],
                ChartYAxisLabel: $scope.strings.NumberInEnvironment,
                BarColor: "#FF8300",
                NumItems: productCountsAndNamesNearingExpiration[0].length - 1,
                DisplayedPageStartIndex: 0,
                ItemsPerPage: 4,
                YMax: $scope.calculateYAxisMax(productCountsAndNamesNearingExpiration),
                YMin: 0,
            };
            $scope.createBarChartWithXAxisLabels($scope.nearEOLBarchartConfig);
            $scope.createTable('top-neareol-table', productCountsAndNamesNearingExpiration[1], productCountsAndNamesNearingExpiration[0]);

            var lifecycleGridInformation = $scope.processLifecycleGridInformation(filteredLifecycleData);
            $scope.createLifecycleTable("#lifecycle-info-grid-table-holder", lifecycleGridInformation);
        }

        $scope.sliderValue = 18;
        $scope.updateMonthsRemaining = function () {

            var sliderVal = document.getElementById('product-filter-slider').value;
            $scope.sliderValue = sliderVal;

            var newSliderLabelText = $scope.formatString($scope.strings.MonthsRemaining, $scope.sliderValue)
            var sliderLabelElement = document.getElementById('slider-label');
            sliderLabelElement.innerHTML = newSliderLabelText;

            /* ensures charts redraw on slider change without losing currently selected category */
            var ind = document.getElementById('product-filter-selector').selectedIndex;
            $scope.updateChartsForCategory(ind);
        }

        $scope.chartCSSFormat =
            ".hcaware .c3 .c3-axis-x path,              \n" +
            ".hcaware .c3 .c3-axis-x line,              \n" +
            ".hcaware .c3 .c3-axis-y path,              \n" +
            ".hcaware .c3 .c3-axis-y line {             \n" +
            "    stroke: {0} !important;                \n" +
            "}                                          \n" +
            "                                           \n" +
            ".hcaware .c3 .c3-axis-x g,                 \n" +
            ".hcaware .c3 .c3-axis-y g,                 \n" +
            ".hcaware .c3 .c3-legend-item-data text,    \n" +
            ".hcaware .c3 .c3-axis-y-label,             \n" +
            ".hcaware .c3 .c3-axis-x-label,             \n" +
            ".hcaware .c3 .c3-legend-item {             \n" +
            "    fill: {0} !important;                  \n" +
            "}                                          \n" +
            "                                           \n" +
            "/*when displaying the data on the chart */ \n" +
            ".hcaware .c3 text.c3-text {                \n" +
            "    fill: {0} !important;                  \n" +
            "    stroke: {0} !important;                \n" +
            "    stroke-opacity: 0.3 !important;        \n" +
            "}                                          \n" +
            "                                           \n" +
            "/* for the tooltip text color */           \n" +
            ".hcaware .c3 .c3-tooltip-container {       \n" +
            "    color: {0} !important;                 \n" +
            "}                                          \n"
            ;

        $scope.addChartCSS = function () {
            var style = document.createElement('style');
            style.type = 'text/css';
            var chartTextColor = window.external.GetThemeTextColor();
            var formattedCSS = $scope.formatString($scope.chartCSSFormat, chartTextColor);
            style.innerHTML = formattedCSS;
            document.getElementsByTagName('head')[0].appendChild(style);
        };

        $scope.addChartCSS();

        document.getElementById('product-filter-selector').selectedIndex = 0;
        $scope.updateMonthsRemaining();

        if (window.external.GetUpdateEnabled2103() == 'false') {
            var monthsString = document.getElementById('slider-label');
            var slider = document.getElementById('product-filter-slider');
            slider.style.display = 'none';
            monthsString.style.display = 'none';
            monthsNum.parentElement.style.paddingTop = '23px';
        }

        if ($scope.aispEnabled == false) {
            document.getElementById('aisp-disabled-warning').style.display = "block";
        }
    });
}());

// SIG // Begin signature block
// SIG // MIInygYJKoZIhvcNAQcCoIInuzCCJ7cCAQExDzANBglg
// SIG // hkgBZQMEAgEFADB3BgorBgEEAYI3AgEEoGkwZzAyBgor
// SIG // BgEEAYI3AgEeMCQCAQEEEBDgyQbOONQRoqMAEEvTUJAC
// SIG // AQACAQACAQACAQACAQAwMTANBglghkgBZQMEAgEFAAQg
// SIG // YYfu2em1UC9V29EeuESLqh9eY3NnYAgshR77wfkjqsGg
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
// SIG // SEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCGaEw
// SIG // ghmdAgEBMIGVMH4xCzAJBgNVBAYTAlVTMRMwEQYDVQQI
// SIG // EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
// SIG // HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAm
// SIG // BgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENB
// SIG // IDIwMTECEzMAAALMjrWWpr3RyU4AAAAAAswwDQYJYIZI
// SIG // AWUDBAIBBQCgga4wGQYJKoZIhvcNAQkDMQwGCisGAQQB
// SIG // gjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcC
// SIG // ARUwLwYJKoZIhvcNAQkEMSIEIO0MJrBN/vAqWLQDBN4h
// SIG // 5I+ffAV2+LwbefCpfLSWezGjMEIGCisGAQQBgjcCAQwx
// SIG // NDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRw
// SIG // Oi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEB
// SIG // BQAEggEABlogoKh9mjaUeV+qnIL5fbhCHgxdsh1NbENO
// SIG // DYJpt/whcq42rBNKL2ixqscJzqlhYIP+r5Z4P8lbWXCu
// SIG // 5qz/r6VTKn09FEIpXaRuCoO3GT2m3zhdnYQgyi6ExWGF
// SIG // Cvy5wwhtY1pCUmsn0lZz/1wg7qThBChjp3/4NHJoE7eB
// SIG // c1RFt1037naSvV+Nz15DPi/Z5rBYK7iDm7QzCMgABm/L
// SIG // gQwnG+bP3ZphqxAIlEkQQqih4omwe4B+oxcm7SCIKWr5
// SIG // qwnz7eNj8XWO6NHzX8ZKGJGLsdYL+jhs73OfA6Q0XsNB
// SIG // tKqbs2CnU+BSYsSLZAozqICbSb7SYkyid+WMi8rsQqGC
// SIG // FyswghcnBgorBgEEAYI3AwMBMYIXFzCCFxMGCSqGSIb3
// SIG // DQEHAqCCFwQwghcAAgEDMQ8wDQYJYIZIAWUDBAIBBQAw
// SIG // ggFYBgsqhkiG9w0BCRABBKCCAUcEggFDMIIBPwIBAQYK
// SIG // KwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCCHHaIz
// SIG // JMYh5sEOseOaPmNw8uCymp7EJxNkLqsCmWUKAwIGY2Pf
// SIG // aYG/GBIyMDIyMTEwNDE3MjMzOS4yM1owBIACAfSggdik
// SIG // gdUwgdIxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
// SIG // aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
// SIG // ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsT
// SIG // JE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGlt
// SIG // aXRlZDEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046RkM0
// SIG // MS00QkQ0LUQyMjAxJTAjBgNVBAMTHE1pY3Jvc29mdCBU
// SIG // aW1lLVN0YW1wIFNlcnZpY2WgghF7MIIHJzCCBQ+gAwIB
// SIG // AgITMwAAAbn2AA1lVE+8AwABAAABuTANBgkqhkiG9w0B
// SIG // AQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
// SIG // aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
// SIG // ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQD
// SIG // Ex1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAe
// SIG // Fw0yMjA5MjAyMDIyMTdaFw0yMzEyMTQyMDIyMTdaMIHS
// SIG // MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
// SIG // bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
// SIG // cm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNy
// SIG // b3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQx
// SIG // JjAkBgNVBAsTHVRoYWxlcyBUU1MgRVNOOkZDNDEtNEJE
// SIG // NC1EMjIwMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1T
// SIG // dGFtcCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOC
// SIG // Ag8AMIICCgKCAgEA40k+yWH1FsfJAQJtQgg3EwXm5CTI
// SIG // 3TtUhKEhNe5sulacA2AEIu8JwmXuj/Ycc5GexFyZIg0n
// SIG // +pyUCYsis6OdietuhwCeLGIwRcL5rWxnzirFha0RVjtV
// SIG // jDQsJzNj7zpT/yyGDGqxp7MqlauI85ylXVKHxKw7F/fT
// SIG // I7uO+V38gEDdPqUczalP8dGNaT+v27LHRDhq3HSaQtVh
// SIG // L3Lnn+hOUosTTSHv3ZL6Zpp0B3LdWBPB6LCgQ5cPvznC
// SIG // /eH5/Af/BNC0L2WEDGEw7in44/3zzxbGRuXoGpFZe53n
// SIG // hFPOqnZWv7J6fVDUDq6bIwHterSychgbkHUBxzhSAmU9
// SIG // D9mIySqDFA0UJZC/PQb2guBI8PwrLQCRfbY9wM5ug+41
// SIG // PhFx5Y9fRRVlSxf0hSCztAXjUeJBLAR444cbKt9B2ZKy
// SIG // UBOtuYf/XwzlCuxMzkkg2Ny30bjbGo3xUX1nxY6IYyM1
// SIG // u+WlwSabKxiXlDKGsQOgWdBNTtsWsPclfR8h+7WxstZ4
// SIG // GpfBunhnzIAJO2mErZVvM6+Li9zREKZE3O9hBDY+Nns1
// SIG // pNcTga7e+CAAn6u3NRMB8mi285KpwyA3AtlrVj4RP+Vv
// SIG // RXKOtjAW4e2DRBbJCM/nfnQtOm/TzqnJVSHgDfD86zmF
// SIG // MYVmAV7lsLIyeljT0zTI90dpD/nqhhSxIhzIrJUCAwEA
// SIG // AaOCAUkwggFFMB0GA1UdDgQWBBS3sDhx21hDmgmMTVmq
// SIG // tKienjVEUjAfBgNVHSMEGDAWgBSfpxVdAF5iXYP05dJl
// SIG // pxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8v
// SIG // d3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNy
// SIG // b3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAxMCgx
// SIG // KS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAC
// SIG // hlBodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3Bz
// SIG // L2NlcnRzL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQ
// SIG // Q0ElMjAyMDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBYG
// SIG // A1UdJQEB/wQMMAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQE
// SIG // AwIHgDANBgkqhkiG9w0BAQsFAAOCAgEAzdxns0VQdEyw
// SIG // srOOXusk8iS/ugn6z2SS63SFmJ/1ZK3rRLNgZQunXOZ0
// SIG // +pz7Dx4dOSGpfQYoKnZNOpLMFcGHAc6bz6nqFTE2UN7A
// SIG // YxlSiz3nZpNduUBPc4oGd9UEtDJRq+tKO4kZkBbfRw1j
// SIG // euNUNSUYP5XKBAfJJoNq+IlBsrr/p9C9RQWioiTeV0Z+
// SIG // OcC2d5uxWWqHpZZqZVzkBl2lZHWNLM3+jEpipzUEbhLH
// SIG // GU+1x+sB0HP9xThvFVeoAB/TY1mxy8k2lGc4At/mRWjY
// SIG // e6klcKyT1PM/k81baxNLdObCEhCY/GvQTRSo6iNSsElQ
// SIG // 6FshMDFydJr8gyW4vUddG0tBkj7GzZ5G2485SwpRbvX/
// SIG // Vh6qxgIscu+7zZx4NVBC8/sYcQSSnaQSOKh9uNgSsGja
// SIG // IIRrHF5fhn0e8CADgyxCRufp7gQVB/Xew/4qfdeAwi8l
// SIG // uosl4VxCNr5JR45e7lx+TF7QbNM2iN3IjDNoeWE5+VVF
// SIG // k2vF57cH7JnB3ckcMi+/vW5Ij9IjPO31xTYbIdBWrEFK
// SIG // tG0pbpbxXDvOlW+hWwi/eWPGD7s2IZKVdfWzvNsE0MxS
// SIG // P06fM6Ucr/eas5TxgS5F/pHBqRblQJ4ZqbLkyIq7Zi7I
// SIG // qIYEK/g4aE+y017sAuQQ6HwFfXa3ie25i76DD0vrII9j
// SIG // SNZhpC3MA/0wggdxMIIFWaADAgECAhMzAAAAFcXna54C
// SIG // m0mZAAAAAAAVMA0GCSqGSIb3DQEBCwUAMIGIMQswCQYD
// SIG // VQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
// SIG // A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
// SIG // IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQg
// SIG // Um9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgMjAxMDAe
// SIG // Fw0yMTA5MzAxODIyMjVaFw0zMDA5MzAxODMyMjVaMHwx
// SIG // CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
// SIG // MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
// SIG // b3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jv
// SIG // c29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMIICIjANBgkq
// SIG // hkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA5OGmTOe0ciEL
// SIG // eaLL1yR5vQ7VgtP97pwHB9KpbE51yMo1V/YBf2xK4OK9
// SIG // uT4XYDP/XE/HZveVU3Fa4n5KWv64NmeFRiMMtY0Tz3cy
// SIG // wBAY6GB9alKDRLemjkZrBxTzxXb1hlDcwUTIcVxRMTeg
// SIG // Cjhuje3XD9gmU3w5YQJ6xKr9cmmvHaus9ja+NSZk2pg7
// SIG // uhp7M62AW36MEBydUv626GIl3GoPz130/o5Tz9bshVZN
// SIG // 7928jaTjkY+yOSxRnOlwaQ3KNi1wjjHINSi947SHJMPg
// SIG // yY9+tVSP3PoFVZhtaDuaRr3tpK56KTesy+uDRedGbsoy
// SIG // 1cCGMFxPLOJiss254o2I5JasAUq7vnGpF1tnYN74kpEe
// SIG // HT39IM9zfUGaRnXNxF803RKJ1v2lIH1+/NmeRd+2ci/b
// SIG // fV+AutuqfjbsNkz2K26oElHovwUDo9Fzpk03dJQcNIIP
// SIG // 8BDyt0cY7afomXw/TNuvXsLz1dhzPUNOwTM5TI4CvEJo
// SIG // LhDqhFFG4tG9ahhaYQFzymeiXtcodgLiMxhy16cg8ML6
// SIG // EgrXY28MyTZki1ugpoMhXV8wdJGUlNi5UPkLiWHzNgY1
// SIG // GIRH29wb0f2y1BzFa/ZcUlFdEtsluq9QBXpsxREdcu+N
// SIG // +VLEhReTwDwV2xo3xwgVGD94q0W29R6HXtqPnhZyacau
// SIG // e7e3PmriLq0CAwEAAaOCAd0wggHZMBIGCSsGAQQBgjcV
// SIG // AQQFAgMBAAEwIwYJKwYBBAGCNxUCBBYEFCqnUv5kxJq+
// SIG // gpE8RjUpzxD/LwTuMB0GA1UdDgQWBBSfpxVdAF5iXYP0
// SIG // 5dJlpxtTNRnpcjBcBgNVHSAEVTBTMFEGDCsGAQQBgjdM
// SIG // g30BATBBMD8GCCsGAQUFBwIBFjNodHRwOi8vd3d3Lm1p
// SIG // Y3Jvc29mdC5jb20vcGtpb3BzL0RvY3MvUmVwb3NpdG9y
// SIG // eS5odG0wEwYDVR0lBAwwCgYIKwYBBQUHAwgwGQYJKwYB
// SIG // BAGCNxQCBAweCgBTAHUAYgBDAEEwCwYDVR0PBAQDAgGG
// SIG // MA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAU1fZW
// SIG // y4/oolxiaNE9lJBb186aGMQwVgYDVR0fBE8wTTBLoEmg
// SIG // R4ZFaHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9j
// SIG // cmwvcHJvZHVjdHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYt
// SIG // MjMuY3JsMFoGCCsGAQUFBwEBBE4wTDBKBggrBgEFBQcw
// SIG // AoY+aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraS9j
// SIG // ZXJ0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcnQw
// SIG // DQYJKoZIhvcNAQELBQADggIBAJ1VffwqreEsH2cBMSRb
// SIG // 4Z5yS/ypb+pcFLY+TkdkeLEGk5c9MTO1OdfCcTY/2mRs
// SIG // fNB1OW27DzHkwo/7bNGhlBgi7ulmZzpTTd2YurYeeNg2
// SIG // LpypglYAA7AFvonoaeC6Ce5732pvvinLbtg/SHUB2Rje
// SIG // bYIM9W0jVOR4U3UkV7ndn/OOPcbzaN9l9qRWqveVtihV
// SIG // J9AkvUCgvxm2EhIRXT0n4ECWOKz3+SmJw7wXsFSFQrP8
// SIG // DJ6LGYnn8AtqgcKBGUIZUnWKNsIdw2FzLixre24/LAl4
// SIG // FOmRsqlb30mjdAy87JGA0j3mSj5mO0+7hvoyGtmW9I/2
// SIG // kQH2zsZ0/fZMcm8Qq3UwxTSwethQ/gpY3UA8x1RtnWN0
// SIG // SCyxTkctwRQEcb9k+SS+c23Kjgm9swFXSVRk2XPXfx5b
// SIG // RAGOWhmRaw2fpCjcZxkoJLo4S5pu+yFUa2pFEUep8beu
// SIG // yOiJXk+d0tBMdrVXVAmxaQFEfnyhYWxz/gq77EFmPWn9
// SIG // y8FBSX5+k77L+DvktxW/tM4+pTFRhLy/AsGConsXHRWJ
// SIG // jXD+57XQKBqJC4822rpM+Zv/Cuk0+CQ1ZyvgDbjmjJnW
// SIG // 4SLq8CdCPSWU5nR0W2rRnj7tfqAxM328y+l7vzhwRNGQ
// SIG // 8cirOoo6CGJ/2XBjU02N7oJtpQUQwXEGahC0HVUzWLOh
// SIG // cGbyoYIC1zCCAkACAQEwggEAoYHYpIHVMIHSMQswCQYD
// SIG // VQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
// SIG // A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
// SIG // IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQg
// SIG // SXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJjAkBgNV
// SIG // BAsTHVRoYWxlcyBUU1MgRVNOOkZDNDEtNEJENC1EMjIw
// SIG // MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBT
// SIG // ZXJ2aWNloiMKAQEwBwYFKw4DAhoDFQDHYh4YeGTnwxCT
// SIG // PNJaScZwuN+BOqCBgzCBgKR+MHwxCzAJBgNVBAYTAlVT
// SIG // MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
// SIG // ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9y
// SIG // YXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0
// SIG // YW1wIFBDQSAyMDEwMA0GCSqGSIb3DQEBBQUAAgUA5w+v
// SIG // WTAiGA8yMDIyMTEwNDIzMzM0NVoYDzIwMjIxMTA1MjMz
// SIG // MzQ1WjB3MD0GCisGAQQBhFkKBAExLzAtMAoCBQDnD69Z
// SIG // AgEAMAoCAQACAiJDAgH/MAcCAQACAhGEMAoCBQDnEQDZ
// SIG // AgEAMDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkK
// SIG // AwKgCjAIAgEAAgMHoSChCjAIAgEAAgMBhqAwDQYJKoZI
// SIG // hvcNAQEFBQADgYEAtSFbSsAlRq/R9KfatXPCzW02b/6K
// SIG // V/9dc1D4gz9mBh/nuP6oBi6kCzNkA+fpgYxccsjhgmwc
// SIG // iVCHPQ+AQ6OKHa64tL6lvrL87hTuJNxb52qbyq6UqE/H
// SIG // ZJWx4I6inSLTbdByslbVQ57qCTI9oDY8m0JbTiEL3yrT
// SIG // IPyhMrpQXC0xggQNMIIECQIBATCBkzB8MQswCQYDVQQG
// SIG // EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
// SIG // BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
// SIG // cnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGlt
// SIG // ZS1TdGFtcCBQQ0EgMjAxMAITMwAAAbn2AA1lVE+8AwAB
// SIG // AAABuTANBglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcN
// SIG // AQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEi
// SIG // BCDABRQRPHUs2gzXsqkllZ+KsJMiieGsQVrjvTqTgIwM
// SIG // YjCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EIGTr
// SIG // Rs7xbzm5MB8lUQ7e9fZotpAVyBwal3Cw6iL5+g/0MIGY
// SIG // MIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
// SIG // c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
// SIG // BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UE
// SIG // AxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAC
// SIG // EzMAAAG59gANZVRPvAMAAQAAAbkwIgQgSkHfGvt7LGlM
// SIG // Mwx/yEaIsvMN4gSHGaPUIiu4f1R8nywwDQYJKoZIhvcN
// SIG // AQELBQAEggIAr+jer5OS8/vmguFSi7hJQmghQBODF79d
// SIG // 4kqEmF/N7YP5ZYCE6xVdR698Eo7pL5Y+lt0VL26NtI6G
// SIG // kDD765BTUwgiJrxQtMcxBt/Ucs8qaTWHF1a+ILDUw9QN
// SIG // uNzwsaZMt/Wv1iz4b6Fxh9dvHskJFEcJcDXmp4yhaZ0R
// SIG // 2yN/eh+SWMCJe+OAqLOHlINohDBtvdDuNwqrURbX5A5E
// SIG // WrCAM7aBr9e2tPqqVmeHjzXw51WqKjAuqWPtmDet9059
// SIG // fZYIUmeM+QPUHPnOXp7XXmN9qExZrbTLswux3qz1hlWK
// SIG // binAAFGP0irYHiFTNHCBUXSzVjpyRB7wTKyUADlR7bmv
// SIG // CTKsQYUmYYYRczJgjvzg2JOT9g4cz6X2FoT6AvEFeGVV
// SIG // LCfyMI+uN5chGdc8vVDgsp8T20GOKF7p5ut+fJHcS5O7
// SIG // KanwuZxAk7FF8bG98Tv/wQ2cPCJDcQgl35imOkf2xoNY
// SIG // WthIDTKdrb6wEm4/NByP9+M1S+qyXZd3bEi1bBhiN3Mp
// SIG // E9rfzbRDBnrM06ZoObG8d4Xh+koZkfRnaWlVgGv5jjIF
// SIG // 8V2NOnrbZ6yj6jC3gU8bJnbGQfVUuKwr7XukLXinEo8r
// SIG // hYVDCwq999ezoyemTQdQ3DtF+JDfxd0o0GOzj9xMh0nR
// SIG // OUFCAcMhB9JQuSRHVydanBpcOGJCrwJwYDk=
// SIG // End signature block
