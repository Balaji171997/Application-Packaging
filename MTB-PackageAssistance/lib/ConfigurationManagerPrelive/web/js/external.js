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
            console.log("Request " + requestType + " was not sent because Microsoft Microsoft Configuration Manager admin console is not available.");

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
                root.style.setProperty('--focus-color', scope.theme.FocusColor);
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
// SIG // MIIomQYJKoZIhvcNAQcCoIIoijCCKIYCAQExDzANBglg
// SIG // hkgBZQMEAgEFADB3BgorBgEEAYI3AgEEoGkwZzAyBgor
// SIG // BgEEAYI3AgEeMCQCAQEEEBDgyQbOONQRoqMAEEvTUJAC
// SIG // AQACAQACAQACAQACAQAwMTANBglghkgBZQMEAgEFAAQg
// SIG // b7F0E8MUwRSvTJ3JVgH9sGuKtNst4CGWnZSUaPSn5leg
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
// SIG // AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCCXUaXYHrMP+mfk
// SIG // AI7h+25/jN88iX4WkJ8EbnrnQwERPzCBigYKKwYBBAGC
// SIG // NwIBDDF8MHqgXIBaAE0AaQBjAHIAbwBzAG8AZgB0AC4A
// SIG // VABvAG8AbABrAGkAdAAuAFcAcABmAC4AVQBJAC4AQwBv
// SIG // AG4AdAByAG8AbABzAC4AVwBlAGIAVgBpAGUAdwAuAGQA
// SIG // bABsoRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
// SIG // BgkqhkiG9w0BAQEFAASCAQCQawTkCv4i1yMqMJG98IMq
// SIG // WDrhSFoUsy5Gd4DL7KpN2KRrZiGbwl72uJmNB7EJEz9f
// SIG // 1CbCw93mK9/WI/xFFobuiQ67Cfiad0195wPgUmcPy3YD
// SIG // AavfXOTsXa70bhjkJgSaN1sCgay2Y9EZtG7Bqw8xc8iu
// SIG // 6x5Mq8Y1pADb+1Szq9iBJMN3Hqg0p1VH3R+DEAX93/ze
// SIG // pvoT1KAD7/S/G4RQEiGb548az1xBvlgQ3ICQjx96VyS+
// SIG // 6njP+U5+tLiB5PQ7sruyP35gQ8Q/EkFucgB8qWmmvnPn
// SIG // j14kva+xN/nxOWjEJ2n63GxyP4hXn2kKH5/RQCb/Spk0
// SIG // Walvp4LYfz4QoYIXrTCCF6kGCisGAQQBgjcDAwExgheZ
// SIG // MIIXlQYJKoZIhvcNAQcCoIIXhjCCF4ICAQMxDzANBglg
// SIG // hkgBZQMEAgEFADCCAVoGCyqGSIb3DQEJEAEEoIIBSQSC
// SIG // AUUwggFBAgEBBgorBgEEAYRZCgMBMDEwDQYJYIZIAWUD
// SIG // BAIBBQAEIPVMjxQ/W5Ls7Iw9E32YbGNv2li+pLfCeTES
// SIG // nsFR5RKEAgZo8jMcZeMYEzIwMjUxMDIzMDI0NjAxLjAy
// SIG // N1owBIACAfSggdmkgdYwgdMxCzAJBgNVBAYTAlVTMRMw
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
// SIG // SIb3DQEJBDEiBCDzC5DdXMnuSQr8iHRPtF/H99H9WX+A
// SIG // /DFZ1BefBLDrKjCB+gYLKoZIhvcNAQkQAi8xgeowgecw
// SIG // geQwgb0EIDZ4q+9bHltyiLjdtE7f4S21BQK/J4PZ1tfL
// SIG // /r7TEr7HMIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzAR
// SIG // BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
// SIG // bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
// SIG // bjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAg
// SIG // UENBIDIwMTACEzMAAAIUjc0jRO4G33IAAQAAAhQwIgQg
// SIG // vxzC5MFtqjj80TDAl3QDb6JOEYmN5s6KaKd5HQeGMncw
// SIG // DQYJKoZIhvcNAQELBQAEggIAaYMFct8l774q0Uyy35Zj
// SIG // OIc6puXjwd1rlqAQJLUGz5ouPOYp4ADExC5KX0glFpxB
// SIG // y9sQh6CZsA3F+LaYhPerbSNKQGI9rIGucDsjLXNDXtQa
// SIG // /qAHEaQ3K1npEBpUKv3wHpPbynmjUn2Tj3uOvWBmHqbt
// SIG // XtKtXx0rjLN6ZH3bSNZXd99kHbJboKQ9WHyT6m7ZO3pV
// SIG // vEbepcwF3CmR+E8y0bvBffM1yrH0+YwtvppyKNTk7oKx
// SIG // EMAl0355Ub/JScx4oH1lNJOqAI8Rl9cq75cEXHTYaLUO
// SIG // iEEACLd6j1Nj9o+WehBCoBiTpe1zsMAAX0KNIqgw0qFn
// SIG // UMJG+0RCGwmcNjbCvcFjfuQ/Pd4pPe7zk71HGAPeGB6U
// SIG // p5bQYVvEZ48aMTGHzfNP48Y2gXhU3Mik2EYiK6vb1PrG
// SIG // aeqqx4ulA/Uqzp0CgaLO8MVytY1kYIF/MQFgdYq11O1A
// SIG // Uygz62n2wg6mBf1RMq4KIlUOC8HH9KDp5340xDUBevk7
// SIG // ACdq3KjUaiBNyGZRq/uUPB+MFS+lr6cXDVbmQc0Jjjfk
// SIG // lH4ClBczakosyZ6Nt+hktZ9u5hGcoTj3KmppKo1svp1F
// SIG // jD3G597i4P0pCsz6VHuzxU57Hnv9nhW5YHRkfRfBcssH
// SIG // 7i6CLWd0QYc7upr5EguhK+2H3yLzgmwwQOB4iyeyIcDYEF8=
// SIG // End signature block
