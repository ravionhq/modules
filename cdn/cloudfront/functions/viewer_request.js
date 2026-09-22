var REDIRECT_RULES = ${redirect_rules_json};

function serializeQueryString(query) {
    if (!query) {
        return '';
    }

    if (typeof query === 'string') {
        return query;
    }

    var parts = [];
    for (var key in query) {
        var parameter = query[key];
        var values = parameter.multiValue || [parameter];
        for (var index = 0; index < values.length; index++) {
            parts.push(encodeURIComponent(key) + '=' + encodeURIComponent(values[index].value || ''));
        }
    }
    return parts.join('&');
}

function parseRoute(route) {
    if (route.indexOf('https://') !== 0) {
        return {host: null, path: route};
    }

    var remainder = route.slice(8);
    var slashIndex = remainder.indexOf('/');
    if (slashIndex < 0) {
        return {host: remainder.toLowerCase(), path: '/'};
    }
    return {
        host: remainder.slice(0, slashIndex).toLowerCase(),
        path: remainder.slice(slashIndex) || '/'
    };
}

function splitPath(path) {
    if (!path || path === '/') {
        return [];
    }
    return path.slice(1).split('/');
}

function normalizeCapturedSegment(segment) {
    var decoded;
    try {
        decoded = decodeURIComponent(segment);
    } catch (error) {
        return null;
    }

    if (decoded === '.' || decoded === '..' || decoded.indexOf('/') >= 0 || decoded.indexOf('\\') >= 0) {
        return null;
    }
    for (var index = 0; index < decoded.length; index++) {
        var code = decoded.charCodeAt(index);
        if (code < 32 || code === 127) {
            return null;
        }
    }
    return encodeURIComponent(decoded);
}

function matchRoute(source, host, uri) {
    var route = parseRoute(source);
    if (route.host && route.host !== host) {
        return null;
    }

    var patternSegments = splitPath(route.path);
    var uriSegments = splitPath(uri);
    var captures = {};
    var uriIndex = 0;

    for (var patternIndex = 0; patternIndex < patternSegments.length; patternIndex++) {
        var patternSegment = patternSegments[patternIndex];
        if (patternSegment.charAt(0) !== ':') {
            if (uriIndex >= uriSegments.length) {
                return null;
            }
            var normalizedPatternSegment = normalizeCapturedSegment(patternSegment);
            var normalizedUriSegment = normalizeCapturedSegment(uriSegments[uriIndex]);
            if (
                normalizedPatternSegment === null ||
                normalizedUriSegment === null ||
                normalizedUriSegment !== normalizedPatternSegment
            ) {
                return null;
            }
            uriIndex++;
            continue;
        }

        var catchAll = patternSegment.charAt(patternSegment.length - 1) === '*';
        var name = patternSegment.slice(1, catchAll ? -1 : patternSegment.length);
        if (catchAll) {
            var remaining = [];
            for (; uriIndex < uriSegments.length; uriIndex++) {
                var normalizedRemainingSegment = normalizeCapturedSegment(uriSegments[uriIndex]);
                if (normalizedRemainingSegment === null) {
                    return null;
                }
                remaining.push(normalizedRemainingSegment);
            }
            captures[name] = remaining.join('/');
            uriIndex = uriSegments.length;
            continue;
        }
        if (uriIndex >= uriSegments.length) {
            return null;
        }
        var normalizedSegment = normalizeCapturedSegment(uriSegments[uriIndex]);
        if (normalizedSegment === null) {
            return null;
        }
        captures[name] = normalizedSegment;
        uriIndex++;
    }

    return uriIndex === uriSegments.length ? captures : null;
}

function expandDestination(destination, fallbackHost, captures) {
    var route = parseRoute(destination);
    var patternSegments = splitPath(route.path);
    var destinationSegments = [];

    for (var index = 0; index < patternSegments.length; index++) {
        var segment = patternSegments[index];
        if (segment.charAt(0) !== ':') {
            var normalizedDestinationSegment = normalizeCapturedSegment(segment);
            if (normalizedDestinationSegment === null) {
                return null;
            }
            destinationSegments.push(normalizedDestinationSegment);
            continue;
        }

        var catchAll = segment.charAt(segment.length - 1) === '*';
        var name = segment.slice(1, catchAll ? -1 : segment.length);
        var value = captures[name] || '';
        if (value) {
            destinationSegments.push(value);
        }
    }

    return {
        host: route.host || fallbackHost,
        path: destinationSegments.length ? '/' + destinationSegments.join('/') : '/'
    };
}

function handler(event) {
    var request = event.request;
    var headers = request.headers || {};
    var host = headers.host ? headers.host.value.toLowerCase() : '';
    var uri = request.uri || '/';
    var method = request.method || 'GET';

    for (var index = 0; index < REDIRECT_RULES.length; index++) {
        var rule = REDIRECT_RULES[index];
        var captures = matchRoute(rule.source, host, uri);
        if (captures === null) {
            continue;
        }
        if (method !== 'GET' && method !== 'HEAD' && !rule.redirect_non_read_methods) {
            continue;
        }

        var destination = expandDestination(rule.destination, host, captures);
        if (destination === null) {
            continue;
        }
        if (destination.host === host && matchRoute(rule.source, destination.host, destination.path) !== null) {
            continue;
        }
        var location = 'https://' + destination.host + destination.path;
        if (rule.preserve_query_string) {
            var queryString = serializeQueryString(request.querystring);
            if (queryString) {
                location += '?' + queryString;
            }
        }

        var descriptions = {
            301: 'Moved Permanently',
            302: 'Found',
            307: 'Temporary Redirect',
            308: 'Permanent Redirect'
        };
        return {
            statusCode: rule.status_code,
            statusDescription: descriptions[rule.status_code],
            headers: {
                location: {value: location}
            }
        };
    }

    return request;
}
