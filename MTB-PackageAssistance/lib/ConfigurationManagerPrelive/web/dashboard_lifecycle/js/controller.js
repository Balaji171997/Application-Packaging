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

        $scope.updateElementHTMLString = function (element, content) {
            utilityUpdateElementHTMLString(element, content);
        };

        $scope.toggleChart = function (chartID, tableID, buttonID) {
            var chart = document.getElementById(chartID);
            var table = document.getElementById(tableID);
            var button = document.getElementById(buttonID);

            if (table.style.display == 'none' || table.style.display == '') {
                table.style.display = 'table';
                chart.style.display = 'none';
                $scope.updateElementHTMLString(button, $scope.strings["ShowChart"]);
            }
            else if (table.style.display = 'table') {
                table.style.display = 'none';
                chart.style.display = 'block';
                $scope.updateElementHTMLString(button, $scope.strings["ShowTable"]);
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
                $scope.updateElementHTMLString(addDiv, '<div class="tablecell lefttext">' + $scope.escapeHtml($scope.strings.NoProductsFound) + '</div><div class="tablecell">' + 0 + '</div>');

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
                    $scope.updateElementHTMLString(addDiv, '<div class="tablecell lefttext">' + $scope.escapeHtml(productNames[i]) + '</div><div class="tablecell">' + installCounts[i] + '</div>');

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
            $scope.updateElementHTMLString(sliderLabelElement, newSliderLabelText);

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
            $scope.updateElementHTMLString(style, formattedCSS);
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
// SIG // MIIomQYJKoZIhvcNAQcCoIIoijCCKIYCAQExDzANBglg
// SIG // hkgBZQMEAgEFADB3BgorBgEEAYI3AgEEoGkwZzAyBgor
// SIG // BgEEAYI3AgEeMCQCAQEEEBDgyQbOONQRoqMAEEvTUJAC
// SIG // AQACAQACAQACAQACAQAwMTANBglghkgBZQMEAgEFAAQg
// SIG // pSiT309eUJrDllKNILiJwCcD5HOZuLWBAqj31VsolpOg
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
// SIG // AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCBMej0LMFm33lpl
// SIG // VKNPhgnhqTI83FjoEOEEjyqn17yTvjCBigYKKwYBBAGC
// SIG // NwIBDDF8MHqgXIBaAE0AaQBjAHIAbwBzAG8AZgB0AC4A
// SIG // VABvAG8AbABrAGkAdAAuAFcAcABmAC4AVQBJAC4AQwBv
// SIG // AG4AdAByAG8AbABzAC4AVwBlAGIAVgBpAGUAdwAuAGQA
// SIG // bABsoRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
// SIG // BgkqhkiG9w0BAQEFAASCAQBeMlxcGnqKTlW7UY2+WqEj
// SIG // YpAQxGRvEykLENmgK4Mw4eB6v85Jgb9G4qP4hmBI1jZL
// SIG // NSAH55m9UryZsJ02ep4hyHZYJe9bITT5xOTqyt9nWIra
// SIG // GnUbls1wiDUtiUO3Sm9s4mLcoiEFG0OZGz4qCbpl1lWz
// SIG // qQz+2u6Eq++p0gZ7T/Y0vTo/M4gXBth5aH1c8/OAa2Nn
// SIG // bFKQLkhTiUEvZbau7UgHIHSmnU229pkOFOJmJ4rDJWXZ
// SIG // Ct4hIhquI9l+U2b37QDx4qce6SLlRmugUVlaMQrRnNo0
// SIG // KQoLqv7rDq1AADX6j30zIuv2pJsel4BQoF3RNWlwAPx2
// SIG // i6PQONz7jJF8oYIXrTCCF6kGCisGAQQBgjcDAwExgheZ
// SIG // MIIXlQYJKoZIhvcNAQcCoIIXhjCCF4ICAQMxDzANBglg
// SIG // hkgBZQMEAgEFADCCAVoGCyqGSIb3DQEJEAEEoIIBSQSC
// SIG // AUUwggFBAgEBBgorBgEEAYRZCgMBMDEwDQYJYIZIAWUD
// SIG // BAIBBQAEIOMSR/JdZay1zKG/UaURUej9dLwNdDnQMkb+
// SIG // 5XqHTzrgAgZo8f/uxzYYEzIwMjUxMDIzMDI0NTU3LjY4
// SIG // NFowBIACAfSggdmkgdYwgdMxCzAJBgNVBAYTAlVTMRMw
// SIG // EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
// SIG // b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
// SIG // b24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9w
// SIG // ZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNoaWVs
// SIG // ZCBUU1MgRVNOOjRDMUEtMDVFMC1EOTQ3MSUwIwYDVQQD
// SIG // ExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloIIR
// SIG // +zCCBygwggUQoAMCAQICEzMAAAIYJdmSBeLn5eQAAQAA
// SIG // AhgwDQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMx
// SIG // EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
// SIG // ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
// SIG // dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3Rh
// SIG // bXAgUENBIDIwMTAwHhcNMjUwODE0MTg0ODI1WhcNMjYx
// SIG // MTEzMTg0ODI1WjCB0zELMAkGA1UEBhMCVVMxEzARBgNV
// SIG // BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
// SIG // HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEt
// SIG // MCsGA1UECxMkTWljcm9zb2Z0IElyZWxhbmQgT3BlcmF0
// SIG // aW9ucyBMaW1pdGVkMScwJQYDVQQLEx5uU2hpZWxkIFRT
// SIG // UyBFU046NEMxQS0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1p
// SIG // Y3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0G
// SIG // CSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCx3Ojq65Am
// SIG // oB/Eue8QF8i+PqScr6npucxcQVn9CM84XLCVyMN/MjwO
// SIG // DWfMOXGbv+mpu+NaHK9rMqYXI7qps/AKV9GcjnuHk4KL
// SIG // GCk44IYklAhlJOIyC6LcHwM+IW0k9x/NG3cWyfGMtfAE
// SIG // iMaCeMZ+ZCXvN6MDVahgv+oGZCHD8UMVNZ5vF+jibREI
// SIG // I7F/arCPfVo6NzZphR4+0sxcexco8UfS2nlIogX/20nF
// SIG // FKDQ1gS9CpWKWN7xpCQ93erMC7HYxzkcxIrg0xO1VUJg
// SIG // BYNRnin7qIMj23kE0IEix/migU1Ra3EKqekViItiQd8V
// SIG // /GFVQFnwsYbFiwDfqycPrmzYd/i3zqTR7xZ6Uf+6x+Fi
// SIG // o4zfPbJojyuDTzrfUiTCpTPJCgQ+oyweAF6bXGmY4ZIh
// SIG // SdW9OwC/6WYQIvZGqtw5mVlrHwrRqKKPyHpSRYE3YgD+
// SIG // KRpyRNIZVEFCZZZm4sVZX9PjG43OxwLRfvGjh962Cmyp
// SIG // oQDSNj9B6+RO8u/g6U03144vws2HtWbRHrk/uhps5AOq
// SIG // 1QUDAKCOA8nSJX+NAJowBw7dJikbnBIBiImSThcuM1KU
// SIG // 3FTYh2OzWw5GGXuzssLqE5vttUAdXA43vgbF8U2IQgDo
// SIG // F+50A2OlAnSdRz+mkRelPimAMEexi1Xw7IpKMqwjE50V
// SIG // Ht8gkiMNzwO9SQIDAQABo4IBSTCCAUUwHQYDVR0OBBYE
// SIG // FCQuocRcOhtjt0e6hAIFrixftovRMB8GA1UdIwQYMBaA
// SIG // FJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYw
// SIG // VKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9w
// SIG // a2lvcHMvY3JsL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAl
// SIG // MjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRg
// SIG // MF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9z
// SIG // b2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIw
// SIG // VGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwG
// SIG // A1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUH
// SIG // AwgwDgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUA
// SIG // A4ICAQCeSNGGPA+B2gim+3hiKhP+PQta4HEXcBEEpcMQ
// SIG // 2CCtoq8LShE/BuMCaxec8Sa26jkwPy4n1fD15ivGqqQr
// SIG // gMX2ydkyscx+ijEJr77WKsvPxiijMLi1yL5rg3ftJuR7
// SIG // Wm3XGz2pm2+Q+BkZafkFzBV+YDBJkseLYK5nTpjT9f63
// SIG // p80GetsxWi81oNfhY93Ij0YTPF8iCAOxyTYimjhVcv8C
// SIG // tzPunYXtsRkZG7LGOAwL7CgKQMlof/KT/BxmkCyLF7g8
// SIG // 503QNbplvfk7cODf5rqmsA0xzdYh298oOXvk/RqpxBtA
// SIG // BHtvR/iAfg0yRRy3RabgY3kqGwTVgrtX/ACoMqYriPHf
// SIG // MvPdrwezFr0cHcbKK2WYLmwOE6XhBMY3mRGLqgKhXiEr
// SIG // 6QgWCeRaMeFJE2ibPfpCdsJIb8EcsSbYZFT27f8jjNR3
// SIG // 0TUAL3sgkQZ/Bv7Q1ZvdARyuTKl0Z1bCXQsQ5uGtBH0H
// SIG // VXv551zI2axfSnYFfSsWl3U+RclJvF/whwSLD9uQ2BqB
// SIG // kT5WUO3Fd6u4t2jmTeUY6/us9i44RqhljEO9m2kc/0/f
// SIG // rCZbgg2NHo0iefZQz6Ss//F4udFsMGSb1GyWegOFWtqW
// SIG // IoMfrYHGFyAv22JGA4eVwjTCq9VYt2/zJbyvGRrA6WEJ
// SIG // GpPcQoQJbyS1QA/A1sFQuRP6hZy8FzCCB3EwggVZoAMC
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
// SIG // OjRDMUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3Nv
// SIG // ZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4D
// SIG // AhoDFQCda0atdaK40TxCsp+bgK0avnvP6aCBgzCBgKR+
// SIG // MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5n
// SIG // dG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
// SIG // aWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1p
// SIG // Y3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqG
// SIG // SIb3DQEBCwUAAgUA7KO+GzAiGA8yMDI1MTAyMjIwMzMz
// SIG // MVoYDzIwMjUxMDIzMjAzMzMxWjB0MDoGCisGAQQBhFkK
// SIG // BAExLDAqMAoCBQDso74bAgEAMAcCAQACAh/PMAcCAQAC
// SIG // AhJdMAoCBQDspQ+bAgEAMDYGCisGAQQBhFkKBAIxKDAm
// SIG // MAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAIAgEA
// SIG // AgMBhqAwDQYJKoZIhvcNAQELBQADggEBAMz+7bnqwwZl
// SIG // VcFQC4Sc3U9rS8EfjGyZyJAqRxaJzx8Y26M1cHH1jzrj
// SIG // SP+FRwMR7VTCh5GVEIhSrqdJJ0WfFK8Mq8kwezpm2kCU
// SIG // u6lUpk49vovZx1YRIcxbDTq6/Brq+5DJhFKZFF+yS2VE
// SIG // hRDJmj98e5IBBvvg34KIBUKMY+C8SJIXzhnGoo5KFpwP
// SIG // 1ohda+RY5+8+yEW36fKYiLzQ6n7gkIFbwZKgjKQKlgBa
// SIG // rfU3bDsSpBIpl5lljeM0C85sHRPkvXzH7HHhMfi8ThK/
// SIG // UDOS8/VDWb8+aQeD0wIGHQR0tF7Y64yHvlD5Ycdq6Hgw
// SIG // u/b+SXjj5gSP90VlIcRTH/ExggQNMIIECQIBATCBkzB8
// SIG // MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
// SIG // bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
// SIG // cm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNy
// SIG // b3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAhgl
// SIG // 2ZIF4ufl5AABAAACGDANBglghkgBZQMEAgEFAKCCAUow
// SIG // GgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqG
// SIG // SIb3DQEJBDEiBCCXz0iFqXzBocPutO/A5bBOtJLJFQMI
// SIG // oWkWtqORLE8oyjCB+gYLKoZIhvcNAQkQAi8xgeowgecw
// SIG // geQwgb0EIJkT3Im45Mi0jBZoRLqXMYorVdxKjPXKdHNo
// SIG // 5XPH14VqMIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzAR
// SIG // BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
// SIG // bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
// SIG // bjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAg
// SIG // UENBIDIwMTACEzMAAAIYJdmSBeLn5eQAAQAAAhgwIgQg
// SIG // x6XrKzbV7C9pKlIxx7FSXCNq1a14xZT2mGEsT5miotkw
// SIG // DQYJKoZIhvcNAQELBQAEggIAhHh22OPWnlYMITpnjFYc
// SIG // 7vx4BaaO5VHj9GlGnCvuAPGUjGJurObsWA0gyh4/kMGX
// SIG // fPqscEI1qEyrchmiHmSiy5oMpCFOiw8eI+gK2bG5mtoX
// SIG // cQ8qaYF20xsigd0nBuv8DPBXrcC1JZKdvSM11YUkrOEh
// SIG // gseHgVV/b7OdrOpIAqlbL7rxpOPmIhTBMfftrPWO8QVJ
// SIG // QHi8o0UFFravjHWeajEXGxWtLRC8Rti6sfLOC/IoQXuL
// SIG // 7UUYpWGDJyZIZiaTjo+Llyi+iJ3QEMoOZFaDHTEGgYUH
// SIG // JoBZzPq+ke/UZpvIAfk8KLDWByQ01jX7gsd3sEFwBN3S
// SIG // 0cYYFsz12hRrUIolanzuDTkxtHBdTk8zt+8PpTHZQsyu
// SIG // pdYGWdxvOt12oMBXufopW8Iwg96yMgHjhofi/fOayRfq
// SIG // OBFBd2QnDJVm5G4Y44FSvwsyG2K5bA90qWcz/IzIRYnK
// SIG // ih33kp982eoT6DkbsG9Zc61ZLa+QC0nfFY2fJvOnWYwl
// SIG // zEFJzsd/uUlTRjEoC03/lvtpyamjXsRGZzzr6iZK6Y3W
// SIG // sqpEuN7NI12Xm9kqaOdxz5ukdvcNGGh+eESqqh9CE8eL
// SIG // m8iGtkH5+xl6qsIPS4+Jl9e/CJDv2lBfViwLtuOjhIo0
// SIG // EsdtzAZMrS7G3IQuF2wf29OuVCRirh4+kIFjhKzNGAsWFeE=
// SIG // End signature block
