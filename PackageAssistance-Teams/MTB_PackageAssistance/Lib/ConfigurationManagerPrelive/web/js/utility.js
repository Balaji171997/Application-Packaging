"use strict";

var bridge = window.external;

var callbackFuncs = {};

var loggingStates = {
    Error: 2,
    Information: 8
}

// standard chart lifecycle stages
var ChartState = {
    Loading: 0,
    NoDataFound: 1,
    DataReady: 2
}

var logger = {
    err: function (text) {
        bridge.Log(text, loggingStates.Error);
        console.error(text);
    },
    info: function (text) {
        bridge.Log(text, loggingStates.Information);
        console.log(text);
    }
}

function setCallbackFunction(callback) {
    var id = Object.keys(callbackFuncs).length;
    callbackFuncs[id] = callback;
    return id;
}

function getChartData(configData, chartGuid, callback) {
    var id = setCallbackFunction(callback);
    bridge["GetChartData"](configData, chartGuid, id);
}

function getChartInfo(collection, functionName, callback, identifier) {
    var id = setCallbackFunction(callback);
    bridge[functionName](collection, identifier, id);
}

function getData(query, functionName, callback) {
    var id = setCallbackFunction(callback);
    bridge[functionName](query, id);
};

function wv_wmiQuery(wql, callback) {
    adminUI.sendNewRequest("PerformWMIQuery", wql, callback);
}

function invokeCallback(data, callbackId) {
    try {
        var results;
        //	logger.err(data);
        if (data) {
            results = JSON.parse(data);
        }
        callbackFuncs[callbackId](results);
    }
    catch (err) {
        logger.err(err);
    }

    callbackFuncs[callbackId] = null;
}

/*
 * ChartTitle is optional if the chart doesn't support screen readers
 */
function createDonutChart(chartSelector, columns, chartTitle) {
    var enable = false;
    var pattern = ["#00BBF1", "#2E75B6", "#70AD47", "#A6A6A6"];
    for (var i = 0; i < columns.length; i++) {
        if (columns[i][1] != 0) {
            enable = true;
            break;
        }
    }

    var chart = document.querySelectorAll(chartSelector);
    var chartEl = angular.element(chart);


    // place the aria-label on the tile element
    var tileEl = chartEl.parent();
    while (tileEl != null && !tileEl.hasClass('tile')) {
        tileEl = tileEl.parent();
    }

    if (!enable) {
        pattern = ["#a9a9a9"];
        columns = [['', 1]];
        if (chartTitle != null)
            var summaryText = chartTitle + getString('SearchFolderEmpty');
    } else if (chartTitle != null) {
        var str = [];
        columns.forEach(function (k, v) { str.push(k[0] + k[1] + ", "); });
        var summaryText = chartTitle + str.join("");
    }

    if (chartTitle != null) {
        tileEl.attr('tabindex', '1')
        tileEl.attr('aria-label', summaryText);
    }

    return {
        bindto: chartSelector,
        data: {
            columns: columns,
            type: "donut"
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
        donut: {
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
    }
}

function getString(name) {
    return bridge.GetString(name);
}

function getStrings(stringNames) {
    var strings = {};

    for (var i = 0; i < stringNames.length; i++) {
        strings[stringNames[i]] = getString(stringNames[i]);
    }

    return strings;
}

/* 
 * Rounds a number to a certain number of digits
 * Example:
 * roundToDecimalPlaces(123.12345, 2) == 123.12
 */
function roundToDecimalPlaces(n, digits) {
    var modifier = Math.pow(10, digits);
    return Math.round(n * modifier) / modifier;
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

// Checks if value is null, 0, undefinded, "" or []
function isEmpty(value) {
    return (value == 0 || value == null || value.length === 0);
}

/*
 * Returns current background color as integer
 */
function GetCurrentBackgroundColor() {
    var rgbBackground = window.getComputedStyle(document.body, null).getPropertyValue('background-color');
    var bg = "rgb(244, 247, 252)";
    var colors = rgbBackground.match(/^rgb\((\d+),\s*(\d+),\s*(\d+)\)$/);

    var r = parseInt(colors[1]);
    var g = parseInt(colors[2]);
    var b = parseInt(colors[3]);

    var brightness = Math.round(((r * 299) + (g * 587) + (b * 114)) / 1000);

    return brightness;
}

/*
 * Sets all h1 elements in the document to specified color.
 * Default is white. 
 */
function SetColorToAllHeaders(color) {
    if (isEmpty(color)) {
        color = 'white';
    }

    var y = document.getElementsByTagName("h1");
    var i;
    for (i = 0; i < y.length; i++) {
        y[i].style.color = color;
    }
}

/*
 * Sets all text elements in the chart to specified color.
 * Default is white. 
 */
function SetColorToAllTextInChart(idToBindTo, color) {
    if (isEmpty(color)) {
        color = 'white';
    }

    // Sets color of text in legends (except bar chart)
    d3.select(idToBindTo).selectAll(".c3-legend-item").style('fill', color);
    // Sets color of x and y labels on bar chart
    d3.select(idToBindTo).selectAll(".c3-axis-x").style('fill', color);
    d3.select(idToBindTo).selectAll(".c3-axis-y").style('fill', color);

    // Sets color of all axis and strokes of bar chart
    d3.select(idToBindTo).selectAll(".c3-axis-y line").style('stroke', color);
    d3.select(idToBindTo).selectAll(".c3-axis-y path").style('stroke', color);
    d3.select(idToBindTo).selectAll(".c3-axis-x line").style('stroke', color);
    d3.select(idToBindTo).selectAll(".c3-axis-x path").style('stroke', color);

    // Sets color of data values inside the charts
    d3.select(idToBindTo).selectAll(".c3-chart-arc text").style("fill", color);
}

// Chart directive helpers - template and directive definition

/*
 * Standard chart template that handles the loading states. See client data sources dashboard for an example.
 */
function initChartTemplate($templateCache) {
    $templateCache.put('chart-view.html', '<div ng-if="status == ChartState.NoDataFound">' + getString('NoChartData') + '</div><div ng-if="status == ChartState.Loading">' + getString('ChartLoadingText') + '</div><!-- Use ng-show to make sure wrapped elements are always available as selectors.  C3 needs to be able to find the charts, even before the state is changed.--><div ng-show="status == ChartState.DataReady" ng-transclude></div>')
}

/*
 * Defines the directive for charts, links the template, and maps the statup input to a locally scoped variable
 */
function defineChartDirective() {
    return {
        templateUrl: 'chart-view.html',
        transclude: true,
        scope: {
            'status': '=chartStatus'
        },
        link: function (scope, element, attributes) {
            scope.ChartState = ChartState;
        }
    };
}

// helper for basic wql queries
function wmiQuery(wql, callback) {
    console.log("WQL> ", wql)
    getData(wql, "PerformWMIQuery", callback);
}

// helper function for dev
// print out result and save to a variable to access in js console
var a;
function wmi(wql) {
    wmiQuery(wql, function (res) {
        console.log(res)
        a = res
    })
}

// given an object and an array of keys to pluck, create an array of arrays for d3
function convertObjectToArrayOfArrays(obj, keys) {
    var arr = []
    for (var i = 0; i < keys.length; i++) {
        var key = keys[i]
        arr.push([key, obj[key]])
    }
    return arr;
}

// replace the content of element with content
function utilityUpdateElementHTMLString(element, content) {
    var domHTML = new DOMParser().parseFromString(content, 'text/html').body;

    while (element.hasChildNodes()) { element.removeChild(element.firstChild); }

    while (domHTML.hasChildNodes()) { element.appendChild(domHTML.firstChild); }
}

// replace the content of element with content using id
function utilityUpdateHTMLString(id, content) {
    utilityUpdateElementHTMLString(document.getElementById(id), content);
}

function createHtmlElement(div, tag, tabIndex, text) {
    var htmlElement = document.createElement(div);
    htmlElement.className = tag;
    htmlElement.tabIndex = tabIndex;
    htmlElement.appendChild(document.createTextNode(text));
    return htmlElement;
}

function appendUpdatedHtmlElement(tabidx, htmlString, Count) {
    var div = "div";
    var row = "row";
    var addDivRow = document.createElement(div);
    addDivRow.className = row;
    var htmlElementString = createHtmlElement(div, "cell", tabidx++, htmlString);
    var htmlElementCount = createHtmlElement(div, "cell", tabidx, Count);
    addDivRow.appendChild(htmlElementString);
    addDivRow.appendChild(htmlElementCount);
    return addDivRow;
}

// SIG // Begin signature block
// SIG // MIIomQYJKoZIhvcNAQcCoIIoijCCKIYCAQExDzANBglg
// SIG // hkgBZQMEAgEFADB3BgorBgEEAYI3AgEEoGkwZzAyBgor
// SIG // BgEEAYI3AgEeMCQCAQEEEBDgyQbOONQRoqMAEEvTUJAC
// SIG // AQACAQACAQACAQACAQAwMTANBglghkgBZQMEAgEFAAQg
// SIG // nqQjO4WRhIZG2j0K08Vg8PmROx23rLBJoeOOWUcNTxmg
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
// SIG // AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCAuoZNk5gsdDcE1
// SIG // 97vEF4iz+P4djEGYwYFCxgDE5W4HwzCBigYKKwYBBAGC
// SIG // NwIBDDF8MHqgXIBaAE0AaQBjAHIAbwBzAG8AZgB0AC4A
// SIG // VABvAG8AbABrAGkAdAAuAFcAcABmAC4AVQBJAC4AQwBv
// SIG // AG4AdAByAG8AbABzAC4AVwBlAGIAVgBpAGUAdwAuAGQA
// SIG // bABsoRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
// SIG // BgkqhkiG9w0BAQEFAASCAQDIMB0erRnxg0Tb7rMvOE/U
// SIG // jjhvL9oocb4hiJqQC+wbZCApR+KDxpl4v86uR/9qw6Cl
// SIG // 9dJzWpd6j5CSdvIIyOoWR58VQJ4RFGU3ZJlLGg4Y9vyT
// SIG // xaa/KVx0yzJn7TJIhDz5k5lMMbbJUPKMkhR3KKOigFHN
// SIG // 4BXXiV+UZIcv4JJlHqExhTmBt+G/OLbEdJAX7hPUJB98
// SIG // rZDUPfOscvv5wt82KkIKRQC7NHsb0LdyTsdQx9cLHdNf
// SIG // rmmjZX3p+r1iPLzdb7kbMO67qEZDGW/aALKZkvfdhcUc
// SIG // CKKlbtvJjXfEs4tB74g5kz029CzDoUK8KbhTlisnfXnw
// SIG // 6GlM2iWJZljdoYIXrTCCF6kGCisGAQQBgjcDAwExgheZ
// SIG // MIIXlQYJKoZIhvcNAQcCoIIXhjCCF4ICAQMxDzANBglg
// SIG // hkgBZQMEAgEFADCCAVoGCyqGSIb3DQEJEAEEoIIBSQSC
// SIG // AUUwggFBAgEBBgorBgEEAYRZCgMBMDEwDQYJYIZIAWUD
// SIG // BAIBBQAEIB8lwq0S+7fO8w0VjfFbAtv+zmuGXEe/WlNp
// SIG // LFGPxC+iAgZo8hKNoGAYEzIwMjUxMDIzMDI0NzQwLjkw
// SIG // M1owBIACAfSggdmkgdYwgdMxCzAJBgNVBAYTAlVTMRMw
// SIG // EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
// SIG // b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
// SIG // b24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9w
// SIG // ZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNoaWVs
// SIG // ZCBUU1MgRVNOOjQzMUEtMDVFMC1EOTQ3MSUwIwYDVQQD
// SIG // ExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloIIR
// SIG // +zCCBygwggUQoAMCAQICEzMAAAIdS8CShziFfjkAAQAA
// SIG // Ah0wDQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMx
// SIG // EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
// SIG // ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
// SIG // dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3Rh
// SIG // bXAgUENBIDIwMTAwHhcNMjUwODE0MTg0ODMzWhcNMjYx
// SIG // MTEzMTg0ODMzWjCB0zELMAkGA1UEBhMCVVMxEzARBgNV
// SIG // BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
// SIG // HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEt
// SIG // MCsGA1UECxMkTWljcm9zb2Z0IElyZWxhbmQgT3BlcmF0
// SIG // aW9ucyBMaW1pdGVkMScwJQYDVQQLEx5uU2hpZWxkIFRT
// SIG // UyBFU046NDMxQS0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1p
// SIG // Y3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0G
// SIG // CSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCitKBoADyg
// SIG // 6XimHnvjPDb16BQ3wMN6lEctfwUzXMc0mZcboqtKpQrD
// SIG // Nwpp+im5h09MRNMK9v1ol8RK4BTSIY1QUj8PpHSS91+l
// SIG // 7ag9f4TextNC8aLgk8fmp0hhRonjlX/hup7x429tbOkL
// SIG // 5kqMfX3cN6IjVcAj3XwmhCYGGURej9OifXvbWW5kmCKd
// SIG // yx/kuMxjeNfzhbJdRJfd2xLuH/vFUj7DXKODulr7TLej
// SIG // +Z7ZOy/pQlR1JNBqnk5EZJ8KdyWc/XPciKJYhavdWjto
// SIG // g9ayAnOrebkbGnFQcJCTyrNSGTnTL+4H4sYTdYgrYLvu
// SIG // LL2IWxJ9ItSfIwTMZENb2ZcdPg8fs7PPoIepASI2/Bwe
// SIG // qW+UKHWkdCHU1dBICo6hUGzmaLp5qx/rLFZN97kOtHv3
// SIG // nTevylTpWoLZj1cxFTjAf1BthdiwhRnfcmad3LbZbUsE
// SIG // MBvEE9AcIGWdwYNTcGB2FVRUt7zSaCAU73wV2RaGjrvD
// SIG // iQ90JNGS92+Rjw+tBgT+dCMdcJrSDstwy21lvp6Mwd9D
// SIG // 61RZe/r6dnhieSvY6RrFyUULDhEhg0xYPboBZtCP9YR3
// SIG // OBrXx8q3DrovmDNc/NrqMUF88l4oTcfxAC7CmKuYfiaz
// SIG // 7mdSM01A6Y2ComfRTX7difsKWzAPv1g3Svd91tgEwMCk
// SIG // Fkmk2UrursddGwIDAQABo4IBSTCCAUUwHQYDVR0OBBYE
// SIG // FIRZ8HE0RqZm1ebyCX3ZirzSN/FdMB8GA1UdIwQYMBaA
// SIG // FJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYw
// SIG // VKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9w
// SIG // a2lvcHMvY3JsL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAl
// SIG // MjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRg
// SIG // MF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9z
// SIG // b2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIw
// SIG // VGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwG
// SIG // A1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUH
// SIG // AwgwDgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUA
// SIG // A4ICAQCR3B4HjLG8uyksqrQP6aLIPhDQRzFUWk1m4nGJ
// SIG // HniBZGR5MMO7KY14HTcmGWwGlvBJgnm5lKAMEK/AcQPZ
// SIG // UvyUmkWU6msnPGxdYLY1N8D47487kWTmPDoseHqN4EAM
// SIG // MR1ADHceqLtmbQnC9D3fPl/p23GSbb1ao5wdhdFd8BDD
// SIG // LWFKstfJ95uWpHrqOk//2fR8KRZTiCCxSNClDY2CPUNX
// SIG // T0nhjfLun013zX5ezqpij77tEqbyqIH/k0N6KA4uOUB4
// SIG // WCIRchFQlb6YnKqlDD445GVqpwWNHwe7Qb7/tsx16Trx
// SIG // hf6Q+kMGTtR74j/GCJgnXFwNEGf+9zMu03vb5EiUPhSB
// SIG // dgu4FIKT/+kMQ9fnPf0Kv6uRzoThjbwU+TgGGWgDK+nr
// SIG // bw/jF8SVBjxNzGtpRtlKHKmhwTqfL3kPUrUGSW1masdU
// SIG // oLGaCWe46UzXk0oitcWVcLN2qkK0jBDjXvA0BUX9AM+/
// SIG // PNu6Y91OLp9vS0ttJxihtXrO9sGwywoQwThOPVv2ghcL
// SIG // x3JsmridtugRdilHCLVABulI2uf4/EZb25/WrrcWcwm7
// SIG // iCbc6HreeNb+JV/vbeq7PIetKKNYyBjQeJGIdCLQnK7S
// SIG // Hwx2FFSnubFuYtByQ+I4XACUhpQ3+TvbnL9otamRFTp+
// SIG // qYuUQ7IflanIt3bcBjL2vy/5ChtrqzCCB3EwggVZoAMC
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
// SIG // OjQzMUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3Nv
// SIG // ZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4D
// SIG // AhoDFQC6g74Ept9fOrJ+L0YsR1YeQIt5P6CBgzCBgKR+
// SIG // MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5n
// SIG // dG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
// SIG // aWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1p
// SIG // Y3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqG
// SIG // SIb3DQEBCwUAAgUA7KPQvDAiGA8yMDI1MTAyMjIxNTMw
// SIG // MFoYDzIwMjUxMDIzMjE1MzAwWjB0MDoGCisGAQQBhFkK
// SIG // BAExLDAqMAoCBQDso9C8AgEAMAcCAQACAhAvMAcCAQAC
// SIG // AhTQMAoCBQDspSI8AgEAMDYGCisGAQQBhFkKBAIxKDAm
// SIG // MAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAIAgEA
// SIG // AgMBhqAwDQYJKoZIhvcNAQELBQADggEBAM9hlMl92nxv
// SIG // D4p+byTPi0J9EGCpDdOQGrZ5C7maQXh23LLpVWv1/Ds3
// SIG // t6oz61Yqfy6EFJC/b9bIdoYD/qat0/r1Uizt1Oak6vK4
// SIG // m9cqzgMJKEjGiQ2T+EMaDTVz0z3AHuXBbisXwch6AvVI
// SIG // W6fQcchI9qImg7kSsuNly2CV0nan3EX0mclx37kXY49f
// SIG // LoJsaDolMAbzbiKyFPsQbCCBgjTSVa11MsiX6m4oSQcj
// SIG // zTY0dt9+hiNi0AkYPUrOfmCG1NfMRz5kGH+4P7ZpM2Se
// SIG // YP5E0p2cuGqyDitkjcKgKtRT1Yh5q+FoMLWgKUnzPRrZ
// SIG // g1+xTGmKIyhOdxnjTMCzBwUxggQNMIIECQIBATCBkzB8
// SIG // MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
// SIG // bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
// SIG // cm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNy
// SIG // b3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAh1L
// SIG // wJKHOIV+OQABAAACHTANBglghkgBZQMEAgEFAKCCAUow
// SIG // GgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqG
// SIG // SIb3DQEJBDEiBCDBsW6c+BawjRKwecoxDesijYPieAaL
// SIG // 3Bq2j6sEPjYSqTCB+gYLKoZIhvcNAQkQAi8xgeowgecw
// SIG // geQwgb0EILG2lcxcSIsnOuozvt6nitM3Csw6PqClY32F
// SIG // m+mPlAVRMIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzAR
// SIG // BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
// SIG // bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
// SIG // bjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAg
// SIG // UENBIDIwMTACEzMAAAIdS8CShziFfjkAAQAAAh0wIgQg
// SIG // c1eY+muWTlIkfMyU9MF3Dy44qOVyz/g1xEqzefytJ5Ew
// SIG // DQYJKoZIhvcNAQELBQAEggIAVJON73IjhuVtk8S9vbU8
// SIG // tznvVx0jzLHWJxf7YB7No1aMN2KPDiAcWfDT/kAmqUZp
// SIG // HIY8tyl0pDjEy5ty8+67xhKGySCiBs5KMLb0kHtreCP3
// SIG // xp6iGNUeiAnL0Kaocdc7tDIAzCrew70aFE7FW8IdkwSz
// SIG // prQ5CO/1U9rJ8sqBon7OYsXCUJQsx/DBWw0kTNIAh2B9
// SIG // pUbvsBBCOrzv5B83jyrHiN664d9qs/1x9UzXuFJ8bxtt
// SIG // nD4OiLsKBV+7sNZC6LHIt3GiBDOOY95MPLQgshsN/nhp
// SIG // 0k3ULcXrEapreGjoujoZQ+RJyQB+3HwbYl52+sexMjRI
// SIG // NBBnOuIv9k7aqPgl/FT0Z84LsJ9YVHBqVUIb8IDNF33Y
// SIG // gSlMP/ljz5GQ1xYS1tLZlfoq3DDTaqJYyiZ026fMhoTW
// SIG // +zmVE71T5tQz8fTt5PuULKIBMR6/UbfwrdESm9f9AIOi
// SIG // t3HfIOB4a3m1Y9nJwDWC5q7ItWmvdqmziptdmEt6nMCe
// SIG // 5w+9tB1axXXV7aVAH2m3UpW881wf8MJ7GpvaekSPoAd/
// SIG // VOpIoNNzYPaRubQ382Hna8UV+aHu9zn1bHxRU1Hh2U5C
// SIG // US/TbMRu3GkLcBMjNzbcuhY1QgckVIOu7vvBLZ1fDjwx
// SIG // M6XTFqeIxQIAedHBBHLOXJDp4yXHfcAHIj93yPqtzkSJJ4U=
// SIG // End signature block
