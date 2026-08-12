////////////////////////////////////////////////
//
//  Copyright (c) Microsoft Corporation.  All rights reserved.
//
//  File: external.js
//
//  Service for interacting with the Browser host. All window.external calls should be 
//  contained in this file so future browser host changes are isolated and don't require broad changes across the application
//
////////////////////////////////////////////////

var cachedRequestTypes = ["GetBuildVersion", "GetConsoleVersion"];

var adminUI = {
    lastRequestId: 0,
    requestList: [],
    isAvailable: false,
    isChrome: false,


    // Send a new request to the adminUI callback  is optional.
    sendNewRequest: function (requestType, requestData, onResponse) {
        "use strict";
        if (this.isAvailable) {

            // Try to get value from sessionStorage
            if (cachedRequestTypes.includes(requestType) && sessionStorage.hasOwnProperty(requestType)) {
                // Bypass call to console
                onResponse(sessionStorage.getItem(requestType), 0);
                return;
            }

            // package up the request in an object
            var wrappedRequestData = {
                requestType: requestType,
                requestData: requestData
            };

            if (typeof onResponse === "undefined") {
                wrappedRequestData.requestId = ""; // indicates no callback to external host.
            } else {
                // This request has a callback, it will need to be tracked so
                // the callback can be called when a response comes.
                var request = {};
                request.onResponse = onResponse;
                request.requestId = String(++this.lastRequestId) + ":" + String(Math.random());
                this.requestList.push(request);
                wrappedRequestData.requestId = request.requestId;
            }
            this.notify(JSON.stringify(wrappedRequestData));
        } else {
            console.log("Request " + requestType + " was not sent because Microsoft Endpoint Configuration Manager admin console is not available.");

            // Console isn't available, so simulate a request and response back with the console not available errorCode
            var fakeRequest = { onResponse: onResponse, requestId: 1 };
            this.requestList.push(fakeRequest);
            var fakeResponse = { requestId: fakeRequest.requestId, response: "Console not available.", ReturnCode: 4000 };
            this.processResponse(JSON.stringify(fakeResponse));

        }
    },

    ////////////////////////////////////////////////
    //
    // Sends a request to the admin console and invokes a method on the server when complete.
    // The requestType of request is used by
    // admin console code to route the request to a handler.  The requestData is 
    // a single string parameter (can contain json and can be null) for the handler.
    // The onResponse is a callback function which recieves a single string (can contain
    // json) parameter callback from the UI handler once the request is completed.
    //
    ////////////////////////////////////////////////
    sendNewRequestAsync: function (jsAwaiter, requestType, requestData) {
        "use strict";

        return this.sendNewRequest(requestType, requestData, function callback(response, returnCode) {
            var maxMessageSize = 29 * 1024;

            var encodedResponse = base64Encode(response);

            var totalLength = encodedResponse.length;
            var index = 0;

            // Store response to session storage
            if (totalLength > 0 && cachedRequestTypes.includes(requestType) && sessionStorage.hasOwnProperty(requestType) === false &&
                (returnCode === undefined || returnCode === 0)) {
                sessionStorage.setItem(requestType, response);
            }

            // Blazor uses signalR, which has a maximum size limit of 32kB, so we need to break the full message into smaller chunks.
            while ((index < totalLength) || (totalLength === 0)) {
                var partialResponse = encodedResponse.substring(index, index + maxMessageSize);

                var isResponseComplete = index + maxMessageSize >= totalLength;

                // The 2002 version of the console never sets return code, so it will be undefined.
                // Call a 2002 compatible version of OnComplete.
                if (returnCode === undefined) {
                    jsAwaiter.invokeMethodAsync("OnComplete2002", partialResponse, requestType, isResponseComplete);
                }
                else {
                    jsAwaiter.invokeMethodAsync("OnComplete", partialResponse, returnCode, isResponseComplete);
                }

                if (totalLength == 0) {
                    break;
                }

                index += maxMessageSize;
            }
        });
    },

    notify: function (notifyParameter) {
        "use strict";
        try {

            if (this.isChrome == true) {
                window.chrome.webview.postMessage(notifyParameter);
            }
            else {
                window.external.notify(notifyParameter);
            }
        }
        catch (err) {
            console.log("Host notifications are not available.");
        }
    },

    removeRequest: function (requestId) {
        "use strict";
        var requestIndex = this.requestList.findIndex(function (x) { return x.requestId === requestId; });
        if (requestIndex !== -1) {
            this.requestList.splice(requestIndex, 1);
        }
    },

    // Process the response from external call.
    // The response is wrapped in a JSON object together with the request id, so we can look up the correct callback and call it.
    // Ex : {"requestId":"/1","response":null}
    processResponse: function (responseData) {
        "use strict";
        try {
            var parsedResponse = JSON.parse(responseData);

            // Some minimal response validation
            if (!(parsedResponse.hasOwnProperty("requestId") &&
                parsedResponse.hasOwnProperty("response"))) {
                console.log("Invalid response from external call. Discarding response.");
                return;
            }

            var request = this.requestList.find(function (x) { return x.requestId === parsedResponse.requestId; });
            if (typeof request === "undefined") {
                console.log("Response for request " + parsedResponse.requestId + " is unexpected, ignoring callback.");
            } else {
                console.log("Removing completed request " + request.requestId);
                this.removeRequest(request.requestId);

                // In 2002 version of the console this property didn't exist.
                if (parsedResponse.hasOwnProperty("ReturnCode") === true) {
                    request.onResponse(parsedResponse.response, parsedResponse.ReturnCode);
                }
                else {
                    request.onResponse(parsedResponse.response);
                }
            }
        }
        catch (err) {
            console.log("Invalid response, ignoring.  Error: " + err.message);
        }
    },

    // function
    sendNewRequestSync: function (requestType, requestData) {
        "use strict";
        return new Promise(resolve => { 
            this.sendNewRequest(requestType, requestData, response => resolve(response));
        });
    },

    wmiQuery: function(wql, callback) {
        "use strict";
        adminUI.sendNewRequest("RunWmiQuery", wql, callback);
    },

    initializeController: function (scope, callback) {

        adminUI.sendNewRequest("GetConnectionManagerDictionaryValue", "Theme", function (response, returnCode) {

            scope.theme = JSON.parse(response);

            if (scope.theme.IsCustomTheme == true) {
                var root = document.querySelector(":root");
                root.style.setProperty('--background-color', scope.theme.BackgroundColor)
                root.style.setProperty('--foreground-color', scope.theme.ForeGroundColor);
                root.style.setProperty('--hyperlink-color', scope.theme.ThemeHyperlinkColor);
            }

            scope.brightness = GetCurrentBackgroundColor();

            adminUI.sendNewRequest("GetStrings", null, function (response, returnCode) {
                scope.strings = JSON.parse(response)
                callback();
            });
        });
    },
};

// This is the global function that AdminUI host calls to trigger request callbacks.
function adminUICallback(returnValue) {
    "use strict";
    adminUI.processResponse(returnValue);
}

// Encode the input into an escaped base64 string
function base64Encode(input) {
    "use strict";

    var escapedInput = encodeURIComponent(input); // escape non-ascii characters
    var encodedInput = btoa(escapedInput); // base64-encode

    return encodedInput;
}

try {
    adminUI.isChrome = window.chrome != null;
    window.chrome.webview.postMessage("");
    adminUI.isAvailable = true;
    window.chrome.webview.addEventListener("message", event => adminUI.processResponse(event.data));
}
catch (err) {
    console.log("Not using Edge chromium, fallback to Edge legacy.")
    // Set availability of adminUI
    try {
        window.external.notify("");
        adminUI.isAvailable = true;
    }
    catch (err) {
        console.log("AdminUI is not available.");
    }
}

// Abstraction call to sendNewRequest. Convert response to JSON
function callJsonParseMethod(requestType, requestData, onResponse) {
    var response = JSON.parse(adminUI.sendNewRequest(requestType, requestData, onResponse)); 
    return response;
}

// Abstraction call to sendNewRequestSync. Convert response to JSON
async function callJsonParseMethodAsync(requestType, requestData) {
    "use strict";
    var response = JSON.parse(await adminUI.sendNewRequestSync(requestType, requestData)); 
    return response;
}

// Abstraction call to sendNewRequest.
function callMethod(requestType, requestData, onResponse) {
    var response = adminUI.sendNewRequest(requestType, requestData, onResponse); 
    return response;
}

// Abstraction call to sendNewRequestSync.
async function callMethodAsync(requestType, requestData) {
    "use strict";
    var response = await adminUI.sendNewRequestSync(requestType, requestData); 
    return response;
}

////////////////////////////////////////////////
//
// Returns whether the hub is hosted in the console.
//
////////////////////////////////////////////////
isConsoleAvailable = function () {
    "use strict";
    return adminUI.isAvailable;
}

////////////////////////////////////////////////
//
// Gets the TimeZone offset from the client.
//
////////////////////////////////////////////////
getTimeZoneOffset = function () {
    "use strict";
    return new Date().getTimezoneOffset();
}

////////////////////////////////////////////////
//
// Determines if the browser host is WebView2
//
////////////////////////////////////////////////
isWebView2 = function () {
    "use strict";
    return adminUI.isChrome;
}
// SIG // Begin signature block
// SIG // MIInygYJKoZIhvcNAQcCoIInuzCCJ7cCAQExDzANBglg
// SIG // hkgBZQMEAgEFADB3BgorBgEEAYI3AgEEoGkwZzAyBgor
// SIG // BgEEAYI3AgEeMCQCAQEEEBDgyQbOONQRoqMAEEvTUJAC
// SIG // AQACAQACAQACAQACAQAwMTANBglghkgBZQMEAgEFAAQg
// SIG // c1F0SJfKksn0I1MX530LSagyjYiBYMKJcePl3tLQhpeg
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
// SIG // ARUwLwYJKoZIhvcNAQkEMSIEILSQQONLsbDnRQ97gqoB
// SIG // L44gkcl43TjwRpj4Oz4+av/YMEIGCisGAQQBgjcCAQwx
// SIG // NDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRw
// SIG // Oi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEB
// SIG // BQAEggEARv9XhY+mxpAkcmVFsmxeiGeeGqxvdH9HwGOA
// SIG // JeGGAJIzpUM4ORr/R3hBVez6X0yCUxGjpysEwFBgD+wc
// SIG // sDHHNP+gFdBM66fpmBBpxqumduU6UPA0k4DSUgji/dEp
// SIG // UQzMpXq9jcQLE301eHVCTKzZrml61yWUbOnH56J9ysr1
// SIG // eA8MsUegz3yRW91mvMOCkMuZFT/3Pw5r5J8SKbJe7Np5
// SIG // lzFuoR0ywqHpIiKkwaiRgfl0wVLpgsJCz96CxIdY7epm
// SIG // v1ITaBWh852KO60FvZ0KP2pVML/DCLa/ALmX2XPZzVnR
// SIG // MycwFDYibG4TE7M5XgSoxa7cUVT4DMNv3c5sLUf+VqGC
// SIG // FyswghcnBgorBgEEAYI3AwMBMYIXFzCCFxMGCSqGSIb3
// SIG // DQEHAqCCFwQwghcAAgEDMQ8wDQYJYIZIAWUDBAIBBQAw
// SIG // ggFYBgsqhkiG9w0BCRABBKCCAUcEggFDMIIBPwIBAQYK
// SIG // KwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCAVWtLp
// SIG // l+DfQHZITg6E95o7hIomIe3F99+8iplV3voOpgIGY2Pe
// SIG // fFX5GBIyMDIyMTEwNDE3MjM0MC4xNVowBIACAfSggdik
// SIG // gdUwgdIxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
// SIG // aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
// SIG // ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsT
// SIG // JE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGlt
// SIG // aXRlZDEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046QTI0
// SIG // MC00QjgyLTEzMEUxJTAjBgNVBAMTHE1pY3Jvc29mdCBU
// SIG // aW1lLVN0YW1wIFNlcnZpY2WgghF7MIIHJzCCBQ+gAwIB
// SIG // AgITMwAAAbgI1MG4eeBRSQABAAABuDANBgkqhkiG9w0B
// SIG // AQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
// SIG // aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
// SIG // ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQD
// SIG // Ex1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAe
// SIG // Fw0yMjA5MjAyMDIyMTZaFw0yMzEyMTQyMDIyMTZaMIHS
// SIG // MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
// SIG // bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
// SIG // cm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNy
// SIG // b3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQx
// SIG // JjAkBgNVBAsTHVRoYWxlcyBUU1MgRVNOOkEyNDAtNEI4
// SIG // Mi0xMzBFMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1T
// SIG // dGFtcCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOC
// SIG // Ag8AMIICCgKCAgEAnBux/BEcRGfkL3lA8affu0nm86Jj
// SIG // 1paN4gPGmBpdpgaKqzDQbRy8Irdi6Wup6YR/YKQZJ1w4
// SIG // kAX74SqE5Kqs7XecZyOrDqEU2ewbAoA3LN13Cc47SPPW
// SIG // V8Egi7vtNt82+dpZvBJG7QNMYcDufs9HQxgn1sL8eilK
// SIG // 2lsV/rTospxNafBpS4R0CHHoUCqDWuSC6CK65prErLFG
// SIG // R2MVksoVcRcv2nTU+3BLR8bq9mJFWcQqB5qXZN4u90Ai
// SIG // pqkHCW09iJ+CqentnhUkxw+jRNaZE1UU5wdE3BYd6E33
// SIG // GDq6AgZc+juEylas+CDiagc7Z6lzRPfquCb2GUOuXbxs
// SIG // blNqSZXs0n3yRsXmWC2WujBPp5zARW24t3hrSDNiqFqd
// SIG // bvNoVmcN+3nIx7HLn2J8RN3OnACuPackDIiyKrU9jdc+
// SIG // baZQwuUAKSyp6Ucp9aKEr8V6HD+bOKi8FXCSSv8bQXX0
// SIG // 5aBH4wFQqJ/Ck7JCIsDGuq9Wd8JjhCMkJmIci5LXkcJD
// SIG // 9Mi39CPjHVa9FrVSqOeaku7j/IFhZmx29mirxJcjuI6z
// SIG // ua55wAl4SRiUzqI6QyKCHMSGNAr1OE+mgC2W5dsvuogc
// SIG // at8WUeZf/iyhzuOPWPy4HfVTfiAmUHZemGMxpP4T471I
// SIG // iaT/oZFX1KbwLzwWeabZV3AyW4I0BTM8WN+8fHcCAwEA
// SIG // AaOCAUkwggFFMB0GA1UdDgQWBBTE/UclN4XDM1ijWeN+
// SIG // 5xe5R9BpbjAfBgNVHSMEGDAWgBSfpxVdAF5iXYP05dJl
// SIG // pxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8v
// SIG // d3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNy
// SIG // b3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAxMCgx
// SIG // KS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAC
// SIG // hlBodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3Bz
// SIG // L2NlcnRzL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQ
// SIG // Q0ElMjAyMDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBYG
// SIG // A1UdJQEB/wQMMAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQE
// SIG // AwIHgDANBgkqhkiG9w0BAQsFAAOCAgEAn26TyaLCkygr
// SIG // DcP33qmITNt6AAbGQAEdifa8/aFuqeRL1T3uz/pCXJk6
// SIG // EYWxW51qIt5FllOxobmFHSgK4Eg1n+V6WjnHMdz6YE6k
// SIG // FenFJpbWGqjFoIuxUfUQG3PuKfbkePL56O4FyKUfoRnR
// SIG // m03GZYYhDPxHQC5LROPhWAlcciVc/11U6LIaj1V6WuT4
// SIG // UbH8EL6IS4Jop38izKkc+IJQKHnYMZz3WzZLuV1DHUfg
// SIG // KWM4C1qcN9u9J6MBJYuj+zfDRcwBsO6tY2ezReJ0AXZG
// SIG // cvU9rGg7LP1VhqQ0YrgXf+4lFmdWBuwJi7A1fUGZLAzV
// SIG // ls9KeCA1IZNnH8VDbQmP+6WsrSvIBu81s1viSRpLhrvr
// SIG // uJ8Kq9Q4UuVRPw83jeGGV3EjrIc8w5Yi0mkQchkGJM0p
// SIG // uUGxhsiuCFvVib219KwtrlkkPNVk2d1F+FSok7JcX4JW
// SIG // b061WYUMb2QjAzpABfxDSJ/vbXPhU7Nk28PyS2DWUj5e
// SIG // NeBcMlWzeHjuwy70ZdJjOTL7t22CZzeJE+R1rdhVF2Y8
// SIG // m00U3Q0vJtyywTu+EUKKPvl4MZAEWrQDgpUbq4F2vpRN
// SIG // bATRUofEHPYGka+fsEKz7nLGcX4dXoJSJyQOqo+L8gjt
// SIG // myx30Rs/27OPiW6V1cMA+tYa10ar7ArSh2UY1W4IzGwv
// SIG // eGfz4qI71SIwggdxMIIFWaADAgECAhMzAAAAFcXna54C
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
// SIG // BAsTHVRoYWxlcyBUU1MgRVNOOkEyNDAtNEI4Mi0xMzBF
// SIG // MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBT
// SIG // ZXJ2aWNloiMKAQEwBwYFKw4DAhoDFQBwa15WoXH8htMp
// SIG // cct65cI9E8wPu6CBgzCBgKR+MHwxCzAJBgNVBAYTAlVT
// SIG // MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
// SIG // ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9y
// SIG // YXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0
// SIG // YW1wIFBDQSAyMDEwMA0GCSqGSIb3DQEBBQUAAgUA5w+u
// SIG // azAiGA8yMDIyMTEwNDIzMjk0N1oYDzIwMjIxMTA1MjMy
// SIG // OTQ3WjB3MD0GCisGAQQBhFkKBAExLzAtMAoCBQDnD65r
// SIG // AgEAMAoCAQACAgMDAgH/MAcCAQACAhGVMAoCBQDnEP/r
// SIG // AgEAMDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkK
// SIG // AwKgCjAIAgEAAgMHoSChCjAIAgEAAgMBhqAwDQYJKoZI
// SIG // hvcNAQEFBQADgYEAACJ1BS1oeoTZpoOeBGzk1ElCxn+r
// SIG // /Q7vxX9SfdDogFtzO2anrnyb2bPDkaSZQ+jgcWKNicyc
// SIG // Zrk7gLFbV+L4dtBOdz8gR+4KcEDGYZt+VoT1ENwOj8/y
// SIG // PzDmSeeDAujZD7wK9tKzM4H3NGp486v28jbOnUl2AAei
// SIG // KLie4e+HgS4xggQNMIIECQIBATCBkzB8MQswCQYDVQQG
// SIG // EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
// SIG // BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
// SIG // cnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGlt
// SIG // ZS1TdGFtcCBQQ0EgMjAxMAITMwAAAbgI1MG4eeBRSQAB
// SIG // AAABuDANBglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcN
// SIG // AQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEi
// SIG // BCAR0Qg/MoHUCpl/WutJOXAXY+foujA0qMQp+cA7tJjz
// SIG // uDCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EICjr
// SIG // 1jigcDtDilL5jU2wF+ukhhN5aw94ZNqaLRfQ8PsfMIGY
// SIG // MIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
// SIG // c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
// SIG // BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UE
// SIG // AxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAC
// SIG // EzMAAAG4CNTBuHngUUkAAQAAAbgwIgQgkMFbrsxErLno
// SIG // JFGFK+7LOxtnT1DpZMM9iBXubMcbBVYwDQYJKoZIhvcN
// SIG // AQELBQAEggIADbnfcCq7zgRh/g8VCndcdC9VaEK0eORb
// SIG // 7+9RAzZZUvJindZfZdfBxZkuhYnT5Q1Tf8NvBXn+dAa7
// SIG // sHsLdYgkuYeFyi0061Cn6qyGC/dc+foQSZ2JP4Gf7cHO
// SIG // oWt9di2IEzBd+L736/ZW6wJYmhZ6XoXA4+WW2I7fej6Y
// SIG // QtO4dL7sob7as2d810WpVckC6WRVur9KVpjX5rFsQuf0
// SIG // KV/1F1OVFMbS6UkxKenBbIStjtluAR1lqJEYmZRpOt/b
// SIG // Oow9VBgKEDAK0tBZpXozSDcjuSY57ANTMDdVFymS8ClC
// SIG // CXMkQKUUpQv7fc0bDies+J44jeTx5vUKObVKTMW1OF7p
// SIG // xeUJnclnMsPH1/7wFjtZoicbgrcsFEpfjNQegncuMADi
// SIG // MYZEqOGUOXcPl8v2HKkKHnauJFuZl2tpWFwmP3H3z5ws
// SIG // rv8m+bkW1qSpHjjdwFmulrDwB1brf5Bgvtzh1+g9GB41
// SIG // eiv4UN9S9i7zvXwFxmurto2J91R9wcRiOoXkqqDXMwY6
// SIG // s2XPYYsEVH+DZm41oXSHdMNrcSsPDGW1Q1jpxDyfo8HK
// SIG // PBi3E5J/Ou82SIWscwd0O8YKn+79oC4WeZGYhblgObGj
// SIG // QOTiCtgiKz7htnSpeZKvt+1oBXosQoFikGiOnK+RRuCD
// SIG // sjcmoselc2EX0kjlXlRD6MHLaSnYLze3IxA=
// SIG // End signature block
