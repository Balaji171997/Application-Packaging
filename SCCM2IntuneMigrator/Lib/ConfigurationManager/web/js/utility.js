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
// SIG // Begin signature block
// SIG // MIInygYJKoZIhvcNAQcCoIInuzCCJ7cCAQExDzANBglg
// SIG // hkgBZQMEAgEFADB3BgorBgEEAYI3AgEEoGkwZzAyBgor
// SIG // BgEEAYI3AgEeMCQCAQEEEBDgyQbOONQRoqMAEEvTUJAC
// SIG // AQACAQACAQACAQACAQAwMTANBglghkgBZQMEAgEFAAQg
// SIG // wan5Sl3eHEMP+Zwx013NajVrQySjBB1GRls2zotoFWmg
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
// SIG // ARUwLwYJKoZIhvcNAQkEMSIEIO9q7kc1Hg1zfTNwWuWJ
// SIG // bngtZqU1QLC4rHwNayAmtX5cMEIGCisGAQQBgjcCAQwx
// SIG // NDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRw
// SIG // Oi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEB
// SIG // BQAEggEAPI8v4C/8yzBI+vRxCLWFk1+etb/mVNGDb/co
// SIG // UAufJrryO8UAHVcp8FA+1e2L/ygW0HWyv1C0OL4Oxz9V
// SIG // 64oihwR8TG/L1JneZe8knNO6tDWmIP88Gq8DqdQ8uqPp
// SIG // EDtzLsM2OkA9EpXuvL2HMmgNg73nmKOMsa6DIxEUFaoG
// SIG // XSM6y1lhB/I6uJaatZnWsbvh1qh1760gXgsUbfdAbQLy
// SIG // Md3WIyRBerWRRcNVx/ygoJTLNKgfDhv/FPlwdwgkKL05
// SIG // MlL0ApgIXmA89AqCrSNDeN1cLpL26FVwDz5TRq3Zo8K+
// SIG // JTAWAGvPfgXmHEGZO+0Y5IKfyGNB/1bfCeYFDzxq5KGC
// SIG // FyswghcnBgorBgEEAYI3AwMBMYIXFzCCFxMGCSqGSIb3
// SIG // DQEHAqCCFwQwghcAAgEDMQ8wDQYJYIZIAWUDBAIBBQAw
// SIG // ggFYBgsqhkiG9w0BCRABBKCCAUcEggFDMIIBPwIBAQYK
// SIG // KwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCCkz/SO
// SIG // Mk0mWbOdp5c7vDPc3bvv5xXlG/6On3T61SmA2wIGY2LW
// SIG // uFahGBIyMDIyMTEwNDE3MjMzOS42NlowBIACAfSggdik
// SIG // gdUwgdIxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
// SIG // aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
// SIG // ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsT
// SIG // JE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGlt
// SIG // aXRlZDEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046MTc5
// SIG // RS00QkIwLTgyNDYxJTAjBgNVBAMTHE1pY3Jvc29mdCBU
// SIG // aW1lLVN0YW1wIFNlcnZpY2WgghF7MIIHJzCCBQ+gAwIB
// SIG // AgITMwAAAbWtGt/XhXBtEwABAAABtTANBgkqhkiG9w0B
// SIG // AQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
// SIG // aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
// SIG // ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQD
// SIG // Ex1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAe
// SIG // Fw0yMjA5MjAyMDIyMTFaFw0yMzEyMTQyMDIyMTFaMIHS
// SIG // MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
// SIG // bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
// SIG // cm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNy
// SIG // b3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQx
// SIG // JjAkBgNVBAsTHVRoYWxlcyBUU1MgRVNOOjE3OUUtNEJC
// SIG // MC04MjQ2MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1T
// SIG // dGFtcCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOC
// SIG // Ag8AMIICCgKCAgEAlwsKuGVegsKNiYXFwU+CSHnt2a7P
// SIG // fWw2yPwiW+YRlEJsH3ibFIiPfk/yblMp8JGantu+7Di/
// SIG // +3e5wWN/nbJUIMUjEWJnc8JMjoPmHCWsMtJOuR/1Ru4a
// SIG // a1RrxQtIelq098TBl4k7NsEE87l7qKFmy8iwGNQjkwr0
// SIG // bMu4BJwy7BUXiXHegOSU992rfQ4xNZoxznv42TLQsc9N
// SIG // mcBq5WslkqVATcc8PSfgBLEpdG1Dp2wqNw4JrJFwJNA1
// SIG // bfzTScYABc5smRZBgsP4JiK/8CVrlocheEyQonjm3rFt
// SIG // trojAreSUnixALu9pDrsBI4DUPGG34oIbieI1oqFl/xk
// SIG // 7A+7uM8k4o8ifMVWNTaczbPldDYtn6hBre7r25RED4ue
// SIG // cCxP8Dxy34YPUElWllPP3LAXp5cMwRjx+EWzjEtILEKX
// SIG // uAcfxrXCTwyYhm5XNzCCZYh4/gF2U2y/bYfekKpaoFYw
// SIG // koZeT6ZxoQbX5Kftgj+tZkFV21UvZIkJ6b34a/44dtrs
// SIG // K6diTmVnNTM9J6P6Ehlk2sfcUwbHIGL8mYqdKOiyd4Rx
// SIG // OCmSvcFNkZEgrk548mHCbDbTyO9xSzN1EkWxbp8n/LHV
// SIG // nZ9fp5hILGntkMzaD5aXRCQyHSIhsPtR7Q/rKoHyjFqg
// SIG // tGO9ftnxYvxzNrbKeMCzwmcqwMrX6Hcxe0SeKZ8CAwEA
// SIG // AaOCAUkwggFFMB0GA1UdDgQWBBRsUIbZgoZVXVXVWQX0
// SIG // Ok1VO2bHUzAfBgNVHSMEGDAWgBSfpxVdAF5iXYP05dJl
// SIG // pxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8v
// SIG // d3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNy
// SIG // b3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAxMCgx
// SIG // KS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAC
// SIG // hlBodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3Bz
// SIG // L2NlcnRzL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQ
// SIG // Q0ElMjAyMDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBYG
// SIG // A1UdJQEB/wQMMAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQE
// SIG // AwIHgDANBgkqhkiG9w0BAQsFAAOCAgEAkFGOpyjKV2s2
// SIG // sA+wTqDwDdhp0mFrPtiU4rN3OonTWqb85M6WH19c/P51
// SIG // 7xujLCih/HllP5xKWmXnAIRV1/NQDkJBLSdLTb/NQtcT
// SIG // 1FWGQ7CMTnrn9tLZxqIFtKVylvQNyh31C/qkC8QmNpyz
// SIG // akO0G38uOGgOkJ9Eq4nA+7QwVfobDlggWuEpzdFnRdyX
// SIG // L32gOqSvrLjFKpv4KEVqaBTiaxCWZDlIhG3YgUza7cnG
// SIG // 5Z2SA/feMq/IiV06AzUadZw6XgcTrqXmEmE0tMmdl44M
// SIG // MFC3wGU9AVeFCWKdD9WOnYA2zHg+XF2LQVto0VYtFLd6
// SIG // c6DQFcmB38GvPCKVYSn8r10EoXuRN+gQ7hLcim12esOn
// SIG // W4F4bHCmHWTVWeAGgPiSItHHRfGKLEUZmotVOdFPR8wi
// SIG // uADT/fHSXBkkdpL12tvgEGELeTznzFulZ16b/Nv6dtbg
// SIG // SRZreesJBNKpTjdYju/GqnlAkpflL6J0wxk957/UVYnm
// SIG // jjRY61jX90QGQmBzm9vs/+2bj02Xx/bXXy8vq57jmNXQ
// SIG // 2ufOaJm3nAcD2qOaSyXEOj9mqhMt4tdvMjHhiNPldfj0
// SIG // Q7Kq1HgdRBrKWkzCQNi4ts8HRJBipNaVpWfU7BcRn8Be
// SIG // YzdLoIzwRLDtatz6aBho3oD/bXHrZagxprM5MsMB/rVf
// SIG // b5Xn1YS7/uEwggdxMIIFWaADAgECAhMzAAAAFcXna54C
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
// SIG // BAsTHVRoYWxlcyBUU1MgRVNOOjE3OUUtNEJCMC04MjQ2
// SIG // MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBT
// SIG // ZXJ2aWNloiMKAQEwBwYFKw4DAhoDFQCNMJ9r11RZj0PW
// SIG // u3uk+aQHF3IsVaCBgzCBgKR+MHwxCzAJBgNVBAYTAlVT
// SIG // MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
// SIG // ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9y
// SIG // YXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0
// SIG // YW1wIFBDQSAyMDEwMA0GCSqGSIb3DQEBBQUAAgUA5w9P
// SIG // UjAiGA8yMDIyMTEwNDE2NDQwMloYDzIwMjIxMTA1MTY0
// SIG // NDAyWjB3MD0GCisGAQQBhFkKBAExLzAtMAoCBQDnD09S
// SIG // AgEAMAoCAQACAgU2AgH/MAcCAQACAhHqMAoCBQDnEKDS
// SIG // AgEAMDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkK
// SIG // AwKgCjAIAgEAAgMHoSChCjAIAgEAAgMBhqAwDQYJKoZI
// SIG // hvcNAQEFBQADgYEAKV1qLvFuKwE25SL+UGIC+e8nP9dx
// SIG // OZ0Do8N5NjTUf6iF5LIb1lknlWQ4OX8DjhLq0keAkvjG
// SIG // ZLDbBL3SQO5sRmaU/sox6MB2sGVKO0SXla3QOKFvOLC+
// SIG // oVWJTvFopkwrTkeG55xtdRn12IvmZNJYm+uHVptHO6r1
// SIG // Ha9w5Eh9t38xggQNMIIECQIBATCBkzB8MQswCQYDVQQG
// SIG // EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
// SIG // BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
// SIG // cnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGlt
// SIG // ZS1TdGFtcCBQQ0EgMjAxMAITMwAAAbWtGt/XhXBtEwAB
// SIG // AAABtTANBglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcN
// SIG // AQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEi
// SIG // BCAz61HKL66HAyapgg6j7h51U1iU7mIcK+k2tSlNtYQS
// SIG // 4jCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EICfK
// SIG // DTUtaGcWifYc3OVnIpp7Ykn0S8JclVzrlAgF8ciDMIGY
// SIG // MIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
// SIG // c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
// SIG // BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UE
// SIG // AxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAC
// SIG // EzMAAAG1rRrf14VwbRMAAQAAAbUwIgQg5C7nwMHaETGQ
// SIG // kRl5ntQ8bReZ80Uzi58XCQa1XVvuuE8wDQYJKoZIhvcN
// SIG // AQELBQAEggIAAnKV0mf4opL9I6ApoLLaze2srBwss36c
// SIG // L0wXYcyuyWi8oYDAPuxVvtceS+d5SdHCXQq/zAAx8VjL
// SIG // PCO1sLANt0x8txiVV1Rm9RbsK2Ly0Eh3G2i6hdJcdqRS
// SIG // xHsZMWX4vjZLaoDOfhpPU4/3OcYfjJA4II7VsuSZipfS
// SIG // q0cIawYPEwBQLyMdFLOpnsmahCCrEg5QrTt2D0MvJ+GM
// SIG // 5fLqMuqGTy0JrcpuxRen6xbA6It8VzzPKTMLNm9N4xtU
// SIG // AETkQYJvnXpFiVG8+JpRb3tCdUHkjnWueupZ2jxtdwCy
// SIG // 5th2r/WeEaoONG6oUuCekBGH4P7vHAZ25uMdDHK5Sb6C
// SIG // RK9XG1g0EuWfXTRV+nDpBpCDoU4iGjpGGGeAjVWfBrxO
// SIG // PrB/GWjbydWGgmoRPM20vYNZK1V/0yGy8G/blNzKAoaj
// SIG // GWaYSsbjljg7gwnhmuXP2eduioZDUfXRD0mjwpgu0zfI
// SIG // Zj7H31wTgF7kU/GdbdZuLe3OZ59GfxOeEveOUE9rCu44
// SIG // p2xKc2KuA8GwXcVRTHkeQ/Zneqvp3Z7L/uDe+dRCGy7L
// SIG // gxKn85SRWgczX/hX9Ch+kvWdjtPfA4mG6eCADDONXJEY
// SIG // QAKEy6uSgSFeZjQ/ItYBeGsH8f5exeg6nuV4j7QsF0GH
// SIG // 5Zo7+6vDBABujiTNpkWFaqnePWDnxa1IMt8=
// SIG // End signature block
